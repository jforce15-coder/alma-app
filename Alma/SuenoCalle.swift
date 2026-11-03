import Foundation

/// Sueño del Modo calle (pedido de Juan, 3-nov-2026): una llamada que abrió el Modo calle (por «Alma» o por un aviso
/// hablado) se cuelga rápido para no gastar créditos de ElevenLabs, y el Modo calle vuelve a esperar «Alma» solo con el
/// detector del teléfono. Aquí solo están las reglas, sin audio ni relojes: VozNativa las consulta cada medio segundo.
///   · silencio: Alma terminó de hablar y Juan no dijo nada en `silencio` s (6 de fábrica; `calle_silencio_s` en la ficha
///     del Hub). Silencio es «Juan no habló» (no llegó lo que dijo, user_transcript), no «no hubo sonido»: el ruido de la
///     calle solo da un poco más de margen (`gracia`), por si Juan está a media frase.
///   · cierre: Juan dijo «espera», «ahorita no», «luego», «gracias, es todo» o algo parecido (esCierre).
///   · tope: `tope` s (45 de fábrica; `calle_tope_s`) sin que Alma hable ni trabaje: aunque haya gente hablando cerca.
///   · corte: otra llamada, Siri, los audífonos que se desconectan, el micrófono que se cae: se cuelga sin reintentar.
enum SuenoCalle {
    enum Motivo: String { case silencio, cierre, tope, corte }

    /// Los momentos de la llamada que cuentan (Date.distantPast = nunca).
    struct Momentos {
        var conectada: Date               // cuando ElevenLabs contestó
        var finVozAlma: Date              // cuando termina de sonar lo que Alma dijo (puede ser en el futuro)
        var vozJuan: Date                 // lo último que Juan dijo y llegó escrito (user_transcript)
        var sonido: Date                  // el último sonido fuerte del micrófono fuera de la voz de Alma (puede ser ruido)
        var herramientaDesde: Date?       // Alma trabaja con una herramienta desde… (nil = no trabaja)
        var finHerramienta: Date          // cuando terminó la última herramienta
    }

    static let silencioDeFabrica: TimeInterval = 6
    static let topeDeFabrica: TimeInterval = 45
    /// Un sonido de hace menos de esto puede ser Juan a media frase (lo escrito llega al final): se espera un poco más…
    static let oyendo: TimeInterval = 1.5
    /// …pero nunca más de esto después del silencio: así el ruido solo no deja la llamada abierta.
    static let gracia: TimeInterval = 8
    /// Una herramienta (la secretaria tarda de 15 a 57 s) no es silencio; si pasa de esto, algo se trabó.
    static let topeHerramienta: TimeInterval = 90

    /// ¿Hay que colgar ya? nil = la llamada sigue.
    static func decidir(_ m: Momentos, ahora: Date, silencio: TimeInterval, tope: TimeInterval) -> Motivo? {
        if let h = m.herramientaDesde { return ahora.timeIntervalSince(h) > topeHerramienta ? .tope : nil }
        let alma = max(m.conectada, m.finVozAlma, m.finHerramienta)
        if ahora.timeIntervalSince(alma) >= tope { return .tope }
        let callado = ahora.timeIntervalSince(max(alma, m.vozJuan))
        if callado < silencio { return nil }
        if ahora.timeIntervalSince(m.sonido) < oyendo && callado < silencio + gracia { return nil }
        return .silencio
    }

    /// ¿Juan cerró la plática? Toda la frase (8 palabras como mucho) es de despedida o de «ahora no», con al menos una
    /// palabra clave. Una palabra que no es de cierre la deja pasar: «espera, también dile a Flor…», «luego mándale…»
    /// (luego = después), «sí, gracias» (aprueba algo: colgar ahí perdería lo que Alma iba a hacer).
    static func esCierre(_ texto: String) -> Bool {
        let llano = texto.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
            .replacingOccurrences(of: "[^a-z ]", with: " ", options: .regularExpression)
        let p = llano.split(separator: " ").map(String.init)
        guard !p.isEmpty, p.count <= 8, p.allSatisfy({ claves.contains($0) || relleno.contains($0) }) else { return false }
        let frase = " " + p.joined(separator: " ") + " "
        return p.contains(where: { claves.contains($0) }) || ["ahorita no", "ahora no", "nada mas", "es todo", "seria todo"]
            .contains(where: { frase.contains(" " + $0 + " ") })
    }
    /// «todo» solo no es clave («¿el resumen o todo?» «Todo»): cuenta en «es todo» o «sería todo».
    private static let claves: Set<String> = ["gracias", "adios", "bye", "luego", "despues", "rato", "tarde", "cuelga",
                                              "espera", "esperame", "esperate", "esperenme"]
    private static let relleno: Set<String> = ["no", "bueno", "pues", "ya", "alma", "muchas", "es", "eso", "seria", "todo", "nada", "mas",
                                               "hasta", "al", "te", "aviso", "digo", "hablamos", "seguimos", "por", "ahora", "ahorita",
                                               "un", "momento", "segundo", "me", "estan", "hablando", "que", "tantito", "favor",
                                               "porfa", "puedo", "lo", "vemos", "mejor", "para", "y", "de", "a"]
}
