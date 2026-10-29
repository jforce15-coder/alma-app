import SwiftUI
import WebKit

/// Alma en un panel encima de la página: abre hub.spacioam.com/alma/ (chat y voz) con la página actual como contexto,
/// igual que el atajo «Alma aquí». Usa la misma sesión que el visor, así ya sabe quién eres.
struct PanelAlma: View {
    let titulo: String
    let desde: String
    /// Captura de la pantalla (triple toque a Alma): la página la recibe con AlmaCaptura(dataURL) al cargar.
    var captura: String? = nil

    var body: some View {
        PanelWeb(url: PanelAlma.direccion(titulo: titulo, desde: desde), captura: captura)
            .ignoresSafeArea(edges: .bottom)
            .background(Color.almaFondo)
    }

    /// ?t=<título>&desde=<url> (desde va al final; alma/index.html lee todo lo que sigue a «desde=»).
    static func direccion(titulo: String, desde: String) -> URL {
        var c = URLComponents(string: "https://hub.spacioam.com/alma/")!
        if !titulo.isEmpty { c.queryItems = [URLQueryItem(name: "t", value: String(titulo.prefix(200)))] }
        var s = c.url?.absoluteString ?? "https://hub.spacioam.com/alma/"
        if !desde.isEmpty {
            let codificada = desde.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            s += (s.contains("?") ? "&" : "?") + "desde=" + codificada
        }
        return URL(string: s) ?? URL(string: "https://hub.spacioam.com/alma/")!
    }
}

struct PanelWeb: UIViewRepresentable {
    let url: URL
    var captura: String? = nil

    func makeCoordinator() -> Coordinador { Coordinador(captura: captura) }

    func makeUIView(context: Context) -> WKWebView {
        let w = WKWebView(frame: .zero, configuration: Navegador.configuracion())
        w.uiDelegate = context.coordinator
        w.navigationDelegate = context.coordinator
        w.isOpaque = false
        w.backgroundColor = UIColor(Color.almaFondo)
        if #available(iOS 16.4, *) { w.isInspectable = true }
        w.load(URLRequest(url: url))
        return w
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinador: NSObject, WKUIDelegate, WKNavigationDelegate {
        private var captura: String?
        init(captura: String?) { self.captura = captura }

        /// Ya cargó la página de Alma: se le pasa la captura (una sola vez).
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let c = captura, webView.url?.path.hasPrefix("/alma") == true,
                  let d = try? JSONSerialization.data(withJSONObject: [c]), let j = String(data: d, encoding: .utf8) else { return }
            captura = nil
            webView.evaluateJavaScript("window.AlmaCaptura && AlmaCaptura(\(j)[0])")
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            Navegador.decidir(navigationAction, decisionHandler)
        }
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
    }
}
