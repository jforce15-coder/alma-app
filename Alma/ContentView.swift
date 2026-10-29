import Combine
import SwiftUI
import WebKit

/// Pantalla principal: barra de dirección arriba, la página en medio y la burbuja de Alma flotando.
struct ContentView: View {
    @EnvironmentObject var nav: Navegador
    @State private var almaAbierta = false
    /// Triple toque a Alma en el navegador: captura de la pantalla que va como contexto de la conversación.
    @State private var captura: String?
    @State private var destello = false
    @State private var barraEnInicio = false
    @State private var salud = false
    @ObservedObject private var voz = VozNativa.shared
    @ObservedObject private var mejora = MejoraCampo.shared
    /// La roca de Alma del navegador: la misma de las web apps, en una capa encima de la página.
    @StateObject private var roca = RocaNavegador()
    @State private var llamadaOculta = false
    /// La conversación del modo anillo sigue en pantalla al abrir la app (y se puede terminar aquí).
    private var llamada: Binding<Bool> {
        Binding(get: { (voz.estado == .hablando || voz.estado == .conectando) && !llamadaOculta },
                set: { if !$0 { llamadaOculta = true } })
    }

    /// En el inicio la página ocupa toda la pantalla; deslizar desde arriba muestra la barra.
    private var limpio: Bool { nav.enInicio && !barraEnInicio }

    var body: some View {
        // La barra de dirección va abajo (al alcance del pulgar); con el teclado, sube con él.
        VStack(spacing: 0) {
            ZStack {
                WebVista(web: nav.web)
                    .ignoresSafeArea(edges: limpio ? .all : [])
                if limpio {
                    // franja invisible arriba: deslizar hacia abajo trae la barra para escribir una dirección
                    Color.clear.contentShape(Rectangle()).frame(maxWidth: .infinity).frame(height: 28)
                        .gesture(DragGesture(minimumDistance: 12).onEnded { g in if g.translation.height > 30 { barraEnInicio = true } })
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                // Fuera de Spacio AM: la roca de Alma (en las páginas de Spacio AM ya vive en la página: no se duplica).
                RocaVista(web: roca.web)
                    .opacity(nav.esSpacio ? 0 : 1)
                    .allowsHitTesting(!nav.esSpacio)
                if !nav.esSpacio && mejora.estado != .apagada {
                    AvisoMejora(zona: roca.zona, texto: mejora.textoAviso)
                }
                // destello de la captura
                Color.white.opacity(destello ? 0.55 : 0).allowsHitTesting(false).ignoresSafeArea()
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: nav.esSpacio)
            if !limpio { BarraDireccion().transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: limpio)
        .onChange(of: nav.enInicio) { _, en in if !en { barraEnInicio = false } }
        .onChange(of: nav.esSpacio) { _, s in roca.web.isHidden = s; if !s { roca.apartar(de: nil) } }   // al salir: a tu lugar (por si la moviste en el inicio)
        // Con un cuadro de texto activo, Alma se aparta (a la posición más lejana); al soltarlo, vuelve a su lugar.
        .onChange(of: nav.campo?.rect) { _, r in roca.apartar(de: r) }
        .onChange(of: mejora.estado) { _, e in roca.escuchar(e == .escuchando || e == .pensando) }
        .onAppear {
            roca.web.isHidden = nav.esSpacio
            // 1 toque: Alma sobre la página · 2: escribe en el cuadro de texto activo · 3: captura
            roca.alToques = { n in
                if n >= 3 { capturar() }
                else if n == 2, let c = nav.campo, !c.clave { mejorar() }
                else { captura = nil; almaAbierta = true }
            }
        }
        // Alma se llevó hacia un lado en el inicio: el navegador, con la barra lista para buscar. "" = volvió al centro.
        .onReceive(NotificationCenter.default.publisher(for: .modoNavegador)) { n in
            let pos = n.object as? String ?? ""
            if Navegador.posiciones.contains(pos) { nav.guardarPosicion(pos); barraEnInicio = true; nav.pedirBusqueda = true }
            else { nav.pedirBusqueda = false; barraEnInicio = false }
        }
        .background(Color.almaFondo)
        .fullScreenCover(isPresented: $salud) { SaludVista() }
        .background { Color.clear.fullScreenCover(isPresented: llamada) { LlamadaVista(voz: voz) { llamadaOculta = true } } }
        .onChange(of: voz.estado) { _, e in if e == .apagada || e == .lista { llamadaOculta = false } }
        .onReceive(NotificationCenter.default.publisher(for: .abrirSalud)) { _ in Portal.shared.pasar { salud = true } }
        .onAppear { Portal.shared.instalar() }
        .sheet(isPresented: $almaAbierta) {
            PanelAlma(titulo: nav.titulo, desde: nav.direccion, captura: captura)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

extension ContentView {
    /// Dos toques con un cuadro de texto activo: Alma escucha lo que le pides y escribe en el cuadro
    /// (sin pedido, mejora lo que ya dice; con el cuadro vacío y sin pedido, pregunta «¿En qué te ayudo?»).
    /// Va con la dirección de la página y, con el cuadro vacío, una captura de la pantalla: Alma ayuda con ese contexto
    /// (y la conversación queda con las demás, en su área de vida).
    func mejorar() {
        guard let c = nav.campo else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        var foto: String?
        let vacio = c.texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if vacio { nav.captura { foto = $0 } }   // se toma ya, mientras escucha
        mejora.empezar(textoCampo: c.texto) { pedido in
            guard let pedido else { return }
            let texto = nav.campo?.texto ?? c.texto
            mejora.escribir(texto: texto, pedido: pedido, pagina: nav.titulo, url: nav.direccion, etiqueta: c.etiqueta, captura: foto) { campo, decir, audio in
                if let campo { nav.ponerEnCampo(campo) }
                mejora.listo(decir: decir, audio: audio)
                UINotificationFeedbackGenerator().notificationOccurred(campo != nil || decir != nil ? .success : .error)
            }
        }
    }

    /// Triple toque: destello, la captura de lo que se ve, y Alma se abre ya con ella.
    func capturar() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        nav.captura { du in
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.08)) { destello = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { withAnimation(.easeOut(duration: 0.35)) { destello = false } }
                captura = du
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { almaAbierta = true }
            }
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
            GeometryReader { g in
                Rectangle().fill(Color.almaCoral)
                    .frame(width: g.size.width * CGFloat(nav.progreso), height: 2)
                    .opacity(nav.cargando ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: nav.progreso)
            }
            .frame(height: 2)
            // Al tocar la barra: acceso directo al home de Spacio AM (arriba del campo, que está abajo).
            if enfocado { atajoHome }
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
                    .frame(height: 34)
                    .background(Capsule().fill(Color.white.opacity(0.85)))
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
            .padding(.vertical, 6)
        }
        .background(Color.almaFondo.ignoresSafeArea(edges: .bottom))
        .animation(.easeOut(duration: 0.15), value: enfocado)
        .onChange(of: nav.direccion) { _, nueva in if !enfocado { texto = nueva } }
        .onChange(of: enfocado) { _, foco in
            if !foco { texto = nav.direccion }
            // Se abrió para buscar desde el inicio y se cerró sin buscar: Alma vuelve al centro.
            if !foco, nav.pedirBusqueda {
                nav.pedirBusqueda = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    if nav.enInicio && !nav.cargando { nav.almaAlCentro(); NotificationCenter.default.post(name: .modoNavegador, object: "") }
                }
            }
        }
        .onChange(of: nav.pedirBusqueda) { _, b in if b { texto = ""; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { enfocado = true } } }
        .onAppear {
            texto = nav.direccion
            if nav.pedirBusqueda { texto = ""; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { enfocado = true } }
        }
    }
}

extension BarraDireccion {
    var atajoHome: some View {
        Button {
            nav.abrir(texto: Navegador.homeSpacio.absoluteString)
            enfocado = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "house").font(.system(size: 14, weight: .medium))
                Text("Home de Spacio AM").font(.system(size: 15))
                Spacer()
                Text("hub.spacioam.com").font(.system(size: 12)).foregroundStyle(Color.almaTinta.opacity(0.5))
            }
            .foregroundStyle(Color.almaTinta)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transition(.opacity)
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

/// El WKWebView del navegador dentro de SwiftUI.
struct WebVista: UIViewRepresentable {
    let web: WKWebView
    func makeUIView(context: Context) -> WKWebView { web }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
