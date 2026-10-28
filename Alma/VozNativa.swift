import AVFoundation
import AudioToolbox
import Foundation
import MediaPlayer
import Security

/// Alma por voz dentro de la app, también con el teléfono bloqueado.
/// · «Alma con el anillo» encendido: la app queda lista en segundo plano como la app de audio del teléfono
///   (un audio en silencio la mantiene viva y en «Reproduciendo»). El anillo en modo Music manda su toque como el botón
///   de unos audífonos → doble toque: Alma escucha y responde · otro doble toque: pausa · otro: retoma.
/// · La voz es el mismo agente de ElevenLabs del Hub (websocket directo con agent_id). La ficha (quién eres, saludo y
///   contexto reciente) se pide al Hub con tu sesión, igual que la voz de las web apps, y la llamada se liga a tu chat.
/// Pausar termina la conversación; al retomar, el Hub le da a Alma lo que venían hablando («¿Retomamos…?»).
final class VozNativa: NSObject, URLSessionWebSocketDelegate {
    static let shared = VozNativa()

    enum Estado: String { case apagada, lista, conectando, hablando }
    private(set) var estado: Estado = .apagada { didSet { avisar() } }
    var alEvento: (([String: Any]) -> Void)?

    private var modoAnillo: Bool { UserDefaults.standard.bool(forKey: "voz_modo_anillo") }
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var formatoSalida = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    private let formatoEntrada = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    private var convertidor: AVAudioConverter?
    private var ws: URLSessionWebSocketTask?
    private var sesionURL: URLSession?
    private var silencio: AVAudioPlayer?
    private var ultimoToque = Date.distantPast
    private var motorListo = false

    // MARK: - Lo que pide la página

    /// Datos para pedir la ficha al Hub: dirección del Apps Script, llave de la app y la sesión firmada.
    func configurar(url: String, token: String, sesion: String) {
        Llave.guardar("voz_url", url); Llave.guardar("voz_token", token); Llave.guardar("voz_sesion", sesion)
    }

    func ponerModoAnillo(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "voz_modo_anillo")
        if on { prepararMandos(); quedarLista() } else { terminar(); apagar() }
    }

    func arrancarSiHaceFalta() { if modoAnillo { prepararMandos(); quedarLista() } }

    /// Doble toque del anillo (o el botón de la página): habla o pausa.
    func alternar() {
        switch estado {
        case .hablando, .conectando: terminar()
        case .lista, .apagada: hablar()
        }
    }

    var resumen: [String: Any] { ["tipo": "estado", "estado": estado.rawValue, "modoAnillo": modoAnillo] }

    // MARK: - Estar lista (audio en silencio + mandos de la pantalla de bloqueo)

    private func quedarLista() {
        guard estado != .hablando, estado != .conectando else { return }
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playback, mode: .default, options: [])
            try s.setActive(true)
        } catch {}
        if silencio == nil, let wav = VozNativa.wavSilencio() { silencio = try? AVAudioPlayer(data: wav); silencio?.numberOfLoops = -1; silencio?.volume = 0.01 }
        silencio?.play()
        estado = .lista
        infoBloqueo("Toca dos veces tu anillo para hablar")
    }

    private func apagar() {
        silencio?.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        estado = .apagada
    }

    private var mandosListos = false
    private func prepararMandos() {
        guard !mandosListos else { return }; mandosListos = true
        let c = MPRemoteCommandCenter.shared()
        // El anillo (modo Music) llega como reproducir/pausar. Un doble toque puede llegar como dos avisos: se cuentan como uno.
        let toque: (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus = { [weak self] _ in
            guard let self else { return .commandFailed }
            if Date().timeIntervalSince(self.ultimoToque) < 0.9 { return .success }
            self.ultimoToque = Date()
            DispatchQueue.main.async { self.alternar() }
            return .success
        }
        c.togglePlayPauseCommand.isEnabled = true; c.togglePlayPauseCommand.addTarget(handler: toque)
        c.playCommand.isEnabled = true; c.playCommand.addTarget(handler: toque)
        c.pauseCommand.isEnabled = true; c.pauseCommand.addTarget(handler: toque)
    }

    private func infoBloqueo(_ texto: String) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: "Alma", MPMediaItemPropertyArtist: texto,
                                                           MPNowPlayingInfoPropertyPlaybackRate: estado == .hablando ? 1.0 : 0.0]
    }

    // MARK: - Hablar

    private func hablar() {
        guard let url = Llave.leer("voz_url"), let token = Llave.leer("voz_token"), let sesion = Llave.leer("voz_sesion"), let u = URL(string: url) else {
            emitir(["tipo": "error", "mensaje": "Abre Alma una vez con tu sesión para que pueda hablar con el teléfono bloqueado."]); return
        }
        estado = .conectando
        AudioServicesPlaySystemSound(1113)
        infoBloqueo("Conectando…")
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["hub": 1, "action": "vozWeb", "ligero": 1, "token": token, "session": sesion])
        URLSession.shared.dataTask(with: r) { [weak self] data, _, _ in
            guard let self else { return }
            guard let d = data, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], (j["ok"] as? Bool) == true,
                  let agente = j["agent_id"] as? String else {
                DispatchQueue.main.async { self.fallo("No pude conectar con Alma.") }; return
            }
            DispatchQueue.main.async { self.conectar(agente: agente, ficha: j) }
        }.resume()
    }

    private func conectar(agente: String, ficha: [String: Any]) {
        guard estado == .conectando else { return }
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            try s.setActive(true)
            try prepararMotor()
        } catch { fallo("No pude abrir el micrófono."); return }
        silencio?.stop()
        guard let u = URL(string: "wss://api.elevenlabs.io/v1/convai/conversation?agent_id=\(agente)") else { return }
        let sesion = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        sesionURL = sesion
        let t = sesion.webSocketTask(with: u); ws = t; t.resume()
        var dv = ficha["dynamic_variables"] as? [String: Any] ?? [:]
        dv["quien_llama"] = ((dv["quien_llama"] as? String) ?? "") + "\n\nEN PANTALLA: habla con Alma desde su anillo, con el teléfono bloqueado (solo voz, sin pantalla). Respuestas cortas y claras."
        var agent: [String: Any] = [:]
        if let fm = ficha["first_message"] as? String, !fm.isEmpty { agent["first_message"] = fm }
        if let l = ficha["language"] as? String, !l.isEmpty { agent["language"] = l }
        var inicio: [String: Any] = ["type": "conversation_initiation_client_data", "dynamic_variables": dv]
        if !agent.isEmpty { inicio["conversation_config_override"] = ["agent": agent] }
        mandar(inicio)
        escuchar()
    }

    private func prepararMotor() throws {
        if !motorListo {
            engine.attach(player)
            try engine.inputNode.setVoiceProcessingEnabled(true)   // quita el eco de la voz de Alma del micrófono
            motorListo = true
        }
        engine.connect(player, to: engine.mainMixerNode, format: formatoSalida)
        let fIn = engine.inputNode.outputFormat(forBus: 0)
        convertidor = AVAudioConverter(from: fIn, to: formatoEntrada)
        engine.inputNode.removeTap(onBus: 0)
        engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: fIn) { [weak self] buf, _ in self?.microfono(buf) }
        if !engine.isRunning { try engine.start() }
        player.play()
    }

    private func microfono(_ buf: AVAudioPCMBuffer) {
        guard estado == .hablando, let conv = convertidor else { return }
        let cap = AVAudioFrameCount(Double(buf.frameLength) * 16000 / buf.format.sampleRate) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: formatoEntrada, frameCapacity: cap) else { return }
        var dado = false
        conv.convert(to: out, error: nil) { _, st in
            if dado { st.pointee = .noDataNow; return nil }
            dado = true; st.pointee = .haveData; return buf
        }
        guard out.frameLength > 0, let p = out.int16ChannelData else { return }
        let datos = Data(bytes: p[0], count: Int(out.frameLength) * 2)
        DispatchQueue.main.async { self.mandar(["user_audio_chunk": datos.base64EncodedString()]) }
    }

    private func escuchar() {
        ws?.receive { [weak self] r in
            guard let self else { return }
            switch r {
            case .success(let m):
                var texto: String?
                if case .string(let s) = m { texto = s } else if case .data(let d) = m { texto = String(data: d, encoding: .utf8) }
                if let t = texto, let d = t.data(using: .utf8), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                    DispatchQueue.main.async { self.mensaje(j) }
                }
                self.escuchar()
            case .failure:
                DispatchQueue.main.async { if self.estado == .hablando || self.estado == .conectando { self.terminar() } }
            }
        }
    }

    private func mensaje(_ j: [String: Any]) {
        switch j["type"] as? String ?? "" {
        case "conversation_initiation_metadata":
            let ev = j["conversation_initiation_metadata_event"] as? [String: Any] ?? [:]
            if let f = ev["agent_output_audio_format"] as? String, f.hasPrefix("pcm_"), let hz = Double(f.dropFirst(4)), hz != formatoSalida.sampleRate,
               let nuevo = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: hz, channels: 1, interleaved: false) {
                formatoSalida = nuevo; player.stop(); engine.disconnectNodeOutput(player); engine.connect(player, to: engine.mainMixerNode, format: nuevo); player.play()
            }
            estado = .hablando
            infoBloqueo("Te escucho · dos toques para pausar")
            if let id = ev["conversation_id"] as? String { vincular(id) }
        case "audio":
            let ev = j["audio_event"] as? [String: Any] ?? [:]
            if let b = ev["audio_base_64"] as? String, let d = Data(base64Encoded: b) { sonar(d) }
        case "interruption":
            player.stop(); player.play()
        case "ping":
            let ev = j["ping_event"] as? [String: Any] ?? [:]
            mandar(["type": "pong", "event_id": ev["event_id"] ?? 0])
        case "agent_response":
            let ev = j["agent_response_event"] as? [String: Any] ?? [:]
            if let t = ev["agent_response"] as? String { emitir(["tipo": "alma", "texto": t]) }
        case "user_transcript":
            let ev = j["user_transcription_event"] as? [String: Any] ?? [:]
            if let t = ev["user_transcript"] as? String { emitir(["tipo": "yo", "texto": t]) }
        default: break
        }
    }

    private func sonar(_ pcm16: Data) {
        let n = pcm16.count / 2
        guard n > 0, let buf = AVAudioPCMBuffer(pcmFormat: formatoSalida, frameCapacity: AVAudioFrameCount(n)), let ch = buf.floatChannelData else { return }
        buf.frameLength = AVAudioFrameCount(n)
        pcm16.withUnsafeBytes { (r: UnsafeRawBufferPointer) in
            let s = r.bindMemory(to: Int16.self)
            for i in 0..<n { ch[0][i] = Float(Int16(littleEndian: s[i])) / 32768 }
        }
        player.scheduleBuffer(buf, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private func mandar(_ o: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) else { return }
        ws?.send(.string(s)) { _ in }
    }

    /// La llamada queda ligada a tu chat con Alma en el Hub (como la voz de las web apps).
    private func vincular(_ id: String) {
        guard let url = Llave.leer("voz_url"), let token = Llave.leer("voz_token"), let sesion = Llave.leer("voz_sesion"), let u = URL(string: url) else { return }
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["hub": 1, "action": "vozWebVincular", "conv_id": id, "token": token, "session": sesion])
        URLSession.shared.dataTask(with: r).resume()
    }

    private func terminar() {
        let habia = estado == .hablando || estado == .conectando
        ws?.cancel(with: .normalClosure, reason: nil); ws = nil
        sesionURL?.invalidateAndCancel(); sesionURL = nil
        engine.inputNode.removeTap(onBus: 0)
        player.stop()
        if engine.isRunning { engine.stop() }
        if habia { AudioServicesPlaySystemSound(1114) }
        estado = .apagada
        if modoAnillo { quedarLista() } else { apagar() }
    }

    private func fallo(_ m: String) {
        emitir(["tipo": "error", "mensaje": m])
        terminar()
    }

    func urlSession(_ s: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith code: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        if estado == .hablando || estado == .conectando { terminar() }
    }

    private func avisar() { emitir(resumen) }
    private func emitir(_ e: [String: Any]) { alEvento?(e) }

    /// Un segundo de silencio en WAV (PCM 16 bits, 8 kHz) para repetir sin fin.
    static func wavSilencio() -> Data? {
        let hz: UInt32 = 8000, muestras = Int(hz), bytes = UInt32(muestras * 2)
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append("RIFF".data(using: .ascii)!); u32(36 + bytes); d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(1); u32(hz); u32(hz * 2); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(bytes); d.append(Data(count: Int(bytes)))
        return d
    }
}

/// Guardado en el llavero de este equipo (la sesión es una llave: no va en las preferencias).
enum Llave {
    static func guardar(_ k: String, _ v: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.spacioam.alma.voz", kSecAttrAccount as String: k]
        SecItemDelete(base as CFDictionary)
        var q = base; q[kSecValueData as String] = Data(v.utf8); q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
    static func leer(_ k: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.spacioam.alma.voz", kSecAttrAccount as String: k,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var r: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess, let d = r as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}
