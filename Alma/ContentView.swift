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
                // En las páginas de Spacio AM, Alma ya vive en la roca de la página: no se duplica.
                if !nav.esSpacio {
                    AlmaFlotante(pos: nav.posAlma, campo: nav.campo?.rect, mejora: mejora.estado, oido: mejora.oido,
                                 mover: { nav.guardarPosicion($0) },
                                 tocar: { captura = nil; almaAbierta = true },
                                 dobleToque: { if nav.campo != nil && nav.campo?.clave == false { mejorar() } else { captura = nil; almaAbierta = true } },
                                 tripleToque: capturar)
                        .transition(.scale.combined(with: .opacity))
                }
                // destello de la captura
                Color.white.opacity(destello ? 0.55 : 0).allowsHitTesting(false).ignoresSafeArea()
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: nav.esSpacio)
            if !limpio { BarraDireccion().transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: limpio)
        .onChange(of: nav.enInicio) { _, en in if !en { barraEnInicio = false } }
        .onChange(of: nav.esSpacio) { _, s in if !s { nav.leerPosicion() } }   // por si la movieron en una web app
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
    func mejorar() {
        guard let c = nav.campo else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        mejora.empezar(textoCampo: c.texto) { pedido in
            guard let pedido else { return }
            let texto = nav.campo?.texto ?? c.texto
            let host = URL(string: nav.direccion)?.host ?? ""
            mejora.escribir(texto: texto, pedido: pedido, pagina: [nav.titulo, host].filter { !$0.isEmpty }.joined(separator: " · "), etiqueta: c.etiqueta) { r in
                mejora.listo()
                if let r { nav.ponerEnCampo(r); UINotificationFeedbackGenerator().notificationOccurred(.success) }
                else { UINotificationFeedbackGenerator().notificationOccurred(.error) }
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

/// Alma en el navegador: en una de las 8 posiciones del Hub, igual que el botón roca de las web apps.
/// Deslizarla la lleva a otra posición (la más cercana a donde la sueltas) · 1 toque: Alma · 3 toques: Alma con captura.
struct AlmaFlotante: View {
    let pos: String
    /// El cuadro de texto activo de la página: mientras está, Alma se va a la posición más alejada de él.
    var campo: CGRect? = nil
    var mejora: MejoraCampo.Estado = .apagada
    var oido = ""
    let mover: (String) -> Void
    let tocar: () -> Void
    let dobleToque: () -> Void
    let tripleToque: () -> Void
    @State private var arrastre: CGSize = .zero
    @State private var arrastrando = false
    @State private var toques = 0
    @State private var espera: DispatchWorkItem?

    var body: some View {
        GeometryReader { g in
            let aqui = campo.map { AlmaFlotante.lejana($0, g.size) } ?? pos
            let p = AlmaFlotante.punto(aqui, g.size)
            RocaAlma()
                .overlay(Circle().stroke(Color.almaCoral, lineWidth: 3).scaleEffect(escucha ? 1.18 : 1.02).opacity(mejora == .apagada ? 0 : escucha ? 0.25 : 0.9)
                    .animation(mejora == .apagada ? .default : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: escucha))
                .scaleEffect(arrastrando ? 1.12 : 1)
                .frame(width: 84, height: 84)
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { v in
                            if !arrastrando { arrastrando = true; UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                            arrastre = v.translation
                        }
                        .onEnded { v in
                            let fin = CGPoint(x: p.x + v.predictedEndTranslation.width, y: p.y + v.predictedEndTranslation.height)
                            let nueva = AlmaFlotante.cercana(fin, g.size)
                            let q = AlmaFlotante.punto(nueva, g.size)
                            // sin salto: el desplazamiento se cuenta desde el lugar nuevo y el resorte lo lleva a cero
                            var t = Transaction(); t.disablesAnimations = true
                            withTransaction(t) { arrastre = CGSize(width: p.x + v.translation.width - q.x, height: p.y + v.translation.height - q.y); mover(nueva) }
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { arrastre = .zero; arrastrando = false }
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        }
                )
                .simultaneousGesture(TapGesture().onEnded { tocado() })
                .accessibilityElement()
                .accessibilityLabel("Alma")
                .accessibilityHint("Un toque para hablar con Alma sobre esta página · dos toques en un cuadro de texto: escribe por ti · tres toques: le mandas una captura")
                .accessibilityAction { tocar() }
                .position(x: p.x + arrastre.width, y: p.y + arrastre.height)
                .animation(.spring(response: 0.45, dampingFraction: 0.75), value: aqui)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: arrastrando)
            // lo que Alma está haciendo en el cuadro: escuchando (con lo que oye) o escribiendo
            if mejora != .apagada {
                Text(mejora == .pensando ? "Escribiendo…" : oido.isEmpty ? "Te escucho…" : oido)
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Color.almaTinta).lineLimit(2)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Capsule().fill(.ultraThinMaterial)).overlay(Capsule().stroke(Color.almaBorde, lineWidth: 0.5))
                    .frame(maxWidth: min(g.size.width - 40, 300))
                    .position(x: max(min(p.x, g.size.width - 160), min(160, g.size.width / 2)), y: p.y + (p.y > g.size.height / 2 ? -74 : 74))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .allowsHitTesting(false)
            }
        }
    }

    private var escucha: Bool { mejora == .escuchando }

    /// Se cuentan los toques seguidos: 1 = Alma · 2 = mejorar el cuadro de texto activo · 3 = captura.
    private func tocado() {
        espera?.cancel(); toques += 1
        if toques >= 3 { toques = 0; tripleToque(); return }
        let w = DispatchWorkItem { let n = toques; toques = 0; if n == 2 { dobleToque() } else { tocar() } }
        espera = w; DispatchQueue.main.asyncAfter(deadline: .now() + 0.32, execute: w)
    }

    /// Las 8 posiciones dentro del área segura (la vista ya está dentro de ella).
    static func punto(_ a: String, _ s: CGSize) -> CGPoint {
        let m: CGFloat = 46
        let x: CGFloat = a.hasSuffix("l") ? m : a.hasSuffix("r") ? s.width - m : s.width / 2
        let y: CGFloat = a.hasPrefix("t") ? m : a.hasPrefix("b") ? s.height - m - 10 : s.height / 2
        return CGPoint(x: x, y: y)
    }

    /// La posición más alejada del cuadro de texto (para no taparlo).
    static func lejana(_ r: CGRect, _ s: CGSize) -> String {
        let c = CGPoint(x: r.midX, y: r.midY)
        return Navegador.posiciones.max { hypot(punto($0, s).x - c.x, punto($0, s).y - c.y) < hypot(punto($1, s).x - c.x, punto($1, s).y - c.y) } ?? "br"
    }

    static func cercana(_ p: CGPoint, _ s: CGSize) -> String {
        Navegador.posiciones.min { hypot(punto($0, s).x - p.x, punto($0, s).y - p.y) < hypot(punto($1, s).x - p.x, punto($1, s).y - p.y) } ?? "br"
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

/// La roca de Alma: blanca y limpia, con su halo coral (igual que el ícono de la app).
/// La roca de Alma: blanca y limpia, con su halo coral (igual que el ícono de la app).
struct RocaAlma: View {
    var body: some View {
            ZStack {
                // halo de Alma
                Circle().fill(Color(red: 0.98, green: 0.68, blue: 0.54).opacity(0.5)).frame(width: 84, height: 84).blur(radius: 14)
                // la roca: blanca, con volumen y un borde coral fino (como el ícono)
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.98, green: 0.976, blue: 0.97), Color(red: 0.94, green: 0.93, blue: 0.92)], center: UnitPoint(x: 0.4, y: 0.35), startRadius: 2, endRadius: 40))
                    .overlay(Circle().stroke(Color.almaCoral.opacity(0.55), lineWidth: 2))
                    .frame(width: 58, height: 58)
                    .shadow(color: Color.almaCoral.opacity(0.25), radius: 10, y: 5)
                // destello grabado, como el del botón roca: gris cálido, luz abajo a la derecha y sombra arriba
                Image(systemName: "sparkle").font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color(red: 0xC9 / 255, green: 0xC1 / 255, blue: 0xB8 / 255))
                    .shadow(color: .white, radius: 0, x: 0.8, y: 1)
                    .shadow(color: Color.black.opacity(0.12), radius: 0.5, x: -0.6, y: -0.6)
            }
    }
}

/// El WKWebView del navegador dentro de SwiftUI.
struct WebVista: UIViewRepresentable {
    let web: WKWebView
    func makeUIView(context: Context) -> WKWebView { web }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
