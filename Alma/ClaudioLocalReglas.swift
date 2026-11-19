import Foundation

/// Claudio local (Hub #629; Juan, 16-nov-2026: «que la voz de Claudio sea local para no consumir créditos en sesiones
/// extensas de trabajo»). Lógica pura, con sus pruebas en Pruebas/ClaudioLocal. Lo que toca iOS está en ClaudioLocal.swift.
/// · Cuándo terminó de hablar Juan (el dictado no avisa): tras una pausa corta sin cambios en lo que oyó; más larga si la
///   frase quedó colgando («… y», «… que»), y con un tope para no esperar para siempre.
/// · Lo que se manda al Hub (acción claudioLocal): lo último que se dijo, corto.
/// · La voz: LA MISMA de Claudio en ElevenLabs (Hub #636; Juan, 17-nov-2026: «mantener la voz igual a la que usábamos antes
///   con ElevenLabs, sin bajar el nivel»). El Hub manda cada frase ya dicha con su voz (audio PCM 16 kHz, como la llamada).
/// · Si no llega audio (ElevenLabs falló o el Hub dice motor «iphone»), la voz del iPhone que más se parece: de hombre, en el
///   primer idioma que haya, la de mejor calidad; los ajustes vienen del Hub (voz_local) y se cambian sin otra versión.
/// · Que suene natural (Hub #687; Juan, 17-nov-2026: «que la voz suene natural otra vez»): la voz del iPhone ya no se
///   aplana a 16 kHz como la de una llamada de ElevenLabs (sonaba de teléfono, sin las eses); sale a 24 kHz. Y una voz
///   mejorada o premium va antes que una normal («compacta», la más robótica) aunque sea de otro país.
enum ClaudioLocalReglas {

    // MARK: - Solo voz local (Juan, 19-nov-2026: «Claudio y Maricarmen solo deben trabajar con voz local»)

    /// Qué falta para hablar con Claudio local, en una frase para que Alma se la diga a Juan; nil si está listo.
    /// Sin Claudio local la app ya NO abre el agente de Claudio en ElevenLabs: sigue Alma.
    static func falta(local: Bool, conv: String?, permiso: Bool, disponible: Bool) -> String? {
        if !local || !(conv ?? "").hasPrefix("conv_local_") { return "Claudio local está apagado en el Hub (CLAUDIO_LOCAL), y Claudio solo habla con voz local." }
        if !permiso { return "Para hablar con Claudio falta el permiso del dictado: Ajustes del iPhone, Alma, Reconocimiento de voz." }
        if !disponible { return "El dictado del iPhone no está disponible ahora, así que Claudio no puede hablar. Probemos en un rato." }
        return nil
    }

    // MARK: - Fin de la frase

    /// Segundos de silencio (sin cambios en lo que oye el dictado) que cierran la frase; si la frase queda colgando, más.
    static let pausa = 1.1, pausaColgando = 2.0, tope = 25.0
    static let colgantes: Set<String> = ["y", "o", "que", "pero", "de", "del", "con", "para", "por", "en", "a", "al", "el", "la", "los", "las", "un", "una", "como", "porque", "si", "cuando", "mmm", "este", "entonces"]

    static func pausa(para texto: String) -> Double {
        let ultima = AgenteVoz.normal(texto).split(separator: " ").last.map(String.init) ?? ""
        return colgantes.contains(ultima) ? pausaColgando : pausa
    }
    /// ¿Ya terminó? Solo con algo dicho: a la pausa sin cambios, o al tope desde que empezó a hablar.
    static func termino(texto: String, ultimoCambio: Date, empezo: Date, ahora: Date) -> Bool {
        guard !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if ahora.timeIntervalSince(empezo) >= tope { return true }
        return ahora.timeIntervalSince(ultimoCambio) >= pausa(para: texto)
    }

    // MARK: - Fin de la frase por el sonido (Juan, 19-nov-2026: «estamos tardando mucho en la transcripción»)

    /// El dictado escribe con atraso (medio segundo o más): contar la pausa desde el último cambio del texto sumaba ese
    /// atraso a cada turno. Ahora la pausa se cuenta también desde la última vez que el micrófono oyó voz: callado
    /// `pausaVoz` (o `pausaVozColgando` si la frase queda en «… y») y con el texto quieto `textoQuieto`, la frase va.
    /// Solo si el micrófono sí oyó voz en esta frase; si no (micrófono muy bajito), manda la regla de antes.
    static let pausaVoz = 0.7, pausaVozColgando = 1.5, textoQuieto = 0.3
    /// Al cerrar, el dictado termina de escribir lo último que oyó (endAudio); se espera su texto final como mucho esto.
    static let esperaFinal = 0.6

    static func pausaVoz(para texto: String) -> Double { pausa(para: texto) == pausaColgando ? pausaVozColgando : pausaVoz }

    /// ¿Ya terminó? Lo de antes (`termino`) o, con voz oída en esta frase, la pausa del sonido.
    static func termino(texto: String, ultimoCambio: Date, empezo: Date, ultimaVoz: Date?, ahora: Date) -> Bool {
        if termino(texto: texto, ultimoCambio: ultimoCambio, empezo: empezo, ahora: ahora) { return true }
        // La voz tiene que ser de esta frase (de cuando empezó a escribirse, con su atraso), no un ruido de antes.
        guard let v = ultimaVoz, v >= empezo.addingTimeInterval(-1), !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return ahora.timeIntervalSince(v) >= pausaVoz(para: texto) && ahora.timeIntervalSince(ultimoCambio) >= textoQuieto
    }

    /// ¿Este trozo del micrófono es voz? Más fuerte que 3 veces el ruido de fondo (y nunca por debajo de 0,02; la limpieza
    /// de voz lleva la voz a 0,08).
    static let vozMinima: Float = 0.02, margenVoz: Float = 3
    static func esVoz(rms: Float, piso: Float) -> Bool { rms > max(vozMinima, piso * margenVoz) }
    /// El ruido de fondo: baja rápido a lo más callado y sube despacio (una voz larga no lo vuelve ruido).
    static func piso(_ p: Float, rms: Float) -> Float { rms < p ? p * 0.9 + rms * 0.1 : p * 0.998 + rms * 0.002 }

    // MARK: - Lo que se manda al Hub

    struct Turno: Equatable { let deClaudio: Bool; let texto: String }
    static let maxTurnos = 14, maxLetras = 600

    static func sumar(_ h: [Turno], _ t: Turno) -> [Turno] {
        let x = t.texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !x.isEmpty else { return h }
        return Array((h + [Turno(deClaudio: t.deClaudio, texto: String(x.prefix(maxLetras)))]).suffix(maxTurnos))
    }
    static func pedido(token: String, sesion: String, conv: String, texto: String, historial: [Turno]) -> [String: Any] {
        ["hub": 1, "action": "claudioLocal", "token": token, "session": sesion, "conv_id": conv,
         "texto": String(texto.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1500)),
         "historial": historial.map { ["de": $0.deClaudio ? "claudio" : "juan", "texto": $0.texto] }]
    }

    /// Lo que se hace con la respuesta del Hub. Sin respuesta (o sin frase), una frase para no quedarse en silencio.
    static let repite = "Perdón, no me llegó la respuesta. ¿Me lo repites?"
    /// poner: lo que pidió poner_voz (Hub #779: voz, enlace, frase); suena después de su frase (PonerVoz.swift).
    struct Respuesta: Equatable { let hablar: String; let volver: Bool; let herramientas: [String]; var audio: Data? = nil; var poner: [String: String]? = nil }
    static func respuesta(_ j: [String: Any]?) -> Respuesta {
        let h = (j?["hablar"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Respuesta(hablar: h.isEmpty ? repite : h, volver: (j?["volver"] as? Bool) == true,
                         herramientas: (j?["herramientas"] as? [String] ?? []).filter { $0.hasPrefix("claudio_") },
                         audio: h.isEmpty ? nil : audio(j),   // sin frase, «¿me lo repites?» va con la voz del iPhone
                         poner: poner(j?["poner"]))
    }
    static func poner(_ x: Any?) -> [String: String]? {
        guard let d = x as? [String: Any] else { return nil }
        var o: [String: String] = [:]
        for k in ["voz", "enlace", "frase"] { if let v = d[k] as? String { o[k] = String(v.prefix(400)) } }
        return o
    }

    // MARK: - La voz de ElevenLabs (del Hub)

    static let hz = 16000
    /// A cuántos hz suena la conversación local. La voz del iPhone, a 24 kHz (Hub #687: a 16 kHz perdía claridad y sonaba
    /// de teléfono). Solo si el Hub manda su voz de ElevenLabs (motor «elevenlabs», siempre a 16 kHz) se queda en 16 kHz.
    static let hzIphone = 24000
    static func hzSalida(_ vozLocal: [String: Any]?) -> Int { (vozLocal?["motor"] as? String) == "elevenlabs" ? hz : hzIphone }
    /// El audio que manda el Hub con la voz de Claudio: PCM 16 bits a 16 kHz en base64 (audio + hz). Otro formato, roto o
    /// vacío: nada (se dice con la voz del iPhone).
    static func audio(_ d: [String: Any]?) -> Data? {
        guard let b = d?["audio"] as? String, !b.isEmpty, (d?["hz"] as? NSNumber)?.intValue == hz,
              let a = Data(base64Encoded: b), a.count >= 2 else { return nil }
        return a.count % 2 == 0 ? a : a.dropLast()
    }
    /// En trozos de un cuarto de segundo (como llegan del socket de ElevenLabs), para que el halo lata con la voz.
    static func trozos(_ a: Data, bytes: Int = 8000) -> [Data] {
        stride(from: 0, to: a.count, by: bytes).map { a.subdata(in: a.index(a.startIndex, offsetBy: $0)..<a.index(a.startIndex, offsetBy: min(a.count, $0 + bytes))) }
    }
    /// Cuánto suena (segundos).
    static func duracion(_ a: Data, hz: Int = hz) -> Double { Double(a.count / 2) / Double(max(1, hz)) }

    // MARK: - El tecleo mientras piensa (Hub #651)

    /// Juan, 17-nov-2026: «Alma usa el indicador de escribiendo y Claudio no». Con Alma, ElevenLabs suena un tecleo suave
    /// mientras trabaja una herramienta; Claudio local no pasa por ElevenLabs y se quedaba en silencio mientras el Hub
    /// pensaba. Aquí se arma un tecleo parecido, en el mismo formato de su voz (PCM 16 bits a 16 kHz).
    /// Empieza si la respuesta tarda más de `tecleoTras` (una respuesta rápida no lo necesita) y sale en trozos cortos, para
    /// que al llegar la respuesta casi no quede tecleo en cola delante de su voz.
    static let tecleoTras = 0.6, tecleoCada = 0.3, tecleoTrozo = 0.28
    /// Un trozo de tecleo: clics cortos de ruido que se apagan (6–10 ms), separados 70–200 ms y a veces una pausa de palabra.
    /// Bajito (como mucho un décimo del volumen). La misma semilla da el mismo trozo (para las pruebas); otra, otro ritmo.
    static func tecleo(segundos: Double = tecleoTrozo, semilla: UInt64, hz: Int = ClaudioLocalReglas.hz) -> Data {
        let n = max(0, Int(segundos * Double(hz)))
        guard n > 0 else { return Data() }
        var m = [Int16](repeating: 0, count: n)
        var x = semilla &* 6364136223846793005 &+ 1442695040888963407
        func azar() -> Double {
            x = x &* 6364136223846793005 &+ 1442695040888963407
            return Double(x >> 11) / 9007199254740992.0   // 2^53: un número entre 0 y 1
        }
        var i = Int(azar() * 0.06 * Double(hz))
        while i < n {
            let largo = Int(0.006 * Double(hz)) + Int(azar() * 0.004 * Double(hz))
            let fuerza = 0.04 + azar() * 0.05
            for k in 0..<largo where i + k < n {
                let caida = exp(-Double(k) / (Double(largo) / 4))
                m[i + k] = Int16(max(-32767, min(32767, (azar() * 2 - 1) * fuerza * caida * 32767)))
            }
            i += Int((azar() < 0.15 ? 0.25 + azar() * 0.2 : 0.07 + azar() * 0.13) * Double(hz))
        }
        return m.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Lo que se anota de cada turno: el total y, si el Hub lo manda, cuánto fue de la IA y cuánto de la voz.
    static func tiempos(total: Double, _ j: [String: Any]?) -> String {
        var t = String(format: "Claudio local contestó en %.1f s", total)
        if let ia = (j?["ms_ia"] as? NSNumber)?.doubleValue, let voz = (j?["ms_voz"] as? NSNumber)?.doubleValue {
            t += String(format: " (IA %.1f s · voz %.1f s · lo demás %.1f s)", ia / 1000, voz / 1000, max(0, total - (ia + voz) / 1000))
        }
        return t
    }

    // MARK: - Lo que dice la voz del iPhone

    /// Lo que la voz del iPhone leería raro: etiquetas de emoción ([warm]), markdown, enlaces y viñetas.
    static func paraDecir(_ t: String) -> String {
        var s = t
        for (patron, por) in [(#"\[[^\]\n]{1,40}\]"#, ""), (#"https?://\S+"#, ""), (#"[*_`#>|~]"#, ""), (#"(?m)^\s*(?:[-•·]|\d+[.)])\s+"#, ""), (#"\s{2,}"#, " ")] {
            s = s.replacingOccurrences(of: patron, with: por, options: .regularExpression)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Los ajustes de la voz (voz_local del Hub), con límites. Sin ellos, los de fábrica (los mismos que el Hub).
    struct Ajustes: Equatable {
        var idiomas = ["es-MX", "es-US", "es-419", "es-ES"]
        var hombre = true
        var velocidad: Float = 0.5   // la de fábrica del iPhone (AVSpeechUtteranceDefaultSpeechRate)
        var tono: Float = 1          // el natural de la voz: cambiarlo la hace sonar procesada (Hub #687; antes 0.92)
        var volumen: Float = 1
        init() {}
        init(_ d: [String: Any]?) {
            guard let d else { return }
            let n = { (k: String, a: Float, b: Float, x: Float) -> Float in ((d[k] as? NSNumber)?.floatValue).map { min(b, max(a, $0)) } ?? x }
            velocidad = n("velocidad", 0.3, 0.65, velocidad); tono = n("tono", 0.6, 1.4, tono); volumen = n("volumen", 0.2, 1, volumen)
            if let l = d["idiomas"] as? [String] { let ok = l.filter { $0.hasPrefix("es") }; if !ok.isEmpty { idiomas = Array(ok.prefix(5)) } }
            if let g = d["genero"] as? String { hombre = g != "mujer" }
        }
    }

    /// Una voz instalada en el iPhone, sin iOS (para elegir con pruebas).
    struct Voz: Equatable {
        let id: String, idioma: String, hombre: Bool
        let calidad: Int   // 0 premium · 1 mejorada · 2 normal
        let rara: Bool     // de novedad (robot, burbujas) o la Voz personal de alguien: nunca
    }
    /// La que más se parece a Claudio: del género pedido y en el primer idioma que haya; dentro del idioma, la mejor calidad.
    /// Una normal («compacta», la más robótica) solo si no hay ninguna mejorada o premium en español (Hub #687: suena más
    /// natural una mejorada de España que una compacta de México).
    /// Si no hay del género pedido, la mejor en español (mejor una voz que ninguna).
    static func elegir(_ voces: [Voz], _ a: Ajustes) -> Voz? {
        func puntos(_ v: Voz, genero: Bool) -> Int? {
            guard !v.rara, let i = a.idiomas.firstIndex(of: v.idioma) else { return nil }
            if genero && v.hombre != a.hombre { return nil }
            return (v.calidad >= 2 ? 1000 : 0) + i * 10 + v.calidad
        }
        let mejor = { (g: Bool) in voces.compactMap { v in puntos(v, genero: g).map { (v, $0) } }.min(by: { $0.1 < $1.1 })?.0 }
        return mejor(true) ?? mejor(false)
    }
}
