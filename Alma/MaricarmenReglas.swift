import Foundation

/// Maricarmen, el alter ego de Alma (Hub #666; Juan, 17-nov-2026: «cuando diga "pásame con Maricarmen", cambiar al agente
/// de voz 100 % local (voz de respaldo, sin ElevenLabs) y con Modo Weebo al máximo (nivel tres)»). Lógica pura, con sus
/// pruebas en Pruebas/Maricarmen. Lo que toca iOS: ClaudioLocal.swift (modo .maricarmen: la misma oreja y la misma forma de
/// hablar que la voz de respaldo) y VozNativa.swift (cuándo entra y cuándo sale).
/// · Entra: en una llamada normal con Alma (también con la voz de respaldo), Juan dice «pásame con Maricarmen». La app lo
///   oye en lo que Juan dijo, cierra ElevenLabs sin colgar y sigue con la voz de mujer del iPhone (de España si la hay).
/// · Piensa: el Chat con Alma por la acción calle, sin audio y con alter «maricarmen»: el Hub le pone el Modo Weebo en 3
///   desde la primera respuesta (apps-script/maricarmen.js). Solo el administrador principal; con otro, contesta Alma.
/// · También desde el Modo calle (Hub #680): «Alma, pásame con Maricarmen» abre la llamada directo con ella (ModoCalle),
///   y en una llamada que abrió el Modo calle también se puede pasar con ella.
/// · Sale: «pásame con Alma», «vuelve Alma» o «quiero hablar con Alma»: vuelve la voz de ElevenLabs sin colgar. No sale
///   sola cuando hay buena señal (no es la voz de respaldo: Juan la pidió).
enum MaricarmenReglas {

    static let alter = "maricarmen"

    /// «Pásame con Maricarmen», «¿me pasas con Maricarmen?», «quiero hablar con Maricarmen», «Maricarmen, ven». El verbo va pegado
    /// a su nombre: «pásale el recado a Maricarmen» o «llama a Maricarmen» (una persona de verdad) no la llaman. «No me pases…» no.
    /// Hub #680 (17-nov-2026, «intento comunicarme con ella y no lo logro»): también «comunícame / quiero comunicarme con
    /// Maricarmen», «pásame ya con la Maricarmen», «conéctame ahora a Maricarmen» y, al empezar, «Hola, Maricarmen». Entre el
    /// verbo y su nombre solo caben palabras de relleno (ya, ahora, por favor…), así un recado o una llamada a otra persona no cuenta.
    static let patronIr = #"(?:^|\s)(?:(?:pasame|pasas|pasar|pasarme|ponme|pones|comunicame|comunicas|comunicar|comunicarme|conectame|conectas|conectar|conectarme|cambiame)(?:\s+(?:me|ya|ahora|otra|vez|por|favor|porfa|un|rato|directo|directamente)){0,3}\s+(?:con|a)\s+(?:la\s+)?maricarmen|(?:hablar|habla|hablo|hablemos|platicar|platica|conversar)(?:\s+(?:me|ya|ahora|otra|vez|por|favor|porfa|un|rato|directo|directamente)){0,3}\s+con\s+(?:la\s+)?maricarmen|(?:ven|aparece)\s+maricarmen|maricarmen\s+(?:ven|aparece))(?:\s|$)|^(?:alma\s+)?hola\s+maricarmen(?:\s|$)"#
    /// Volver con Alma: «pásame con Alma», «vuelve Alma», «regresa con Alma», «quiero hablar con Alma».
    static let patronVolver = #"(?:^|\s)(?:(?:pasame|pasas|ponme|pones|comunicame|conectame|cambiame|regresame|devuelveme|vuelveme)\s+(?:con|a)\s+alma|(?:hablar|habla|hablo|volver|vuelvo|regresar|regreso)\s+con\s+alma|(?:vuelve|regresa|ven)\s+alma)(?:\s|$)"#
    static let patronNo = #"(?:^|\s)no\s+(?:quiero\s+|necesito\s+|me\s+)?(?:hablar|habla|pases|pasar|pasame|comuniques|conectes|cambies|volver|regresar|vuelvas|regreses)(?:\s|$)"#

    /// Cómo puede escribir su nombre el dictado (ElevenLabs o el del iPhone). Hub #680: «Marycarmen» o «María Carmen» no la llamaban.
    static let variantes = ["mari carmen", "mary carmen", "marycarmen", "maria carmen", "mari karmen", "marikarmen", "mary karmen"]
    /// Minúsculas, sin acentos y sin signos: «¿Me pasas con Maricarmen?» → «me pasas con maricarmen». «Mari Carmen» cuenta igual.
    static func normal(_ t: String) -> String {
        let s = t.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es")).lowercased()
        let solo = String(s.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " })
        var r = " " + solo.split(separator: " ").joined(separator: " ") + " "
        for v in variantes { r = r.replacingOccurrences(of: " " + v + " ", with: " maricarmen ") }   // como lo escribe el dictado
        return r.trimmingCharacters(in: .whitespaces)
    }
    private static func hay(_ patron: String, _ t: String) -> Bool {
        guard let re = try? NSRegularExpression(pattern: patron) else { return false }
        return re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
    }
    /// ¿Juan pide pasar con Maricarmen?
    static func pideIr(_ texto: String) -> Bool {
        let t = normal(texto)
        return !t.isEmpty && hay(patronIr, t) && !hay(patronNo, t)
    }
    /// ¿Juan pide volver con Alma (estando con Maricarmen)?
    static func pideVolver(_ texto: String) -> Bool {
        let t = normal(texto)
        return !t.isEmpty && hay(patronVolver, t) && !hay(patronNo, t)
    }

    // MARK: - Lo que dice (lo de en medio lo contesta el Hub, con el Weebo en 3)

    static let saludo = "¡Hola, Juan! Aquí Maricarmen. Venga, cuéntame: ¿qué hacemos hoy?"
    static let despedida = "Venga, te paso con Alma. ¡Un beso!"
    static let vuelta = "Aquí estoy de nuevo. ¿Qué más hacemos?"
    static let noLista = "No puedo pasarte con Maricarmen: falta el permiso del dictado en los Ajustes del iPhone."

    // MARK: - Su voz (la del iPhone, sin ElevenLabs)

    /// De mujer y, como el nivel 3 del Modo Weebo habla español de España, primero las voces de España.
    static let idiomas = ["es-ES", "es-MX", "es-US", "es-419"]
    static let tono: Float = 1.05, velocidad: Float = 0.52
}
