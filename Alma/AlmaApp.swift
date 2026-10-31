import SwiftUI

/// Alma · navegador con Alma integrada.
/// Abre cualquier página (las apps de Spacio AM, GitHub, Google…) y tiene a Alma a un toque, con la página como contexto.
@main
struct AlmaApp: App {
    @StateObject private var navegador = Navegador()

    init() {
        // Con un anillo ya conectado antes, se retoma la conexión desde el arranque (también si iOS despierta la app por él).
        if Anillo.hayGuardado { _ = Anillo.shared }
        // «Alma con el anillo»: la app queda lista para que dos toques del anillo enciendan o apaguen el modo conferencia, también con el teléfono bloqueado.
        VozNativa.shared.arrancarSiHaceFalta()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(navegador)
                // alma://abrir?u=<enlace> (atajo de Compartir de iOS) o alma://https://…
                .onOpenURL { navegador.abrir(desdeEnlace: $0) }
        }
    }
}

extension Color {
    /// Colores de la marca (Spacio AM · design system).
    static let almaCoral = Color(red: 0xE9 / 255, green: 0x82 / 255, blue: 0x6A / 255)
    static let almaTinta = Color(red: 0x3E / 255, green: 0x3F / 255, blue: 0x3F / 255)
    static let almaFondo = Color(red: 0xF5 / 255, green: 0xF3 / 255, blue: 0xF0 / 255)
    static let almaBorde = Color(red: 0xD8 / 255, green: 0xD4 / 255, blue: 0xCE / 255)
}
