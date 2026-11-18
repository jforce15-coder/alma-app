import Foundation

/// Modo Creator (Hub #770; Juan, 18-nov-2026): hablando con Claudio, Juan ve la app que se trabaja en BORRADOR y los cambios al momento.
/// La pantalla es la del Hub (alma/creator.html: el borrador aislado, BORRADOR o EN VIVO, lo pedido y publicar); la app solo decide cuándo
/// abrirla a pantalla completa, con la llamada abajo. Lógica pura: la prueba Pruebas/Creator.
enum CreatorReglas {
    /// La herramienta de Claudio que cambia, deshace, abre una app o publica (apps-script/creator.js).
    static let herramienta = "claudio_creator"
    /// `app=1`: la página esconde su botón de volver (la cierra el botón de la app).
    static let direccion = URL(string: "https://hub.spacioam.com/alma/creator.html?app=1")!

    /// Se abre cuando Claudio usó su herramienta del Modo Creator y salió bien: así Juan ve el cambio sin tocar nada.
    /// Solo con Claudio (con Alma no hay Modo Creator) y nunca si el Hub contestó con error.
    static func abre(herramienta: String, conClaudio: Bool, error: Bool) -> Bool {
        conClaudio && !error && herramienta == Self.herramienta
    }

    /// ¿Esta dirección es el Modo Creator? (para no abrirlo dos veces encima del navegador que ya lo muestra)
    static func esCreator(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.host == "hub.spacioam.com" && url.path == "/alma/creator.html"
    }
}
