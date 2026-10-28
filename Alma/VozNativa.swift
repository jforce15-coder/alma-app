import AVFoundation
import AudioToolbox
import Foundation
import MediaPlayer
import Security
import UIKit

/// Alma por voz dentro de la app, también con el teléfono bloqueado.
/// · «Alma con el anillo» encendido: la app queda lista en segundo plano como la app de audio del teléfono
///   (un audio en silencio la mantiene viva y en «Reproduciendo»). El anillo en modo Music manda su toque como el botón
///   de unos audífonos → doble toque: Alma escucha y responde · otro doble toque: pausa · otro: retoma.
/// · La voz es el mismo agente de ElevenLabs del Hub (websocket con la URL firmada del Hub). La ficha (quién eres, saludo y
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
    private var formatoMono: AVAudioFormat?
    private var sinEco = false   // si la cancelación de eco falló una vez, ya no se intenta
    private var sono = false

    // MARK: - Lo que pide la página

    /// Datos para pedir la ficha al Hub: dirección del Apps Script, llave de la app y la sesión firmada.
    func configurar(url: String, token: String, sesion: String) {
        Llave.guardar("voz_url", url); Llave.guardar("voz_token", token); Llave.guardar("voz_sesion", sesion)
    }

    func ponerModoAnillo(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "voz_modo_anillo")
        if on {
            // El permiso del micrófono se pide ahora, con la app abierta: con el teléfono bloqueado iOS no puede preguntar.
            AVAudioSession.sharedInstance().requestRecordPermission { _ in }
            prepararMandos(); quedarLista()
        } else { terminar(); apagar() }
    }

    func arrancarSiHaceFalta() {
        let d = UserDefaults.standard
        if d.bool(forKey: "voz_abierta") {   // la app se cerró a media conversación (iOS la volvió a abrir por el anillo)
            d.set("Alma se cerró sola en el paso: " + (d.string(forKey: "voz_paso") ?? "?"), forKey: "voz_ultimo_error"); d.set(false, forKey: "voz_abierta")
        }
        if modoAnillo { prepararMandos(); quedarLista() }
    }

    /// Lo último que hizo la voz (se ve en Ajustes y ayuda a saber dónde se queda).
    private func paso(_ t: String) {
        let d = UserDefaults.standard; d.set(t, forKey: "voz_paso")
        var lista = d.stringArray(forKey: "voz_pasos") ?? []
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        lista.append(f.string(from: Date()) + " " + t); d.set(Array(lista.suffix(14)), forKey: "voz_pasos")
        emitir(["tipo": "paso", "texto": t])
    }

    /// Doble toque del anillo (o el botón de la página): habla o pausa.
    func alternar() {
        switch estado {
        case .hablando, .conectando: terminar()
        case .lista, .apagada: hablar()
        }
    }

    var resumen: [String: Any] { ["tipo": "estado", "estado": estado.rawValue, "modoAnillo": modoAnillo, "ultimoError": UserDefaults.standard.string(forKey: "voz_ultimo_error") ?? "",
                                  "pasos": UserDefaults.standard.stringArray(forKey: "voz_pasos") ?? [],
                                  "microfono": AVAudioSession.sharedInstance().recordPermission == .granted ? "si" : AVAudioSession.sharedInstance().recordPermission == .denied ? "no" : "sin preguntar"] }
    static let opciones: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]

    // MARK: - Estar lista (audio en silencio + mandos de la pantalla de bloqueo)

    private func quedarLista() {
        guard estado != .hablando, estado != .conectando else { return }
        do {
            let s = AVAudioSession.sharedInstance()
            // Desde que queda lista ya es «hablar y escuchar»: con la pantalla bloqueada iOS no deja cambiar a micrófono después.
            try s.setCategory(.playAndRecord, mode: .default, options: VozNativa.opciones)
            try s.setActive(true)
        } catch {}
        if silencio == nil, let wav = VozNativa.wavSilencio() { silencio = try? AVAudioPlayer(data: wav); silencio?.numberOfLoops = -1; silencio?.volume = 0.01 }
        silencio?.play()
        estado = .lista
        encenderMicrofono()
    }

    /// iOS no deja *empezar* a usar el micrófono con el teléfono bloqueado; sí deja seguir usándolo.
    /// Por eso, con «Alma con el anillo», el micrófono queda abierto desde que la app está a la vista (no se manda nada
    /// hasta el doble toque) y sigue listo al bloquear.
    private func encenderMicrofono() {
        if engine.isRunning { infoBloqueo("Toca dos veces tu anillo para hablar"); return }
        guard UIApplication.shared.applicationState != .background else {
            paso("Esperando a que abras Alma para dejar el micrófono listo")
            infoBloqueo("Abre Alma una vez para dejarla lista"); return
        }
        do { try prepararMotor(); paso("Micrófono listo para el anillo"); infoBloqueo("Toca dos veces tu anillo para hablar") }
        catch { paso("No pude dejar listo el micrófono (\((error as NSError).code))"); infoBloqueo("Abre Alma para dejarla lista") }
    }

    private func apagar() {
        silencio?.stop()
        engine.inputNode.removeTap(onBus: 0); player.stop(); if engine.isRunning { engine.stop() }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        estado = .apagada
    }

    private var mandosListos = false
    private func prepararMandos() {
        guard !mandosListos else { return }; mandosListos = true
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let t = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, t == AVAudioSession.InterruptionType.began.rawValue else { return }
            if self.estado == .hablando || self.estado == .conectando { self.fallo("Otra app o una llamada tomó el audio.") }
        }
        // Al abrir la app (o al volver a ella) el micrófono queda listo otra vez.
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.modoAnillo, self.estado == .lista || self.estado == .apagada else { return }
            self.quedarLista()
        }
        // Si iOS reinicia el audio (cambio de audífonos, por ejemplo), se vuelve a encender.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, self.modoAnillo, !self.engine.isRunning else { return }
            try? self.prepararMotor()
        }
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
        UserDefaults.standard.set([String](), forKey: "voz_pasos"); UserDefaults.standard.set(true, forKey: "voz_abierta")
        paso("Pidiendo tu ficha al Hub" + (UIApplication.shared.applicationState == .active ? "" : " (en segundo plano)"))
        estado = .conectando
        AudioServicesPlaySystemSound(1113)
        infoBloqueo("Conectando…")
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["hub": 1, "action": "vozWeb", "token": token, "session": sesion])
        URLSession.shared.dataTask(with: r) { [weak self] data, resp, err in
            guard let self else { return }
            guard let d = data, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], (j["ok"] as? Bool) == true,
                  let agente = j["agent_id"] as? String else {
                let por = err?.localizedDescription ?? (data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["error"] as? String) ?? "sin respuesta del Hub"
                DispatchQueue.main.async { self.fallo("No pude pedir tu ficha: \(por)") }; return
            }
            DispatchQueue.main.async { self.paso("Ficha lista" + (j["signed_url"] != nil ? " (URL firmada)" : "")); self.conectar(agente: agente, ficha: j) }
        }.resume()
    }

    private func conectar(agente: String, ficha: [String: Any]) {
        guard estado == .conectando else { return }
        do {
            let s = AVAudioSession.sharedInstance()
            guard s.recordPermission == .granted else { fallo("Falta el permiso del micrófono: Ajustes del iPhone → Alma → Micrófono."); return }
            if !engine.isRunning {
                guard UIApplication.shared.applicationState != .background else {
                    fallo("Abre Alma una vez para dejar el micrófono listo; después funciona bloqueado."); return
                }
                paso("Abriendo el micrófono")
                try s.setCategory(.playAndRecord, mode: .default, options: VozNativa.opciones)
                try s.setActive(true)
                try prepararMotor()
            }
            paso("Micrófono abierto · conectando la voz")
        } catch { fallo("No pude abrir el micrófono (\((error as NSError).code))."); return }
        let firmada = (ficha["signed_url"] as? String).flatMap { URL(string: $0) }
        guard let u = firmada ?? URL(string: "wss://api.elevenlabs.io/v1/convai/conversation?agent_id=\(agente)") else { return }
        var pedido = URLRequest(url: u); pedido.setValue("https://hub.spacioam.com", forHTTPHeaderField: "Origin")
        let sesion = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        sesionURL = sesion
        let t = sesion.webSocketTask(with: pedido); ws = t; t.resume()
        // Si en 12 s Alma no contestó, se avisa (y no queda «Conectando…» para siempre).
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in if self?.estado == .conectando { self?.fallo("Alma no contestó. Revisa tu internet.") } }
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

    /// Abre el micrófono. Primero con cancelación de eco; si iOS la rechaza (error «what»), sin ella: así Alma igual escucha.
    private func prepararMotor() throws {
        if !motorListo { engine.attach(player); motorListo = true }
        if !sinEco {
            do { try armarMotor(eco: true); return }
            catch {
                paso("La cancelación de eco falló (\((error as NSError).code)); abro el micrófono sin ella")
                engine.inputNode.removeTap(onBus: 0); engine.stop(); engine.reset()
                sinEco = true
            }
        }
        try armarMotor(eco: false)
    }

    private func armarMotor(eco: Bool) throws {
        if engine.inputNode.isVoiceProcessingEnabled != eco { try engine.inputNode.setVoiceProcessingEnabled(eco) }
        engine.connect(player, to: engine.mainMixerNode, format: formatoSalida)
        let fIn = engine.inputNode.outputFormat(forBus: 0)
        guard fIn.sampleRate > 0, fIn.channelCount > 0, let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: fIn.sampleRate, channels: 1, interleaved: false) else {
            throw NSError(domain: "Alma", code: -1, userInfo: [NSLocalizedDescriptionKey: "el micrófono no está disponible"])
        }
        formatoMono = mono
        convertidor = AVAudioConverter(from: mono, to: formatoEntrada)
        engine.inputNode.removeTap(onBus: 0)
        engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: fIn) { [weak self] buf, _ in self?.microfono(buf) }
        if !engine.isRunning { engine.prepare(); try engine.start() }
        player.play()
    }

    private func microfono(_ buf: AVAudioPCMBuffer) {
        guard estado == .hablando, let conv = convertidor, let mf = formatoMono, let src = buf.floatChannelData,
              let mono = AVAudioPCMBuffer(pcmFormat: mf, frameCapacity: buf.frameLength), let dst = mono.floatChannelData else { return }
        mono.frameLength = buf.frameLength
        dst[0].update(from: src[0], count: Int(buf.frameLength))   // primer canal
        let cap = AVAudioFrameCount(Double(buf.frameLength) * 16000 / buf.format.sampleRate) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: formatoEntrada, frameCapacity: cap) else { return }
        var dado = false
        conv.convert(to: out, error: nil) { _, st in
            if dado { st.pointee = .noDataNow; return nil }
            dado = true; st.pointee = .haveData; return mono
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
            case .failure(let e):
                DispatchQueue.main.async {
                    if self.estado == .conectando || self.estado == .hablando { self.fallo("La voz se cortó: \(e.localizedDescription)") }
                }
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
            paso("Alma conectada · te escucha")
            infoBloqueo("Te escucho · dos toques para pausar")
            if let id = ev["conversation_id"] as? String { vincular(id) }
        case "audio":
            let ev = j["audio_event"] as? [String: Any] ?? [:]
            if let b = ev["audio_base_64"] as? String, let d = Data(base64Encoded: b) { if !sono { sono = true; paso("Alma está hablando") }; sonar(d) }
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
        if habia { paso("Pausa") }
        UserDefaults.standard.set(false, forKey: "voz_abierta"); sono = false
        ws?.cancel(with: .normalClosure, reason: nil); ws = nil
        sesionURL?.invalidateAndCancel(); sesionURL = nil
        player.stop()
        if modoAnillo { player.play() }   // el micrófono sigue listo para el próximo doble toque
        else { engine.inputNode.removeTap(onBus: 0); if engine.isRunning { engine.stop() } }
        if habia { AudioServicesPlaySystemSound(1114) }
        estado = .apagada
        if modoAnillo { quedarLista() } else { apagar() }
    }

    private func fallo(_ m: String) {
        paso("Error: " + m)
        UserDefaults.standard.set(m, forKey: "voz_ultimo_error")
        emitir(["tipo": "error", "mensaje": m])
        terminar()
        infoBloqueo(m)   // se ve en la pantalla de bloqueo
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in if self?.estado == .lista { self?.infoBloqueo("Toca dos veces tu anillo para hablar") } }
    }

    func urlSession(_ s: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith code: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let por = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        if estado == .conectando || estado == .hablando { fallo("ElevenLabs cerró la voz (\(code.rawValue)) \(por)") }
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
