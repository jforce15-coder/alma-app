import SwiftUI
import WebKit

/// Pantalla principal: barra de dirección arriba, la página en medio y la burbuja de Alma flotando.
struct ContentView: View {
    @EnvironmentObject var nav: Navegador
    @State private var almaAbierta = false

    var body: some View {
        VStack(spacing: 0) {
            BarraDireccion()
            ZStack(alignment: .bottomTrailing) {
                WebVista(web: nav.web)
                    .ignoresSafeArea(edges: .bottom)
                // En las páginas de Spacio AM, Alma ya vive en la roca de la página: no se duplica.
                if !nav.esSpacio {
                    BurbujaAlma { almaAbierta = true }
                        .padding(.trailing, 18)
                        .padding(.bottom, 26)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: nav.esSpacio)
        }
        .background(Color.almaFondo)
        .sheet(isPresented: $almaAbierta) {
            PanelAlma(titulo: nav.titulo, desde: nav.direccion)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

/// ‹ › · dirección o búsqueda · compartir · recargar. Línea coral de progreso debajo mientras carga.
struct BarraDireccion: View {
    @EnvironmentObject var nav: Navegador
    @State private var texto = ""
    @FocusState private var enfocado: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Boton(simbolo: "chevron.left", activo: nav.puedeAtras) { nav.web.goBack() }
                Boton(simbolo: "chevron.right", activo: nav.puedeAdelante) { nav.web.goForward() }
                TextField("Dirección o búsqueda", text: $texto)
                    .focused($enfocado)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.webSearch)
                    .submitLabel(.go)
                    .onSubmit { nav.abrir(texto: texto); enfocado = false }
                    .font(.system(size: 15))
                    .foregroundStyle(Color.almaTinta)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(Capsule().fill(Color.white))
                    .overlay(Capsule().stroke(Color.almaBorde, lineWidth: 1))
                if !enfocado, let u = URL(string: nav.direccion), u.scheme != nil {
                    ShareLink(item: u) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 16, weight: .medium)).frame(width: 36, height: 38)
                    }
                    .tint(Color.almaTinta)
                }
                Boton(simbolo: nav.cargando ? "xmark" : "arrow.clockwise", activo: true) {
                    if nav.cargando { nav.web.stopLoading() } else { nav.web.reload() }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            GeometryReader { g in
                Rectangle().fill(Color.almaCoral)
                    .frame(width: g.size.width * CGFloat(nav.progreso), height: 2)
                    .opacity(nav.cargando ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: nav.progreso)
            }
            .frame(height: 2)
        }
        .background(Color.almaFondo)
        .onChange(of: nav.direccion) { _, nueva in if !enfocado { texto = nueva } }
        .onChange(of: enfocado) { _, foco in if !foco { texto = nav.direccion } }
        .onAppear { texto = nav.direccion }
    }
}

struct Boton: View {
    let simbolo: String
    let activo: Bool
    let accion: () -> Void
    var body: some View {
        Button(action: accion) {
            Image(systemName: simbolo).font(.system(size: 16, weight: .medium)).frame(width: 34, height: 38)
        }
        .disabled(!activo)
        .tint(Color.almaTinta)
    }
}

/// La roca de Alma: blanca y limpia, con su halo coral (igual que el ícono de la app).
struct BurbujaAlma: View {
    let accion: () -> Void
    var body: some View {
        Button(action: accion) {
            ZStack {
                // halo de Alma
                Circle().fill(Color.almaCoral.opacity(0.28)).frame(width: 74, height: 74).blur(radius: 12)
                // la roca: blanca, con volumen y un borde coral fino (como el ícono)
                Circle()
                    .fill(RadialGradient(colors: [Color(white: 0.98), Color(red: 0.91, green: 0.90, blue: 0.88)], center: UnitPoint(x: 0.38, y: 0.32), startRadius: 2, endRadius: 40))
                    .overlay(Circle().stroke(Color.almaCoral.opacity(0.55), lineWidth: 2))
                    .frame(width: 58, height: 58)
                    .shadow(color: Color.almaCoral.opacity(0.25), radius: 10, y: 5)
                Image(systemName: "sparkle").font(.system(size: 15, weight: .medium)).foregroundStyle(Color.almaCoral.opacity(0.5))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hablar con Alma sobre esta página")
    }
}

/// El WKWebView del navegador dentro de SwiftUI.
struct WebVista: UIViewRepresentable {
    let web: WKWebView
    func makeUIView(context: Context) -> WKWebView { web }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
