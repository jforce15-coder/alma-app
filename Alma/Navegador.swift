import SwiftUI
import WebKit

/// El visor principal: un WKWebView con la misma sesión que Safari guardaría (data store por defecto),
/// así el login de Spacio AM y de GitHub se queda entre una apertura y otra.
final class Navegador: NSObject, ObservableObject {
    /// Inicio de la app: Alma grande al centro sobre el atardecer (hub.spacioam.com/alma/inicio.html).
    static let inicio = URL(string: "https://hub.spacioam.com/alma/inicio.html")!

    let web: WKWebView
    @Published var direccion = ""
    @Published var titulo = ""
    @Published var puedeAtras = false
    @Published var puedeAdelante = false
    @Published var progreso: Double = 0
    @Published var cargando = false

    private var observaciones: [NSKeyValueObservation] = []
    /// Entrar con Face ID o Google desde la página de inicio (Puente.swift).
    private let puente = Puente()

    override init() {
        web = WKWebView(frame: .zero, configuration: Navegador.configuracion())
        super.init()
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        if #available(iOS 16.4, *) { web.isInspectable = true }
        puente.web = web
        web.configuration.userContentController.add(PuenteDebil(puente), name: Puente.nombre)
        observaciones = [
            web.observe(\.url, options: [.new]) { [weak self] w, _ in DispatchQueue.main.async { self?.direccion = w.url?.absoluteString ?? "" } },
            web.observe(\.title, options: [.new]) { [weak self] w, _ in DispatchQueue.main.async { self?.titulo = w.title ?? "" } },
            web.observe(\.canGoBack, options: [.new]) { [weak self] w, _ in DispatchQueue.main.async { self?.puedeAtras = w.canGoBack } },
            web.observe(\.canGoForward, options: [.new]) { [weak self] w, _ in DispatchQueue.main.async { self?.puedeAdelante = w.canGoForward } },
            web.observe(\.estimatedProgress, options: [.new]) { [weak self] w, _ in DispatchQueue.main.async { self?.progreso = w.estimatedProgress } },
            web.observe(\.isLoading, options: [.new]) { [weak self] w, _ in DispatchQueue.main.async { self?.cargando = w.isLoading } }
        ]
        web.load(URLRequest(url: Navegador.inicio))
    }

    /// Configuración compartida por el visor y el panel de Alma (misma sesión, micrófono y video en línea).
    static func configuracion() -> WKWebViewConfiguration {
        let c = WKWebViewConfiguration()
        c.websiteDataStore = .default()
        c.allowsInlineMediaPlayback = true
        c.mediaTypesRequiringUserActionForPlayback = []
        // Se presenta como Safari (algunas páginas cambian si ven un visor) y avisa que es la app de Alma.
        c.applicationNameForUserAgent = "Version/18.0 Mobile/15E148 Safari/604.1 AlmaApp/1.0"
        return c
    }

    /// ¿La página es de Spacio AM? Esas ya traen a Alma (la roca), así que la burbuja de la app se esconde.
    var esSpacio: Bool {
        guard let h = URL(string: direccion)?.host?.lowercased() else { return false }
        return h == "spacioam.com" || h.hasSuffix(".spacioam.com")
    }

    /// ¿Está en el inicio (Alma al centro)? Ahí la pantalla va limpia, sin barra.
    var enInicio: Bool {
        guard let u = URL(string: direccion) else { return true }
        return u.host?.lowercased() == Navegador.inicio.host && u.path == Navegador.inicio.path
    }

    /// Lo que se escribe en la barra: una dirección o una búsqueda en Google.
    func abrir(texto: String) {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if let u = URL(string: t), let s = u.scheme, ["http", "https"].contains(s.lowercased()) {
            web.load(URLRequest(url: u)); return
        }
        if !t.contains(" "), t.contains("."), let u = URL(string: "https://" + t) {
            web.load(URLRequest(url: u)); return
        }
        var c = URLComponents(string: "https://www.google.com/search")!
        c.queryItems = [URLQueryItem(name: "q", value: t)]
        if let u = c.url { web.load(URLRequest(url: u)) }
    }

    /// alma://abrir?u=https%3A%2F%2F… · alma://https://… · alma://github.com/…
    func abrir(desdeEnlace enlace: URL) {
        guard enlace.scheme?.lowercased() == "alma" else { return }
        if let c = URLComponents(url: enlace, resolvingAgainstBaseURL: false),
           let u = c.queryItems?.first(where: { $0.name == "u" || $0.name == "url" })?.value, !u.isEmpty {
            abrir(texto: u); return
        }
        var resto = enlace.absoluteString
        if let r = resto.range(of: "alma://") { resto = String(resto[r.upperBound...]) }
        if resto.hasPrefix("abrir") { resto = "" }
        if let d = resto.removingPercentEncoding, !d.isEmpty { abrir(texto: d) }
    }

    func irAlInicio() { web.load(URLRequest(url: Navegador.inicio)) }
}

// MARK: - Navegación

extension Navegador: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        Navegador.decidir(navigationAction, decisionHandler)
    }

    /// tel:, mailto:, whatsapp:, maps… se abren con la app del teléfono; lo web se queda aquí.
    static func decidir(_ accion: WKNavigationAction, _ decision: @escaping (WKNavigationActionPolicy) -> Void) {
        if let u = accion.request.url, let s = u.scheme?.lowercased(),
           !["http", "https", "about", "data", "blob", "file", "javascript"].contains(s) {
            UIApplication.shared.open(u)
            decision(.cancel); return
        }
        decision(.allow)
    }
}

// MARK: - Ventanas, permisos y avisos de la página

extension Navegador: WKUIDelegate {
    /// target="_blank" y window.open: en el mismo visor.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let u = navigationAction.request.url { webView.load(URLRequest(url: u)) }
        return nil
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(Avisos.permiso(origin))
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        Avisos.alerta(message, completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        Avisos.confirmar(message, completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        Avisos.preguntar(prompt, defaultText, completionHandler)
    }
}

/// alert(), confirm() y prompt() de las páginas, como avisos de iOS. Lo usan el visor y el panel de Alma.
enum Avisos {
    /// Micrófono y cámara: las páginas de Spacio AM sin preguntar (ya lo autorizaste para la app); las demás preguntan.
    static func permiso(_ origin: WKSecurityOrigin) -> WKPermissionDecision {
        let h = origin.host.lowercased()
        return h == "spacioam.com" || h.hasSuffix(".spacioam.com") ? .grant : .prompt
    }

    static func alerta(_ texto: String, _ listo: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: texto, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in listo() })
        if !mostrar(a) { listo() }
    }

    static func confirmar(_ texto: String, _ listo: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: texto, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in listo(false) })
        a.addAction(UIAlertAction(title: "Aceptar", style: .default) { _ in listo(true) })
        if !mostrar(a) { listo(false) }
    }

    static func preguntar(_ texto: String, _ inicial: String?, _ listo: @escaping (String?) -> Void) {
        let a = UIAlertController(title: nil, message: texto, preferredStyle: .alert)
        a.addTextField { $0.text = inicial }
        a.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in listo(nil) })
        a.addAction(UIAlertAction(title: "Aceptar", style: .default) { _ in listo(a.textFields?.first?.text) })
        if !mostrar(a) { listo(nil) }
    }

    /// Presenta sobre lo que esté encima (el visor o el panel de Alma). false si no hay dónde.
    @discardableResult
    static func mostrar(_ vc: UIViewController) -> Bool {
        let escena = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard var arriba = escena?.windows.first(where: { $0.isKeyWindow })?.rootViewController ?? escena?.windows.first?.rootViewController else { return false }
        while let p = arriba.presentedViewController { arriba = p }
        arriba.present(vc, animated: true)
        return true
    }
}
