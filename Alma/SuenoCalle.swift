import Foundation

/// Sueño del Modo calle (pedido de Juan, 3-nov-2026): una llamada que abrió el Modo calle (por «Alma» o por un aviso
/// hablado) se cuelga rápido para no gastar créditos de ElevenLabs, y el Modo calle vuelve a esperar «Alma» solo con el
/// detector del teléfono. Aquí solo están las reglas, sin audio ni relojes: VozNativa las consulta cada medio segundo.
///   · silencio: Alma terminó de hablar y Juan no dijo nada en `silencio` s (6 de fábrica; `calle_silencio_s` en la ficha
///     del Hub). Silencio es «Juan no habló» (no llegó lo que dijo, user_transcript), no «no hubo sonido»: el ruido de la
///     calle no cuenta como Juan si no llega nada escrito en `soloRuido` s.
///   · cierre: Juan dijo «espera», «ahorita no», «luego», «gracias, es todo» o algo parecido (esCierre).
///   · tope: `tope` s (45 de fábrica; `calle_tope_s`) sin que Alma hable ni trabaje: aunque haya gente hablando cerca, pero
///     se espera a la primera pausa (nunca a media frase).
///   · Si alguien está hablando, la llamada NO se corta (Juan, 16-nov-2026: «si el usuario está hablando, la comunicación no
///     se puede cortar»): ni el silencio ni el tope cuelgan mientras se oye voz. Solo el ruido sin palabras (`soloRuido` s
///     de sonido sin que llegue nada escrito) deja de contar como voz.
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
        /// Desde cuándo suena el micrófono casi sin parar (sin huecos de `huecoDictado` s): el inicio del sonido de ahora.
        var sonidoDesde: Date = .distantPast
    }

    static let silencioDeFabrica: TimeInterval = 6
    static let topeDeFabrica: TimeInterval = 45
    /// Un sonido de hace menos de esto puede ser Juan a media frase (lo escrito llega al final): se espera un poco más…
    static let oyendo: TimeInterval = 1.5
    /// Sonido sin que llegue nada escrito (ni de Juan ni de Alma) en tanto tiempo: es ruido, no alguien hablando. Antes eran
    /// 8 s después del silencio y cortaba a Juan a media frase larga (lo escrito llega al final de la frase).
    static let soloRuido: TimeInterval = 30
    /// Una herramienta (la secretaria tarda de 15 a 57 s) no es silencio; si pasa de esto, algo se trabó.
    static let topeHerramienta: TimeInterval = 90

    /// ¿Hay que colgar ya? nil = la llamada sigue.
    /// `ruido`: voz sin nada escrito en ese tiempo ya no cuenta como alguien hablando. `pausa`: el tope (sin que Alma hable)
    /// solo cierra cuando nadie suena desde hace esto. 16-nov-2026 (23:43): el silencio se contaba desde lo último ESCRITO, y
    /// Juan, explicándole 50 s un pedido sin que llegara su texto, quedaba «callado»: ahora el silencio es que nadie suene.
    /// `duro` (solo conferencia; Juan, 17-nov-2026: «debe colgar y regresar al modo conferencia en escucha»): en una reunión
    /// siempre hay alguien hablando y llegan sus palabras, así que la pausa de `pausa` s casi nunca llega y la llamada quedaba
    /// abierta sin fin. Tras `duro` s sin que Alma hable ni trabaje, se cierra en la primera pausa corta (`pausaDura` s).
    static let pausaDura: TimeInterval = 3
    /// `dictado` (solo conferencia; guardia 20-nov-2026): mientras Juan le dicta a Alma una instrucción larga (`dictando`),
    /// la voz sin nada escrito cuenta como alguien hablando hasta `dictado` s (no `ruido`) y no se usa el tope duro.
    static func decidir(_ m: Momentos, ahora: Date, silencio: TimeInterval, tope: TimeInterval,
                        ruido: TimeInterval = soloRuido, pausa: TimeInterval = oyendo, duro: TimeInterval? = nil,
                        dictado: TimeInterval? = nil) -> Motivo? {
        if let h = m.herramientaDesde { return ahora.timeIntervalSince(h) > topeHerramienta ? .tope : nil }
        let alma = max(m.conectada, m.finVozAlma, m.finHerramienta)
        let dicta = dictado != nil && dictando(m, ahora: ahora)
        if !dicta, let d = duro, ahora.timeIntervalSince(alma) >= d, ahora.timeIntervalSince(m.sonido) >= pausaDura { return .tope }
        let palabras = max(alma, m.vozJuan)
        let limite = dicta ? max(ruido, dictado ?? 0) : ruido
        let esVoz = ahora.timeIntervalSince(palabras) < limite   // la voz sin nada escrito por mucho rato es ruido de fondo
        if esVoz && ahora.timeIntervalSince(m.sonido) < pausa { return nil }   // alguien habla (o hace una pausa corta): no se corta
        if ahora.timeIntervalSince(alma) >= tope { return .tope }
        let callado = ahora.timeIntervalSince(esVoz ? max(palabras, m.sonido) : palabras)
        return callado < silencio ? nil : .silencio
    }

    /// Guardia 20-nov-2026 (conferencia): Juan dictó 3 min seguidos una instrucción para Alma; ElevenLabs no cerró su turno
    /// (no llegó nada escrito) y a los 180 s la app tomó su voz como ruido y colgó a media frase. ¿Juan le está dictando a
    /// Alma? El sonido de ahora sigue casi sin parar (huecos de menos de `huecoDictado` s), empezó cerca de lo último escrito
    /// (un turno de Juan o lo que Alma dijo, `arranqueDictado` s antes o después) y desde entonces no llegó nada escrito. En
    /// una reunión sí llegan las palabras de los demás mientras suenan: eso no es dictado y el tope duro sigue igual.
    static let huecoDictado: TimeInterval = 6
    static let arranqueDictado: TimeInterval = 15
    static func dictando(_ m: Momentos, ahora: Date) -> Bool {
        guard m.sonidoDesde != .distantPast, ahora.timeIntervalSince(m.sonido) < huecoDictado else { return false }
        let escrito = max(m.conectada, m.finVozAlma, m.finHerramienta, m.vozJuan)
        return abs(escrito.timeIntervalSince(m.sonidoDesde)) <= arranqueDictado
    }

    /// ¿Alguien está hablando ahora? Hubo voz hace menos de `oyendo` s y no es solo ruido.
    static func hablando(_ m: Momentos, ahora: Date, callado: TimeInterval) -> Bool {
        ahora.timeIntervalSince(m.sonido) < oyendo && callado < soloRuido
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
