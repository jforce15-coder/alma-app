import SwiftUI

/// UNA ROCA (Juan, 16-nov-2026): «en cada pantalla solo debe haber un botón roca […] siempre tiene que ser la misma con
/// diferentes tamaños». Esta es la única piedra que dibuja la app: la gemela de la de la web (js/sa-nav.js, piedraHTML):
/// el halo del atardecer (todo naranja con Claudio), su anillo, el alabastro con su luz, el borde y el destello.
/// La usan la llamada (LlamadaVista), Health (conectar el anillo y Respira) y el portal entre pantallas. Ninguna otra
/// pantalla dibuja la suya (lo revisa el robot: solo este archivo tiene el degradado de la piedra).
///
/// El pulso (RocaPulso): respira siempre; con la voz (Alma, Claudio o tú) crece con su nivel. Capas separadas: el halo
/// respira en su capa, la piedra respira en la suya y la voz agranda a las dos desde afuera; quien la cambie de tamaño o
/// la mueva (la tarjeta, Respira) lo hace por fuera, con su propio scaleEffect, sin pisar el pulso.
struct RocaAlma: View {
    var diametro: CGFloat
    /// Nivel de la voz (0…1): VozNativa.nivel. Sin llamada, 0.
    var nivel: CGFloat = 0
    /// En llamada respira hacia afuera (+2 %); quieta, hacia adentro (−3 %), como en la web.
    var enLlamada: Bool = false
    /// Hablar con Claudio (Hub #550): el halo todo naranja. nil = el atardecer de Alma.
    var claudio: Bool = false
    /// Sin el destello (el portal pone el suyo cuando ya cubrió).
    var destello: Bool = true
    @Environment(\.accessibilityReduceMotion) private var quieto

    static func rgb(_ h: UInt32) -> Color { Color(red: Double((h >> 16) & 0xFF) / 255, green: Double((h >> 8) & 0xFF) / 255, blue: Double(h & 0xFF) / 255) }
    /// El alabastro de la piedra (web: #F7F5F2 → #D3CEC8).
    static let alabastro: [Color] = [rgb(0xF7F5F2), rgb(0xEFECE8), rgb(0xE3DFDA), rgb(0xD3CEC8)]
    /// El halo: el atardecer del inicio (azul, lavanda, coral, durazno, malva) o el naranja de Claudio.
    static let atardecer: [Color] = [rgb(0x8FA5C8), rgb(0xB8B6C8), rgb(0xE9826A), rgb(0xE3A47F), rgb(0xA98C93)]
    static let naranja: [Color] = [rgb(0xFFB25E), rgb(0xFF9A3C), rgb(0xF5821F), rgb(0xE66A0E)]

    private var colores: [Color] { claudio ? RocaAlma.naranja : RocaAlma.atardecer }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: quieto)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                // El halo: su propia capa (respira y sube con la voz; no comparte transform con la piedra).
                Circle()
                    .fill(LinearGradient(colors: colores, startPoint: .top, endPoint: .bottom))
                    .frame(width: diametro * 1.5, height: diametro * 1.5)
                    .blur(radius: diametro * 0.16)
                    .opacity(0.75 * RocaPulso.halo(t, nivel: Double(nivel), quieto: quieto))
                piedra
                    .scaleEffect(RocaPulso.respira(t, enLlamada: enLlamada, quieto: quieto))
            }
        }
        // La voz la agranda desde afuera, con un resorte vivo (el bounce): no pisa la respiración de adentro.
        .scaleEffect(RocaPulso.voz(Double(nivel)))
        .animation(quieto ? nil : .spring(response: 0.22, dampingFraction: 0.55), value: nivel)
        .animation(quieto ? nil : .easeInOut(duration: 0.6), value: claudio)
        .frame(width: diametro, height: diametro)
        .accessibilityHidden(true)
    }

    /// La piedra: anillo del halo, alabastro, su luz, el borde y el destello (las capas de piedraHTML en la web).
    private var piedra: some View {
        ZStack {
            Circle()
                .strokeBorder(LinearGradient(colors: colores, startPoint: .top, endPoint: .bottom), lineWidth: max(2, diametro * 0.024))
                .frame(width: diametro * 1.065, height: diametro * 1.065)
            Circle()
                .fill(RadialGradient(colors: RocaAlma.alabastro, center: UnitPoint(x: 0.40, y: 0.34), startRadius: 0, endRadius: diametro * 0.62))
                .shadow(color: Color(red: 70 / 255, green: 50 / 255, blue: 40 / 255).opacity(0.42), radius: diametro * 0.09, y: diametro * 0.1)
            Circle()   // la luz cálida de adentro
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.97, blue: 0.93).opacity(0.55), Color(red: 0.98, green: 0.82, blue: 0.71).opacity(0)],
                                     center: UnitPoint(x: 0.42, y: 0.36), startRadius: 0, endRadius: diametro * 0.5))
            Circle()   // el borde: brillo arriba a la izquierda, sombra suave abajo
                .fill(RadialGradient(stops: [.init(color: .white.opacity(0.28), location: 0), .init(color: .white.opacity(0), location: 0.4),
                                             .init(color: .black.opacity(0), location: 0.46), .init(color: .black.opacity(0.045), location: 0.74),
                                             .init(color: .black.opacity(0.10), location: 1)],
                                     center: UnitPoint(x: 0.36, y: 0.30), startRadius: 0, endRadius: diametro * 0.72))
            if destello {
                Destello()
                    .fill(RocaAlma.rgb(0xCBC4BC))
                    .frame(width: diametro * 0.22, height: diametro * 0.22)
                    .shadow(color: .white.opacity(0.8), radius: 0, y: 1)
                    .shadow(color: Color(red: 80 / 255, green: 70 / 255, blue: 60 / 255).opacity(0.32), radius: 0, y: -0.8)
            }
        }
        .frame(width: diametro, height: diametro)
    }
}

/// El destello de Alma (el mismo trazo de la web: SPARK en js/sa-nav.js, en una caja de 24).
struct Destello: Shape {
    func path(in r: CGRect) -> Path {
        let s = min(r.width, r.height) / 24, ox = r.midX - 12 * s, oy = r.midY - 12 * s
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        var c = Path()
        c.move(to: p(12, 2.5))
        c.addCurve(to: p(19, 10), control1: p(12.4, 7.1), control2: p(13.6, 8.7))
        c.addCurve(to: p(12, 19.5), control1: p(13.6, 11.3), control2: p(12.4, 12.9))
        c.addCurve(to: p(5, 10), control1: p(11.6, 12.9), control2: p(10.4, 11.3))
        c.addCurve(to: p(12, 2.5), control1: p(10.4, 8.7), control2: p(11.6, 7.1))
        c.closeSubpath()
        return c
    }
}
