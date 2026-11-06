import Foundation

/// El orden al empezar una llamada con ElevenLabs (lógica pura, con sus pruebas en Pruebas/InicioVoz).
/// Juan, 6-nov-2026 (conv_1801m6q42bpzegvbj2ke5wjwa839, modo conferencia): Alma lo trató como un huésped («Número no
/// identificado»). La app sí arma las mismas variables que en la llamada normal (quien_llama, audiencia…), pero en la
/// conferencia lo que dijo con «Alma» (user_message) salía en cuanto ElevenLabs contestaba, ANTES de la ficha
/// (conversation_initiation_client_data, que espera la ventana del saludo): ElevenLabs empezó la conversación con lo de
/// fábrica y la ficha que llegó después ya no contó («Unrecognized message type received from client»).
/// Regla: antes de la ficha no sale nada de la conversación (texto, contexto, audio); solo la ficha y el pong.
enum InicioVoz {
    enum Paso: Equatable { case mandar, esperar }
    static let ficha = "conversation_initiation_client_data"
    /// `tipo`: el «type» del mensaje (o «user_audio_chunk» para el audio).
    static func decidir(tipo: String, inicioEnviado: Bool) -> Paso {
        if inicioEnviado || tipo == ficha || tipo == "pong" { return .mandar }
        return .esperar
    }
    /// El tipo de un mensaje para el socket.
    static func tipo(_ o: [String: Any]) -> String {
        if let t = o["type"] as? String { return t }
        return o["user_audio_chunk"] != nil ? "user_audio_chunk" : ""
    }
}
