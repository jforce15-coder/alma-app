import Foundation

/// Coro de espera (Juan, 17-nov-2026): la lógica pura, sin audio (se prueba sola: Pruebas/CoroTrabajo).
/// «El typing es el sonido mientras se procesa la solicitud; el eco es el sonido de espera, como el de las operadoras.»
/// Mientras corre una herramienta suena primero el tecleo de ElevenLabs (viene en la voz del agente). Si pasa de 2,5 s,
/// el tecleo se baja y entra el coro de Juan (Recursos/Sonidos/alma-trabaja.wav). Aquí se decide CUÁNDO y A QUÉ VOLUMEN;
/// CoroTrabajo.swift solo lo toca.
/// · Lleva la cuenta de las herramientas que corren (por tool_call_id): suena desde la primera y para al terminar la última.
/// · Las largas (pasar a Claudio o volver con Alma: se espera la conversación nueva) entran de inmediato. Entra en 0,4 s y
///   sale en 0,5 s. Mientras suena, la voz del agente (el tecleo) baja a 0,12; Alma hablando se oye completa.
/// · Mientras Alma habla baja 10 dB (en 150 ms) y vuelve en 400 ms; mientras Juan habla baja 6 dB.
/// · Las que no esperan respuesta (nivel_weebo, mostrar_gif…) y las de fondo no cuentan. Ninguna cuenta más de 75 s
///   (secretaria corta a los 60) ni el cambio de agente más de 12 s: si una respuesta nunca llega, el coro no se queda.
struct CoroReglas {
    static let umbral: TimeInterval = 2.5
    static let umbralLarga: TimeInterval = 0
    static let tecleo: Float = 0.12
    /// Las que siempre son espera larga: cambiar de agente (la app pide al Hub la conversación nueva).
    static let largas: Set<String> = ["hablar_con_claudio", "volver_con_alma"]
    static let entrada: TimeInterval = 0.4
    static let salida: TimeInterval = 0.5
    static let tope: TimeInterval = 75
    static let topeLarga: TimeInterval = 12
    static let bajaAlma: Float = -10
    static let bajaJuan: Float = -6
    static let rampaBaja: TimeInterval = 0.15
    static let rampaSube: TimeInterval = 0.4
    /// Herramientas de cliente que no esperan respuesta o contestan al instante: nunca suenan.
    /// Las de fondo (enviar_confirmado, claudio_pedido: async, la conversación sigue) tampoco: no hay espera.
    static let sinEspera: Set<String> = ["nivel_weebo", "mostrar_gif", "pasar_a_maricarmen", "mostrar_tarjeta_club",
                                         "mostrar_en_chat", "skip_turn", "end_call", "enviar_confirmado", "claudio_pedido",
                                         "poner_voz"]   // poner_voz (Hub #779): lo que suena es la voz misma, sin coro encima

    /// id → desde cuándo puede sonar (inicio + su umbral)
    private(set) var activas: [String: Date] = [:]
    private var deLargas: Set<String> = []

    var cuantas: Int { activas.count }

    /// Empezó una herramienta. Devuelve si cuenta (las que no esperan respuesta no cuentan; la misma no cuenta dos veces).
    @discardableResult
    mutating func empieza(_ id: String, nombre: String, ahora: Date) -> Bool {
        guard !id.isEmpty, !nombre.isEmpty, !CoroReglas.sinEspera.contains(nombre), activas[id] == nil else { return false }
        let larga = CoroReglas.largas.contains(nombre)
        activas[id] = ahora.addingTimeInterval(larga ? CoroReglas.umbralLarga : CoroReglas.umbral)
        if larga { deLargas.insert(id) }
        return true
    }

    /// Terminó una herramienta. Devuelve true si con esta ya no queda ninguna.
    @discardableResult
    mutating func termina(_ id: String) -> Bool {
        guard activas.removeValue(forKey: id) != nil else { return false }
        deLargas.remove(id)
        return activas.isEmpty
    }

    /// Una interrupción o colgar: se corta todo.
    mutating func corta() { activas = [:]; deLargas = [] }

    /// Quita las que pasan del tope (una respuesta que nunca llegó).
    mutating func vencer(_ ahora: Date) {
        activas = activas.filter { ahora.timeIntervalSince($0.value) < (deLargas.contains($0.key) ? CoroReglas.topeLarga : CoroReglas.tope) }
        deLargas = deLargas.filter { activas[$0] != nil }
    }

    /// ¿Suena ahora? Solo si alguna herramienta ya pasó su umbral (2,5 s; las largas, de inmediato).
    func debeSonar(_ ahora: Date) -> Bool {
        guard let primera = activas.values.min() else { return false }
        return ahora >= primera
    }

    /// El volumen de la voz del agente (por ahí llega el tecleo): baja mientras suena la espera y Alma no habla.
    static func volumenTecleo(coroSuena: Bool, almaHabla: Bool, normal: Float) -> Float {
        coroSuena && !almaHabla ? min(normal, tecleo) : normal
    }

    /// A cuántos dB debe sonar: Alma hablando manda sobre Juan hablando.
    static func objetivoDb(almaHabla: Bool, juanHabla: Bool) -> Float {
        almaHabla ? bajaAlma : (juanHabla ? bajaJuan : 0)
    }

    static func lineal(_ db: Float) -> Float { powf(10, db / 20) }

    /// Cuánto tarda en ir de un volumen a otro (lineales, 0 = callado): entrar 0,4 s, salir 0,5 s, bajar 150 ms, subir 400 ms.
    static func duracion(desde: Float, hacia: Float) -> TimeInterval {
        if hacia <= 0.0001 { return salida }
        if desde <= 0.0001 { return entrada }
        return hacia < desde ? rampaBaja : rampaSube
    }

    /// Un paso de la rampa: el volumen avanza hacia el objetivo a la velocidad que da `duracion` (desde donde arrancó la rampa).
    static func paso(nivel: Float, objetivo: Float, velocidad: Float, dt: TimeInterval) -> Float {
        let d = velocidad * Float(dt)
        if nivel < objetivo { return min(objetivo, nivel + d) }
        return max(objetivo, nivel - d)
    }
}
