import Foundation

// Muestras de voz (Hub #781; Juan, 18-nov-2026): «que Claudio pueda reproducir audios de las voces que pida durante la
// llamada». Claudio busca la voz en el Hub (claudio_voces, muestrasvoz.js) y llama a la herramienta de cliente
// reproducir_voz con su voice_id. La app pide la muestra al Hub (acción vozMuestra) en el formato de ESTA llamada (PCM 16
// bits al hz de la salida) y la pone por la misma salida que la voz del agente (VozNativa.sonar): la cancelación de eco la
// resta del micrófono. Contesta cuando terminó de sonar, así Claudio no habla encima y luego pregunta qué le pareció.
// Aquí, la lógica pura (sin iOS; se prueba sola en Pruebas/MuestraVoz): validar lo que llega y armar lo que se contesta.
enum MuestraVoz {
    static let herramienta = "reproducir_voz"
    /// Lo que se espera después de que termina de sonar, antes de contestar (el último trozo y el eco se apagan).
    static let colita: TimeInterval = 0.35

    /// El voice_id de ElevenLabs: letras y números, de 12 a 40.
    static func idValido(_ id: String) -> Bool {
        (12...40).contains(id.count) && id.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) && $0.isASCII }
    }

    /// El nombre para lo que se le dice a Claudio (limpio y corto).
    static func nombre(_ crudo: Any?) -> String {
        let t = (crudo as? String ?? "").split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        return t.isEmpty ? "esa voz" : String(t.prefix(40))
    }

    /// Segundos que dura el PCM de 16 bits mono a `hz`.
    static func duracion(bytes: Int, hz: Double) -> TimeInterval { hz > 0 ? Double(bytes / 2) / hz : 0 }

    /// Lo que llegó del Hub: el PCM si sirve para esta llamada (mismo hz), o el porqué no.
    static func audio(_ j: [String: Any]?, hz: Double) -> (pcm: Data?, error: String) {
        guard let j else { return (nil, "el Hub no respondió") }
        guard (j["ok"] as? Bool) == true else { return (nil, (j["error"] as? String).map { String($0.prefix(160)) } ?? "el Hub no la mandó") }
        guard ((j["hz"] as? NSNumber)?.doubleValue ?? 0) == hz else { return (nil, "llegó en otro formato de audio") }
        guard let a = j["audio"] as? String, let pcm = Data(base64Encoded: a), pcm.count >= 2 else { return (nil, "llegó vacía") }
        return (pcm, "")
    }

    static func sono(_ nombre: String, segundos: TimeInterval) -> String {
        "Ya sonó la muestra de \(nombre) (\(max(1, Int(segundos.rounded()))) s). Pregúntale a Juan qué le pareció; si quiere otra, pon la siguiente."
    }
    static func noSono(_ porque: String) -> String {
        "No sonó la muestra: \(porque). Díselo a Juan en una frase; la tarjeta con su botón quedó en el hilo de Claudio para oírla ahí."
    }
}
