import AVFoundation
import CryptoKit
import Network
import UIKit

/// Modo compañero con voz (Hub #727; Juan, 17-nov-2026: «el modo Companion debería ser como una retransmisión de lo que se
/// está viendo… el audio que se reproduce en el teléfono es lo mismo que se debería reproducir en el iPad… sólo haya una
/// llamada»). La voz de Alma no pasa por el Hub: va directo por la red local (el mismo Wi-Fi o Wi-Fi entre dispositivos).
///   · El compañero (el iPad con «Modo compañero» encendido, lo dice la página: Puente → `companero`) escucha en la red con
///     el servicio `_almacomp._tcp` y suena lo que le llega.
///   · El dispositivo de la llamada, mientras el Hub dice que alguien mira (Companero.swift), lo busca y le manda cada trozo
///     de la voz tal cual llega de ElevenLabs (TramaVivo.swift), el corte cuando Alma se calla y el fin.
///   · Los dos usan la clave del compañero (el Hub, vivo.js, la da solo al mismo administrador con su sesión): el nombre del
///     servicio sale de ella y la conexión va cifrada con ella (TLS con llave compartida). Otro teléfono en la red no la oye.
///   · Una sola llamada: mientras la página del compañero ve la llamada del otro, aquí no se abre otra (VozNativa.hablar).
final class Retransmision {
    static let shared = Retransmision()
    static let servicio = "_almacomp._tcp"
    private let cola = DispatchQueue(label: "alma.retransmision")
    private var clave = ""

    // El dispositivo de la llamada
    private var emitiendo = false
    private var buscador: NWBrowser?
    private var salida: NWConnection?
    private var hzMandado: Double = 0

    // El compañero
    private var recibiendo = false
    private var oyente: NWListener?
    private var entrada: NWConnection?
    private var buf = Data()
    private let motor = AVAudioEngine()
    private let reproductor = AVAudioPlayerNode()
    private var formato: AVAudioFormat?
    private var conSonido = true

    /// Lo ve la voz (en el hilo principal): la llamada del otro dispositivo sigue.
    private var otraVista: Date?
    var otraLlamadaViva: Bool { TramaVivo.otraLlamada(vista: otraVista, ahora: Date()) }

    // MARK: lo que dice la página del compañero (Puente → { accion: "companero", on, viva, clave, sonido })
    func companero(on: Bool, viva: Bool, clave k: String, sonido: Bool) {
        otraVista = on && viva ? Date() : nil
        cola.async {
            self.conSonido = sonido; self.reproductor.volume = sonido ? 1 : 0
            if !k.isEmpty, k != self.clave { self.clave = k; self.pararOyente(); self.pararEmisor() }
            if on, !self.clave.isEmpty { self.escuchar() } else { self.pararOyente() }
        }
    }

    // MARK: lo que dice el dispositivo de la llamada
    /// Companero.swift, con cada respuesta del Hub: si alguien mira (y con qué clave).
    func mirando(_ m: Bool, clave k: String?) {
        cola.async {
            if let k, !k.isEmpty, k != self.clave { self.clave = k; self.pararEmisor(); self.pararOyente() }
            if m, !self.clave.isEmpty, !self.recibiendo { self.buscar() } else if !m { self.pararEmisor() }
        }
    }
    /// VozNativa.sonar: cada trozo de la voz de Alma, tal cual (PCM de 16 bits).
    func voz(_ pcm16: Data, hz: Double) {
        cola.async {
            guard let c = self.salida, c.state == .ready else { return }
            if hz != self.hzMandado { self.hzMandado = hz; c.send(content: TramaVivo.formato(hz), completion: .idempotent) }
            c.send(content: TramaVivo.armar(.audio, pcm16), completion: .idempotent)
        }
    }
    /// Alma se calló porque le hablaron: en el compañero tampoco suena lo que faltaba.
    func corte() { cola.async { self.salida?.send(content: TramaVivo.armar(.corte), completion: .idempotent) } }
    /// La llamada terminó: se avisa y se suelta la red.
    func fin() {
        cola.async {
            if let c = self.salida, c.state == .ready { c.send(content: TramaVivo.armar(.fin), completion: .contentProcessed { _ in c.cancel() }); self.salida = nil }
            self.pararEmisor()
        }
    }

    // MARK: red
    private func nombre() -> String {
        "alma-" + SHA256.hash(data: Data(("nombre:" + clave).utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }
    /// TLS con llave compartida (como el ejemplo de Apple de juegos entre dispositivos): solo quien tiene la clave conecta.
    private func parametros() -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let llave = SymmetricKey(data: SHA256.hash(data: Data(("llave:" + clave).utf8)))
        let psk = Data(HMAC<SHA256>.authenticationCode(for: Data("alma-companero".utf8), using: llave))
        let dPsk = psk.withUnsafeBytes { DispatchData(bytes: $0) }, dId = Data("alma-companero".utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions, dPsk as __DispatchData, dId as __DispatchData)
        if let cs = tls_ciphersuite_t(rawValue: 0x00A8) { sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions, cs) }   // TLS_PSK_WITH_AES_128_GCM_SHA256
        let tcp = NWProtocolTCP.Options(); tcp.noDelay = true; tcp.enableKeepalive = true; tcp.keepaliveIdle = 2
        let p = NWParameters(tls: tls, tcp: tcp); p.includePeerToPeer = true
        return p
    }

    private func escuchar() {
        guard oyente == nil else { return }
        recibiendo = true
        do {
            let l = try NWListener(using: parametros())
            l.service = NWListener.Service(name: nombre(), type: Retransmision.servicio)
            l.newConnectionHandler = { [weak self] c in
                guard let self else { return }
                self.entrada?.cancel(); self.entrada = c; self.buf = Data()
                c.stateUpdateHandler = { [weak self] s in if case .failed = s { self?.soltarEntrada(c) } }
                c.start(queue: self.cola); self.recibir(c)
            }
            l.stateUpdateHandler = { [weak self] s in if case .failed = s { self?.cola.asyncAfter(deadline: .now() + 3) { self?.pararOyente(); self?.escuchar() } } }
            l.start(queue: cola); oyente = l
        } catch { oyente = nil }
    }
    private func pararOyente() {
        recibiendo = false
        oyente?.cancel(); oyente = nil
        if let c = entrada { soltarEntrada(c) }
    }
    private func soltarEntrada(_ c: NWConnection) {
        c.cancel(); guard c === entrada else { return }
        entrada = nil; buf = Data(); callar()
    }
    private func recibir(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] d, _, fin, err in
            guard let self, c === self.entrada else { return }
            if let d, !d.isEmpty {
                self.buf.append(d)
                guard let ts = TramaVivo.sacar(&self.buf) else { self.soltarEntrada(c); return }
                ts.forEach { self.tratar($0.0, $0.1) }
            }
            if fin || err != nil { self.soltarEntrada(c); return }
            self.recibir(c)
        }
    }

    private func buscar() {
        guard !emitiendo else { return }
        emitiendo = true
        let b = NWBrowser(for: .bonjour(type: Retransmision.servicio, domain: nil), using: parametros())
        b.browseResultsChangedHandler = { [weak self] _, _ in self?.probar() }
        b.stateUpdateHandler = { [weak self] s in if case .failed = s { self?.cola.asyncAfter(deadline: .now() + 3) { self?.pararEmisor() } } }
        b.start(queue: cola); buscador = b
    }
    /// Entre lo que se ve en la red, el compañero de este administrador (su nombre sale de la clave).
    private func probar() {
        guard emitiendo, salida == nil, let b = buscador else { return }
        let n = nombre()
        let e = b.browseResults.first { r -> Bool in
            if case let .service(name, _, _, _) = r.endpoint { return name == n }
            return false
        }
        if let e { conectar(e.endpoint) }
    }
    private func conectar(_ e: NWEndpoint) {
        let c = NWConnection(to: e, using: parametros())
        salida = c; hzMandado = 0
        c.stateUpdateHandler = { [weak self] s in
            guard let self else { return }
            switch s {
            case .failed, .cancelled:
                guard self.salida === c else { return }
                self.salida = nil; self.hzMandado = 0
                self.cola.asyncAfter(deadline: .now() + 2) { [weak self] in self?.probar() }   // se vuelve a intentar mientras alguien mire
            default: break
            }
        }
        c.start(queue: cola)
    }
    private func pararEmisor() {
        emitiendo = false
        buscador?.cancel(); buscador = nil
        salida?.cancel(); salida = nil; hzMandado = 0
    }

    // MARK: audio del compañero
    private func tratar(_ t: TramaVivo.Tipo, _ d: Data) {
        switch t {
        case .formato:
            if let hz = TramaVivo.hz(d), hz != formato?.sampleRate, let f = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: hz, channels: 1, interleaved: false) {
                callar(); if formato != nil { motor.disconnectNodeOutput(reproductor) }
                formato = f
            }
        case .audio: sonar(d)
        case .corte: reproductor.stop(); if motor.isRunning { reproductor.play() }
        case .fin: break   // lo que ya llegó termina de sonar; la página cierra el espejo
        }
    }
    private func sonar(_ pcm16: Data) {
        guard let f = formato else { return }
        let n = pcm16.count / 2
        guard n > 0, let b = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: AVAudioFrameCount(n)), let ch = b.floatChannelData else { return }
        b.frameLength = AVAudioFrameCount(n)
        pcm16.withUnsafeBytes { (r: UnsafeRawBufferPointer) in
            let s = r.bindMemory(to: Int16.self)
            for i in 0..<n { ch[0][i] = Float(Int16(littleEndian: s[i])) / 32768 }
        }
        guard encender(f) else { return }
        reproductor.scheduleBuffer(b, completionHandler: nil)
        if !reproductor.isPlaying { reproductor.play() }
    }
    /// El audio del compañero se prende con la primera voz. Si este dispositivo ya tiene el micrófono abierto (el Inicio con
    /// escucha activa), se respeta su sesión; si no, solo reproducir, junto con lo demás.
    private func encender(_ f: AVAudioFormat) -> Bool {
        if motor.isRunning, motor.outputConnectionPoints(for: reproductor, outputBus: 0).isEmpty == false { return true }
        let s = AVAudioSession.sharedInstance()
        if s.category != .playAndRecord { try? s.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers]) }
        try? s.setActive(true)
        if motor.attachedNodes.contains(reproductor) == false { motor.attach(reproductor) }
        if motor.outputConnectionPoints(for: reproductor, outputBus: 0).isEmpty { motor.connect(reproductor, to: motor.mainMixerNode, format: f) }
        reproductor.volume = conSonido ? 1 : 0
        if !motor.isRunning { do { try motor.start() } catch { return false } }
        return true
    }
    private func callar() {
        reproductor.stop()
        if motor.isRunning { motor.stop() }
    }
}
