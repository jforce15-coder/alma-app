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
/// · Más rápido: la ficha y la URL firmada quedan pedidas de antemano (cada 9 min); al doble toque suena la señal
///   enseguida y lo que dices se guarda mientras conecta.
/// · Pausa: dos toques mientras hablan pausan (Alma espera). Otros dos la retoman. Si no se retoma en 25 s, lo dicho se
///   toma como enviado: Alma responde y la conversación se cierra sola.
/// · Avisos al oído: cada 45 s pregunta al Hub si Alma terminó algo (segundo plano, Claude). Suena la señal y Alma lo dice
///   con su voz; si tocas dos veces en los 5 min siguientes, la conversación retoma ese aviso.
final class VozNativa: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    static let shared = VozNativa()

    enum Estado: String { case apagada, lista, conectando, hablando }
    @Published private(set) var estado: Estado = .apagada { didSet { avisar(); if estado != .hablando { nivel = 0 } } }
    /// Para la pantalla de la llamada: cuánto suena la voz (0…1), quién habla y lo último que se dijo.
    @Published private(set) var nivel: CGFloat = 0
    @Published private(set) var almaHabla = false
    struct Linea: Identifiable { let id: Int; let alma: Bool; let texto: String }
    @Published private(set) var lineas: [Linea] = []
    private var campanas: [String: AVAudioPlayer] = [:]
    private var finHabla: DispatchWorkItem?
    private var contador = 0
    private func linea(_ alma: Bool, _ t: String) { contador += 1; lineas = Array((lineas + [Linea(id: contador, alma: alma, texto: t)]).suffix(6)) }
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
    private var sinEco = false
    private var vozEnviada = 0.0          // segundos de tu voz mandados a Alma en este tramo
    private var ultimaVoz = Date.distantPast
    private var vigia: Timer?   // si la cancelación de eco falló una vez, ya no se intenta
    private var sono = false
    // ficha pedida de antemano (la URL firmada de ElevenLabs dura ~15 min; se usa si tiene menos de 9)
    private var fichaLista: (j: [String: Any], t: Date)?
    private var pidiendoFicha = false
    private var precarga: Timer?
    private var colaVoz: [String] = []      // lo que dices mientras conecta
    // pausa: Alma espera; si no se retoma en 25 s, responde a lo dicho y se cierra
    @Published private(set) var pausada = false
    private var pausaT: DispatchWorkItem?
    private var cerrarTrasRespuesta = false
    private var desdeCierre = Date.distantPast
    private var ultimoAudioAlma = Date.distantPast
    // avisos al oído
    private var avisosT: Timer?
    private var avisoPlayer: AVAudioPlayer?
    private var ultimoAviso: (texto: String, t: Date)?

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
        case .hablando: if cerrarTrasRespuesta { terminar() } else if pausada { reanudar() } else { pausar() }
        case .conectando: terminar()
        case .lista, .apagada: hablar()
        }
    }

    /// «Terminar» en la pantalla: cierra la conversación (el doble toque, en cambio, pausa).
    func colgar() { if estado == .hablando || estado == .conectando { terminar() } }

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
        precargarSiToca()
        if precarga == nil { precarga = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.precargarSiToca() } }
        if avisosT == nil { avisosT = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in self?.buscarAvisos() } }
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
        precarga?.invalidate(); precarga = nil; avisosT?.invalidate(); avisosT = nil; fichaLista = nil
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
            guard let self, self.modoAnillo else { return }
            self.paso("iOS reacomodó el audio" + (self.engine.isRunning ? "" : " y apagó el micrófono"))
            self.revivirMicrofono()
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, self.estado == .hablando, let r = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt else { return }
            let salida = AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? "?"
            self.paso("Cambió la salida de audio (motivo \(r)) → \(salida)")
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
        UserDefaults.standard.set([String](), forKey: "voz_pasos"); UserDefaults.standard.set(true, forKey: "voz_abierta"); lineas = []
        estado = .conectando; colaVoz = []; pausada = false; cerrarTrasRespuesta = false
        sonido("alma-inicio")   // la señal suena ya: lo que digas se guarda mientras conecta
        infoBloqueo("Te escucho…")
        if let f = fichaLista, Date().timeIntervalSince(f.t) < 540 {
            fichaLista = nil; paso("Ficha lista de antemano"); conectar(agente: f.j["agent_id"] as? String ?? "", ficha: f.j); return
        }
        paso("Pidiendo tu ficha al Hub" + (UIApplication.shared.applicationState == .active ? "" : " (en segundo plano)"))
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
        dv["quien_llama"] = ((dv["quien_llama"] as? String) ?? "") + "\n\nMODO ANILLO: Juan te habla desde su anillo, casi siempre con el teléfono bloqueado (solo voz, sin pantalla). Ya sonó la señal: NO saludes ni hables primero. Escucha. Habla en tramos, con pausas, como quien piensa en voz alta: mientras no haya pedido algo concreto o su idea quede a medias, usa skip_turn y sigue escuchando; junta todo lo que dijo como un solo mensaje. Responde solo cuando ya pidió algo claro o terminó de hablar. Respuestas cortas, claras y cálidas."
        if let a = ultimoAviso, Date().timeIntervalSince(a.t) < 300 {
            let min = max(1, Int(Date().timeIntervalSince(a.t) / 60))
            dv["quien_llama"] = ((dv["quien_llama"] as? String) ?? "") + "\n\nRETOMA UN AVISO: hace \(min) min le dijiste al oído: «\(a.texto)». Tocó el anillo para retomarlo: si lo primero que dice no es otra cosa, sigue con ese tema (sin repetir el aviso completo)."
            ultimoAviso = nil
        }
        var agent: [String: Any] = [:]
        agent["first_message"] = ""   // modo anillo: Alma no saluda; solo suena la señal y escucha
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
        guard estado == .hablando || estado == .conectando, !pausada, let conv = convertidor, let mf = formatoMono, let src = buf.floatChannelData,
              let mono = AVAudioPCMBuffer(pcmFormat: mf, frameCapacity: buf.frameLength), let dst = mono.floatChannelData else { return }
        mono.frameLength = buf.frameLength
        dst[0].update(from: src[0], count: Int(buf.frameLength))   // primer canal
        var e: Float = 0; for i in 0..<Int(buf.frameLength) { e += src[0][i] * src[0][i] }
        let rmsTu = sqrt(e / Float(max(1, buf.frameLength)))
        let cap = AVAudioFrameCount(Double(buf.frameLength) * 16000 / buf.format.sampleRate) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: formatoEntrada, frameCapacity: cap) else { return }
        var dado = false
        conv.convert(to: out, error: nil) { _, st in
            if dado { st.pointee = .noDataNow; return nil }
            dado = true; st.pointee = .haveData; return mono
        }
        guard out.frameLength > 0, let p = out.int16ChannelData else { return }
        let datos = Data(bytes: p[0], count: Int(out.frameLength) * 2)
        let seg = Double(out.frameLength) / 16000
        DispatchQueue.main.async {
            if self.estado == .conectando { if self.colaVoz.count < 80 { self.colaVoz.append(datos.base64EncodedString()) }; return }
            self.vozEnviada += seg; self.ultimaVoz = Date(); self.mandar(["user_audio_chunk": datos.base64EncodedString()])
            if !self.almaHabla { self.nivel = min(1, CGFloat(rmsTu) * 9) }
        }
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
            vigilar()
            paso("Alma conectada · te escucha" + (colaVoz.isEmpty ? "" : String(format: " (%.1f s dichos mientras conectaba)", Double(colaVoz.count) * 0.128)))
            for c in colaVoz { mandar(["user_audio_chunk": c]) }; colaVoz = []
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
            if let t = ev["agent_response"] as? String { emitir(["tipo": "alma", "texto": t]); linea(true, t) }
        case "user_transcript":
            let ev = j["user_transcription_event"] as? [String: Any] ?? [:]
            if let t = ev["user_transcript"] as? String { emitir(["tipo": "yo", "texto": t]); linea(false, t) }
        default: break
        }
    }

    private func sonar(_ pcm16: Data) {
        let n = pcm16.count / 2
        guard n > 0, let buf = AVAudioPCMBuffer(pcmFormat: formatoSalida, frameCapacity: AVAudioFrameCount(n)), let ch = buf.floatChannelData else { return }
        buf.frameLength = AVAudioFrameCount(n)
        var e: Float = 0
        pcm16.withUnsafeBytes { (r: UnsafeRawBufferPointer) in
            let s = r.bindMemory(to: Int16.self)
            for i in 0..<n { let v = Float(Int16(littleEndian: s[i])) / 32768; ch[0][i] = v; e += v * v }
        }
        // Alma habla mientras suena este trozo: el círculo late con su voz
        let dur = Double(n) / formatoSalida.sampleRate, nv = min(1, CGFloat(sqrt(e / Float(n))) * 6)
        almaHabla = true; nivel = nv; ultimoAudioAlma = Date()
        finHabla?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.almaHabla = false; self?.nivel = 0 }
        finHabla = w; DispatchQueue.main.asyncAfter(deadline: .now() + dur + 0.25, execute: w)
        player.scheduleBuffer(buf, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    /// Los sonidos de Alma (Recursos/Sonidos): calma primero, tecnología después.
    private func sonido(_ n: String) {
        if campanas[n] == nil, let u = Bundle.main.url(forResource: n, withExtension: "wav") { campanas[n] = try? AVAudioPlayer(contentsOf: u) }
        campanas[n]?.volume = 0.9; campanas[n]?.currentTime = 0; campanas[n]?.play()
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

    /// Mientras hablan: cada 10 s anota cuánta voz llegó; si el micrófono calla más de 3 s, lo vuelve a abrir.
    private func vigilar() {
        vigia?.invalidate(); vozEnviada = 0; ultimaVoz = Date()
        var tramo = 0
        vigia = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self, self.estado == .hablando else { t.invalidate(); return }
            tramo += 1
            if self.cerrarTrasRespuesta {   // pausa sin retomar: cuando Alma terminó de responder (o a los 45 s), se cierra
                let callada = Date().timeIntervalSince(self.ultimoAudioAlma) > 5 && self.ultimoAudioAlma > self.desdeCierre
                if (callada && !self.almaHabla) || Date().timeIntervalSince(self.desdeCierre) > 45 { self.terminar() }
                return
            }
            if self.pausada { self.ultimaVoz = Date(); return }
            if Date().timeIntervalSince(self.ultimaVoz) > 3 {
                self.paso("El micrófono dejó de mandar voz (motor " + (self.engine.isRunning ? "encendido" : "apagado") + ")")
                self.ultimaVoz = Date()
                self.revivirMicrofono()
            }
            if tramo % 10 == 0 { self.paso(String(format: "Voz enviada: %.1f s en 10 s", self.vozEnviada)); self.vozEnviada = 0 }
        }
    }

    private func revivirMicrofono() {
        do { try prepararMotor(); paso("Micrófono abierto otra vez") }
        catch {
            paso("No pude volver a abrir el micrófono (\((error as NSError).code))")
            if estado == .hablando { fallo("iOS apagó el micrófono y no dejó volver a abrirlo. Abre Alma y vuelve a intentar.") }
        }
    }

    private func terminar() {
        vigia?.invalidate(); vigia = nil
        pausaT?.cancel(); pausaT = nil; pausada = false; cerrarTrasRespuesta = false; colaVoz = []
        let habia = estado == .hablando || estado == .conectando
        if habia { paso("Pausa") }
        UserDefaults.standard.set(false, forKey: "voz_abierta"); sono = false
        ws?.cancel(with: .normalClosure, reason: nil); ws = nil
        sesionURL?.invalidateAndCancel(); sesionURL = nil
        player.stop()
        if modoAnillo { player.play() }   // el micrófono sigue listo para el próximo doble toque
        else { engine.inputNode.removeTap(onBus: 0); if engine.isRunning { engine.stop() } }
        if habia { sonido("alma-fin") }
        estado = .apagada
        if modoAnillo { quedarLista(); DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.fichaLista = nil; self?.precargarSiToca() } }
        else { apagar() }
    }

    // MARK: - Pausa

    private func pausar() {
        pausada = true; paso("Pausa · Alma espera")
        mandar(["type": "contextual_update", "text": "PAUSA: Juan tocó el anillo para pausar (está pensando o lo interrumpieron). No hables ni respondas hasta que retome."])
        sonido("alma-fin"); infoBloqueo("En pausa · dos toques para seguir")
        let w = DispatchWorkItem { [weak self] in self?.pausaVencida() }
        pausaT = w; DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: w)
    }
    private func reanudar() {
        pausaT?.cancel(); pausaT = nil; pausada = false; ultimaVoz = Date(); paso("Sigue la conversación")
        mandar(["type": "contextual_update", "text": "SIGUE: Juan retomó; sigue escuchando donde iba."])
        sonido("alma-inicio"); infoBloqueo("Te escucho · dos toques para pausar")
    }
    /// 25 s en pausa: lo dicho se toma como enviado. Alma responde y la conversación se cierra sola al terminar.
    private func pausaVencida() {
        guard estado == .hablando, pausada else { return }
        paso("Pausa larga · Alma responde a lo dicho y cierra")
        cerrarTrasRespuesta = true; desdeCierre = Date()
        mandar(["type": "user_message", "text": "(Terminé de hablar. Responde ahora, breve, a lo que te pedí; si ya no hay nada pendiente, despídete en una frase.)"])
        infoBloqueo("Alma te responde…")
    }

    // MARK: - Más rápido: la ficha pedida de antemano

    private func precargarSiToca() {
        guard modoAnillo, !pidiendoFicha, estado == .lista || estado == .apagada else { return }
        if let f = fichaLista, Date().timeIntervalSince(f.t) < 480 { return }
        guard let url = Llave.leer("voz_url"), let token = Llave.leer("voz_token"), let sesion = Llave.leer("voz_sesion"), let u = URL(string: url) else { return }
        pidiendoFicha = true
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["hub": 1, "action": "vozWeb", "token": token, "session": sesion])
        URLSession.shared.dataTask(with: r) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self else { return }; self.pidiendoFicha = false
                guard let d = data, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], (j["ok"] as? Bool) == true, j["agent_id"] is String else { return }
                self.fichaLista = (j, Date())
            }
        }.resume()
    }

    // MARK: - Avisos al oído

    private func buscarAvisos() {
        guard modoAnillo, estado == .lista || estado == .apagada,
              let url = Llave.leer("voz_url"), let token = Llave.leer("voz_token"), let sesion = Llave.leer("voz_sesion"), let u = URL(string: url) else { return }
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type"); r.timeoutInterval = 40
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["hub": 1, "action": "vozAvisos", "token": token, "session": sesion])
        URLSession.shared.dataTask(with: r) { [weak self] data, _, _ in
            guard let d = data, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let l = j["avisos"] as? [[String: Any]], !l.isEmpty else { return }
            DispatchQueue.main.async { self?.decirAvisos(l) }
        }.resume()
    }
    private func decirAvisos(_ l: [[String: Any]]) {
        guard estado == .lista || estado == .apagada, let a = l.first else { return }
        let texto = a["texto"] as? String ?? ""
        ultimoAviso = (texto, Date()); paso("Aviso al oído: " + String(texto.prefix(60)))
        infoBloqueo("Alma: " + texto)
        sonido("alma-inicio")
        let resto = Array(l.dropFirst())
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self else { return }
            if let b = a["audio"] as? String, let mp3 = Data(base64Encoded: b), let pl = try? AVAudioPlayer(data: mp3) {
                self.avisoPlayer = pl; pl.volume = 1; pl.play()
                if !resto.isEmpty { DispatchQueue.main.asyncAfter(deadline: .now() + pl.duration + 1.2) { self.decirAvisos(resto) } }
            } else if !resto.isEmpty { self.decirAvisos(resto) }
        }
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
