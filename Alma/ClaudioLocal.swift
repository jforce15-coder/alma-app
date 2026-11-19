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
/// La voz de respaldo de Alma (Hub #657, RespaldoReglas.swift) usa esta misma clase con el modo .respaldo: la misma oreja y
/// la misma forma de hablar con VozNativa, pero contesta el Hub por la acción calle (el Chat con Alma) y habla la voz de
/// mujer del iPhone (VozIphone). Sin internet, lo que Juan pide se guarda (Senal) y se manda al volver la señal.
/// La voz local (Juan, 17-nov-2026; VozKokoro.swift): Claudio local y Maricarmen hablan con Kokoro, en el teléfono, si lo
/// tienen elegido en Ajustes → Voz y modos → Voces locales y ya se bajó; si no, falla o tarda, con la voz del iPhone.
final class ClaudioLocal: NSObject {
    enum Modo { case claudio, respaldo, maricarmen }   // maricarmen: el alter ego de Alma (Hub #666, MaricarmenReglas.swift)
    let modo: Modo
    /// Los eventos para VozNativa, siempre en el hilo principal.
    var alEvento: (([String: Any]) -> Void)?
    var paso: ((String) -> Void)?

    private let conv: String, saludo: String
    private let saludoAudio: Data?
    private let ajustes: ClaudioLocalReglas.Ajustes
    private let reconocedor: SFSpeechRecognizer
    private let voz: AVSpeechSynthesisVoice?
    /// La voz que habla: Kokoro del personaje (si está listo) y, de respaldo, la del iPhone.
    private let habla: HablaPorFrases
    private let vozLocal: String
    private let formatoOido = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    /// A cuántos hz sale su voz (Hub #687): 24 kHz con la voz del iPhone; 16 kHz solo con la de ElevenLabs del Hub.
    private let hz: Int

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
    /// poner_voz (Hub #779; PonerVoz.swift): las voces o el audio del enlace, por el mismo camino que su voz.
    private let poner = PonerVoz()

    init?(ficha: [String: Any]) {
        guard (ficha["local"] as? Bool) == true, let c = ficha["conv_id"] as? String, c.hasPrefix("conv_local_"),
              SFSpeechRecognizer.authorizationStatus() == .authorized,
              let r = SFSpeechRecognizer(locale: Locale(identifier: "es-MX")), r.isAvailable else { return nil }
        conv = c; reconocedor = r; modo = .claudio
        saludo = ficha["first_message"] as? String ?? AgenteVoz.saludoClaudio
        ajustes = ClaudioLocalReglas.Ajustes(ficha["voz_local"] as? [String: Any])
        saludoAudio = ClaudioLocalReglas.audio(ficha["voz_local"] as? [String: Any])
        hz = ClaudioLocalReglas.hzSalida(ficha["voz_local"] as? [String: Any])
        voz = ClaudioLocal.elegirVoz(ajustes)
        let vl = ClaudioLocal.voces(.claudio, voz: voz, ajustes: ajustes, hz: hz)
        habla = vl.0; vozLocal = vl.1
        super.init()
    }

    /// La voz de respaldo de Alma (Hub #657): sin ficha (con poca señal no hace falta pedirla); abre con `frase`.
    init?(respaldo frase: String) {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              let r = SFSpeechRecognizer(locale: Locale(identifier: "es-MX")), r.isAvailable else { return nil }
        conv = "conv_respaldo_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20).lowercased()
        reconocedor = r; modo = .respaldo
        saludo = frase; saludoAudio = nil; hz = ClaudioLocalReglas.hzIphone
        var a = ClaudioLocalReglas.Ajustes(); a.hombre = false; a.tono = 1
        ajustes = a
        voz = VozIphone.elegida ?? ClaudioLocal.elegirVoz(a)
        let vl = ClaudioLocal.voces(nil, voz: voz, ajustes: a, hz: hz)
        habla = vl.0; vozLocal = vl.1
        super.init()
    }

    /// Maricarmen, el alter ego de Alma (Hub #666, MaricarmenReglas.swift): como la voz de respaldo (el Chat con Alma, sin
    /// ElevenLabs), con una voz de mujer de España si el iPhone la tiene y el alter «maricarmen» en cada pedido (Weebo 3).
    init?(maricarmen saludo: String) {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              let r = SFSpeechRecognizer(locale: Locale(identifier: "es-MX")), r.isAvailable else { return nil }
        conv = "conv_maricarmen_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20).lowercased()
        reconocedor = r; modo = .maricarmen
        self.saludo = saludo; saludoAudio = nil; hz = ClaudioLocalReglas.hzIphone
        var a = ClaudioLocalReglas.Ajustes(); a.hombre = false; a.idiomas = MaricarmenReglas.idiomas
        a.tono = MaricarmenReglas.tono; a.velocidad = MaricarmenReglas.velocidad
        ajustes = a
        let e = ClaudioLocal.elegirVoz(a)
        voz = e?.gender == .female ? e : (VozIphone.elegida ?? e)   // nunca una voz de hombre: si no hay de mujer en español, la elegida de Alma
        let vl = ClaudioLocal.voces(.maricarmen, voz: voz, ajustes: a, hz: hz)
        habla = vl.0; vozLocal = vl.1
        super.init()
    }

    /// Kokoro del personaje (si lo tiene elegido y ya está en el teléfono) con la voz del iPhone de respaldo. La voz de
    /// respaldo de Alma (sin personaje) habla solo con la del iPhone.
    private static func voces(_ p: VozKokoroReglas.Personaje?, voz: AVSpeechSynthesisVoice?, ajustes: ClaudioLocalReglas.Ajustes, hz: Int) -> (HablaPorFrases, String) {
        let iphone = MotorIphone(voz: voz, ajustes: ajustes)
        guard let p else { return (HablaPorFrases(principal: nil, respaldo: iphone, hz: hz), "") }
        let k = VocesLocales.shared.motor(para: p)
        return (HablaPorFrases(principal: k, respaldo: iphone, hz: hz), VozKokoroReglas.descripcion(VocesLocales.shared.ajustes(p), usa: k != nil))
    }

    /// Callado: ni piensa, ni habla, ni Juan está a media frase (la voz de respaldo solo cambia en un silencio así).
    var quieto: Bool { vivo && !pensando && Date() >= ocupadoHasta && texto.isEmpty }

    /// Una frase que llega de fuera (lo guardado sin internet ya se mandó): se dice solo si está callado.
    func avisar(_ t: String) { if quieto { decir(t) } }

    /// Para el registro: «Juan · es-MX · hombre · mejorada · dictado en el teléfono».
    var descripcion: String {
        let v = voz.map { v -> String in
            let calidad: String
            switch v.quality { case .premium: calidad = "premium"; case .enhanced: calidad = "mejorada"; default: calidad = "normal" }
            return v.name + " · " + v.language + " · " + (v.gender == .male ? "hombre" : v.gender == .female ? "mujer" : "sin género") + " · " + calidad
        } ?? "la de por defecto"
        let lv = vozLocal.isEmpty || vozLocal == "voz del iPhone" ? v : vozLocal + " (respaldo: " + v + ")"
        if modo == .maricarmen { return "Maricarmen · " + (vozES ? "voz de ElevenLabs " + MaricarmenReglas.vozElevenLabs + " (respaldo: " + lv + ")" : lv) + (reconocedor.supportsOnDeviceRecognition ? " · dictado en el teléfono" : " · dictado de Apple") }
        if modo == .respaldo { return "voz de respaldo de Alma · " + v + (reconocedor.supportsOnDeviceRecognition ? " · dictado en el teléfono" : " · dictado de Apple") }
        return (saludoAudio != nil ? "voz de ElevenLabs (respaldo: " + lv + ")" : lv) + (reconocedor.supportsOnDeviceRecognition ? " · dictado en el teléfono" : " · dictado de Apple")
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

    /// Como si ElevenLabs hubiera conectado: la conversación (para el Panel de Claudio) y la voz en `hz`. Después, el saludo.
    func empezar() {
        emitir(["type": "conversation_initiation_metadata",
                "conversation_initiation_metadata_event": ["conversation_id": conv, "agent_output_audio_format": "pcm_\(hz)"]])
        paso?(modo == .respaldo ? "Alma con la voz de respaldo · " + descripcion : modo == .maricarmen ? "Con " + descripcion : "Claudio local · " + descripcion)
        historial = ClaudioLocalReglas.sumar(historial, .init(deClaudio: true, texto: saludo))
        habla.paso = { [weak self] t in self?.paso?(t) }
        if vozES { conVozES(saludo) { [weak self] a in self?.decir(self?.saludo ?? "", audio: a) } } else { decir(saludo, audio: saludoAudio) }
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
        habla.cancelar()
        poner.cancelar()
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
        if modo != .claudio { turnoRespaldo(t); return }   // la voz de respaldo y Maricarmen: el Chat con Alma
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

    private func contestar(_ j: [String: Any]?, error: String?) {
        pararTecleo()
        if let e = error { paso?("Claudio local: " + e) }
        let r = ClaudioLocalReglas.respuesta(j)
        for h in r.herramientas { emitir(["type": "agent_tool_response", "agent_tool_response": ["tool_name": h]]) }   // el Panel de Claudio
        emitir(["type": "agent_tool_response", "agent_tool_response": ["tool_name": "claudio_local"]])
        historial = ClaudioLocalReglas.sumar(historial, .init(deClaudio: true, texto: r.hablar))
        pensando = false
        decir(r.hablar, audio: r.audio) { [weak self] in
            guard let self else { return }
            if let pv = r.poner, !r.volver { self.ponerVoz(pv); return }
            guard r.volver else { return }
            // Ya dijo «Listo, te paso con Alma.»: la app vuelve con Alma, como con la herramienta de ElevenLabs.
            self.emitir(["type": "client_tool_call", "client_tool_call": ["tool_call_id": "local_volver", "tool_name": "volver_con_alma", "parameters": [String: Any]()]])
        }
    }

    /// Después de su frase suenan las voces (o el audio del enlace) que pidió poner_voz; mientras suenan, el micrófono no
    /// cuenta. Lo que sonó va como nota de la app en el próximo turno, así Claudio sabe qué escuchó Juan.
    private func ponerVoz(_ p: [String: String]) {
        ocupadoHasta = .distantFuture
        texto = ""; soltarPedido()
        var finCola = Date()
        poner.correr(p, hz: hz, trozo: { [weak self] d in
            guard let self, self.vivo else { return }
            finCola = VozKokoroReglas.finCola(finCola, ahora: Date(), dura: Double(d.count / 2) / Double(self.hz))
            self.emitir(["type": "audio", "audio_event": ["audio_base_64": d.base64EncodedString()]])
        }, fin: { [weak self] res, error in
            guard let self, self.vivo else { return }
            self.paso?("Claudio puso una voz" + (error ? " (no sonó)" : ""))
            self.notas = Array((self.notas + [String(res.prefix(400))]).suffix(3))
            let dice = self.poner.paraJuan
            if !dice.isEmpty {   // no sonó nada (o pidió la lista): lo dice él, en simple
                self.historial = ClaudioLocalReglas.sumar(self.historial, .init(deClaudio: true, texto: dice))
                self.decir(dice); return
            }
            let fin = max(finCola, Date()).addingTimeInterval(0.45)
            self.ocupadoHasta = fin
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, fin.timeIntervalSinceNow)) { [weak self] in
                guard let self, self.vivo, !self.pensando else { return }
                self.soltarPedido(); self.nuevoPedido()
            }
        })
    }

    // MARK: - Pensar con la voz de respaldo de Alma (el Chat con Alma, acción calle)

    /// Lo que Juan dijo va al Hub como en el Modo calle, sin audio. Sin internet se guarda y se manda al volver la señal.
    private func turnoRespaldo(_ t: String) {
        emitir(["type": "user_transcript", "user_transcription_event": ["user_transcript": t]])
        // Maricarmen (Hub #666): «pásame con Alma» vuelve a la voz de siempre; «pásame con Maricarmen» desde la voz de respaldo
        // la llama. Lo decide la app (VozNativa, evento «maricarmen»), sin ir al Hub.
        if modo == .maricarmen, MaricarmenReglas.pideVolver(t) {
            let volver: (Data?) -> Void = { [weak self] a in self?.decir(MaricarmenReglas.despedida, audio: a) { [weak self] in self?.emitir(["type": "maricarmen", "hacer": "volver"]) } }
            if vozES { ocupadoHasta = .distantFuture; soltarPedido(); conVozES(MaricarmenReglas.despedida, volver) } else { volver(nil) }
            return
        }
        if modo == .respaldo, MaricarmenReglas.pideIr(t) { emitir(["type": "maricarmen", "hacer": "ir"]); return }
        let conNotas = notas.isEmpty ? t : t + "\n(Nota de la app: " + notas.joined(separator: " · ") + ")"
        notas = []
        guard Senal.shared.hayRed else { guardarSinRed(t); return }
        guard let url = Llave.leer("voz_url"), let token = Llave.leer("voz_token"), let sesion = Llave.leer("voz_sesion"), let u = URL(string: url) else {
            paso?("Voz de respaldo: sin sesión del Hub"); decir(RespaldoReglas.fraseSinRespuesta); return
        }
        pensando = true
        empezarTecleo()
        emitir(["type": "agent_tool_request", "agent_tool_request": ["tool_name": "respaldo"]])   // trabaja: no se cuelga por silencio
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type"); r.timeoutInterval = 30
        r.httpBody = try? JSONSerialization.data(withJSONObject: RespaldoReglas.pedido(token: token, sesion: sesion, texto: conNotas,
                                                                                alter: modo == .maricarmen ? MaricarmenReglas.alter : nil, vozMaricarmen: vozES))
        llamadas += 1; let mia = llamadas, t0 = Date()
        URLSession.shared.dataTask(with: r) { [weak self] data, _, err in
            let j = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let deRed = j == nil && err.map { RespaldoReglas.esDeRed(($0 as NSError).code) } == true
            DispatchQueue.main.async {
                guard let self, self.vivo, self.llamadas == mia else { return }
                self.pararTecleo()
                self.pensando = false
                self.emitir(["type": "agent_tool_response", "agent_tool_response": ["tool_name": "respaldo"]])
                self.paso?(String(format: "Voz de respaldo: el Hub contestó en %.1f s", Date().timeIntervalSince(t0)))
                if deRed { self.guardarSinRed(t); return }
                guard let res = RespaldoReglas.respuesta(j) else {
                    self.paso?("Voz de respaldo: " + (err?.localizedDescription ?? "sin respuesta del Hub")); self.decir(RespaldoReglas.fraseSinRespuesta); return
                }
                if self.vozES { self.paso?(res.audio != nil ? "Maricarmen: con su voz de ElevenLabs" : "Maricarmen: sin su voz de ElevenLabs, sigue la local") }
                self.decir(res.hablar, audio: res.audio) { [weak self] in
                    guard let self, res.claudio else { return }
                    // «Quiero hablar con Claudio»: como la herramienta de Alma (Claudio local tampoco usa ElevenLabs).
                    self.emitir(["type": "client_tool_call", "client_tool_call": ["tool_call_id": "respaldo_claudio", "tool_name": "hablar_con_claudio", "parameters": ["motivo": t]]])
                }
            }
        }.resume()
    }

    /// Maricarmen con su voz de ElevenLabs (a prueba; MaricarmenReglas.vozElevenLabs): el interruptor de Voces locales.
    private var vozES: Bool { modo == .maricarmen && VocesLocales.shared.maricarmenElevenLabs }

    /// Una frase fija (el saludo, la despedida) con su voz de ElevenLabs, por calleVoz del Hub. Sin red, sin sesión, si tarda
    /// más de MaricarmenReglas.esperaVoz o no llega: nil (la dice su voz local).
    private func conVozES(_ t: String, _ listo: @escaping (Data?) -> Void) {
        ocupadoHasta = .distantFuture
        guard Senal.shared.hayRed, let url = Llave.leer("voz_url"), let token = Llave.leer("voz_token"), let sesion = Llave.leer("voz_sesion"),
              let u = URL(string: url) else { listo(nil); return }
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        r.timeoutInterval = MaricarmenReglas.esperaVoz
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["hub": 1, "action": "calleVoz", "app": "alma", "token": token, "session": sesion,
                                                                  "texto": t, "alter": MaricarmenReglas.alter, "voz_maricarmen": true])
        URLSession.shared.dataTask(with: r) { [weak self] data, _, _ in
            let j = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async {
                guard let self, self.vivo else { return }
                let a = RespaldoReglas.audio(j, hz: MaricarmenReglas.hzVoz)
                if a == nil { self.paso?("Maricarmen: su voz de ElevenLabs no llegó (" + String(j?["motivo"] as? String ?? "sin respuesta del Hub") + "); sigue la local") }
                listo(a)
            }
        }.resume()
    }

    private func guardarSinRed(_ t: String) {
        let ok = Senal.shared.guardar(t)
        paso?(ok ? "Voz de respaldo: sin internet, el pedido quedó guardado" : "Voz de respaldo: sin internet y ya no caben más pedidos guardados")
        decir(ok ? RespaldoReglas.fraseGuardado : RespaldoReglas.fraseLleno)
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
            self.emitir(["type": "audio", "audio_event": ["audio_base_64": ClaudioLocalReglas.tecleo(semilla: self.teclas, hz: self.hz).base64EncodedString()]])
        }
    }

    private func pararTecleo() { relojTecleo?.invalidate(); relojTecleo = nil }

    // MARK: - Hablar (su voz de ElevenLabs del Hub; si no llegó, Kokoro o la del iPhone)

    /// Dice la frase. Con el audio del Hub (su voz de ElevenLabs, PCM 16 kHz) lo suena tal cual; si no, con la voz del iPhone.
    /// El audio sale en trozos de `hz` (24 kHz con la voz del iPhone), como el del socket de ElevenLabs, y VozNativa lo suena en su reproductor (el
    /// halo late con la voz). Al terminar de sonar, vuelve a escuchar.
    private func decir(_ t: String, audio: Data? = nil, luego: (() -> Void)? = nil) {
        ocupadoHasta = .distantFuture
        texto = ""; soltarPedido()
        emitir(["type": "agent_response", "agent_response_event": ["agent_response": t]])
        if let a = audio {
            for d in ClaudioLocalReglas.trozos(a) { emitir(["type": "audio", "audio_event": ["audio_base_64": d.base64EncodedString()]]) }
            let fin = Date().addingTimeInterval(ClaudioLocalReglas.duracion(a, hz: hz) + 0.45)
            ocupadoHasta = fin
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, fin.timeIntervalSinceNow)) { [weak self] in
                guard let self, self.vivo else { return }
                luego?()
                if !self.pensando, self.pedido == nil { self.nuevoPedido() }
            }
            return
        }
        // Kokoro o la voz del iPhone, por frases (HablaPorFrases): sale en trozos de `hz` y VozNativa los pone en cola.
        // Al terminar de entregar, suena hasta el fin de la cola; un respiro y vuelve a escuchar.
        habla.decir(ClaudioLocalReglas.paraDecir(t), trozo: { [weak self] d in
            guard let self, self.vivo else { return }
            self.emitir(["type": "audio", "audio_event": ["audio_base_64": d.base64EncodedString()]])
        }, fin: { [weak self] in
            guard let self, self.vivo else { return }
            let fin = max(self.habla.finCola ?? Date(), Date()).addingTimeInterval(0.45)
            self.ocupadoHasta = fin
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, fin.timeIntervalSinceNow)) { [weak self] in
                guard let self, self.vivo else { return }
                luego?()
                if !self.pensando, self.pedido == nil { self.nuevoPedido() }
            }
        })
    }

    /// Suelta el dictado de ahora; lo que llegue tarde de él ya no cuenta (otra vuelta).
    private func soltarPedido() {
        vuelta += 1
        tarea?.cancel(); tarea = nil; pedido?.endAudio(); pedido = nil
    }

    private func emitir(_ e: [String: Any]) { alEvento?(e) }
}
