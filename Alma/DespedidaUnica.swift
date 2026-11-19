import Foundation

/// Despedida única (Juan, 19-nov-2026: «solo te puedes despedir una vez, a menos que haya una interrupción del usuario
/// antes de cortar la llamada… si te despides, cuelgas, pero dejas unos segundos después de despedirte para esperar una
/// respuesta. Si el usuario no responde, cuelgas»). En una llamada normal de la app (la roca, el anillo) el silencio no
/// cierra la llamada (LlamadaContinua): si Alma se despedía y no usaba end_call, la llamada quedaba abierta. Ahora, cuando
/// lo último que dijo Alma es una despedida, la app espera `tras` segundos de silencio desde que su voz terminó y cuelga.
/// Si Juan habla en ese rato, no cuelga: la conversación sigue y una despedida nueva vuelve a empezar la cuenta.
/// La regla del Hub (voz.js, DESPEDIDA ÚNICA) le pide a Alma lo mismo con end_call; esto es el respaldo de la app.
/// Lógica pura, sin iOS: se prueba sola en Pruebas/DespedidaUnica.
enum DespedidaUnica {
    /// Segundos de silencio después de la despedida (cuando su voz terminó de sonar) antes de colgar.
    static let tras: TimeInterval = 5
    /// Si la voz de la despedida nunca llega a sonar, cuelga a estos segundos.
    static let tope: TimeInterval = 25
    /// Juan hablando (el micrófono oyó voz hace menos de esto): no se cuelga encima de él.
    static let oyendo: TimeInterval = 1.5
    /// Una despedida es una frase corta: más palabras en la última frase ya no es un cierre.
    static let palabrasMaximas = 14

    /// ¿Lo último que dijo Alma es una despedida? Mira solo la última frase (sin pregunta) y busca un cierre claro
    /// («que descanses», «hasta luego», «te dejo», «si me necesitas, aquí estoy»). «¿Algo más?» o una respuesta con datos, no.
    static func esDespedida(_ texto: String) -> Bool {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty, !limpio.hasSuffix("?") else { return false }
        let frases = limpio.components(separatedBy: CharacterSet(charactersIn: ".!?…\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard var ultima = frases.last else { return false }
        // «Si me necesitas, aquí estoy» o «Que descanses, Juan»: la última frase puede ser corta; se junta con la de antes.
        if frases.count > 1, ultima.split(separator: " ").count <= 2 { ultima = frases[frases.count - 2] + " " + ultima }
        let n = ultima.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
            .map { $0.isLetter || $0.isNumber ? String($0) : " " }.joined()
        let palabras = n.split(separator: " ").map(String.init)
        guard !palabras.isEmpty, palabras.count <= palabrasMaximas else { return false }
        let junto = " " + palabras.joined(separator: " ") + " "
        return cierres.contains(where: { junto.contains(" " + $0 + " ") })
    }
    private static let cierres = ["que descanses", "descansa", "hasta luego", "hasta pronto", "hasta manana", "hasta la proxima",
                                  "nos vemos", "nos hablamos", "hablamos luego", "hablamos despues", "cuidate", "te dejo",
                                  "adios", "bye", "chao", "chau", "que te vaya bien", "que estes bien", "feliz noche", "feliz dia",
                                  "buen fin de semana", "que tengas buen", "que tengas un buen", "que tengas una buena",
                                  "aqui estare", "estare aqui", "solo llamame", "si me necesitas", "cuando me necesites"]

    /// ¿Ya cuelga la app? Alma se despidió en `desde`; `finVoz` es cuándo termina (o terminó) de sonar su voz; `juanHablo`,
    /// la última vez que Juan dijo algo (lo que llegó escrito); `vozJuan`, la última vez que el micrófono oyó su voz;
    /// `trabajando`, si hay una herramienta en curso (no se cuelga a media búsqueda).
    static func cuelga(desde: Date, finVoz: Date, juanHablo: Date?, vozJuan: Date, trabajando: Bool, ahora: Date) -> Bool {
        if let j = juanHablo, j >= desde { return false }
        if trabajando { return false }
        let sono = finVoz > desde, base = sono ? finVoz : desde, espera = sono ? tras : tope
        guard ahora >= base else { return false }
        if ahora.timeIntervalSince(base) >= ruido { return true }   // sonido sin palabras (tele, calle): no la deja abierta
        if ahora.timeIntervalSince(vozJuan) < oyendo { return false }
        return ahora.timeIntervalSince(max(base, vozJuan)) >= espera
    }
    /// Sonido en el micrófono sin que llegue nada escrito (ruido) no detiene el colgado más de esto.
    static let ruido: TimeInterval = 40
}
