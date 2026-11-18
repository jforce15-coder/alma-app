import SwiftUI

/// Modo Creator (Hub #770) a pantalla completa en iPhone y iPad: la página del Hub con la misma sesión que el visor
/// (PanelWeb). La llamada con Claudio sigue abajo: Juan habla y la vista previa se redibuja sola.
struct CreatorVista: View {
    @Environment(\.dismiss) private var cerrar

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PanelWeb(url: CreatorReglas.direccion)
                .ignoresSafeArea(edges: .bottom)
            Button { cerrar() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .foregroundStyle(Color.primary)
            .accessibilityLabel("Cerrar el Modo Creator")
            .padding(.trailing, 14)
            .padding(.top, 6)
        }
        .background(Color.almaFondo)
    }
}

extension Notification.Name {
    /// Claudio usó claudio_creator (VozNativa) o Juan pidió verlo: ContentView lo abre a pantalla completa.
    static let abrirCreator = Notification.Name("alma.creator.abrir")
}
