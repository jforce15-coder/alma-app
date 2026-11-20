import Foundation

/// Comandos internos en voz alta (Juan, 20-nov-2026: «no estés diciendo skip turn, ese es un comando interno, no lo tienes
/// que decir en voz»). A veces el modelo de voz escribe el nombre de una herramienta como texto («skip_turn», «end call»,
/// «nivel weebo dos») en vez de usarla en silencio, y ElevenLabs lo lee en voz alta. El Hub ya lo quita de lo que se guarda
/// y se muestra (voz.js, vozSinNotas_), pero la voz en vivo solo se puede cortar aquí, en la app: si lo que Alma va a decir
/// es solo un comando (o un comando con 3 palabras o menos alrededor, como «Claro. skip_turn»), su voz no suena, como la
/// pregunta de «¿sigues ahí?» (VozNativa.callarPregunta). Una respuesta de verdad con un comando en medio se deja sonar:
/// no se pierde lo que respondió (el prompt del Hub sigue pidiendo que nunca lo diga).
/// Lógica pura, sin iOS: se prueba sola en Pruebas/ComandoInterno.
enum ComandoInterno {
    /// Palabras de verdad que pueden ir pegadas al comando y aun así se calla todo («Claro.», «Ok, te escucho»).
    static let palabrasAlrededor = 3
    /// Cómo suenan los comandos al hablarlos (sin guion bajo): «skip turn», «end call», «nivel weebo», «mostrar gif».
    static let hablados: [[String]] = [["skip", "turn"], ["skip"], ["end", "call"], ["nivel", "weebo"], ["mostrar", "gif"]]
    private static let numeros: Set<String> = ["0", "1", "2", "3", "cero", "uno", "dos", "tres"]

    /// ¿Hay que callar esta respuesta de Alma? Sí si trae un comando y lo demás son `palabrasAlrededor` palabras o menos.
    static func callar(_ texto: String) -> Bool {
        let r = quitar(texto)
        return r.habia && r.palabras.count <= palabrasAlrededor
    }

    /// Las palabras que quedan sin comandos (sin acentos, en minúsculas) y si había alguno.
    static func quitar(_ texto: String) -> (palabras: [String], habia: Bool) {
        var t = texto
        var habia = false
        // Notas de actuación ([warm], [softly]) no son palabras dichas.
        t = reemplazar(t, #"\[[^\]\n]{0,40}\]"#, &habia, cuenta: false)
        // Un nombre con guion bajo (skip_turn, nivel_weebo, mostrar_gif("…")) nunca es español hablado. Los correos no se tocan.
        t = reemplazar(t, #"(?<![\w@.])[A-Za-z]+(?:_[A-Za-z0-9]+)+(?:\s*\([^)\n]{0,80}\))?(?![\w@])"#, &habia, cuenta: true)
        let n = t.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
            .map { $0.isLetter || $0.isNumber ? String($0) : " " }.joined()
        let palabras = n.split(separator: " ").map(String.init)
        var quedan: [String] = []
        var i = 0
        while i < palabras.count {
            if let h = hablados.first(where: { i + $0.count <= palabras.count && Array(palabras[i..<(i + $0.count)]) == $0 }) {
                habia = true
                i += h.count
                if h == ["nivel", "weebo"], i < palabras.count, numeros.contains(palabras[i]) { i += 1 }   // «nivel weebo dos»
                continue
            }
            quedan.append(palabras[i]); i += 1
        }
        return (quedan, habia)
    }

    private static func reemplazar(_ t: String, _ patron: String, _ habia: inout Bool, cuenta: Bool) -> String {
        guard let rx = try? NSRegularExpression(pattern: patron) else { return t }
        let rango = NSRange(t.startIndex..., in: t)
        if cuenta, rx.firstMatch(in: t, range: rango) != nil { habia = true }
        return rx.stringByReplacingMatches(in: t, range: rango, withTemplate: " ")
    }
}
