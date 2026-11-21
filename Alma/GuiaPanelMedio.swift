import CoreLocation
import SwiftUI

/// Los colores de la pantalla de la Guía de camino (el prototipo que eligió Juan, 20-nov-2026): piedra clara, tinta
/// cálida, el coral de Alma y el azul de la ruta.
enum GuiaColor {
    static let fondo = RocaAlma.rgb(0xF4F2EF)
    static let fondo2 = RocaAlma.rgb(0xECE9E5)
    static let tarjeta = Color.white
    static let tinta = RocaAlma.rgb(0x3E3A37)
    static let tinta2 = RocaAlma.rgb(0x6F6862)
    static let tinta3 = RocaAlma.rgb(0x9C928A)
    static let linea = RocaAlma.rgb(0xE3DED8)
    static let coral = Color.almaCoral
    static let azul = RocaAlma.rgb(0x3F6FE0)
    static let gris = RocaAlma.rgb(0xB4ADA6)
}

/// El panel del medio (el de la izquierda en Tesla): el selector carro · bici · bus · metro · a pie, la escena con tu
/// medio en su camino y las siluetas grises de lo que algún día verá la cámara, y tu velocidad en grande (a pie, también
/// el ritmo por km). En A va debajo de la tarjeta del giro con el selector compacto (solo íconos, una fila con «bajar»);
/// en B, a la izquierda con la frase de Alma abajo. La escena se anima según el medio y la velocidad (EscenaMedio).
struct GuiaPanelMedio: View {
    @ObservedObject var guia: GuiaCamino
    var distribucion: GuiaPantalla.Distribucion
    var bordes: EdgeInsets
    /// Pantalla alta (iPad): en B también lleva el título y los nombres del selector.
    var amplio = false
    var bajar: () -> Void

    private var a: Bool { distribucion == .dividido }
    /// En A el selector va compacto (Juan, 21-nov-2026: más espacio para la escena y el mapa); en B, con nombres si es alto.
    private var conNombres: Bool { !a && amplio }
    private var medio: String { guia.medio.isEmpty ? GuiaPantalla.medioVisto(hub: guia.modo, elegido: "") : guia.medio }
    private var ms: Double { max(0, guia.posicion?.speed ?? 0) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            EscenaMedio(medio: medio, horizonte: a ? 0.4 : 0.56, fuga: a ? 0.62 : 0.5, ms: ms)
            VStack(alignment: .leading, spacing: a ? 10 : 8) {
                if conNombres {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("GUÍA DE CAMINO").font(.custom("Montserrat", size: 12).weight(.semibold)).tracking(1.6).foregroundStyle(GuiaColor.tinta3)
                        Text("· te llevo " + GuiaPanelMedio.dicho(medio)).font(.custom("Montserrat", size: 15).weight(.bold)).foregroundStyle(GuiaColor.tinta)
                        Spacer(minLength: 0)
                        botonBajar
                    }
                    selector
                } else {
                    HStack(spacing: 8) { selector; botonBajar }
                }
                velocidadVista
                Spacer(minLength: 0)
                if !a { fraseAlma }
            }
            .padding(.top, bordes.top + (a ? 8 : 12))
            .padding(.leading, bordes.leading + 16)
            .padding(.trailing, 16)
            .padding(.bottom, a ? 0 : bordes.bottom + 14)

            camara
                .padding(.trailing, 14)
                .padding(.bottom, a ? 10 : bordes.bottom + 96)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .background(GuiaColor.fondo)
        .clipped()
    }

    // MARK: - El selector

    private var selector: some View {
        HStack(spacing: 4) {
            ForEach(GuiaPantalla.medios, id: \.self) { m in
                let si = m == medio
                Button { if !si { guia.cambiarMedio(m) } } label: {
                    VStack(spacing: 3) {
                        Image(systemName: GuiaPanelMedio.icono(m)).font(.system(size: conNombres ? 19 : 17, weight: .medium))
                            .foregroundStyle(si ? GuiaColor.coral : GuiaColor.tinta3)
                        if conNombres {
                            Text(GuiaPanelMedio.nombre(m)).font(.custom("Montserrat", size: 11).weight(.semibold))
                                .foregroundStyle(si ? GuiaColor.tinta : GuiaColor.tinta3).lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, conNombres ? 7 : 9)
                    .background {
                        if si { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(GuiaColor.tarjeta).shadow(color: GuiaColor.tinta.opacity(0.18), radius: 6, y: 3) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(GuiaPanelMedio.nombre(m))
                .accessibilityAddTraits(si ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.easeOut(duration: 0.2), value: medio)
    }

    private var botonBajar: some View {
        Button(action: bajar) {
            Image(systemName: "chevron.down").font(.system(size: 15, weight: .bold)).foregroundStyle(GuiaColor.tinta2)
                .frame(width: 36, height: 36).background(Color.white.opacity(0.7), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Bajar el mapa (la guía sigue por voz)")
    }

    // MARK: - La velocidad

    private var velocidadVista: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(GuiaPantalla.velocidad(ms)).font(.custom("Cormorant Garamond", size: a ? 54 : 58).weight(.light))
                    .foregroundStyle(GuiaColor.tinta).monospacedDigit().contentTransition(.numericText())
                Text("km/h").font(.custom("Montserrat", size: 13).weight(.semibold)).foregroundStyle(GuiaColor.tinta3)
            }
            Text(subtitulo).font(.custom("Montserrat", size: 13).weight(.medium)).foregroundStyle(GuiaColor.tinta2).lineLimit(1)
        }
        .padding(.top, a ? 0 : 6)
        .background {
            // Una luz de fondo para que el número se lea encima de la escena.
            EllipticalGradient(colors: [GuiaColor.fondo.opacity(0.92), GuiaColor.fondo.opacity(0)], center: .center, startRadiusFraction: 0.04, endRadiusFraction: 0.5)
                .frame(width: 280, height: 170)
        }
        .accessibilityElement(children: .combine)
        .animation(.easeOut(duration: 0.3), value: GuiaPantalla.velocidad(ms))
    }

    private var subtitulo: String {
        if medio == "caminando", let r = GuiaPantalla.ritmo(ms) { return "Ritmo " + r + " por km" }
        return guia.destino.isEmpty ? " " : "Hacia " + guia.destino
    }

    // MARK: - La frase de Alma (B) y la etiqueta de la cámara

    private var fraseAlma: some View {
        let t = GuiaPantalla.tarjeta(faltan: guia.faltan, proximo: guia.proximo, luego: "", llego: guia.llego)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(LinearGradient(colors: RocaAlma.atardecer, startPoint: .top, endPoint: .bottom)).frame(width: 12, height: 12)
                .overlay(Circle().stroke(GuiaColor.coral.opacity(0.2), lineWidth: 3))
            (Text(t.titulo + " ").font(.custom("Montserrat", size: 17).weight(.bold)).foregroundColor(GuiaColor.tinta)
             + Text(t.frase).font(.custom("Montserrat", size: 16).weight(.medium)).foregroundColor(GuiaColor.tinta2))
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: GuiaColor.tinta.opacity(0.18), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
    }

    private var camara: some View {
        HStack(spacing: 6) {
            Image(systemName: "video").font(.system(size: 11, weight: .semibold))
            Text("Lo gris lo verá la cámara · pronto").font(.custom("Montserrat", size: 11).weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(GuiaColor.tinta3)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.white.opacity(0.72), in: Capsule())
    }

    // MARK: - Los medios

    static func icono(_ m: String) -> String {
        switch m {
        case "carro": return "car"
        case "bici": return "bicycle"
        case "bus": return "bus"
        case "metro": return "tram"
        default: return "figure.walk"
        }
    }

    static func nombre(_ m: String) -> String {
        switch m {
        case "carro": return "Carro"
        case "bici": return "Bici"
        case "bus": return "Bus"
        case "metro": return "Metro"
        default: return "A pie"
        }
    }

    /// «te llevo …»
    static func dicho(_ m: String) -> String {
        switch m {
        case "carro": return "en carro"
        case "bici": return "en bici"
        case "bus": return "en bus"
        case "metro": return "en metro"
        default: return "a pie"
        }
    }
}

/// La escena en perspectiva: tu medio (blanco, con el coral de Alma) en su camino y, alrededor, siluetas grises de lo
/// que la cámara verá algún día (personas, carros). Formas simples dibujadas en un Canvas: nada se detecta todavía.
/// Se anima según el medio y la velocidad (Juan, 21-nov-2026; GuiaPantalla.paso/cadencia/Andar):
///   · a pie: quieto a 0; camina por debajo de ~7 km/h (piernas y brazos alternan); más rápido, corre (más zancada).
///   · en bici: las piernas pedalean y la rueda gira más rápido con la velocidad.
///   · carro, bus, metro: el camino, las rayas del carril (o los durmientes) avanzan según la velocidad.
///   · lo gris se mueve: las personas de la orilla pasan a tu lado y los carros avanzan en su carril.
/// Con «Reducir movimiento», sin ciclo de piernas: solo un avance suave. A 30 cuadros por segundo como máximo y en pausa
/// si la app no está a la vista o si todo está quieto (batería).
struct EscenaMedio: View {
    var medio: String
    /// Dónde está el horizonte (fracción del alto) y el punto de fuga (fracción del ancho).
    var horizonte: CGFloat
    var fuga: CGFloat
    /// Tu velocidad (m/s).
    var ms: Double = 0
    @Environment(\.accessibilityReduceMotion) private var suave
    @Environment(\.scenePhase) private var faseApp
    @State private var reloj = RelojEscena()

    private var kmh: Double { max(0, ms.isFinite ? ms : 0) * 3.6 }

    var body: some View {
        let pausa = GuiaPantalla.escenaPausada(activa: faseApp == .active, kmh: kmh)
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: pausa)) { t in
            let andar = reloj.avanzar(t.date, medio: medio, kmh: kmh, suave: suave)
            Canvas { c, s in dibujar(c, s, andar) }
        }
        .accessibilityHidden(true)
    }

    private static let suelo = RocaAlma.rgb(0xE7E3DE)
    private static let calle = RocaAlma.rgb(0xD9D4CE)
    private static let piedra = RocaAlma.rgb(0xFBFAF8)
    private static let borde = RocaAlma.rgb(0xE3DED8)

    /// Dónde cae en la escena algo que está `z` metros adelante (v = 1 es el borde de abajo; 0, el horizonte).
    static func profundidad(_ z: CGFloat) -> CGFloat { 1.2 / (1 + max(z, -0.9) / 5) }

    private func dibujar(_ c: GraphicsContext, _ s: CGSize, _ an: GuiaPantalla.Andar) {
        let w = s.width, h = s.height, hz = h * horizonte, vx = w * fuga
        func mitad(_ v: CGFloat) -> CGFloat { w * (0.02 + 0.56 * v) }   // medio ancho de la calle a esa profundidad
        func p(_ u: CGFloat, _ v: CGFloat) -> CGPoint { CGPoint(x: vx + u * mitad(v), y: hz + (h - hz) * v) }
        func franja(_ u0: CGFloat, _ u1: CGFloat, _ v0: CGFloat, _ v1: CGFloat) -> Path {
            var q = Path(); q.move(to: p(u0, v0)); q.addLine(to: p(u1, v0)); q.addLine(to: p(u1, v1)); q.addLine(to: p(u0, v1)); q.closeSubpath(); return q
        }
        func vz(_ z: CGFloat) -> CGFloat { EscenaMedio.profundidad(z) }
        let paso = GuiaPantalla.paso(medio: medio, kmh: kmh)
        let anda = paso != .quieto
        let rec = CGFloat(an.recorrido), t = CGFloat(an.tiempo)
        func corrido(_ periodo: Double) -> CGFloat { CGFloat(GuiaPantalla.vuelta(an.recorrido, periodo)) }

        // Cielo y suelo.
        c.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .linearGradient(Gradient(colors: [GuiaColor.fondo, GuiaColor.fondo2]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        c.fill(Path(CGRect(x: 0, y: hz, width: w, height: h - hz)), with: .color(EscenaMedio.suelo))
        // La calle (o la vía del metro).
        c.fill(franja(-1, 1, 0, 1.2), with: .color(self.medio == "metro" ? RocaAlma.rgb(0xD3CEC8) : EscenaMedio.calle))
        // Orillas blancas.
        for u in [-1.0, 1.0] as [CGFloat] { c.fill(franja(u - 0.03, u + 0.03, 0, 1.2), with: .color(.white.opacity(0.85))) }

        switch self.medio {
        case "metro":
            // Durmientes (avanzan con la velocidad) y rieles.
            let off = corrido(0.9)
            for k in 0..<72 {
                let z0 = CGFloat(k) * 0.9 - off
                guard z0 + 0.2 > -0.8 else { continue }
                c.fill(franja(-0.5, 0.5, vz(z0 + 0.2), vz(z0)), with: .color(RocaAlma.rgb(0xBDB6AE)))
            }
            for u in [-0.3, 0.3] as [CGFloat] { c.fill(franja(u - 0.025, u + 0.025, 0, 1.2), with: .color(RocaAlma.rgb(0x9F978F))) }
        default:
            // Las rayas del carril (avanzan con la velocidad).
            let off = corrido(4)
            for k in 0..<26 {
                let z0 = CGFloat(k) * 4 - off
                guard z0 + 1.6 > -0.8 else { continue }
                for u in [-0.34, 0.34] as [CGFloat] { c.fill(franja(u - 0.012, u + 0.012, vz(z0 + 1.6), vz(z0)), with: .color(.white.opacity(0.9))) }
            }
            if self.medio == "bici" { c.fill(franja(-0.95, -0.4, 0, 1.2), with: .color(GuiaColor.coral.opacity(0.22))) }
            if self.medio == "bus" { c.fill(franja(0.05, 0.7, 0, 1.2), with: .color(GuiaColor.coral.opacity(0.14))) }
            if self.medio == "caminando" {
                // El paso de cebra se acerca mientras caminas y vuelve a aparecer adelante.
                let zc = CGFloat(GuiaPantalla.vuelta(14 - an.recorrido, 40)) - 3
                for k in 0..<7 {
                    let u0 = -0.9 + CGFloat(k) * 0.27
                    c.fill(franja(u0, u0 + 0.15, vz(zc + 3), vz(zc)), with: .color(.white.opacity(0.92)))
                }
            }
        }

        // Lo gris (lo que verá la cámara): las personas de la orilla pasan a tu lado (y caminan); los carros van en su carril.
        let gris = GraphicsContext.Shading.color(GuiaColor.gris.opacity(0.6))
        func escala(_ v: CGFloat) -> CGFloat { 0.12 + 0.88 * v }
        let ritmo: CGFloat = suave ? 0.3 : 1
        let personas: [(CGFloat, CGFloat)] = [(-1.2, 34), (1.2, 22), (-1.3, 11), (1.3, 6)]
        for (i, (u, z0)) in personas.enumerated() {
            let z = CGFloat(GuiaPantalla.vuelta(Double(z0 - rec), 40)) - 2
            let v = vz(z)
            guard v < 1.25 else { continue }
            let f: Double? = anda && !suave ? GuiaPantalla.vuelta(Double(t) * 0.85 + Double(i) * 0.37, 1) : nil
            persona(c, p(u, v), alto: w * 0.28 * escala(v), relleno: gris, borde: nil, fase: f, corre: false, brazos: false)
        }
        if self.medio != "metro" {
            let carros: [(CGFloat, CGFloat)] = [(-0.15, 70), (0.55, 13.7)]
            for (i, (u, z0)) in carros.enumerated() {
                var z = z0
                if anda {
                    if paso == .rueda {
                        // Van más o menos a tu velocidad: se adelantan y se quedan un poco.
                        z = z0 + 3 * sin(t * 0.35 * ritmo + CGFloat(i) * 2)
                    } else {
                        // Tú vas a pie o en bici: los carros avanzan más rápido que tú.
                        z = CGFloat(GuiaPantalla.vuelta(Double(z0 + t * 6 * ritmo - rec), 80)) + 3
                    }
                }
                let v = vz(z)
                carro(c, p(u, v), ancho: w * 0.34 * escala(v), relleno: gris, luces: nil, borde: nil)
            }
        }

        // La niebla del horizonte.
        c.fill(Path(CGRect(x: 0, y: hz - 30, width: w, height: (h - hz) * 0.35 + 30)),
               with: .linearGradient(Gradient(colors: [GuiaColor.fondo.opacity(0.95), GuiaColor.fondo.opacity(0)]), startPoint: CGPoint(x: 0, y: hz - 30), endPoint: CGPoint(x: 0, y: hz + (h - hz) * 0.35)))

        // Tu medio, con su luz coral en el piso.
        let blanco = GraphicsContext.Shading.color(EscenaMedio.piedra), linea = GraphicsContext.Shading.color(EscenaMedio.borde)
        let u: CGFloat = self.medio == "bici" ? -0.67 : (self.medio == "bus" ? 0.38 : 0), v: CGFloat = 0.82
        var pie = p(u, v)
        let e = escala(v)
        var luz = c
        luz.addFilter(.blur(radius: 14))
        luz.fill(Path(ellipseIn: CGRect(x: pie.x - w * 0.16 * e, y: pie.y - w * 0.035, width: w * 0.32 * e, height: w * 0.07)), with: .color(GuiaColor.coral.opacity(0.35)))
        // Con el motor andando, un leve temblor del carro, el bus o el metro.
        if paso == .rueda && !suave { pie.y -= abs(sin(t * 9)) * 0.8 }
        let fase: Double? = (paso == .camina || paso == .corre || paso == .pedalea) && !suave ? an.fase : nil
        switch self.medio {
        case "carro": carro(c, pie, ancho: w * 0.36 * e, relleno: blanco, luces: GuiaColor.coral, borde: linea)
        case "bus": bus(c, pie, ancho: w * 0.3 * e, alto: w * 0.36 * e, metro: false, relleno: blanco, borde: linea)
        case "metro": bus(c, pie, ancho: w * 0.32 * e, alto: w * 0.34 * e, metro: true, relleno: blanco, borde: linea)
        case "bici": ciclista(c, pie, alto: w * 0.3 * e, relleno: blanco, borde: linea, fase: fase, giro: anda ? Double(rec) : nil)
        default: persona(c, pie, alto: w * 0.3 * e, relleno: blanco, borde: linea, fase: fase, corre: paso == .corre, brazos: true)
        }
    }

    // MARK: - Las figuras (de espaldas, paradas sobre `pie`)

    private func sombra(_ c: GraphicsContext, _ pie: CGPoint, _ ancho: CGFloat) {
        c.fill(Path(ellipseIn: CGRect(x: pie.x - ancho / 2, y: pie.y - ancho * 0.06, width: ancho, height: ancho * 0.12)), with: .color(.black.opacity(0.08)))
    }

    /// Una persona de espaldas. Con `fase` (0…1 del ciclo) camina: las piernas se levantan una y otra, los brazos van al
    /// revés y el cuerpo sube un poco; corriendo, más zancada, más rebote y un leve vaivén. Sin fase, parada.
    private func persona(_ c: GraphicsContext, _ pie: CGPoint, alto a: CGFloat, relleno: GraphicsContext.Shading, borde: GraphicsContext.Shading?,
                         fase: Double? = nil, corre: Bool = false, brazos: Bool = false) {
        sombra(c, pie, a * 0.32)
        let sn = fase.map { CGFloat(sin($0 * 2 * .pi)) } ?? 0
        let amp: CGFloat = corre ? 0.14 : 0.07
        let bote = abs(sn) * a * (corre ? 0.04 : 0.015)
        let x = pie.x + sn * a * (corre ? 0.025 : 0.01)
        let cadera = pie.y - a * 0.42 - bote
        let alza1 = max(0, sn) * a * amp, alza2 = max(0, -sn) * a * amp
        let cabeza = Path(ellipseIn: CGRect(x: x - a * 0.085, y: pie.y - a - bote, width: a * 0.17, height: a * 0.17))
        let cuerpo = Path(roundedRect: CGRect(x: x - a * 0.13, y: pie.y - a * 0.8 - bote, width: a * 0.26, height: a * 0.42), cornerRadius: a * 0.09)
        let pierna1 = Path(roundedRect: CGRect(x: x - a * 0.105, y: cadera, width: a * 0.09, height: max(a * 0.1, pie.y - alza1 - cadera)), cornerRadius: a * 0.04)
        let pierna2 = Path(roundedRect: CGRect(x: x + a * 0.015, y: cadera, width: a * 0.09, height: max(a * 0.1, pie.y - alza2 - cadera)), cornerRadius: a * 0.04)
        var partes = [pierna1, pierna2]
        if brazos {
            // Los brazos van al revés de las piernas.
            let largo = a * (corre ? 0.26 : 0.3), hombro = pie.y - a * 0.77 - bote
            let b1 = Path(roundedRect: CGRect(x: x - a * 0.185, y: hombro - sn * a * amp * 0.5, width: a * 0.065, height: largo), cornerRadius: a * 0.03)
            let b2 = Path(roundedRect: CGRect(x: x + a * 0.12, y: hombro + sn * a * amp * 0.5, width: a * 0.065, height: largo), cornerRadius: a * 0.03)
            partes += [b1, b2]
        }
        for f in partes + [cuerpo, cabeza] {
            c.fill(f, with: relleno)
            if let b = borde { c.stroke(f, with: b, lineWidth: 1) }
        }
    }

    /// En bici, de espaldas. Con `fase` las rodillas suben y bajan al pedalear (una y otra) y el cuerpo se mece un poco;
    /// con `giro` (metros recorridos) las marcas de la rueda corren hacia abajo: gira más rápido con la velocidad.
    private func ciclista(_ c: GraphicsContext, _ pie: CGPoint, alto a: CGFloat, relleno: GraphicsContext.Shading, borde: GraphicsContext.Shading?,
                          fase: Double? = nil, giro: Double? = nil) {
        sombra(c, pie, a * 0.3)
        let ang = fase.map { CGFloat($0 * 2 * .pi) } ?? 0
        let x = pie.x + (fase == nil ? 0 : sin(ang) * a * 0.015)
        // La rueda de atrás (de espaldas es una línea) con sus marcas, y la persona encima.
        let rueda = Path(roundedRect: CGRect(x: pie.x - a * 0.025, y: pie.y - a * 0.36, width: a * 0.05, height: a * 0.36), cornerRadius: a * 0.025)
        c.fill(rueda, with: .color(GuiaColor.tinta.opacity(0.75)))
        if let g = giro {
            let vuelta = CGFloat(GuiaPantalla.vuelta(g / 0.7, 1))
            for k in 0..<3 {
                let y = pie.y - a * 0.36 + CGFloat(GuiaPantalla.vuelta(Double(vuelta) + Double(k) / 3, 1)) * a * 0.33
                c.fill(Path(roundedRect: CGRect(x: pie.x - a * 0.018, y: y, width: a * 0.036, height: a * 0.03), cornerRadius: 1), with: .color(.white.opacity(0.55)))
            }
        }
        let manubrio = Path(roundedRect: CGRect(x: pie.x - a * 0.2, y: pie.y - a * 0.68, width: a * 0.4, height: a * 0.035), cornerRadius: a * 0.02)
        c.fill(manubrio, with: .color(GuiaColor.tinta.opacity(0.55)))
        let cuerpo = Path(roundedRect: CGRect(x: x - a * 0.14, y: pie.y - a * 0.86, width: a * 0.28, height: a * 0.4), cornerRadius: a * 0.1)
        let cabeza = Path(ellipseIn: CGRect(x: x - a * 0.085, y: pie.y - a * 1.02, width: a * 0.17, height: a * 0.17))
        // Las dos piernas: de la cadera al pedal, que sube y baja (opuestos).
        let cadera = pie.y - a * 0.5
        let pedal1 = pie.y - a * 0.24 + sin(ang) * a * 0.07, pedal2 = pie.y - a * 0.24 - sin(ang) * a * 0.07
        let pierna1 = Path(roundedRect: CGRect(x: x - a * 0.1, y: cadera, width: a * 0.085, height: pedal1 - cadera), cornerRadius: a * 0.04)
        let pierna2 = Path(roundedRect: CGRect(x: x + a * 0.015, y: cadera, width: a * 0.085, height: pedal2 - cadera), cornerRadius: a * 0.04)
        for f in [pierna1, pierna2, cuerpo, cabeza] {
            c.fill(f, with: relleno)
            if let b = borde { c.stroke(f, with: b, lineWidth: 1) }
        }
        c.fill(Path(roundedRect: CGRect(x: x - a * 0.04, y: pie.y - a * 0.3, width: a * 0.08, height: a * 0.04), cornerRadius: 1), with: .color(GuiaColor.coral))
    }

    private func carro(_ c: GraphicsContext, _ pie: CGPoint, ancho a: CGFloat, relleno: GraphicsContext.Shading, luces: Color?, borde: GraphicsContext.Shading?) {
        sombra(c, pie, a * 1.05)
        let cuerpo = Path(roundedRect: CGRect(x: pie.x - a / 2, y: pie.y - a * 0.42, width: a, height: a * 0.36), cornerRadius: a * 0.09)
        var techo = Path()
        techo.move(to: CGPoint(x: pie.x - a * 0.4, y: pie.y - a * 0.4))
        techo.addLine(to: CGPoint(x: pie.x - a * 0.3, y: pie.y - a * 0.66))
        techo.addLine(to: CGPoint(x: pie.x + a * 0.3, y: pie.y - a * 0.66))
        techo.addLine(to: CGPoint(x: pie.x + a * 0.4, y: pie.y - a * 0.4))
        techo.closeSubpath()
        c.fill(techo, with: relleno)
        c.fill(cuerpo, with: relleno)
        if let b = borde { c.stroke(cuerpo, with: b, lineWidth: 1); c.stroke(techo, with: b, lineWidth: 1) }
        if let l = luces {
            var vidrio = Path()
            vidrio.move(to: CGPoint(x: pie.x - a * 0.33, y: pie.y - a * 0.43))
            vidrio.addLine(to: CGPoint(x: pie.x - a * 0.26, y: pie.y - a * 0.61))
            vidrio.addLine(to: CGPoint(x: pie.x + a * 0.26, y: pie.y - a * 0.61))
            vidrio.addLine(to: CGPoint(x: pie.x + a * 0.33, y: pie.y - a * 0.43))
            vidrio.closeSubpath()
            c.fill(vidrio, with: .color(RocaAlma.rgb(0xCFD2D8)))
            for x in [-0.4, 0.27] as [CGFloat] {
                c.fill(Path(roundedRect: CGRect(x: pie.x + a * x, y: pie.y - a * 0.33, width: a * 0.13, height: a * 0.045), cornerRadius: 2), with: .color(l))
            }
        }
    }

    private func bus(_ c: GraphicsContext, _ pie: CGPoint, ancho a: CGFloat, alto h: CGFloat, metro: Bool, relleno: GraphicsContext.Shading, borde: GraphicsContext.Shading?) {
        sombra(c, pie, a * 1.1)
        let cuerpo = Path(roundedRect: CGRect(x: pie.x - a / 2, y: pie.y - h, width: a, height: h * 0.96), cornerRadius: metro ? a * 0.22 : a * 0.08)
        c.fill(cuerpo, with: relleno)
        if let b = borde { c.stroke(cuerpo, with: b, lineWidth: 1) }
        let vidrio = Path(roundedRect: CGRect(x: pie.x - a * 0.4, y: pie.y - h * 0.9, width: a * 0.8, height: h * 0.36), cornerRadius: a * 0.06)
        c.fill(vidrio, with: .color(RocaAlma.rgb(0xCFD2D8)))
        for x in [-0.4, 0.27] as [CGFloat] {
            c.fill(Path(roundedRect: CGRect(x: pie.x + a * x, y: pie.y - h * 0.22, width: a * 0.13, height: a * 0.05), cornerRadius: 2), with: .color(GuiaColor.coral))
        }
    }
}

/// El reloj de la escena: suma lo que avanzó el camino y el ciclo de las piernas cuadro a cuadro (GuiaPantalla.Andar),
/// para que nada brinque si cambia la velocidad. Es una clase para no redibujar la pantalla al guardar.
final class RelojEscena {
    private var ultimo: Date?
    private var andar = GuiaPantalla.Andar()

    func avanzar(_ ahora: Date, medio: String, kmh: Double, suave: Bool) -> GuiaPantalla.Andar {
        if let u = ultimo { andar.avanzar(dt: ahora.timeIntervalSince(u), medio: medio, kmh: kmh, suave: suave) }
        ultimo = ahora
        return andar
    }
}
