import Foundation

/// Hablar con Claudio (Hub #550; Juan, 16-nov-2026): con quién habla la llamada y cuándo se cambia. Lógica pura, con sus
/// pruebas en Pruebas/AgenteVoz.
/// · Juan pide hablar con Claudio: Alma dice «Sí, no hay problema, te paso con Claudio» y usa hablar_con_claudio (herramienta
///   de la app). La app espera a que termine esa frase, pide al Hub la conversación de Claudio (acción vozClaudio, solo el
///   administrador principal) y cambia el socket sin colgar: otro agente, otra voz y el halo todo naranja.
/// · Claudio usa volver_con_alma: la app vuelve a Alma (acción vozWeb) y Alma dice que está de nuevo.
/// · Solo cambia la herramienta del agente que corresponde: Alma no «vuelve con Alma» ni Claudio pasa «con Claudio».
enum AgenteVoz: String, Equatable {
    case alma, claudio

    /// El agente al que lleva una herramienta de cliente, o nil si no es un cambio válido para quien habla ahora.
    static func cambio(herramienta: String, actual: AgenteVoz) -> AgenteVoz? {
        switch (herramienta, actual) {
        case ("hablar_con_claudio", .alma): return .claudio
        case ("volver_con_alma", .claudio): return .alma
        default: return nil
        }
    }
    /// ¿Es una de las herramientas de cambio? (No se contestan: expects_response false, así no hacen hablar al agente.)
    static func esCambio(_ herramienta: String) -> Bool { herramienta == "hablar_con_claudio" || herramienta == "volver_con_alma" }

    var nombre: String { self == .claudio ? "Claudio" : "Alma" }
    /// La acción del Hub que da su conversación (URL firmada y ficha).
    var accion: String { self == .claudio ? "vozClaudio" : "vozWeb" }

    /// Lo que se manda al Hub para abrir la conversación de este agente. Con Alma va «claudio»: la app sabe cambiar de
    /// agente, y el Hub le da a Alma el permiso de pasar a Claudio (solo con el principal).
    static func pedido(_ a: AgenteVoz, token: String, sesion: String, motivo: String = "") -> [String: Any] {
        var b: [String: Any] = ["hub": 1, "action": a.accion, "token": token, "session": sesion]
        if a == .claudio { b["motivo"] = String(motivo.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)) }
        else { b["app"] = "alma"; b["claudio"] = true }
        return b
    }

    /// ¿Ya se puede cerrar la conversación de antes? Cuando terminó de sonar su frase («te paso con Claudio») y pasó un
    /// respiro, o a los `tope` segundos de pedido el cambio (para no quedarse esperando si el audio no avisa).
    static let respiro = 0.35, tope = 6.0
    static func listo(finVoz: Date, pedido: Date, ahora: Date) -> Bool {
        ahora.timeIntervalSince(finVoz) >= respiro || ahora.timeIntervalSince(pedido) >= tope
    }

    /// El primer mensaje de la conversación nueva: Claudio, el que trae su ficha; Alma al volver, esta frase (Juan no la
    /// llamó: ya estaba en la llamada).
    static let vuelta = "Aquí estoy de nuevo. ¿Qué más hacemos?"
    static func primerMensaje(_ a: AgenteVoz, ficha: String) -> String {
        a == .claudio ? (ficha.isEmpty ? "Hola, aquí Claudio. ¿Qué hacemos?" : ficha) : vuelta
    }

    /// Lo que dice la pantalla de la llamada mientras habla el agente.
    func estadoTexto(habla: Bool) -> String { habla ? nombre + " te responde" : "Te escucho" }

    /// El color del halo (rojo, verde, azul de 0 a 1): Claudio todo naranja; Alma, nil (su coral de siempre).
    var halo: (r: Double, g: Double, b: Double)? { self == .claudio ? (0.96, 0.51, 0.12) : nil }
}
