import Foundation

/// Claudio local (Hub #629; Juan, 16-nov-2026: «que la voz de Claudio sea local para no consumir créditos en sesiones
/// extensas de trabajo»). Lógica pura, con sus pruebas en Pruebas/ClaudioLocal. Lo que toca iOS está en ClaudioLocal.swift.
/// · Cuándo terminó de hablar Juan (el dictado no avisa): tras una pausa corta sin cambios en lo que oyó; más larga si la
///   frase quedó colgando («… y», «… que»), y con un tope para no esperar para siempre.
/// · Lo que se manda al Hub (acción claudioLocal): lo último que se dijo, corto.
/// · La voz del iPhone que imita a Claudio: de hombre, en el primer idioma que haya, la de mejor calidad; los ajustes vienen
///   del Hub (voz_local) y se cambian sin una versión nueva de la app.
enum ClaudioLocalReglas {

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
    struct Respuesta: Equatable { let hablar: String; let volver: Bool; let herramientas: [String] }
    static func respuesta(_ j: [String: Any]?) -> Respuesta {
        let h = (j?["hablar"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Respuesta(hablar: h.isEmpty ? repite : h, volver: (j?["volver"] as? Bool) == true,
                         herramientas: (j?["herramientas"] as? [String] ?? []).filter { $0.hasPrefix("claudio_") })
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
        var tono: Float = 0.92       // un poco más grave, como su voz de ElevenLabs
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
    /// Si no hay del género pedido, la mejor en español (mejor una voz que ninguna).
    static func elegir(_ voces: [Voz], _ a: Ajustes) -> Voz? {
        func puntos(_ v: Voz, genero: Bool) -> Int? {
            guard !v.rara, let i = a.idiomas.firstIndex(of: v.idioma) else { return nil }
            if genero && v.hombre != a.hombre { return nil }
            return i * 10 + v.calidad
        }
        let mejor = { (g: Bool) in voces.compactMap { v in puntos(v, genero: g).map { (v, $0) } }.min(by: { $0.1 < $1.1 })?.0 }
        return mejor(true) ?? mejor(false)
    }
}
