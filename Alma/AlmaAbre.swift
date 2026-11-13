import Foundation

/// Alma abre la conversación (Hub #509 T4, Juan 13-nov-2026). Cuando el Hub marca un aviso con `abre` (el resultado de uno
/// de los pedidos recientes de Juan: terminó, falta unir o necesita algo de él), Alma no solo dice la frase: abre ella misma
/// la conversación de ElevenLabs con esa frase como primer mensaje y, si Juan contesta, siguen hablando.
///   · Dónde: solo en Modo calle o en modo conferencia (en conferencia es activar a Alma y que hable primero). La app se lo
///     dice al Hub (`abre: true` en vozAvisos) solo ahí; fuera de esos modos va la notificación hablada de siempre.
///   · Si Juan está hablando con Alma, el aviso espera a que termine (los avisos ni se piden durante una llamada); si esperó
///     en la fila de la app más de `vence`, va como la notificación de siempre.
///   · Nunca dos veces: el mismo aviso no entra otra vez a la fila (avisos_dichos) y el Hub tampoco lo vuelve a marcar.
///   · Cuelga sola con el sueño (SuenoCalle) si Juan no contesta, también en conferencia: cada conversación cuesta.
/// Lógica pura, sin iOS: se prueba sola en Pruebas/AlmaAbre.
enum AlmaAbre {
    /// Lo que manda el Hub en el aviso: la frase con la que Alma abre y el contexto para seguir la conversación.
    struct Datos: Equatable {
        let primer: String
        let contexto: String
    }

    /// El `abre` de un aviso del Hub (nil si no viene o viene sin frase).
    static func desde(_ aviso: [String: Any]) -> Datos? {
        guard let o = aviso["abre"] as? [String: Any] else { return nil }
        let p = (o["primer_mensaje"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return nil }
        let c = (o["contexto"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Datos(primer: p, contexto: String(c.prefix(1500)))
    }

    /// ¿Se le pide al Hub que marque lo que abre? Solo donde Alma puede abrir, y nunca con las habladas en «Silencio».
    static func pedir(calle: Bool, conferencia: Bool, hablado: Int) -> Bool { (calle || conferencia) && hablado > 0 }

    enum Donde: Equatable { case calle, conferencia, otro }
    static func donde(calle: Bool, conferencia: Bool) -> Donde { calle ? .calle : (conferencia ? .conferencia : .otro) }

    enum Paso: Equatable { case abrir, avisoDeSiempre }
    /// Lo que el aviso esperó en la fila de la app, como mucho, para todavía abrir (luego queda la notificación y Pendientes).
    static let vence: TimeInterval = 10 * 60
    /// Le toca al aviso (la voz ya está libre): ¿abre la conversación o va la notificación hablada de siempre?
    /// `espera`: cuánto lleva en la fila de la app. `mudo`: la conferencia silenciada (Juan no quiere que Alma oiga).
    static func decidir(_ d: Datos?, donde: Donde, espera: TimeInterval, mudo: Bool = false) -> Paso {
        guard d != nil, donde != .otro, !mudo, espera < vence else { return .avisoDeSiempre }
        return .abrir
    }

    /// ¿Es nuevo? El mismo aviso no se dice ni se abre dos veces.
    static func nuevo(_ id: String, dichos: [String], enFila: [String]) -> Bool { !dichos.contains(id) && !enFila.contains(id) }

    /// La ficha de la conversación que abre Alma: el contexto del Hub (qué pedido, qué falta) va al final de quien_llama.
    static func ficha(_ quienLlama: String, _ d: Datos) -> String {
        d.contexto.isEmpty ? quienLlama : quienLlama + "\n\n" + d.contexto
    }

    /// El primer mensaje: el del aviso gana siempre (Juan no la llamó: el ruido de la reunión o de la calle no la calla).
    static func primerMensaje(_ d: Datos?, deSiempre: String) -> String { d?.primer ?? deSiempre }

    /// ¿Vigila el sueño? En una llamada del Modo calle siempre; en conferencia, si la abrió un aviso.
    static func sueno(calle: Bool, porAviso: Bool) -> Bool { calle || porAviso }
}
