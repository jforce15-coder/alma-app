import Foundation

/// ¿Le contestó el aviso? (Juan, 17-nov-2026: «cuando Alma dé una notificación en llamada o modo continuo, no debe
/// interpretar cualquier audio posterior inmediatamente como respuesta… si no es para ella o habla con otra persona / ruido
/// de fondo, debe permanecer en silencio y salir sin interrumpir ni decir nada»).
/// Antes: tras la notificación hablada la conferencia escuchaba 8 s y CUALQUIER voz abría la llamada de Alma («Juan te
/// contestó»), y en el Modo calle iba al Hub como respuesta. Ahora decide el juez del aviso del Hub
/// (apps-script/avisorespuesta.js): «Alma», lo corto o lo que empieza como respuesta cuenta; lo largo lo decide el
/// clasificador rápido con el aviso al lado.
///   · Conferencia: antes de abrir la llamada se pregunta al Hub (`avisoRespuesta`). No → nada suena, no se abre la llamada
///     y el aviso vuelve en la rotación (no cuenta como atendido). Sin respuesta del Hub a tiempo → se abre como antes.
///   · Modo calle: el pedido va con `puede_callar`; si el Hub dice `silencio`, Alma no dice nada (ni «Listo.») y vuelve a
///     esperar «Alma».
///   · Dentro de la llamada (la ficha): la misma regla con skip_turn (`regla`).
/// Lógica pura, sin iOS: se prueba sola en Pruebas/RespuestaAviso.
enum RespuestaAviso {
    /// Lo que la ficha le dice a Alma cuando la llamada se abrió por la respuesta a su aviso.
    static let regla = "Pero no tomes cualquier voz como respuesta: si lo que oyes no responde a ese aviso ni te habla a ti (otra plática, otra persona, ruido), usa skip_turn y no digas nada; la app cierra sola."

    /// Cuánto se espera al juez del Hub antes de abrir la llamada como antes.
    static let espera: TimeInterval = 4

    /// «no», «luego», «después»…: solo cierran la espera (el aviso queda en Pendientes). Sin IA.
    static func esNoOLuego(_ dicho: String) -> Bool {
        let llano = dicho.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
        return llano.range(of: "^\\W*(no|ahorita no|ahora no|luego|despues|mas tarde|al rato)\\b", options: .regularExpression) != nil
    }

    /// Lo que contestó el Hub a `avisoRespuesta` o a «calle»: ¿Alma se queda callada? Solo si el Hub lo dice claro; sin
    /// respuesta, con error o con un Hub de antes (sin `es`), contesta como antes.
    static func callar(avisoRespuesta j: [String: Any]?) -> Bool {
        guard let j, (j["ok"] as? Bool) == true, let es = j["es"] as? Bool else { return false }
        return !es
    }
    static func callar(calle j: [String: Any]?) -> Bool {
        guard let j, (j["ok"] as? Bool) == true else { return false }
        return (j["silencio"] as? Bool) == true
    }

    /// Por qué calló (para «Lo que pasó» en el diagnóstico), sin lo que se dijo.
    static func motivo(_ j: [String: Any]?) -> String {
        switch j?["por"] as? String ?? "" {
        case "ia_no": return "el juez del aviso vio que era otra plática"
        case "nada": return "no se oyeron palabras"
        default: return "no respondía al aviso"
        }
    }
}
