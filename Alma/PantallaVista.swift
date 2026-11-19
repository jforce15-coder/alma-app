import Foundation

/// Lo que Alma sabe de la pantalla de Juan en los tres toques a la roca del navegador (Hub #908; Juan, 19-nov-2026).
/// En la llamada conv_6301… la captura no se pudo leer y Alma igual dijo «Sí, ahora lo veo», nombró una sección y ofreció
/// llenar campos, mientras Juan pagaba en la página de su banco. Tres cosas:
/// · El saludo ya no dice que ve («Hola, ahora lo veo» la ataba a fingir): dice que va a mirar.
/// · Hasta que llega la lectura de la captura (o lo que devuelve leer_pagina), Alma NO ve la pantalla y la ficha lo dice así.
/// · Si la captura no se pudo leer, el aviso es firme («NO VES LA PANTALLA») y trae el motivo, que también queda en el
///   registro de la llamada («No pude leer la captura: …»), para saber la próxima vez por qué falló.
/// Lógica pura, con sus pruebas en Pruebas/PantallaVista.
enum PantallaVista {
    /// Lo primero que dice Alma al abrirla con tres toques (todavía no tiene la lectura de la captura).
    static let saludo = "Hola, déjame mirarlo."

    /// Para la ficha de la llamada: dónde está Juan (`donde`: título y dirección, y si es una pantalla privada).
    static func ficha(_ donde: String) -> String {
        "MODO PANTALLA: Juan está en el navegador de la app de Alma viendo " + donde + " y tocó tres veces la roca para hablar contigo de lo que ve. "
            + "Ya le dijiste «" + saludo + "»: no saludes otra vez; escucha. "
            + "Todavía NO ves su pantalla. Si no es una pantalla privada, en unos segundos te llega «LO QUE SE VE EN LA PANTALLA» (la lectura de su captura) "
            + "o «NO VES LA PANTALLA» si no se pudo leer. Hasta que llegue esa lectura no digas que la ves ni adivines nada de ella (secciones, montos, datos, botones); "
            + "si pregunta, dile «Dame un segundo, todavía la estoy cargando». Solo hablas de lo que diga esa lectura o lo que devuelva leer_pagina."
    }

    /// La lectura llegó: es lo único que Alma sabe de la pantalla.
    static func leida(_ texto: String, aviso: String?) -> String {
        (aviso.map { $0 + " " } ?? "") + "LO QUE SE VE EN LA PANTALLA (la captura que te mandó Juan): " + texto
            + "\nHabla solo de lo que dice esta lectura; si te pregunta algo que no está aquí, dile que eso no lo alcanzas a ver."
    }

    /// La lectura no llegó: Alma no ve nada y lo tiene que decir.
    static func sinLectura(_ motivo: String) -> String {
        "NO VES LA PANTALLA: la captura no se pudo leer (" + motivo + "). No sabes qué hay en la pantalla de Juan. "
            + "Nunca digas que la ves o que ya la miraste, ni nombres una sección, un monto, un dato o un botón, ni ofrezcas llenar algo con lo que creas que dice. "
            + "Si ya le dijiste que la veías, corrígete en tu próxima frase: «Perdón, no alcanzo a ver tu pantalla». "
            + "Si tienes leer_pagina (NAVEGADOR DE ALMA), úsala para leerla de verdad y habla solo de lo que devuelva; si no, pídele que te diga qué ve. "
            + "En una página de banco o de pagos nunca supongas: los montos y los datos los confirma Juan."
    }

    /// Por qué no llegó la lectura, en palabras simples. `respuesta`: lo que contestó el Hub (almaFoto); `http`: el código;
    /// `sinRed`: el error de red (p. ej. «tardó más de 40 s»), si lo hubo.
    static func motivo(respuesta: [String: Any]?, http: Int?, sinRed: String?) -> String {
        if let s = sinRed, !s.isEmpty { return s }
        guard let j = respuesta else { return "el Hub no contestó" + (http.map { " (HTTP \($0))" } ?? "") }
        if (j["ok"] as? Bool) == true { return "la lectura llegó vacía" }
        if (j["cupo"] as? Bool) == true { return "el cupo de Google" }
        switch (j["error"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) {
        case "": return "el Hub no dijo por qué"
        case "session": return "la sesión de la app venció"
        case "foto": return "la captura salió muy grande o en un formato que el Hub no acepta"
        case "lectura": return "la IA no pudo describirla"
        case let e: return String(e.prefix(120))
        }
    }
}
