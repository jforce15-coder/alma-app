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
    /// «Mostrar en el chat»: lo que Alma puso en pantalla en la llamada (mostrar_en_chat). Con esto el chat se abrió desde la
    /// voz: la llamada sigue mientras lo ves y, al cerrarlo, cuelga y la app vuelve al inicio.
    @State private var chatDeVoz: VozNativa.Mostrado?
    /// La conversación del modo anillo sigue en pantalla al abrir la app (y se puede terminar aquí).
    private var llamada: Binding<Bool> {
        // En el inicio la conversación vive en la roca de la página (sa-nav), no en esta pantalla.
        Binding(get: { (voz.estado == .hablando || voz.estado == .conectando) && !llamadaOculta && !(nav.enInicio && nav.esSpacio) },
                set: { if !$0 { llamadaOculta = true } })
    }

    /// En el inicio la página ocupa toda la pantalla; deslizar desde arriba muestra la barra.
    private var limpio: Bool { nav.enInicio && !barraEnInicio }

    // (dividido en partes: todo junto era demasiado para el compilador)
    var body: some View {
        conRoca
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
            // Manos de Alma (navegador): Alma lee o actúa en la página; la pantalla de la llamada se baja para que la veas.
            .onReceive(NotificationCenter.default.publisher(for: .manosAlma)) { _ in llamadaOculta = true }
            // Los chips de la llamada (LlamadaVista): la pantalla de la llamada se baja y el inicio abre Personalidad de Alma.
            .onReceive(NotificationCenter.default.publisher(for: .abrirPersonalidad)) { _ in
                llamadaOculta = true
                nav.web.load(URLRequest(url: Navegador.personalidad))
            }
            .onAppear { Portal.shared.instalar() }
            .sheet(isPresented: $almaAbierta, onDismiss: chatCerrado) {
                PanelAlma(titulo: chatDeVoz == nil ? nav.titulo : "", desde: chatDeVoz == nil ? nav.direccion : "", captura: captura, mostrar: chatDeVoz)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
    }

    /// La roca del navegador: se aparta de los cuadros de texto, brilla mientras escucha y cuenta los toques.
    private var conRoca: some View {
        pantalla
            .onChange(of: nav.enInicio) { _, en in nav.mostrarBarra(); if !en { barraEnInicio = false } }   // cada pantalla empieza con la barra a la vista
            .onChange(of: nav.esSpacio) { _, s in roca.web.isHidden = s; if !s { roca.abajo(textoActivo) } }   // al salir: a tu lugar (por si la moviste en el inicio)
            // Con el teclado arriba (un cuadro de texto de la página o la barra), Alma va abajo al centro; al terminar, vuelve a su lugar.
            .onChange(of: textoActivo) { _, on in alma(abajo: on) }
            .onChange(of: mejora.estado) { _, _ in brilloRoca() }
            .onChange(of: voz.estado) { _, _ in brilloRoca() }   // la roca brilla durante la llamada de los tres toques
            .onChange(of: voz.mostrado) { _, m in if let m { ponerEnChat(m) } }
            .onAppear {
                roca.web.isHidden = nav.esSpacio
                roca.alToques = { n in tocaron(n) }
                nav.puntoRoca = { puntoRoca() }
            }
    }

    private var textoActivo: Bool { nav.campo != nil || nav.escribiendo }

    /// En las páginas de Spacio AM Alma es la de la página (sa-nav); en las demás, la de la capa de la app.
    private func alma(abajo on: Bool) {
        if nav.esSpacio {
            if !on && nav.enInicio { return }   // en el inicio, al cerrar la búsqueda Alma vuelve al centro (almaAlCentro)
            nav.web.evaluateJavaScript(on ? "window.SANav && SANav.ir && SANav.ir('bc')" : "window.SANav && SANav.volver && SANav.volver()")
        } else { roca.abajo(on) }
    }

    /// 1 toque: al inicio (en el navegador no hay menú que abrir; con la llamada abierta, muestra la llamada) · 2: escribe
    /// en el cuadro de texto activo, o Alma sobre la página · 3: captura y Alma por voz
    private func tocaron(_ n: Int) {
        if n >= 3 { capturar() }
        else if n == 2 { if let c = nav.campo, !c.clave { mejorar() } else { captura = nil; almaAbierta = true } }
        else if voz.estado == .hablando || voz.estado == .conectando { llamadaOculta = false }
        else { cerrarNavegador() }
    }

    /// ✕ (y un toque a la roca): cierra el navegador y vuelve al inicio de Alma, con su transición de siempre.
    private func cerrarNavegador() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        nav.irAlInicio()
    }

    /// La roca de la capa brilla mientras Alma escucha: al mejorar un cuadro de texto o en una llamada.
    private func brilloRoca() {
        roca.escuchar(mejora.estado == .escuchando || mejora.estado == .pensando || voz.estado == .hablando || voz.estado == .conectando)
    }

    /// Alma puso algo en pantalla (mostrar_en_chat): el chat se abre con eso y la llamada sigue. Si la pantalla de la llamada
    /// está encima, primero se baja (no se pueden mostrar las dos). Con el chat ya abierto, la página recibe lo nuevo.
    private func ponerEnChat(_ m: VozNativa.Mostrado) {
        chatDeVoz = m
        guard !almaAbierta else { return }
        let tapada = llamada.wrappedValue
        llamadaOculta = true; captura = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + (tapada ? 0.5 : 0.05)) { almaAbierta = true }
    }

    /// Se cerró el chat. Si lo abrió la voz, la llamada cuelga y la app queda en el inicio (escuchando como siempre).
    private func chatCerrado() {
        guard chatDeVoz != nil else { return }
        chatDeVoz = nil
        voz.colgar()
        if !nav.enInicio { nav.irAlInicio() }
    }

    /// Con la barra escondida: la pestañita abajo al centro (no con el teclado arriba).
    private var conPestanita: Bool { !limpio && nav.barraOculta && !textoActivo }
    /// Si la roca está abajo al centro en una página de Spacio AM (la de la página no se puede subir), la pestañita se corre.
    private var pestanitaCorrida: Bool { nav.esSpacio && nav.posAlma == "bc" }
    /// La roca arriba a la izquierda: el ✕ se corre a su derecha para no taparla.
    private var cerrarCorrido: Bool {
        if nav.esSpacio { return nav.posAlma == "tl" }
        return roca.zona.width > 0 && roca.zona.minX < 64 && roca.zona.minY < 64
    }

    /// Dónde está la roca en la pantalla: en el navegador, la de la capa (a la derecha); en el inicio, abajo al centro
    /// (ahí queda mientras se escribe la búsqueda).
    private func puntoRoca() -> CGPoint? {
        let v = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        let arriba = v?.safeAreaInsets.top ?? 0, tam = v?.bounds.size ?? .zero
        if !nav.esSpacio, roca.zona.width > 0 { return CGPoint(x: roca.zona.midX, y: roca.zona.midY + arriba) }
        if nav.enInicio { return CGPoint(x: tam.width / 2, y: tam.height - 150) }
        return nil
    }

    private var pantalla: some View {
        // La barra de dirección va abajo (al alcance del pulgar); con el teclado, sube con él.
        VStack(spacing: 0) {
            ZStack {
                WebVista(web: nav.web)
                    .ignoresSafeArea(edges: limpio ? .all : (nav.barraOculta ? .bottom : []))   // sin barra, la página llega hasta abajo
                if limpio {
                    // franja invisible arriba: deslizar hacia abajo trae la barra para escribir una dirección
                    Color.clear.contentShape(Rectangle()).frame(maxWidth: .infinity).frame(height: 28)
                        .gesture(DragGesture(minimumDistance: 12).onEnded { g in if g.translation.height > 30 { barraEnInicio = true } })
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                // Fuera de Spacio AM: la roca de Alma (en las páginas de Spacio AM ya vive en la página: no se duplica).
                RocaVista(web: roca.web)
                    .padding(.bottom, conPestanita ? 40 : 0)   // la roca de abajo queda encima de la pestañita, nunca sobre ella
                    .opacity(nav.esSpacio ? 0 : 1)
                    .allowsHitTesting(!nav.esSpacio)
                if !nav.esSpacio && mejora.estado != .apagada {
                    AvisoMejora(zona: roca.zona, texto: mejora.textoAviso)
                }
                if !nav.enInicio {
                    BotonCerrar { cerrarNavegador() }
                        .padding(.leading, cerrarCorrido ? 76 : 6).padding(.top, 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .transition(.opacity)
                }
                if conPestanita {
                    Pestanita { nav.mostrarBarra() }
                        .offset(x: pestanitaCorrida ? -84 : 0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                // destello de la captura
                Color.white.opacity(destello ? 0.55 : 0).allowsHitTesting(false).ignoresSafeArea()
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: nav.esSpacio)
            if !limpio && !nav.barraOculta { BarraDireccion().transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: limpio)
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: nav.barraOculta)
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

    /// Triple toque: destello, la captura de lo que se ve, y Alma por voz (solo la voz, sin el chat) con esa captura de
    /// contexto. La página queda a la vista mientras hablan (un toque a la roca muestra la llamada). Si la app todavía no
    /// tiene cómo llamar (nunca se abrió el inicio con sesión), se abre el chat con la captura, como antes.
    func capturar() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let titulo = nav.titulo, direccion = nav.direccion
        nav.captura { du in
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.08)) { destello = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { withAnimation(.easeOut(duration: 0.35)) { destello = false } }
                if voz.puedeHablar {
                    llamadaOculta = true
                    voz.hablarSobrePantalla(captura: du, titulo: titulo, direccion: direccion)
                } else {
                    captura = du
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { almaAbierta = true }
                }
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
            nav.escribiendo = foco
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

/// ✕ arriba a la izquierda (debajo del área segura): cierra el navegador y vuelve al inicio de Alma.
/// Se ve de 34 px, semitransparente oscuro; se toca en 44 px.
struct BotonCerrar: View {
    let accion: () -> Void
    var body: some View {
        Button(action: accion) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.black.opacity(0.45)))
                .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cerrar y volver al inicio")
    }
}

/// La pestañita de la barra: con la barra escondida, queda abajo al centro (70 × 22, oscura translúcida, con su raya blanca).
/// Un toque o deslizar hacia arriba trae la barra. Se toca en 44 px de alto.
struct Pestanita: View {
    let mostrar: () -> Void
    var body: some View {
        Capsule().fill(Color.black.opacity(0.55))
            .overlay(Capsule().fill(Color.white.opacity(0.9)).frame(width: 26, height: 3))
            .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.5))
            .frame(width: 70, height: 22)
            .shadow(color: Color.black.opacity(0.18), radius: 6, y: 2)
            .frame(width: 100, height: 44)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { g in
                let dx = g.translation.width, dy = g.translation.height
                if dy < -8 || (abs(dx) < 12 && abs(dy) < 12) { mostrar() }   // deslizar hacia arriba o un toque
            })
            .accessibilityElement()
            .accessibilityLabel("Mostrar la barra")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { mostrar() }
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
