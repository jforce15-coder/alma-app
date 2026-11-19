import Foundation

/// Archivos como entrada para Alma (Hub, Juan 18-nov-2026: «si hacemos drag and drop de un archivo en el app de Alma debe
/// leerlo como input… el archivo solo quedará cargado y el usuario tiene que dar un prompt»).
/// «Compartir» o «Abrir en Alma» desde Archivos, Mail o cualquier app: iOS abre la app con el archivo (onOpenURL, una URL
/// de archivo). Aquí, sin UIKit: qué tipos sirven, el tope de 8 MB (el mismo del Hub, adjuntos.js) y el JavaScript que
/// lo deja cargado en el chat del inicio (AlmaArchivos.recibir → SANav.adjuntar). Soltarlo encima en el iPad lo recibe la
/// página misma (WKWebView entrega el archivo al «drop» del inicio).
enum ArchivosEntrada {
    static let maxBytes = 8_000_000

    /// El tipo que el Hub sabe leer, por la extensión (iOS a veces no dice el tipo). nil = no se puede leer.
    static func mime(nombre: String) -> String? {
        let ext = (nombre as NSString).pathExtension.lowercased()
        let tipos: [String: String] = [
            "pdf": "application/pdf",
            "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "doc": "application/msword",
            "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "xls": "application/vnd.ms-excel",
            "csv": "text/csv", "txt": "text/plain",
            "mp3": "audio/mpeg", "m4a": "audio/mp4", "aac": "audio/aac", "wav": "audio/wav", "ogg": "audio/ogg", "opus": "audio/ogg", "amr": "audio/amr",
            "jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "heic": "image/heic", "webp": "image/webp"
        ]
        return tipos[ext]
    }

    enum Resultado: Equatable { case listo(String), noSirve(String) }

    /// El JavaScript para el inicio, o por qué no (lo que Alma le dice a Juan en el chat).
    static func js(nombre: String, datos: Data) -> Resultado {
        let limpio = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = limpio.isEmpty ? "archivo" : String(limpio.prefix(100))
        guard let mime = mime(nombre: n) else { return .noSirve("«\(n)» no lo puedo abrir. Mándame un PDF, Word, Excel, CSV, una foto o un audio.") }
        guard !datos.isEmpty else { return .noSirve("«\(n)» está vacío.") }
        guard datos.count <= maxBytes else { return .noSirve("«\(n)» pasa de 8 MB.") }
        let o: [String: String] = ["nombre": n, "mime": mime, "data": datos.base64EncodedString()]
        guard let j = try? JSONSerialization.data(withJSONObject: o), let s = String(data: j, encoding: .utf8) else { return .noSirve("No pude leer «\(n)».") }
        return .listo("window.AlmaArchivos && AlmaArchivos.recibir(\(s))")
    }

    /// Lo que no sirve también se dice en el chat (nunca se calla): el mismo camino, con el texto ya escrito.
    static func jsAviso(_ texto: String) -> String {
        guard let j = try? JSONSerialization.data(withJSONObject: ["error": texto]), let s = String(data: j, encoding: .utf8) else { return "" }
        return "window.AlmaArchivos && AlmaArchivos.recibir(\(s))"
    }
}
