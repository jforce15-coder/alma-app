import Foundation

/// Maricarmen, el alter ego de Alma (Hub #666; Juan, 17-nov-2026: «cuando diga "pásame con Maricarmen", cambiar al agente
/// de voz 100 % local (voz de respaldo, sin ElevenLabs) y con Modo Weebo al máximo (nivel tres)»). Lógica pura, con sus
/// pruebas en Pruebas/Maricarmen. Lo que toca iOS: ClaudioLocal.swift (modo .maricarmen: la misma oreja y la misma forma de
/// hablar que la voz de respaldo) y VozNativa.swift (cuándo entra y cuándo sale).
/// · Entra: en una llamada normal con Alma (también con la voz de respaldo), Juan dice «pásame con Maricarmen». La app lo
///   oye en lo que Juan dijo, cierra ElevenLabs sin colgar y sigue con la voz de mujer del iPhone (de España si la hay).
///   También desde el Modo calle o el inicio con escucha («Alma, pásame con Maricarmen»): se abre la llamada y sigue con
///   ella, sin mandarle el pedido a Alma (Hub #679: antes iba como pedido de texto y Alma buscaba a una persona).
/// · Piensa: el Chat con Alma por la acción calle, sin audio y con alter «maricarmen»: el Hub le pone el Modo Weebo en 3
///   desde la primera respuesta (apps-script/maricarmen.js). Solo el administrador principal; con otro, contesta Alma.
/// · Sale: «pásame con Alma», «vuelve Alma» o «quiero hablar con Alma»: vuelve la voz de ElevenLabs sin colgar. No sale
///   sola cuando hay buena señal (no es la voz de respaldo: Juan la pidió).
enum MaricarmenReglas {

    static let alter = "maricarmen"
    /// La herramienta de cliente con la que Alma (ElevenLabs) pasa a Juan con Maricarmen cuando la app no reconoció la frase
    /// (Hub #707, Juan 17-nov-2026: «hablar directamente con Maricarmen dentro de la llamada, sin derivarlo a WhatsApp ni
    /// llamadas externas»). No se contesta (expects_response false): no hace hablar a Alma.
    static let herramienta = "pasar_a_maricarmen"

    /// «Pásame con Maricarmen», «¿me pasas con Maricarmen?», «quiero hablar con Maricarmen», «Maricarmen, ven». El verbo va pegado
    /// a su nombre: «pásale el recado a Maricarmen» o «llama a Maricarmen» (una persona de verdad) no la llaman. «No me pases…» no.
    /// Hub #679: también «¿me puedes pasar con Maricarmen?», «quiero comunicarme con Maricarmen», «comunícate con Maricarmen»,
    /// «Marycarmen» y «Hola, Maricarmen» al empezar la frase. Hub #680: «pásame ya con la Maricarmen» (relleno corto y «la»). Con un infinitivo («pasar», «comunicarme») va solo con «con».
    static let patronIr = #"(?:^|\s)(?:(?:pasame|pasas|pases|pasarme|pasarias|ponme|pones|ponerme|comunicame|comunicas|comuniques|comunicarme|conectame|conectas|conectarme|cambiame|cambiarme)(?:\s+(?:me|ya|ahora|otra|vez|por|favor|porfa|un|rato|directo|directamente)){0,3}\s+(?:con|a)\s+(?:la\s+)?maricarmen|(?:pasar|comunicar|comunicate|comunicarte|comunicarnos|conectar|conectate|conectarte|hablar|habla|hablo|hablemos|platicar|platica|conversar)(?:\s+(?:me|ya|ahora|otra|vez|por|favor|porfa|un|rato|directo|directamente)){0,3}\s+con\s+(?:la\s+)?maricarmen|(?:ven|aparece)\s+maricarmen|maricarmen\s+(?:ven|aparece))(?:\s|$)|^(?:alma\s+)?(?:hola|oye|hey)\s+maricarmen(?:\s|$)"#
    /// Volver con Alma: «pásame con Alma», «vuelve Alma», «regresa con Alma», «quiero hablar con Alma».
    static let patronVolver = #"(?:^|\s)(?:(?:pasame|pasas|pases|pasarme|ponme|pones|ponerme|comunicame|comunicarme|conectame|conectarme|cambiame|cambiarme|regresame|devuelveme|vuelveme)\s+(?:con|a)\s+alma|(?:hablar|habla|hablo|volver|vuelvo|regresar|regreso)\s+con\s+alma|(?:vuelve|regresa|ven)\s+alma)(?:\s|$)"#
    static let patronNo = #"(?:^|\s)no\s+(?:quiero\s+|necesito\s+|me\s+)?(?:hablar|habla|pases|pasar|pasame|comuniques|comunicar|comunicarme|conectes|cambies|volver|regresar|vuelvas|regreses)(?:\s|$)"#

    /// Cómo puede escribir su nombre el dictado (ElevenLabs o el del iPhone). Hub #680: «María Carmen» o «Mari Karmen» no la llamaban.
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
