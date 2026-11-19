import Foundation

/// Poner una voz en la llamada (Hub #779; Juan, 18-nov-2026: «que Claudio, durante la llamada, pueda reproducir audios o
/// voces cuando se lo pida, por ejemplo las voces que se han desarrollado»). Lógica pura, con sus pruebas en
/// Pruebas/PonerVoz. Lo que suena está en PonerVoz.swift.
/// · La herramienta poner_voz es de Claudio y la atiende la app (con su agente de ElevenLabs y con Claudio local).
/// · «voz»: el nombre de una voz (Alex, Dora, Santa, una propia del catálogo, Claudio gratis o Maricarmen gratis), «la del iPhone», «la de Maricarmen» o
///   «la tuya» (la que tiene elegida cada personaje), «todas», o vacío para saber cuáles hay.
/// · «enlace»: un audio https (mp3, m4a, wav o aiff) que suena tal cual, hasta minuto y medio.
/// · Cada voz dice una frase corta con su nombre (o la que Juan pidió), por la misma salida de la llamada.
enum PonerVozReglas {
    static let herramienta = "poner_voz"
    static let maxVoces = 8
    static let maxSegundos = 90.0
    static let maxBytes = 20_000_000
    static let maxFrase = 220
    static let pausa = 0.6

    struct Muestra: Equatable {
        let id: String       // el id de Kokoro, o «iphone»
        let nombre: String   // como se dice: «Dora», «la voz del iPhone»
        let kokoro: Bool
        /// La voz gratis (Pocket, temporal; Juan, 18-nov-2026): Claudio (gratis) y Maricarmen (gratis).
        var pocket = false
    }
    enum Pedido: Equatable { case lista, voces([Muestra]), enlace(URL), nada(String) }

    static let iphone = Muestra(id: "iphone", nombre: "la voz del iPhone", kokoro: false)
    /// Las voces gratis (mismos ids que VozPocketReglas).
    static let gratis = [Muestra(id: "claudio_gratis", nombre: "Claudio gratis", kokoro: false, pocket: true),
                         Muestra(id: "maricarmen_gratis", nombre: "Maricarmen gratis", kokoro: false, pocket: true)]

    /// Sin acentos, en minúsculas y solo letras y números separados por un espacio.
    static func normal(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es")).lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    /// «Dora (mujer)» → «Dora»; sin nombre, el id.
    static func corto(_ v: VozKokoroReglas.Voz) -> String {
        let n = v.nombre.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? ""
        return n.isEmpty ? v.id : n
    }
    static func muestras(_ voces: [VozKokoroReglas.Voz]) -> [Muestra] {
        voces.map { Muestra(id: $0.id, nombre: corto($0), kokoro: true) } + gratis + [iphone]
    }

    /// Qué pidió Claudio. `personajes`: personaje → id de su voz de ahora («iphone» si habla con la voz del iPhone).
    static func pedido(voz: String, enlace: String, voces: [VozKokoroReglas.Voz], personajes: [String: String]) -> Pedido {
        let e = enlace.trimmingCharacters(in: .whitespacesAndNewlines)
        if !e.isEmpty {
            guard e.lowercased().hasPrefix("https://"), let u = URL(string: e), u.host != nil else { return .nada("El enlace tiene que empezar con https://; no sonó nada.") }
            return .enlace(u)
        }
        let v = normal(voz), palabras = Set(v.split(separator: " ").map(String.init))
        let todas = muestras(voces)
        if v.isEmpty || ["lista", "cuales", "cuales hay", "voces", "las voces"].contains(v) { return .lista }
        if palabras.contains("todas") || palabras.contains("todos") { return .voces(Array(todas.prefix(maxVoces))) }
        var out: [Muestra] = []
        let poner = { (m: Muestra) in if !out.contains(m) { out.append(m) } }
        let porPersonaje = { (p: String) in
            guard let id = personajes[p] else { return }
            if let m = todas.first(where: { $0.id == id }) { poner(m) }
        }
        if palabras.contains("maricarmen") { porPersonaje("maricarmen") }
        if palabras.contains("tuya") || palabras.contains("claudio") || v.contains("tu voz") { porPersonaje("claudio") }
        if palabras.contains("iphone") || palabras.contains("telefono") { poner(iphone) }
        for m in todas where m.kokoro || m.pocket {
            let nombre = Set(normal(m.nombre).split(separator: " ").map(String.init)).subtracting(["claudio", "maricarmen", "voz", "la", "de", "el"])
            if !nombre.isDisjoint(with: palabras) || palabras.contains(normal(m.id)) || v.contains(normal(m.id)) { poner(m) }
        }
        if out.isEmpty { return .nada("No encontré esa voz; no sonó nada. " + lista(voces, personajes: personajes)) }
        return .voces(Array(out.prefix(maxVoces)))
    }

    /// Cuáles hay, para que Claudio se las diga a Juan.
    static func lista(_ voces: [VozKokoroReglas.Voz], personajes: [String: String]) -> String {
        let dicho = nombres(voces)
        let de = { (p: String) -> String in
            guard let id = personajes[p] else { return "" }
            return muestras(voces).first { $0.id == id }?.nombre ?? id
        }
        return "Las voces que hay en el iPhone: " + dicho + ". Claudio local habla con " + de("claudio") + " y Maricarmen con " + de("maricarmen")
            + ". Pregúntale a Juan cuál quiere oír (o «todas») y vuelve a usar poner_voz con ese nombre."
    }

    /// La frase que dice cada voz: la que Juan pidió (corta) o una presentación con su nombre.
    static func frase(_ m: Muestra, pedida: String) -> String {
        let p = pedida.trimmingCharacters(in: .whitespacesAndNewlines)
        if !p.isEmpty { return String(p.prefix(maxFrase)) }
        if m.kokoro { return "Hola, Juan. Soy \(m.nombre), una de las voces de Spacio AM." }
        if m.pocket { return "Hola, Juan. Soy \(m.nombre), la voz de prueba mientras se hace la definitiva." }
        return "Hola, Juan. Esta es la voz del iPhone, la de respaldo."
    }

    /// El silencio entre una voz y la siguiente (PCM de 16 bits).
    static func silencio(hz: Int, segundos: Double = pausa) -> Data { Data(count: max(0, Int(Double(hz) * segundos)) * 2) }

    /// Lo que se le contesta a Claudio cuando terminó de sonar. error: no sonó nada.
    static func resultado(sonaron: [String], faltan: [String], sinModelo: Bool) -> (texto: String, error: Bool) {
        var t = ""
        if !sonaron.isEmpty {
            t = "Ya sonó en la llamada: " + sonaron.joined(separator: ", ") + ". Juan ya la escuchó: no la describas ni la repitas; pregúntale en una frase qué le pareció o si quiere oír otra."
        } else { t = "No sonó nada." }
        if sinModelo {
            t += " Kokoro todavía no está en el iPhone: se baja una vez en Ajustes, Voz y modos, Voces locales (92 MB, mejor con Wi-Fi)."
        } else if !faltan.isEmpty {
            t += " No sonó: " + faltan.joined(separator: ", ") + " (todavía no estaba en el iPhone; ya se está bajando: pídela otra vez en un minuto)."
        }
        return (t, sonaron.isEmpty)
    }
    static func enlaceListo(segundos: Double) -> String {
        "Ya sonó el audio del enlace en la llamada (\(Int(segundos.rounded())) s" + (segundos >= maxSegundos - 0.5 ? ", solo el primer minuto y medio" : "")
            + "). No lo describas: pregúntale a Juan en una frase qué le pareció."
    }
    // Lo que Claudio local le dice a Juan cuando no sonó nada (con ElevenLabs lo dice el agente con el resultado).
    static func nombres(_ voces: [VozKokoroReglas.Voz]) -> String {
        let ns = muestras(voces).map { $0.nombre }
        return ns.count > 1 ? ns.dropLast().joined(separator: ", ") + " y " + (ns.last ?? "") : ns.joined()
    }
    static func listaParaJuan(_ voces: [VozKokoroReglas.Voz]) -> String { "Tengo " + nombres(voces) + ". ¿Cuál quieres oír, o todas?" }
    static func noEstaParaJuan(_ voces: [VozKokoroReglas.Voz]) -> String { "No encontré esa voz. Tengo " + nombres(voces) + ". ¿Cuál quieres oír?" }
    static let enlaceParaJuan = "No pude poner ese audio: el enlace no bajó o no es un audio."
    static func noSonoParaJuan(sinModelo: Bool) -> String {
        sinModelo ? "Todavía no está Kokoro en el iPhone. Se baja una vez en Ajustes, Voz y modos, Voces locales."
                  : "Esa voz todavía no está en el iPhone; ya se está bajando. Pídemela otra vez en un minuto."
    }
    static let enlaceFallo = "No se pudo poner el audio del enlace (no bajó o no es un audio mp3, m4a, wav o aiff de hasta 20 MB). Díselo a Juan en una frase."
}
