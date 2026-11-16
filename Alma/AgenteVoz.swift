import Foundation

/// Hablar con Claudio (Hub #550; Juan, 16-nov-2026): con quién habla la llamada y cuándo se cambia. Lógica pura, con sus
/// pruebas en Pruebas/AgenteVoz.
/// · Juan pide hablar con Claudio: Alma dice «Sí, no hay problema, te paso con Claudio» y usa hablar_con_claudio (herramienta
///   de la app). La app espera a que termine esa frase, pide al Hub la conversación de Claudio (acción vozClaudio, solo el
///   administrador principal) y cambia el socket sin colgar: otro agente, otra voz y el halo todo naranja.
/// · Claudio usa volver_con_alma: la app vuelve a Alma (acción vozWeb) y Alma dice que está de nuevo.
/// · Solo cambia la herramienta del agente que corresponde: Alma no «vuelve con Alma» ni Claudio pasa «con Claudio».
enum AgenteVoz: String, Equatable {
    case alma, claudio

    /// El agente al que lleva una herramienta de cliente, o nil si no es un cambio válido para quien habla ahora.
    static func cambio(herramienta: String, actual: AgenteVoz) -> AgenteVoz? {
        switch (herramienta, actual) {
        case ("hablar_con_claudio", .alma): return .claudio
        case ("volver_con_alma", .claudio): return .alma
        default: return nil
        }
    }
    /// ¿Es una de las herramientas de cambio? (No se contestan: expects_response false, así no hacen hablar al agente.)
    static func esCambio(_ herramienta: String) -> Bool { herramienta == "hablar_con_claudio" || herramienta == "volver_con_alma" }

    var nombre: String { self == .claudio ? "Claudio" : "Alma" }
    /// La acción del Hub que da su conversación (URL firmada y ficha).
    var accion: String { self == .claudio ? "vozClaudio" : "vozWeb" }

    /// Lo que se manda al Hub para abrir la conversación de este agente. Con Alma va «claudio»: la app sabe cambiar de
    /// agente, y el Hub le da a Alma el permiso de pasar a Claudio (solo con el principal).
    static func pedido(_ a: AgenteVoz, token: String, sesion: String, motivo: String = "") -> [String: Any] {
        var b: [String: Any] = ["hub": 1, "action": a.accion, "token": token, "session": sesion]
        if a == .claudio { b["motivo"] = String(motivo.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)) }
        else { b["app"] = "alma"; b["claudio"] = true }
        return b
    }

    /// ¿Ya se puede cerrar la conversación de antes? Cuando terminó de sonar su frase («te paso con Claudio») y pasó un
    /// respiro, o a los `tope` segundos de pedido el cambio (para no quedarse esperando si el audio no avisa).
    static let respiro = 0.35, tope = 6.0
    static func listo(finVoz: Date, pedido: Date, ahora: Date) -> Bool {
        ahora.timeIntervalSince(finVoz) >= respiro || ahora.timeIntervalSince(pedido) >= tope
    }

    /// El primer mensaje de la conversación nueva: Claudio, el que trae su ficha; Alma al volver, esta frase (Juan no la
    /// llamó: ya estaba en la llamada).
    static let vuelta = "Aquí estoy de nuevo. ¿Qué más hacemos?"
    static func primerMensaje(_ a: AgenteVoz, ficha: String) -> String {
        a == .claudio ? (ficha.isEmpty ? "Hola, aquí Claudio. ¿Qué hacemos?" : ficha) : vuelta
    }

    /// Lo que dice la pantalla de la llamada mientras habla el agente.
    func estadoTexto(habla: Bool) -> String { habla ? nombre + " te responde" : "Te escucho" }

    /// El color del halo (rojo, verde, azul de 0 a 1): Claudio todo naranja; Alma, nil (su coral de siempre).
    var halo: (r: Double, g: Double, b: Double)? { self == .claudio ? (0.96, 0.51, 0.12) : nil }

    // MARK: - Desde el Modo calle (Juan, 16-nov-2026)
    // «Quiero hablar con Claudio» en el Modo calle no pasaba a Claudio: iba como pedido de texto al Hub. Ahora la app lo
    // reconoce sola, pide su conversación (vozClaudio, solo el principal) y abre directo la llamada con Claudio.

    /// La misma regla que el Hub (calle.js, CALLE_CLAUDIO_RE_), sobre el texto sin acentos ni signos: un verbo de hablar o
    /// de pasar y «con Claudio» o «con el equipo de desarrollo». «Dile a Claudio que…» no (eso es un pedido) ni «no quiero…».
    static let patronClaudio = #"(?:^|\s)(?:hablar|habla|hablo|hablemos|platicar|platica|conversar|pasame|pasas|pasar|pasarme|comunicame|comunicas|comunicar|comunicarme|conectame|conectas|conectar|conectarme|ponme|pones|llama|llamale|llamar|marca|marcale)(?:\s+\S+){0,3}?\s+(?:con|a|al)\s+(?:el\s+|los\s+de\s+)?(?:claudio|equipo\s+de\s+desarrollo|desarrollo)(?:\s|$)"#
    static let patronNoClaudio = #"(?:^|\s)no\s+(?:quiero\s+|necesito\s+|me\s+)?(?:hablar|habla|pases|pasar|pasame|comuniques|conectes|llames|llamar)(?:\s|$)"#

    /// Minúsculas, sin acentos y sin signos: «¿Me pasas con Claudio?» → «me pasas con claudio».
    static func normal(_ t: String) -> String {
        let s = t.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es")).lowercased()
        let solo = String(s.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " })
        return solo.split(separator: " ").joined(separator: " ")
    }
    private static func busca(_ patron: String, _ t: String) -> NSRange? {
        guard let re = try? NSRegularExpression(pattern: patron) else { return nil }
        return re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t))?.range
    }
    /// ¿Pide hablar con Claudio (o con el equipo de desarrollo)?
    static func pideClaudio(_ texto: String) -> Bool {
        let t = normal(texto)
        return !t.isEmpty && busca(patronClaudio, t) != nil && busca(patronNoClaudio, t) == nil
    }
    /// Lo que Claudio oye como «LO QUE LE DIJO A ALMA»: la frase entera si trae algo más que el pedido de hablar con él
    /// (3 palabras o más: «… sobre el botón de pagos»); si no, nada (Claudio saluda con «¿Qué hacemos?»).
    static func motivoDe(_ texto: String) -> String {
        let t = normal(texto)
        guard let r = busca(patronClaudio, t), let rango = Range(r, in: t) else { return "" }
        let resto = String(t[..<rango.lowerBound]) + " " + String(t[rango.upperBound...])
        let relleno: Set<String> = ["alma", "quiero", "quisiera", "por", "favor", "oye", "porfa", "necesito"]
        let palabras = resto.split(separator: " ").filter { !relleno.contains(String($0)) }.count
        return palabras >= 3 ? String(texto.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)) : ""
    }

    /// Lo que se hace con la respuesta de vozClaudio en el Modo calle.
    enum EnCalle: Equatable { case abrir, comoPedido, decir(String) }
    static let sinClaudio = "Claudio todavía no está listo. Mientras, te ayudo yo."
    static let noPase = "No pude pasarte con Claudio. Inténtalo otra vez en un rato."
    static func enCalle(_ j: [String: Any]?) -> EnCalle {
        guard let j else { return .decir(noPase) }   // el Hub no contestó a tiempo: una frase, sin quedarse colgado
        if (j["ok"] as? Bool) == true, j["signed_url"] is String { return .abrir }
        let codigo = j["codigo"] as? String ?? "", error = (j["error"] as? String ?? "").lowercased()
        // No es el principal (Claudio no existe para él) o un Hub sin vozClaudio: va como pedido, como antes.
        if codigo == "no_principal" || error.contains("administrador principal") || error == "accion" { return .comoPedido }
        if codigo == "sin_agente" || error.contains("todavía no está listo") || error.contains("todavia no esta listo") { return .decir(sinClaudio) }
        return .decir(noPase)
    }
}
