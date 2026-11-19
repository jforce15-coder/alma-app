import Foundation

/// Coro de espera (Juan, 17-nov-2026): la lógica pura, sin audio (se prueba sola: Pruebas/CoroTrabajo).
/// «El typing es el sonido mientras se procesa la solicitud; el eco es el sonido de espera, como el de las operadoras.»
/// Mientras corre una herramienta suena primero el tecleo de ElevenLabs (viene en la voz del agente). Si pasa de 2,5 s,
/// el tecleo se baja y entra el coro de Juan (Recursos/Sonidos/alma-trabaja.wav). Aquí se decide CUÁNDO y A QUÉ VOLUMEN;
/// CoroTrabajo.swift solo lo toca.
/// · Lleva la cuenta de las herramientas que corren (por tool_call_id): suena desde la primera y para al terminar la última.
/// · Las largas (pasar a Claudio o volver con Alma: se espera la conversación nueva) entran de inmediato. Mientras suena,
///   la voz del agente (el tecleo) baja a 0,12; Alma hablando se oye completa.
/// · Entradas y salidas suaves (Juan, 19-nov-2026: «fade in y fade out, ease in y ease out, más suave, que no entre ni se
///   corte de golpe»): entra en 1,2 s y sale en 1,2 s con curva coseno (arranca y termina despacio, sin escalón); una
///   interrupción o colgar ya no lo apaga en seco: sale en 0,35 s con la misma curva.
/// · Mientras Alma habla baja 10 dB (en 250 ms) y vuelve en 600 ms; mientras Juan habla baja 6 dB.
/// · Las que no esperan respuesta (nivel_weebo, mostrar_gif…) y las de fondo no cuentan. Ninguna cuenta más de 75 s
///   (secretaria corta a los 60) ni el cambio de agente más de 12 s: si una respuesta nunca llega, el coro no se queda.
struct CoroReglas {
    static let umbral: TimeInterval = 2.5
    static let umbralLarga: TimeInterval = 0
    static let tecleo: Float = 0.12
    /// Las que siempre son espera larga: cambiar de agente (la app pide al Hub la conversación nueva).
    static let largas: Set<String> = ["hablar_con_claudio", "volver_con_alma"]
    static let entrada: TimeInterval = 1.2
    static let salida: TimeInterval = 1.2
    /// Interrupción, cambio de agente o colgar: sale rápido pero sin cortar en seco.
    static let corte: TimeInterval = 0.35
    static let tope: TimeInterval = 75
    static let topeLarga: TimeInterval = 12
    static let bajaAlma: Float = -10
    static let bajaJuan: Float = -6
    static let rampaBaja: TimeInterval = 0.25
    static let rampaSube: TimeInterval = 0.6
    /// Herramientas de cliente que no esperan respuesta o contestan al instante: nunca suenan.
    /// Las de fondo (enviar_confirmado, claudio_pedido: async, la conversación sigue) tampoco: no hay espera.
    static let sinEspera: Set<String> = ["nivel_weebo", "mostrar_gif", "pasar_a_maricarmen", "mostrar_tarjeta_club",
                                         "mostrar_en_chat", "skip_turn", "end_call", "enviar_confirmado", "claudio_pedido",
                                         "poner_voz", "reproducir_voz"]   // poner_voz (Hub #779) y la muestra de voz (Hub #781): lo que suena es la voz misma, sin coro encima

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

    /// Cuánto tarda en ir de un volumen a otro (lineales, 0 = callado): entrar 1,2 s, salir 1,2 s, bajar 250 ms, subir 600 ms.
    static func duracion(desde: Float, hacia: Float) -> TimeInterval {
        if hacia <= 0.0001 { return salida }
        if desde <= 0.0001 { return entrada }
        return hacia < desde ? rampaBaja : rampaSube
    }

    /// La curva ease-in/ease-out (coseno): 0 → 0, 1 → 1, y empieza y termina con velocidad cero (sin escalón).
    static func curva(_ p: Double) -> Double {
        let x = max(0, min(1, p))
        return (1 - cos(Double.pi * x)) / 2
    }

    /// El volumen a `transcurrido` segundos de una rampa de `desde` a `hacia` que dura `duracion`.
    static func nivel(desde: Float, hacia: Float, duracion: TimeInterval, transcurrido: TimeInterval) -> Float {
        guard duracion > 0 else { return hacia }
        return desde + (hacia - desde) * Float(curva(transcurrido / duracion))
    }
}
