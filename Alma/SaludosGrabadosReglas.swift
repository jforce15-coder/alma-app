import Foundation

/// Saludos grabados (Hub #724; Juan, 17-nov-2026: «reducir el tiempo de conexión inicial en llamadas con ElevenLabs: unos 50
/// saludos pregrabados con la voz de Alma en diferentes tonos para responder de inmediato mientras conecta, y un mensaje
/// pregrabado de respaldo si la conexión falla o no se escucha nada, pidiendo reiniciar la llamada»). Lógica pura, con sus
/// pruebas en Pruebas/SaludosGrabados. Lo que toca iOS: SaludosGrabados.swift (bajar, guardar y sonar) y VozNativa.swift.
/// · El Hub los graba con la voz de Alma (apps-script/saludosgrabados.js) y la app los guarda en el teléfono.
/// · Al abrir la llamada, pasada la señal, suena uno al instante (nunca el mismo dos veces seguidas) y ElevenLabs ya no
///   saluda: Alma solo escucha. Solo donde Alma abriría con el Saludo variado; si Juan ya habla, no suena.
/// · Aviso de volver a llamar: si la llamada termina porque no conectó (o se cayó y no se pudo seguir), Alma lo dice con su voz.
enum SaludosGrabadosReglas {
    /// El id del Aviso de volver a llamar (los saludos son s01…s50).
    static let aviso = "aviso"
    /// Cada cuánto se le pregunta al Hub como mucho, y cuántas vueltas seguidas mientras faltan (cada una graba hasta 12).
    static let cadaCuanto: TimeInterval = 90
    static let vueltas = 6

    /// Dónde se abre la llamada (lo que decide si Alma saludaría con el Saludo variado).
    struct Llamada {
        var alma = true            // no Claudio ni Alma que vuelve de Claudio
        var reabierta = false      // tras un corte: abre con su frase
        var porAviso = false       // Alma abre para contar un resultado
        var pantalla = false       // tres toques en el navegador: «Hola, ahora lo veo»
        var conferencia = false    // la nombraron en conferencia (o el Modo Inicio)
        var conPedido = false      // dijeron el pedido junto con «Alma»
        var juanHabla = false      // ya hablaba al conectar
        var sinRed = false         // va con la voz de respaldo
    }

    /// ¿Suena un saludo grabado? Igual que el Saludo variado: no con otra frase de apertura ni si Juan ya habla.
    static func toca(_ l: Llamada) -> Bool {
        guard l.alma, !l.reabierta, !l.porAviso, !l.pantalla, !l.juanHabla, !l.sinRed else { return false }
        if l.conferencia && l.conPedido { return false }
        return true
    }

    /// Uno al azar entre los saludos guardados, nunca el último que sonó.
    static func elegir(_ ids: [String], ultimo: String?, azar: (Int) -> Int = { Int.random(in: 0..<$0) }) -> String? {
        let saludos = ids.filter { $0 != aviso }
        let opciones = saludos.count > 1 ? saludos.filter { $0 != ultimo } : saludos
        return opciones.isEmpty ? nil : opciones[azar(opciones.count)]
    }

    /// El primer mensaje para ElevenLabs cuando ya sonó un saludo grabado: vacío (Alma escucha), salvo un tema por retomar.
    static func primerMensaje(retomar: String?) -> String { retomar ?? "" }

    /// ¿Hay que preguntarle al Hub? Si la versión cambió, si faltan o si nunca se pidió; como mucho cada `cadaCuanto`.
    static func pedir(version: String?, local: String, completo: Bool, ultimo: Date?, ahora: Date) -> Bool {
        if let u = ultimo, ahora.timeIntervalSince(u) < cadaCuanto { return false }
        if let v = version, !v.isEmpty, v != local { return true }
        return local.isEmpty || !completo
    }

    /// Lo que se manda al Hub: los que ya tiene (con su versión), para recibir solo los que faltan.
    static func pedido(token: String, sesion: String, version: String, tiene: [String]) -> [String: Any] {
        ["hub": 1, "action": "vozSaludosGrabados", "token": token, "session": sesion, "version": version, "tiene": tiene.sorted()]
    }

    /// Lo que contestó el Hub: la versión, si ya están todos y los clips nuevos (id → mp3 en base64).
    struct Respuesta: Equatable { let version: String; let completo: Bool; let clips: [String: String] }
    static func respuesta(_ j: [String: Any]?) -> Respuesta? {
        guard let j, (j["ok"] as? Bool) == true, let v = j["version"] as? String, !v.isEmpty else { return nil }
        var clips: [String: String] = [:]
        for c in (j["clips"] as? [[String: Any]]) ?? [] {
            if let id = c["id"] as? String, id.range(of: "^[a-z0-9]{1,12}$", options: .regularExpression) != nil, let mp3 = c["mp3"] as? String, !mp3.isEmpty { clips[id] = mp3 }
        }
        return Respuesta(version: v, completo: (j["completo"] as? Bool) == true, clips: clips)
    }
}
