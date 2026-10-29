import SwiftUI
import WebKit

/// La roca de Alma en el navegador: la misma de las web apps (hub.spacioam.com/alma/roca.html, con sa-nav.js), en una
/// capa transparente encima de la página. Así se ve, respira y se mueve por las 8 posiciones igual que en el Hub.
/// Solo la roca recibe toques (la página avisa dónde está); lo demás pasa a la página de abajo.
final class RocaNavegador: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    static let direccion = URL(string: "https://hub.spacioam.com/alma/roca.html")!
    let web: RocaWebView
    /// Dónde está la roca en la pantalla (para dejar pasar los toques fuera de ella y poner los avisos junto a ella).
    @Published private(set) var zona: CGRect = .zero
    var alToques: ((Int) -> Void)?
    private var lista = false
    private var pendiente: String?

    override init() {
        let c = Navegador.configuracion()   // misma sesión y cookies: la posición sa_nav_pos es la de las web apps
        web = RocaWebView(frame: .zero, configuration: c)
        super.init()
        c.userContentController.add(PuenteDebil(self), name: "almaRoca")
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.navigationDelegate = self
        if #available(iOS 16.4, *) { web.isInspectable = true }
        web.load(URLRequest(url: RocaNavegador.direccion))
    }

    func userContentController(_ uc: WKUserContentController, didReceive m: WKScriptMessage) {
        guard m.frameInfo.securityOrigin.host.lowercased() == "hub.spacioam.com", let d = m.body as? [String: Any] else { return }
        switch d["tipo"] as? String ?? "" {
        case "zona":
            let n = { (k: String) in CGFloat((d[k] as? NSNumber)?.doubleValue ?? 0) }
            let r = CGRect(x: n("x"), y: n("y"), width: n("w"), height: n("h"))
            zona = r; web.zona = r
        case "toques":
            alToques?((d["n"] as? NSNumber)?.intValue ?? 1)
        case "lista":
            lista = true
            if let js = pendiente { pendiente = nil; web.evaluateJavaScript(js) }
        default: break
        }
    }

    /// Si la página de la roca no carga (sin internet), se reintenta en un rato.
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { reintentar() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { reintentar() }
    private func reintentar() {
        lista = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.web.load(URLRequest(url: RocaNavegador.direccion)) }
    }

    private func js(_ s: String) {
        if lista { web.evaluateJavaScript(s) } else { pendiente = s }
    }

    /// Escribiendo (teclado arriba): Alma va de paso abajo al centro, justo encima del teclado; al terminar, vuelve a tu lugar.
    func abajo(_ on: Bool) {
        js(on ? "window.AlmaRoca && (AlmaRoca.ir ? AlmaRoca.ir('bc') : AlmaRoca.apartar())" : "window.AlmaRoca && AlmaRoca.volver()")
    }

    /// El brillo de Alma mientras escucha o escribe.
    func escuchar(_ on: Bool) { js("window.AlmaRoca && AlmaRoca.escuchar(\(on))") }
}

/// Deja tocar solo la roca: fuera de ella, el toque sigue a la página de abajo.
/// (Mientras se arrastra, el dedo ya es de la roca: iOS le sigue mandando el gesto aunque salga de la zona.)
final class RocaWebView: WKWebView {
    var zona: CGRect = .zero
    override func hitTest(_ p: CGPoint, with e: UIEvent?) -> UIView? {
        guard !isHidden, zona.width > 0, zona.insetBy(dx: -14, dy: -14).contains(p) else { return nil }
        return super.hitTest(p, with: e)
    }
}

struct RocaVista: UIViewRepresentable {
    let web: RocaWebView
    func makeUIView(context: Context) -> RocaWebView { web }
    func updateUIView(_ uiView: RocaWebView, context: Context) {}
}

/// Lo que Alma está haciendo con el cuadro de texto, junto a la roca: escuchando (con lo que oye), escribiendo o lo que contesta.
struct AvisoMejora: View {
    let zona: CGRect
    let texto: String
    var body: some View {
        GeometryReader { g in
            let abajo = zona.midY < g.size.height / 2
            Text(texto)
                .font(.system(size: 14, weight: .medium)).foregroundStyle(Color.almaTinta).lineLimit(4).multilineTextAlignment(.center)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Capsule().fill(.ultraThinMaterial)).overlay(Capsule().stroke(Color.almaBorde, lineWidth: 0.5))
                .frame(maxWidth: min(g.size.width - 40, 300))
                .position(x: max(min(zona.midX, g.size.width - 160), min(160, g.size.width / 2)),
                          y: abajo ? zona.maxY + 44 : zona.minY - 44)
        }
        .allowsHitTesting(false)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}
