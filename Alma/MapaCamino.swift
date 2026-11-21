import CoreLocation
import MapKit
import SwiftUI

/// La pantalla de la Guía de camino (GuiaCamino.swift) con dos paneles, como la de un Tesla (Juan, 20-nov-2026: «A
/// teléfono, A iPad y B teléfono girado»):
///   · A (vertical, iPhone y iPad), sin hueco (Juan, 21-nov-2026: «demasiado espacio muerto arriba»): arriba, pegada al
///     área segura, la tarjeta del giro con su punto de referencia y el «Luego»; debajo el panel del medio (GuiaPanelMedio:
///     selector compacto, escena animada, velocidad; ~40 %) y el mapa hasta abajo (~60 %) con la llegada encima
///     (GuiaPantalla.cortesA).
///   · B (pantalla acostada): lado a lado, el panel del medio a la izquierda (~40 %) con la frase de Alma abajo y el
///     mapa a la derecha con la tarjeta del giro arriba.
///   · En el mapa, tu punto es la roca de Alma (RocaAlma, con su halo y su pulso) y de ella sale la luz de rumbo: un cono
///     de 90° con los colores del halo que apunta hacia donde mira el teléfono («me gusta mucho la luz que indica hacia
///     dónde ve el usuario, pero hay que incrementar el ángulo»). Con «Reducir movimiento» la roca no late, pero la luz
///     sigue el rumbo: es información.
///   · Abajo, la llegada: hora, minutos, distancia y «Terminar».
///   · La roca va al centro (a lo ancho) de lo que se ve del mapa y un poco abajo, para ver las calles que siguen
///     (GuiaPantalla.margenMapa). «Ver ruta» muestra la ruta entera en 2D; «Centrar», o 10 s sin tocar, vuelve a seguirte.
/// El mapa es de Google Maps (MapaGoogle.swift); sin su llave, el de Apple con la misma pantalla. Al girar el teléfono
/// los paneles se acomodan con una transición suave (el mapa es el mismo, no se vuelve a crear).
struct MapaCaminoVista: View {
    @ObservedObject var guia = GuiaCamino.shared
    @Environment(\.dismiss) private var cerrar
    @Environment(\.accessibilityReduceMotion) private var quieto
    @State private var camara: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
    @State private var siguiendo = true
    /// «Ver ruta»: la ruta entera en el mapa (2D) hasta «Centrar» o unos segundos sin tocar.
    @State private var verRuta = false
    /// Cuenta cada vez que tocas el mapa o pides «Ver ruta»: desde el último, a los 10 s vuelve a seguir a la roca.
    @State private var toque = 0
    /// El alto de la tarjeta del giro en A (para que el panel empiece justo debajo).
    @State private var altoGiro: CGFloat = 104

    private var puntos: [CLLocationCoordinate2D] { guia.linea.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) } }
    private var fin: CLLocationCoordinate2D? { guia.fin.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) } }

    var body: some View {
        GeometryReader { geo in
            let d = GuiaPantalla.distribucion(ancho: Double(geo.size.width), alto: Double(geo.size.height))
            let m = Medidas(d, geo.size, geo.safeAreaInsets, altoGiro: altoGiro)
            ZStack(alignment: .topLeading) {
                mapa(m)
                    .overlay { if MapaGoogle.listo { RocaSobreMapa() } }
                    .frame(width: m.mapa.width, height: m.mapa.height)
                    .clipped()
                    .offset(x: m.mapa.minX, y: m.mapa.minY)

                GuiaPanelMedio(guia: guia, distribucion: d, bordes: m.bordesPanel, amplio: m.amplio, bajar: { cerrar() })
                    .frame(width: m.panel.width, height: m.panel.height)
                    .offset(x: m.panel.minX, y: m.panel.minY)

                // Con offset y no con una guía de alineación: la guía (centro de la tarjeta = unión de los paneles) se
                // pasaba al ZStack y bajaba el panel y el mapa (el hueco de arriba de build 379).
                tarjetaGiro(d, luego: d == .dividido || m.amplio)
                    .frame(width: m.giroAncho)
                    .background {
                        GeometryReader { g in Color.clear.preference(key: AltoGiroClave.self, value: g.size.height) }
                    }
                    .offset(x: d == .dividido ? ((geo.size.width - m.giroAncho) / 2).rounded() : m.mapa.minX + 12, y: m.giroArriba)

                HStack(alignment: .bottom, spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 10) {
                        if d == .dividido { botonesMapa }
                        llegadaVista.frame(maxWidth: m.llegadaAncho)
                    }
                }
                .padding(.trailing, m.derecha)
                .padding(.bottom, m.abajo)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomTrailing)

                if d == .ladoALado {
                    botonesMapa
                        .padding(.top, 12).padding(.trailing, m.derecha)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .topTrailing)
                }
            }
            .animation(quieto ? nil : .smooth(duration: 0.4), value: d)
            .onAppear { orientar() }
            .onChange(of: d) { _, _ in orientar() }
            .onPreferenceChange(AltoGiroClave.self) { h in
                if d == .dividido, h > 20, abs(h - altoGiro) > 0.5 { altoGiro = h }
            }
        }
        .ignoresSafeArea()
        .background(GuiaColor.fondo)
        .preferredColorScheme(.light)
        .onAppear { guia.rumbo(true) }
        .onDisappear { guia.rumbo(false); RumboGuia.shared.apagar() }
        .onChange(of: guia.activa) { _, a in if !a { cerrar() } }
        .task(id: toque) {
            // Tras «Ver ruta» o mover el mapa con el dedo: unos segundos sin tocar y vuelve a seguir a la roca.
            guard toque > 0, !siguiendo else { return }
            try? await Task.sleep(nanoseconds: UInt64(GuiaPantalla.volverASeguir * 1_000_000_000))
            if !Task.isCancelled, !siguiendo { centrar() }
        }
    }

    private func orientar() {
        let o = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.interfaceOrientation ?? .portrait
        guia.orientarRumbo(o)
    }

    // MARK: - Medidas de cada distribución

    struct Medidas {
        var panel: CGRect, mapa: CGRect
        var bordesPanel: EdgeInsets
        var amplio: Bool
        var giroAncho: CGFloat, giroArriba: CGFloat
        var llegadaAncho: CGFloat, derecha: CGFloat, abajo: CGFloat
        /// Lo que tapan las tarjetas sobre el mapa (Google centra la cámara en lo que queda libre).
        var margen: UIEdgeInsets

        init(_ d: GuiaPantalla.Distribucion, _ s: CGSize, _ i: EdgeInsets, altoGiro: CGFloat) {
            amplio = s.height >= 600
            switch d {
            case .dividido:
                // Sin hueco: tarjeta pegada al área segura, panel ~40 % y mapa ~60 % de lo que queda.
                let c = GuiaPantalla.cortesA(alto: Double(s.height), arriba: Double(i.top), tarjeta: Double(altoGiro))
                panel = CGRect(x: 0, y: c.panelY, width: s.width, height: c.panelAlto)
                mapa = CGRect(x: 0, y: c.mapaY, width: s.width, height: c.mapaAlto)
                bordesPanel = EdgeInsets(top: 0, leading: i.leading, bottom: 0, trailing: i.trailing)
                giroAncho = min(s.width - 32, 560); giroArriba = c.tarjetaY
                let bajo = max(i.bottom, 12) + 4
                llegadaAncho = min(s.width - 32, 560); derecha = 16 + i.trailing; abajo = bajo
                // La roca al centro a lo ancho y un poco abajo de lo que se ve (encima de la llegada, ~76 de alto).
                let b = GuiaPantalla.margenMapa(ancho: Double(s.width), alto: c.mapaAlto, tapaArriba: 0, tapaAbajo: 76 + Double(bajo),
                                                derecha: Double(i.trailing), izquierda: Double(i.leading))
                margen = UIEdgeInsets(top: b.arriba, left: b.izquierda, bottom: b.abajo, right: b.derecha)
            case .ladoALado:
                let ancho = (s.width * CGFloat(GuiaPantalla.partePanel)).rounded()
                panel = CGRect(x: 0, y: 0, width: ancho, height: s.height)
                mapa = CGRect(x: ancho, y: 0, width: s.width - ancho, height: s.height)
                bordesPanel = EdgeInsets(top: i.top, leading: i.leading, bottom: i.bottom, trailing: 0)
                giroAncho = min((s.width - ancho) * 0.62, 440); giroArriba = i.top + 12
                llegadaAncho = min(s.width - ancho - 24, 480); derecha = 12 + i.trailing; abajo = max(i.bottom, 12)
                margen = UIEdgeInsets(top: 110, left: 0, bottom: 96 + i.bottom, right: i.trailing)
            }
        }
    }

    // MARK: - El mapa

    @ViewBuilder private func mapa(_ m: Medidas) -> some View {
        if MapaGoogle.listo {
            MapaGoogleVista(puntos: puntos, fin: fin, destino: guia.destino, posicion: guia.posicion, modo: guia.modo, margen: m.margen,
                            verRuta: verRuta, siguiendo: $siguiendo, tocaste: { verRuta = false; toque += 1 })
        } else {
            Map(position: $camara) {
                if puntos.count >= 2 {
                    MapPolyline(coordinates: puntos).stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 13, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: puntos).stroke(GuiaColor.azul, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                }
                if let f = fin { Marker(guia.destino, systemImage: "flag.checkered", coordinate: f).tint(GuiaColor.tinta) }
                UserAnnotation()
                if let p = guia.posicion {
                    Annotation("", coordinate: p.coordinate, anchor: .center) { RocaGuia() }
                        .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
            .safeAreaPadding(EdgeInsets(top: m.margen.top, leading: m.margen.left, bottom: m.margen.bottom, trailing: m.margen.right))
            .onMapCameraChange(frequency: .continuous) { ctx in
                RumboGuia.shared.mapa(giro: ctx.camera.heading)
                if !camara.followsUserLocation, !verRuta {
                    siguiendo = false
                    toque += 1
                }
            }
        }
    }

    private func centrar() {
        verRuta = false
        siguiendo = true
        camara = .userLocation(followsHeading: true, fallback: .automatic)
    }

    /// «Ver ruta»: la ruta entera (y tu punto) en 2D, con margen. Google lo hace en MapaGoogleVista; Apple aquí.
    private func mostrarRuta() {
        var todos = guia.linea
        if let f = guia.fin { todos.append(f) }
        if let p = guia.posicion { todos.append(GuiaPunto(lat: p.coordinate.latitude, lng: p.coordinate.longitude)) }
        guard let k = GuiaPantalla.cajaRuta(todos) else { return }
        siguiendo = false
        verRuta = true
        toque += 1
        if !MapaGoogle.listo {
            let a = MKMapPoint(CLLocationCoordinate2D(latitude: k.norte, longitude: k.oeste))
            let b = MKMapPoint(CLLocationCoordinate2D(latitude: k.sur, longitude: k.este))
            let r = MKMapRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
            withAnimation(quieto ? nil : .smooth(duration: 0.6)) { camara = .rect(r) }
        }
    }

    // MARK: - La tarjeta del giro

    private func tarjetaGiro(_ d: GuiaPantalla.Distribucion, luego: Bool) -> some View {
        let t = GuiaPantalla.tarjeta(faltan: guia.faltan, proximo: guia.proximo, luego: luego ? guia.luego : "", llego: guia.llego)
        let grande = d == .dividido
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: guia.llego ? "checkmark" : GuiaCaminoReglas.simbolo(guia.giro))
                    .font(.system(size: grande ? 30 : 26, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: grande ? 56 : 48, height: grande ? 56 : 48)
                    .background(guia.llego ? GuiaColor.coral : GuiaColor.azul, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.titulo).font(.custom("Montserrat", size: grande ? 26 : 22).weight(.bold)).foregroundStyle(GuiaColor.tinta)
                        .monospacedDigit().contentTransition(.numericText())
                    Text(t.frase).font(.custom("Montserrat", size: grande ? 18 : 14).weight(.medium)).foregroundStyle(GuiaColor.tinta2)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    if !t.luego.isEmpty {
                        Text(t.luego).font(.custom("Montserrat", size: 13).weight(.medium)).foregroundStyle(GuiaColor.tinta3).lineLimit(1).padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, grande ? 16 : 12)
            if !guia.aviso.isEmpty {
                Text(guia.aviso).font(.custom("Montserrat", size: 12).weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(GuiaColor.coral, in: Capsule())
                    .padding(.leading, 16).padding(.bottom, 10)
            }
        }
        .background(GuiaColor.tarjeta, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color(red: 60 / 255, green: 45 / 255, blue: 35 / 255).opacity(0.22), radius: 16, y: 8)
        .accessibilityElement(children: .combine)
        .animation(quieto ? nil : .snappy, value: guia.proximo)
    }

    // MARK: - La brújula (y «Centrar» si moviste el mapa)

    private var brujula: some View {
        BrujulaGuia(siguiendo: siguiendo, centrar: centrar)
    }

    /// «Ver ruta» y la brújula (que dice «Centrar» si el mapa no te sigue).
    private var botonesMapa: some View {
        HStack(spacing: 8) {
            if !verRuta && guia.linea.count >= 2 {
                Button(action: mostrarRuta) {
                    HStack(spacing: 6) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").font(.system(size: 15, weight: .medium)).foregroundStyle(GuiaColor.azul)
                        Text("Ver ruta").font(.custom("Montserrat", size: 13).weight(.semibold)).foregroundStyle(GuiaColor.tinta2)
                    }
                    .padding(.leading, 10).padding(.trailing, 13).frame(height: 40)
                    .background(GuiaColor.tarjeta, in: Capsule())
                    .shadow(color: Color(red: 60 / 255, green: 45 / 255, blue: 35 / 255).opacity(0.2), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ver toda la ruta en el mapa")
                .transition(.opacity)
            }
            brujula
        }
        .animation(quieto ? nil : .easeOut(duration: 0.2), value: verRuta)
    }

    // MARK: - La llegada

    private var llegadaVista: some View {
        HStack(spacing: 14) {
            if guia.llego {
                Text("Llegaste a " + guia.destino).font(.custom("Montserrat", size: 16).weight(.bold)).foregroundStyle(GuiaColor.tinta).lineLimit(2)
            } else {
                HStack(spacing: 18) {
                    dato(guia.llegada, "llegada")
                    dato("\(guia.minutosFaltan) min", "faltan")
                    if !guia.restante.isEmpty { dato(guia.restante, "distancia") }
                }
            }
            Spacer(minLength: 0)
            Button { guia.terminar() } label: {
                Text("Terminar").font(.custom("Montserrat", size: 16).weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 13)
                    .background(GuiaColor.coral, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 18).padding(.trailing, 12).padding(.vertical, 12)
        .background(GuiaColor.tarjeta, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color(red: 60 / 255, green: 45 / 255, blue: 35 / 255).opacity(0.22), radius: 16, y: 8)
    }

    private func dato(_ grande: String, _ chico: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(grande).font(.custom("Montserrat", size: 19).weight(.bold)).foregroundStyle(GuiaColor.tinta).monospacedDigit().lineLimit(1)
            Text(chico).font(.custom("Montserrat", size: 11).weight(.medium)).foregroundStyle(GuiaColor.tinta3).lineLimit(1)
        }
    }
}

/// El alto de la tarjeta del giro (A pone el panel justo debajo).
private struct AltoGiroClave: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - La brújula

/// La píldora de la brújula: el rumbo del teléfono en grados; si moviste el mapa con el dedo, «Centrar».
private struct BrujulaGuia: View {
    var siguiendo: Bool
    var centrar: () -> Void
    @ObservedObject private var rumbo = RumboGuia.shared

    var body: some View {
        Button(action: centrar) {
            HStack(spacing: 6) {
                Image(systemName: siguiendo ? "safari" : "location.north.line.fill").font(.system(size: 17, weight: .medium)).foregroundStyle(GuiaColor.azul)
                Text(siguiendo ? (rumbo.hay ? "\(rumbo.grados)°" : "Norte") : "Centrar")
                    .font(.custom("Montserrat", size: 13).weight(.semibold)).foregroundStyle(GuiaColor.tinta2).monospacedDigit()
            }
            .padding(.leading, 10).padding(.trailing, 13).frame(height: 40)
            .background(GuiaColor.tarjeta, in: Capsule())
            .shadow(color: Color(red: 60 / 255, green: 45 / 255, blue: 35 / 255).opacity(0.2), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(siguiendo ? "Rumbo del teléfono" : "Centrar el mapa en ti")
    }
}

// MARK: - El rumbo y la roca

/// El rumbo del teléfono para la luz de la roca (Luz de rumbo): la brújula de iOS (GuiaCamino.rumbo) menos lo que va
/// girado el mapa, suavizado 30 veces por segundo por el camino corto (GuiaPantalla.suavizar). Es su propio objeto para
/// que solo la roca se vuelva a dibujar, no toda la pantalla.
final class RumboGuia: ObservableObject {
    static let shared = RumboGuia()

    /// Hacia dónde apunta la luz en la pantalla (grados, sin normalizar: nunca da la vuelta entera).
    @Published private(set) var angulo: Double = .nan
    /// El rumbo del teléfono (0…359), para la brújula.
    @Published private(set) var grados = 0
    @Published private(set) var hay = false
    /// Dónde va la roca sobre el mapa de Google (en puntos del mapa); nil = no se sabe todavía.
    @Published private(set) var punto: CGPoint?

    private var rumbo = 0.0
    private var giroMapa = 0.0
    private var reloj: Timer?

    func brujula(_ r: Double) {
        rumbo = r
        if !hay { hay = true }
        let g = Int(r.rounded()) % 360
        if g != grados { grados = g }
        guard reloj == nil else { return }
        reloj = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.paso() }
    }

    func mapa(giro: Double) { giroMapa = giro }

    func roca(_ p: CGPoint?) { if p != punto { punto = p } }

    func apagar() {
        reloj?.invalidate(); reloj = nil
        hay = false; angulo = .nan; punto = nil
    }

    private func paso() {
        let objetivo = GuiaPantalla.luzEnPantalla(rumbo: rumbo, mapa: giroMapa)
        let n = GuiaPantalla.suavizar(angulo, hacia: objetivo, k: 0.2)
        if !angulo.isFinite || abs(n - angulo) > 0.05 { angulo = n }
    }
}

/// Sobre el mapa de Google: la roca va donde el mapa dice que estás.
private struct RocaSobreMapa: View {
    @ObservedObject private var rumbo = RumboGuia.shared

    var body: some View {
        GeometryReader { _ in
            if let p = rumbo.punto {
                RocaGuia().position(p)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Tu punto en el mapa: la roca de Alma (la misma de toda la app, con su halo y su pulso) y, debajo, su luz de rumbo.
struct RocaGuia: View {
    @ObservedObject private var rumbo = RumboGuia.shared
    static let diametro: CGFloat = 34
    static let radioLuz: CGFloat = 120

    var body: some View {
        ZStack {
            if rumbo.hay, rumbo.angulo.isFinite {
                LuzDeRumbo(radio: RocaGuia.radioLuz)
                    .rotationEffect(.degrees(rumbo.angulo))
            }
            RocaAlma(diametro: RocaGuia.diametro)
        }
        .frame(width: RocaGuia.radioLuz * 2, height: RocaGuia.radioLuz * 2)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Tú estás aquí. La luz de la roca apunta hacia donde mira tu teléfono.")
    }
}

/// La luz de rumbo: un cono de 90° (GuiaPantalla.apertura) con los colores del halo (azul, lavanda, coral, durazno),
/// más fuerte al centro y cerca de la roca, con el borde difuminado. Apunta hacia arriba; quien lo usa lo gira.
struct LuzDeRumbo: View {
    var radio: CGFloat

    var body: some View {
        let mitad = GuiaPantalla.apertura / 2
        let c = RocaAlma.atardecer
        Sector(apertura: GuiaPantalla.apertura)
            .fill(AngularGradient(stops: [
                .init(color: c[0].opacity(0.22), location: 0),
                .init(color: c[1].opacity(0.45), location: 0.24),
                .init(color: c[2].opacity(0.66), location: 0.5),
                .init(color: c[3].opacity(0.45), location: 0.76),
                .init(color: c[4].opacity(0.22), location: 1),
            ], center: .center, startAngle: .degrees(-90 - mitad), endAngle: .degrees(-90 + mitad)))
            .mask {
                EllipticalGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.1),
                .init(color: .black, location: 0.17),
                .init(color: .black.opacity(0.75), location: 0.45),
                .init(color: .black.opacity(0.25), location: 0.75),
                .init(color: .clear, location: 1),
                ], center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
            }
            .blur(radius: radio * 0.05)
            .frame(width: radio * 2, height: radio * 2)
            .allowsHitTesting(false)
    }
}

/// Un sector de círculo centrado hacia arriba.
struct Sector: Shape {
    var apertura: Double

    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY), radio = min(r.width, r.height) / 2
        var p = Path()
        p.move(to: c)
        p.addArc(center: c, radius: radio, startAngle: .degrees(-90 - apertura / 2), endAngle: .degrees(-90 + apertura / 2), clockwise: false)
        p.closeSubpath()
        return p
    }
}
