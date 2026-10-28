import SwiftUI
import UIKit

/// La animación de Alma entre pantallas nativas (Health, Respira, la conexión del anillo): la roca crece desde el centro
/// hasta cubrir la pantalla, detrás se cambia de pantalla y la roca se encoge para mostrar la nueva.
/// Las páginas del Hub (el inicio) ya traen su propia animación de Alma: aquí no se duplica.
/// Fuera del cambio, la ventana queda oculta: no se ve nada.
/// Vive en su propia ventana, por encima de todo (también de las pantallas completas), y no deja tocar mientras pasa.
final class Portal: ObservableObject {
    static let shared = Portal()
    @Published private(set) var cubierto = false
    private var ventana: UIWindow?
    private var cubiertoDesde = Date.distantPast
    private var pendiente: DispatchWorkItem?

    static let entrada = 0.42, salida = 0.5

    /// Se instala una vez, en la escena de la app.
    func instalar() {
        guard ventana == nil, let escena = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let v = UIWindow(windowScene: escena)
        v.windowLevel = .alert + 1
        v.backgroundColor = .clear
        let raiz = UIHostingController(rootView: PortalVista(portal: self))
        raiz.view.backgroundColor = .clear
        v.rootViewController = raiz
        v.isUserInteractionEnabled = false
        v.isHidden = true
        ventana = v
    }

    /// Cubre, hace el cambio sin la animación del sistema y descubre.
    func pasar(_ cambio: @escaping () -> Void) {
        cubrir()
        DispatchQueue.main.asyncAfter(deadline: .now() + Portal.entrada) {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { cambio() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.descubrir() }
        }
    }

    func cubrir() {
        instalar()
        pendiente?.cancel()
        guard !cubierto else { return }
        ventana?.isHidden = false
        ventana?.isUserInteractionEnabled = true
        cubiertoDesde = Date()
        withAnimation(.timingCurve(0.65, 0, 0.35, 1, duration: Portal.entrada)) { cubierto = true }
        // por si nadie lo descubre (una página que nunca termina de cargar)
        let w = DispatchWorkItem { [weak self] in self?.descubrir() }
        pendiente = w; DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: w)
    }

    /// Descubre cuando ya terminó de cubrir (la roca nunca se corta a media animación).
    func descubrir() {
        pendiente?.cancel()
        let falta = max(0, Portal.entrada - Date().timeIntervalSince(cubiertoDesde))
        DispatchQueue.main.asyncAfter(deadline: .now() + falta) {
            guard self.cubierto else { return }
            withAnimation(.timingCurve(0.22, 0.61, 0.36, 1, duration: Portal.salida)) { self.cubierto = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + Portal.salida + 0.05) { if !self.cubierto { self.ventana?.isUserInteractionEnabled = false; self.ventana?.isHidden = true } }
        }
    }
}

struct PortalVista: View {
    @ObservedObject var portal: Portal
    @Environment(\.accessibilityReduceMotion) private var quieto
    var body: some View {
        GeometryReader { g in
            let lado = hypot(g.size.width, g.size.height) * 1.15
            ZStack {
                // el halo coral de Alma, que llega primero
                Circle().fill(Color.almaCoral.opacity(0.35)).frame(width: lado, height: lado).blur(radius: 60)
                    .scaleEffect(portal.cubierto ? 1.1 : 0.001).opacity(portal.cubierto ? 1 : 0)
                // la roca: blanca y cálida, con su luz arriba a la izquierda
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 1, green: 0.99, blue: 0.98), Color(red: 0.99, green: 0.95, blue: 0.93),
                                                  Color(red: 0.98, green: 0.9, blue: 0.86)],
                                         center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: lado * 0.6))
                    .frame(width: lado, height: lado)
                    .scaleEffect(portal.cubierto ? 1 : 0.001).opacity(portal.cubierto ? 1 : 0)
                // el destello, que aparece en el centro cuando ya cubrió
                Image(systemName: "sparkle").font(.system(size: 30)).foregroundStyle(Color(red: 0.79, green: 0.76, blue: 0.72))
                    .opacity(portal.cubierto ? 1 : 0).scaleEffect(portal.cubierto ? 1 : 0.6)
            }
            .frame(width: g.size.width, height: g.size.height)
            .opacity(quieto ? (portal.cubierto ? 1 : 0) : 1)
        }
        .ignoresSafeArea()
        .allowsHitTesting(portal.cubierto)
    }
}
