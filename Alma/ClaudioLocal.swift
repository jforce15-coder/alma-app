import AVFoundation
import Speech

/// Claudio local (Hub #629; Juan, 16-nov-2026: «configurar la voz de Claudio para que sea local, imitando la voz, patrones y
/// system prompt de ElevenLabs, para no consumir créditos en sesiones extensas de trabajo»).
/// La conversación con Claudio sin ElevenLabs:
///   · oído: el dictado del iPhone, en el teléfono cuando se puede (lo mismo que el modo conferencia);
///   · cabeza: el Hub (acción claudioLocal), con el mismo prompt, la misma ficha y las mismas herramientas de Claudio;
///   · voz: la misma de Claudio en ElevenLabs (Hub #636): el Hub manda cada frase ya dicha con su voz y aquí solo suena.
///     Si no llega (ElevenLabs falló), una voz de hombre del iPhone afinada como la de Claudio (voz_local del Hub).
/// VozNativa no cambia su manera de llevar la llamada: esta clase habla el mismo idioma que el socket de ElevenLabs
/// (recibe user_audio_chunk y devuelve conversation_initiation_metadata, audio, user_transcript, agent_response,
/// agent_tool_request/response y client_tool_call de volver_con_alma). Así el halo naranja, el Panel de Claudio, la vuelta
/// con Alma, el sueño del Modo calle y la conferencia siguen igual.
/// Turnos: Juan habla → pausa → el Hub contesta → Claudio habla → vuelve a escuchar. Mientras Claudio piensa o habla, lo del
/// micrófono no cuenta (así no se oye a sí mismo); para cortarlo, se espera a que termine su frase (son cortas).
/// Si el dictado no tiene permiso o no está disponible, no se crea (init devuelve nil) y la llamada sigue con ElevenLabs.
/// Voz de respaldo de Alma (Hub #657, RespaldoVoz.swift): el mismo motor, con init(respaldo:). Oye el dictado del iPhone (en
/// el teléfono, sirve sin internet), contesta el Hub con la acción «calle» (solo texto) y habla una voz de mujer del iPhone.
/// Sin internet, lo que dice Juan se guarda y se manda solo cuando vuelve.
final class ClaudioLocal: NSObject {
    /// Los eventos para VozNativa, siempre en el hilo principal.
    var alEvento: (([String: Any]) -> Void)?
    var paso: ((String) -> Void)?

    private let conv: String, saludo: String
    /// Es la voz de respaldo de Alma (no Claudio): otra cabeza (acción «calle») y otra voz.
    let respaldo: Bool
    /// Respaldo: lo que Juan dijo sin internet, por mandar.
    private var cola: [String] = []
    private let saludoAudio: Data?
    private let ajustes: ClaudioLocalReglas.Ajustes
    private let reconocedor: SFSpeechRecognizer
    private let voz: AVSpeechSynthesisVoice?
    private let sintetizador = AVSpeechSynthesizer()
    private let formatoOido = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    private let formatoVoz = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    private var convertidor: AVAudioConverter?

    private var pedido: SFSpeechAudioBufferRecognitionRequest?
    private var tarea: SFSpeechRecognitionTask?
    private var vuelta = 0
    private var texto = "", ultimoCambio = Date(), empezo = Date(), desdePedido = Date()
    private var historial: [ClaudioLocalReglas.Turno] = []
    private var notas: [String] = []
    private var ocupadoHasta = Date.distantFuture   // piensa o habla: el micrófono no cuenta (hasta que termine el saludo)
    private var pensando = false
    private var reloj: Timer?
    private var relojTecleo: Timer?, desdeTurno = Date(), teclas: UInt64 = 0
    private var vivo = true
    private var llamadas = 0

    init?(ficha: [String: Any]) {
        guard (ficha["local"] as? Bool) == true, let c = ficha["conv_id"] as? String, c.hasPrefix("conv_local_"),
              SFSpeechRecognizer.authorizationStatus() == .authorized,
              let r = SFSpeechRecognizer(locale: Locale(identifier: "es-MX")), r.isAvailable else { return nil }
        conv = c; reconocedor = r; respaldo = false
        saludo = ficha["first_message"] as? String ?? AgenteVoz.saludoClaudio
        ajustes = ClaudioLocalReglas.Ajustes(ficha["voz_local"] as? [String: Any])
        saludoAudio = ClaudioLocalReglas.audio(ficha["voz_local"] as? [String: Any])
        voz = ClaudioLocal.elegirVoz(ajustes)
        super.init()
    }

    /// La voz de respaldo de Alma: abre con `frase` («Se me fue el internet…») y sigue con la voz del iPhone.
    init?(respaldo frase: String) {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              let r = SFSpeechRecognizer(locale: Locale(identifier: "es-MX")), r.isAvailable || r.supportsOnDeviceRecognition else { return nil }
        conv = "respaldo_" + UUID().uuidString.prefix(8).lowercased(); reconocedor = r; respaldo = true
        saludo = frase; saludoAudio = nil
        ajustes = ClaudioLocalReglas.Ajustes(RespaldoVoz.voz)
        voz = ClaudioLocal.elegirVoz(ajustes)
        super.init()
    }

    /// Respaldo: ¿está pensando o hablando? (Mientras, no se vuelve a ElevenLabs.) ¿Cuánto queda guardado por mandar?
    var ocupada: Bool { pensando || Date() < ocupadoHasta || !texto.isEmpty }   // con texto: Juan está a media frase
    var pendientes: Int { cola.count }

    /// Para el registro: «Juan · es-MX · hombre · mejorada · dictado en el teléfono».
    var descripcion: String {
        let v = voz.map { v -> String in
            let calidad: String
            switch v.quality { case .premium: calidad = "premium"; case .enhanced: calidad = "mejorada"; default: calidad = "normal" }
            return v.name + " · " + v.language + " · " + (v.gender == .male ? "hombre" : v.gender == .female ? "mujer" : "sin género") + " · " + calidad
        } ?? "la de por defecto"
        return (saludoAudio != nil ? "voz de ElevenLabs (respaldo: " + v + ")" : v) + (reconocedor.supportsOnDeviceRecognition ? " · dictado en el teléfono" : " · dictado de Apple")
    }

    private static func elegirVoz(_ a: ClaudioLocalReglas.Ajustes) -> AVSpeechSynthesisVoice? {
        let todas = AVSpeechSynthesisVoice.speechVoices()
        let lista = todas.map { v -> ClaudioLocalReglas.Voz in
            let calidad: Int
            switch v.quality { case .premium: calidad = 0; case .enhanced: calidad = 1; default: calidad = 2 }
            return ClaudioLocalReglas.Voz(id: v.identifier, idioma: v.language, hombre: v.gender == .male, calidad: calidad,
                                          rara: v.voiceTraits.contains(.isNoveltyVoice) || v.voiceTraits.contains(.isPersonalVoice))
        }
        guard let e = ClaudioLocalReglas.elegir(lista, a) else { return AVSpeechSynthesisVoice(language: a.idiomas.first ?? "es-MX") }
        return AVSpeechSynthesisVoice(identifier: e.id)
    }

    // MARK: - Lo que pide VozNativa

    /// Como si ElevenLabs hubiera conectado: la conversación (para el Panel de Claudio) y la voz en 16 kHz. Después, el saludo.
    func empezar() {
        emitir(["type": "conversation_initiation_metadata",
                "conversation_initiation_metadata_event": ["conversation_id": conv, "agent_output_audio_format": "pcm_16000"]])
        paso?((respaldo ? "Voz de respaldo · " : "Claudio local · ") + descripcion)
        historial = ClaudioLocalReglas.sumar(historial, .init(deClaudio: true, texto: saludo))
        decir(saludo, audio: saludoAudio)
        reloj = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.revisar() }
    }

    /// Lo que VozNativa le mandaría al socket: el micrófono, un texto de Juan o una nota de la app. Lo demás no aplica.
    func recibir(_ o: [String: Any]) {
        guard vivo else { return }
        if let b = o["user_audio_chunk"] as? String { if let d = Data(base64Encoded: b) { oir(d) }; return }
        switch o["type"] as? String ?? "" {
        case "user_message": if let t = o["text"] as? String { turno(t) }
        case "contextual_update": if let t = o["text"] as? String { notas = Array((notas + [String(t.prefix(400))]).suffix(3)) }
        default: break
        }
    }

    func parar() {
        vivo = false
        reloj?.invalidate(); reloj = nil
        pararTecleo()
        soltarPedido()
        sintetizador.stopSpeaking(at: .immediate)
    }

    // MARK: - Oír

    private func oir(_ d: Data) {
        guard !pensando, Date() >= ocupadoHasta, let p = pedido else { return }
        let n = d.count / 2
        guard n > 0, let buf = AVAudioPCMBuffer(pcmFormat: formatoOido, frameCapacity: AVAudioFrameCount(n)), let ch = buf.floatChannelData else { return }
        buf.frameLength = AVAudioFrameCount(n)
        d.withUnsafeBytes { (r: UnsafeRawBufferPointer) in
            let s = r.bindMemory(to: Int16.self)
            for i in 0..<n { ch[0][i] = Float(Int16(littleEndian: s[i])) / 32768 }
        }
        p.append(buf)
    }

    /// Un dictado nuevo para la próxima frase de Juan.
    private func nuevoPedido() {
        soltarPedido()
        let p = SFSpeechAudioBufferRecognitionRequest(); p.shouldReportPartialResults = true
        if reconocedor.supportsOnDeviceRecognition { p.requiresOnDeviceRecognition = true }
        if #available(iOS 16, *) { p.addsPunctuation = true }
        p.contextualStrings = ["Claudio", "Alma", "une", "únelo", "súbelo", "Opus", "Sonnet", "Hub", "órbita", "Pendientes"]
        pedido = p
        vuelta += 1; let mia = vuelta
        texto = ""; ultimoCambio = Date(); empezo = Date(); desdePedido = Date()
        tarea = reconocedor.recognitionTask(with: p) { [weak self] r, e in
            DispatchQueue.main.async {
                guard let self, self.vivo, self.vuelta == mia, !self.pensando else { return }
                if let r {
                    let t = r.bestTranscription.formattedString
                    if self.texto.isEmpty && !t.isEmpty { self.empezo = Date() }
                    if t != self.texto { self.texto = t; self.ultimoCambio = Date() }
                    if r.isFinal { self.cerrarFrase() }
                } else if e != nil {
                    // Sin voz por un rato (o el dictado se cansó): si ya dijo algo, eso va; si no, se vuelve a escuchar (con un
                    // respiro, para no dar vueltas si el dictado falla al instante).
                    if !self.texto.isEmpty { self.cerrarFrase(); return }
                    self.soltarPedido()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                        guard let self, self.vivo, !self.pensando, self.pedido == nil, Date() >= self.ocupadoHasta else { return }
                        self.nuevoPedido()
                    }
                }
            }
        }
    }

    private func revisar() {
        guard vivo, !pensando, Date() >= ocupadoHasta else { return }
        if pedido == nil { nuevoPedido(); return }
        if ClaudioLocalReglas.termino(texto: texto, ultimoCambio: ultimoCambio, empezo: empezo, ahora: Date()) { cerrarFrase(); return }
        // Respaldo: volvió el internet y hay algo guardado (y Juan no está hablando): se manda solo.
        if respaldo, !cola.isEmpty, texto.isEmpty, Conexion.shared.hayRed {
            let piezas = cola; cola = []
            paso?("Voz de respaldo: volvió el internet, mando lo guardado (\(piezas.count))")
            pedirRespaldo(RespaldoVoz.juntar(piezas), piezas: piezas)
            return
        }
        // El dictado de Apple escucha como un minuto por pedido: callado, se renueva antes.
        if texto.isEmpty && Date().timeIntervalSince(desdePedido) > 50 { nuevoPedido() }
    }

    private func cerrarFrase() {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        texto = ""; soltarPedido()
        if t.isEmpty { nuevoPedido(); return }
        turno(t)
    }

    // MARK: - Pensar (el Hub)

    private func turno(_ t: String) {
        guard vivo, !pensando else { return }
        if respaldo {
            emitir(["type": "user_transcript", "user_transcription_event": ["user_transcript": t]])
            if !Conexion.shared.hayRed {
                let g = RespaldoVoz.guardar(cola, t); cola = g.cola
                paso?("Voz de respaldo: sin internet, lo guardo (\(cola.count) por mandar)")
                decir(RespaldoVoz.trasGuardar(cuantas: cola.count, cupo: g.cupo))
                return
            }
            pedirRespaldo(t, piezas: [t]); return
        }
        pensando = true
        empezarTecleo()
        emitir(["type": "user_transcript", "user_transcription_event": ["user_transcript": t]])
        emitir(["type": "agent_tool_request", "agent_tool_request": ["tool_name": "claudio_local"]])   // trabaja: no se cuelga por silencio
        let conNotas = notas.isEmpty ? t : t + "\n(Nota de la app: " + notas.joined(separator: " · ") + ")"
        notas = []
        let previos = historial
        historial = ClaudioLocalReglas.sumar(historial, .init(deClaudio: false, texto: t))
        guard let url = Llave.leer("voz_url"), let token = Llave.leer("voz_token"), let sesion = Llave.leer("voz_sesion"), let u = URL(string: url) else {
            contestar(nil, error: "sin sesión del Hub"); return
        }
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type"); r.timeoutInterval = 35
        r.httpBody = try? JSONSerialization.data(withJSONObject: ClaudioLocalReglas.pedido(token: token, sesion: sesion, conv: conv, texto: conNotas, historial: previos))
        llamadas += 1; let mia = llamadas, t0 = Date()
        URLSession.shared.dataTask(with: r) { [weak self] data, _, err in
            let j = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async {
                guard let self, self.vivo, self.llamadas == mia else { return }
                self.paso?(ClaudioLocalReglas.tiempos(total: Date().timeIntervalSince(t0), j))
                self.contestar(j, error: j == nil ? (err?.localizedDescription ?? "sin respuesta del Hub") : (j?["ok"] as? Bool) == false ? (j?["error"] as? String) : nil)
            }
        }.resume()
    }

    /// Respaldo: la frase al Hub (acción «calle», sin audio). Si se fue el internet a medio camino, lo de `piezas` vuelve a
    /// quedar guardado; si el Hub no contestó por otra cosa (tardó), no se repite solo (pudo haberse hecho): se dice.
    private func pedirRespaldo(_ t: String, piezas: [String]) {
        guard let url = Llave.leer("voz_url"), let token = Llave.leer("voz_token"), let sesion = Llave.leer("voz_sesion"), let u = URL(string: url) else {
            decir("No tengo la sesión del Hub. Ábreme con sesión y seguimos."); return
        }
        pensando = true
        empezarTecleo()
        emitir(["type": "agent_tool_request", "agent_tool_request": ["tool_name": "respaldo"]])   // trabaja: no se cuelga por silencio
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type"); r.timeoutInterval = 25
        r.httpBody = try? JSONSerialization.data(withJSONObject: RespaldoVoz.pedido(token: token, sesion: sesion, texto: t))
        llamadas += 1; let mia = llamadas, t0 = Date()
        URLSession.shared.dataTask(with: r) { [weak self] data, _, err in
            let j = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let sinRed = j == nil && err.map { EstadoCalle.esSinRed(($0 as NSError).code) } == true
            DispatchQueue.main.async {
                guard let self, self.vivo, self.llamadas == mia else { return }
                self.pararTecleo()
                self.emitir(["type": "agent_tool_response", "agent_tool_response": ["tool_name": "respaldo"]])
                self.pensando = false
                self.paso?(String(format: "Voz de respaldo: el Hub contestó en %.1f s", Date().timeIntervalSince(t0)) + (j == nil ? " (sin respuesta" + (sinRed ? ", sin internet)" : ")") : ""))
                if sinRed {
                    self.cola = Array((piezas + self.cola).prefix(RespaldoVoz.maxCola))
                    self.decir(RespaldoVoz.trasGuardar(cuantas: self.cola.count, cupo: true))
                    return
                }
                let h = RespaldoVoz.hablar(j)
                self.historial = ClaudioLocalReglas.sumar(self.historial, .init(deClaudio: true, texto: h))
                self.decir(h)
            }
        }.resume()
    }

    private func contestar(_ j: [String: Any]?, error: String?) {
        pararTecleo()
        if let e = error { paso?("Claudio local: " + e) }
        let r = ClaudioLocalReglas.respuesta(j)
        for h in r.herramientas { emitir(["type": "agent_tool_response", "agent_tool_response": ["tool_name": h]]) }   // el Panel de Claudio
        emitir(["type": "agent_tool_response", "agent_tool_response": ["tool_name": "claudio_local"]])
        historial = ClaudioLocalReglas.sumar(historial, .init(deClaudio: true, texto: r.hablar))
        pensando = false
        decir(r.hablar, audio: r.audio) { [weak self] in
            guard let self, r.volver else { return }
            // Ya dijo «Listo, te paso con Alma.»: la app vuelve con Alma, como con la herramienta de ElevenLabs.
            self.emitir(["type": "client_tool_call", "client_tool_call": ["tool_call_id": "local_volver", "tool_name": "volver_con_alma", "parameters": [String: Any]()]])
        }
    }

    // MARK: - El tecleo mientras piensa (Hub #651: como el de ElevenLabs cuando Alma usa una herramienta)

    /// Mientras el Hub piensa suena un tecleo suave, por el mismo camino que su voz (el halo late apenas): Juan sabe que se
    /// está trabajando. Empieza si tarda más de un respiro y se apaga en cuanto llega la respuesta.
    private func empezarTecleo() {
        pararTecleo()
        desdeTurno = Date()
        relojTecleo = Timer.scheduledTimer(withTimeInterval: ClaudioLocalReglas.tecleoCada, repeats: true) { [weak self] _ in
            guard let self, self.vivo, self.pensando, Date().timeIntervalSince(self.desdeTurno) >= ClaudioLocalReglas.tecleoTras else { return }
            self.teclas &+= 1
            self.emitir(["type": "audio", "audio_event": ["audio_base_64": ClaudioLocalReglas.tecleo(semilla: self.teclas).base64EncodedString()]])
        }
    }

    private func pararTecleo() { relojTecleo?.invalidate(); relojTecleo = nil }

    // MARK: - Hablar (su voz de ElevenLabs; si no llegó, la del iPhone)

    /// Dice la frase. Con el audio del Hub (su voz de ElevenLabs, PCM 16 kHz) lo suena tal cual; si no, con la voz del iPhone.
    /// El audio sale en trozos de 16 kHz, igual que el del socket de ElevenLabs, y VozNativa lo suena en su reproductor (el
    /// halo late con la voz). Al terminar de sonar, vuelve a escuchar.
    private func decir(_ t: String, audio: Data? = nil, luego: (() -> Void)? = nil) {
        ocupadoHasta = .distantFuture
        texto = ""; soltarPedido()
        emitir(["type": "agent_response", "agent_response_event": ["agent_response": t]])
        if let a = audio {
            for d in ClaudioLocalReglas.trozos(a) { emitir(["type": "audio", "audio_event": ["audio_base_64": d.base64EncodedString()]]) }
            let fin = Date().addingTimeInterval(ClaudioLocalReglas.duracion(a) + 0.45)
            ocupadoHasta = fin
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, fin.timeIntervalSinceNow)) { [weak self] in
                guard let self, self.vivo else { return }
                luego?()
                if !self.pensando, self.pedido == nil { self.nuevoPedido() }
            }
            return
        }
        let u = AVSpeechUtterance(string: ClaudioLocalReglas.paraDecir(t))
        u.voice = voz; u.rate = ajustes.velocidad; u.pitchMultiplier = ajustes.tono; u.volume = ajustes.volumen
        u.preUtteranceDelay = 0; u.postUtteranceDelay = 0
        let e = Escritura()
        sintetizador.write(u) { [weak self] b in
            guard let pcm = b as? AVAudioPCMBuffer else { return }
            let datos = pcm.frameLength > 0 ? self?.a16k(pcm) : nil
            DispatchQueue.main.async {
                guard let self, self.vivo, !e.listo else { return }
                if let d = datos, !d.isEmpty {
                    if e.inicio == nil { e.inicio = Date() }
                    e.total += Double(d.count / 2) / 16000
                    self.emitir(["type": "audio", "audio_event": ["audio_base_64": d.base64EncodedString()]])
                    return
                }
                guard pcm.frameLength == 0 else { return }
                // Terminó de escribir: suena hasta inicio + total (VozNativa la pone en cola). Un respiro y vuelve a escuchar.
                e.listo = true
                let fin = (e.inicio ?? Date()).addingTimeInterval(e.total + 0.45)
                self.ocupadoHasta = fin
                DispatchQueue.main.asyncAfter(deadline: .now() + max(0, fin.timeIntervalSinceNow)) { [weak self] in
                    guard let self, self.vivo else { return }
                    luego?()
                    if !self.pensando, self.pedido == nil { self.nuevoPedido() }
                }
            }
        }
    }

    /// Un trozo de la voz del iPhone (22 kHz o lo que traiga) a PCM de 16 bits en 16 kHz.
    private func a16k(_ b: AVAudioPCMBuffer) -> Data? {
        if convertidor == nil || convertidor?.inputFormat != b.format { convertidor = AVAudioConverter(from: b.format, to: formatoVoz) }
        guard let c = convertidor else { return nil }
        let cap = AVAudioFrameCount(Double(b.frameLength) * 16000 / b.format.sampleRate) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: formatoVoz, frameCapacity: cap) else { return nil }
        var dado = false
        c.convert(to: out, error: nil) { _, st in
            if dado { st.pointee = .noDataNow; return nil }
            dado = true; st.pointee = .haveData; return b
        }
        guard out.frameLength > 0, let p = out.int16ChannelData else { return nil }
        return Data(bytes: p[0], count: Int(out.frameLength) * 2)
    }

    /// Suelta el dictado de ahora; lo que llegue tarde de él ya no cuenta (otra vuelta).
    private func soltarPedido() {
        vuelta += 1
        tarea?.cancel(); tarea = nil; pedido?.endAudio(); pedido = nil
    }

    private func emitir(_ e: [String: Any]) { alEvento?(e) }
}

/// Lo que va sonando de una frase (los trozos llegan de a poco desde la voz del iPhone).
private final class Escritura { var inicio: Date?; var total = 0.0; var listo = false }
