import Foundation

/// Coro «Alma está trabajando» (Juan, 17-nov-2026): la lógica pura, sin audio (se prueba sola: Pruebas/CoroTrabajo).
/// Mientras Alma usa una herramienta suena el coro de Juan (Recursos/Sonidos/alma-trabaja.wav) en lugar del tecleo de
/// ElevenLabs. Aquí se decide CUÁNDO suena y A QUÉ VOLUMEN; CoroTrabajo.swift solo lo toca.
/// · Lleva la cuenta de las herramientas que corren (por tool_call_id): suena desde la primera y para al terminar la última.
/// · Solo si la herramienta tarda más de 0,6 s (las rápidas no suenan). Entra en 0,4 s y sale en 0,5 s.
/// · Mientras Alma habla baja 10 dB (en 150 ms) y vuelve en 400 ms; mientras Juan habla baja 6 dB.
/// · Las herramientas que no esperan respuesta (nivel_weebo, mostrar_gif, cambiar de agente…) no cuentan, y ninguna cuenta
///   más de 75 s (secretaria corta a los 60): si una respuesta nunca llega, el coro no se queda sonando.
struct CoroReglas {
    static let umbral: TimeInterval = 0.6
    static let entrada: TimeInterval = 0.4
    static let salida: TimeInterval = 0.5
    static let tope: TimeInterval = 75
    static let bajaAlma: Float = -10
    static let bajaJuan: Float = -6
    static let rampaBaja: TimeInterval = 0.15
    static let rampaSube: TimeInterval = 0.4
    /// Herramientas de cliente que no esperan respuesta o contestan al instante: nunca suenan.
    static let sinEspera: Set<String> = ["nivel_weebo", "mostrar_gif", "hablar_con_claudio", "volver_con_alma",
                                         "pasar_a_maricarmen", "mostrar_tarjeta_club", "mostrar_en_chat", "skip_turn", "end_call"]

    private(set) var activas: [String: Date] = [:]

    var cuantas: Int { activas.count }

    /// Empezó una herramienta. Devuelve si cuenta (las que no esperan respuesta no cuentan; la misma no cuenta dos veces).
    @discardableResult
    mutating func empieza(_ id: String, nombre: String, ahora: Date) -> Bool {
        guard !id.isEmpty, !CoroReglas.sinEspera.contains(nombre), activas[id] == nil else { return false }
        activas[id] = ahora
        return true
    }

    /// Terminó una herramienta. Devuelve true si con esta ya no queda ninguna.
    @discardableResult
    mutating func termina(_ id: String) -> Bool {
        guard activas.removeValue(forKey: id) != nil else { return false }
        return activas.isEmpty
    }

    /// Una interrupción o colgar: se corta todo.
    mutating func corta() { activas = [:] }

    /// Quita las que pasan del tope (una respuesta que nunca llegó).
    mutating func vencer(_ ahora: Date) {
        activas = activas.filter { ahora.timeIntervalSince($0.value) < CoroReglas.tope }
    }

    /// ¿Suena ahora? Solo si alguna herramienta lleva más del umbral corriendo.
    func debeSonar(_ ahora: Date) -> Bool {
        guard let primera = activas.values.min() else { return false }
        return ahora.timeIntervalSince(primera) >= CoroReglas.umbral
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
