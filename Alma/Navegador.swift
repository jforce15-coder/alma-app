import SwiftUI
import WebKit

/// El visor principal: un WKWebView con la misma sesión que Safari guardaría (data store por defecto),
/// así el login de Spacio AM y de GitHub se queda entre una apertura y otra.
final class Navegador: NSObject, ObservableObject {
    /// Inicio de la app: Alma grande al centro sobre el atardecer (hub.spacioam.com/alma/inicio.html).
    static let inicio = URL(string: "https://hub.spacioam.com/alma/inicio.html")!

    /// Acceso directo que sale al tocar la barra de dirección.
    static let homeSpacio = URL(string: "https://hub.spacioam.com/")!

    let web: WKWebView
    @Published var direccion = ""
    @Published var titulo = ""
    @Published var puedeAtras = false
    @Published var puedeAdelante = false
    @Published var progreso: Double = 0
    @Published var cargando = false
    /// Dónde vive Alma en el navegador: una de las 8 posiciones del Hub (tl tc tr ml mr bl bc br).
    /// Es la misma que usan las web apps (cookie sa_nav_pos de .spacioam.com), así Alma está en el mismo lugar en todas.
    @Published var posAlma = "br"
    /// La barra pide el teclado (modo búsqueda): se pone en true al llevar a Alma hacia un lado.
    @Published var pedirBusqueda = false
    /// El cuadro de texto activo de la página (dónde está y qué dice): Alma se aparta de él y, con dos toques, lo mejora.
    struct Campo: Equatable { var rect: CGRect; var texto: String; var etiqueta: String; var clave: Bool }
    @Published var campo: Campo?
    /// La barra de dirección tiene el teclado (se escribe una dirección o una búsqueda).
    @Published var escribiendo = false
    /// La roca tapa una carga en curso (Portal.swift); se destapa al terminar de cargar.
    var cargaTapada = false
    /// Dónde está la roca de Alma en la pantalla (lo da ContentView): de ahí sale y ahí vuelve la transición.
    var puntoRoca: (() -> CGPoint?)?

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
        web.configuration.userContentController.add(PuenteDebil(self), name: "almaCampo")
        web.configuration.userContentController.addUserScript(WKUserScript(source: Navegador.scriptCampo, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        observaciones = [
            web.observe(\.url, options: [.new]) { [weak self] w, _ in DispatchQueue.main.async { self?.direccion = w.url?.absoluteString ?? ""; self?.campo = nil } },
            web.observe(\.title, options: [.new]) { [weak self] w, _ in DispatchQueue.main.async { self?.titulo = w.title ?? "" } },
            web.observe(\.canGoBack, options: [.new]) { [weak self] w, _ in DispatchQueue.main.async { self?.puedeAtras = w.canGoBack } },
            web.observe(\.canGoForward, options: [.new]) { [weak self] w, _ in DispatchQueue.main.async { self?.puedeAdelante = w.canGoForward } },
            web.observe(\.estimatedProgress, options: [.new]) { [weak self] w, _ in DispatchQueue.main.async { self?.progreso = w.estimatedProgress } },
            web.observe(\.isLoading, options: [.new]) { [weak self] w, _ in DispatchQueue.main.async { self?.cargando = w.isLoading } }
        ]
        web.load(URLRequest(url: Navegador.inicio))
        leerPosicion()
    }

    static let posiciones = ["tl", "tc", "tr", "ml", "mr", "bl", "bc", "br"]

    /// En cada página: avisa cuando se activa o se suelta un cuadro de texto (posición y texto; nunca el de una contraseña)
    /// y deja window.__almaPoner(texto) para que Alma escriba en él.
    static let scriptCampo = """
    (function(){
      if (window.__almaCampoOk) return; window.__almaCampoOk = true;
      function editable(e){ if(!e) return false; if(e.isContentEditable) return true; var t=e.tagName;
        if(t==='TEXTAREA') return !e.readOnly && !e.disabled; if(t!=='INPUT') return false;
        var ty=(e.type||'text').toLowerCase(); return ['text','search','email','url','tel','password','number'].indexOf(ty)>=0 && !e.readOnly && !e.disabled; }
      function val(e){ return e.isContentEditable ? e.innerText : e.value; }
      function enviar(e,on){ try { var r=e.getBoundingClientRect(), clave=(e.type||'')==='password';
        webkit.messageHandlers.almaCampo.postMessage({ on:on, x:r.left, y:r.top, w:r.width, h:r.height, clave:clave,
          texto: on && !clave ? String(val(e)||'').slice(0,6000) : '',
          etiqueta: String(e.getAttribute('aria-label')||e.placeholder||e.name||'').slice(0,120) }); } catch(x){} }
      document.addEventListener('focusin', function(ev){ var e=ev.target; if(editable(e)){ window.__almaCampo=e; enviar(e,true); } }, true);
      document.addEventListener('focusout', function(ev){ var e=ev.target; setTimeout(function(){ if(!editable(document.activeElement)) enviar(e,false); }, 150); }, true);
      var t=0; document.addEventListener('input', function(ev){ if(ev.target===window.__almaCampo){ clearTimeout(t); t=setTimeout(function(){ enviar(ev.target,true); }, 350); } }, true);
      window.__almaPoner = function(txt){ var e=window.__almaCampo; if(!e) return false; e.focus();
        if(e.isContentEditable){ var s=getSelection(), r=document.createRange(); r.selectNodeContents(e); s.removeAllRanges(); s.addRange(r); document.execCommand('insertText', false, txt); }
        else { var p=e.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype; Object.getOwnPropertyDescriptor(p,'value').set.call(e,txt);
          e.dispatchEvent(new Event('input',{bubbles:true})); e.dispatchEvent(new Event('change',{bubbles:true})); }
        return true; };
    })();
    """

    /// Escribe en el cuadro de texto activo (lo que respondió Alma).
    func ponerEnCampo(_ texto: String) {
        guard let d = try? JSONSerialization.data(withJSONObject: [texto]), let j = String(data: d, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.__almaPoner && __almaPoner(\(j)[0])")
    }

    /// La posición que dejaron las web apps (cookie compartida de .spacioam.com).
    func leerPosicion() {
        web.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cs in
            guard let v = cs.first(where: { $0.name == "sa_nav_pos" && $0.domain.hasSuffix("spacioam.com") })?.value,
                  Navegador.posiciones.contains(v) else { return }
            DispatchQueue.main.async { self?.posAlma = v }
        }
    }

    /// Alma cambió de lugar en la app: se guarda también para las web apps.
    func guardarPosicion(_ p: String) {
        guard Navegador.posiciones.contains(p) else { return }
        posAlma = p
        if let c = HTTPCookie(properties: [.domain: ".spacioam.com", .path: "/", .name: "sa_nav_pos", .value: p, .secure: "TRUE",
                                           .expires: Date().addingTimeInterval(365 * 86400)]) {
            web.configuration.websiteDataStore.httpCookieStore.setCookie(c)
        }
    }

    /// Alma vuelve al centro del inicio (se llevó hacia un lado pero no se buscó nada).
    func almaAlCentro() {
        guard enInicio else { return }
        web.evaluateJavaScript("window.SANav && SANav.escena(null)")
    }

    /// Captura de lo que se ve en el navegador, lista para Alma (JPEG chico en data URL).
    func captura(_ fin: @escaping (String?) -> Void) {
        let c = WKSnapshotConfiguration()
        c.snapshotWidth = NSNumber(value: Double(min(web.bounds.width, 430)))
        web.takeSnapshot(with: c) { img, _ in
            guard let img, let d = img.jpegData(compressionQuality: 0.7) else { fin(nil); return }
            fin("data:image/jpeg;base64," + d.base64EncodedString())
        }
    }

    /// Configuración compartida por el visor y el panel de Alma (misma sesión, micrófono y video en línea).
    static func configuracion() -> WKWebViewConfiguration {
        let c = WKWebViewConfiguration()
        c.websiteDataStore = .default()
        c.allowsInlineMediaPlayback = true
        c.mediaTypesRequiringUserActionForPlayback = []
        // Se presenta exactamente como Safari: Google (y otros) no dejan entrar si ven un visor dentro de una app
        // («This browser or app may not be secure»). Las páginas de Spacio AM reconocen la app por el puente, no por esto.
        c.applicationNameForUserAgent = Navegador.firmaSafari
        return c
    }

    /// El final del agente de Safari de esta versión de iOS: «Version/26.0 Mobile/15E148 Safari/604.1» en el iPhone,
    /// «Version/26.0 Safari/605.1.15» en el iPad (que se presenta como Mac, igual que Safari).
    static var firmaSafari: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let ver = "Version/\(v.majorVersion).\(v.minorVersion)"
        return UIDevice.current.userInterfaceIdiom == .pad ? ver + " Safari/605.1.15" : ver + " Mobile/15E148 Safari/604.1"
    }

    /// ¿La página es de Spacio AM? Esas ya traen a Alma (la roca), así que la burbuja de la app se esconde.
    var esSpacio: Bool {
        // Mientras la app abre (todavía sin dirección) se asume Spacio AM: así la burbuja no aparece un instante sola.
        guard let h = URL(string: direccion)?.host?.lowercased() else { return true }
        return h == "spacioam.com" || h.hasSuffix(".spacioam.com")
    }

    /// Pantallas propias de la app (el inicio con Alma y Health): van a pantalla completa, sin barra.
    static let pantallasCompletas = ["/alma/inicio.html", "/health/", "/health/index.html"]
    var enInicio: Bool {
        guard let u = URL(string: direccion) else { return true }
        return u.host?.lowercased() == Navegador.inicio.host && Navegador.pantallasCompletas.contains(u.path)
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

// MARK: - El cuadro de texto activo

extension Navegador: WKScriptMessageHandler {
    func userContentController(_ uc: WKUserContentController, didReceive m: WKScriptMessage) {
        guard m.name == "almaCampo", let d = m.body as? [String: Any] else { return }
        guard (d["on"] as? Bool) == true else { campo = nil; return }
        let n = { (k: String) in CGFloat((d[k] as? NSNumber)?.doubleValue ?? 0) }
        campo = Campo(rect: CGRect(x: n("x"), y: n("y"), width: n("w"), height: n("h")), texto: d["texto"] as? String ?? "",
                      etiqueta: d["etiqueta"] as? String ?? "", clave: (d["clave"] as? Bool) ?? false)
    }
}

// MARK: - Navegación

extension Navegador: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        Navegador.decidir(navigationAction) { [weak self] pol in
            if pol == .allow, navigationAction.targetFrame?.isMainFrame ?? true, let u = navigationAction.request.url, self?.taparCarga(hacia: u) == true {
                self?.cargaTapada = true; Portal.shared.cubrir(desde: self?.puntoRoca?())
            }
            decisionHandler(pol)
        }
    }

    /// Lo que tarda en cargar una página nueva lo tapa la roca de Alma (como el cambio de app en el Hub): crece, detrás
    /// carga la página y se encoge al estar lista. No en las de Spacio AM entre sí (sa-nav ya hace su propia transición),
    /// ni al volver al inicio (trae la suya), ni dentro de la misma página.
    func taparCarga(hacia u: URL) -> Bool {
        guard let s = u.scheme?.lowercased(), s == "http" || s == "https", let h = u.host?.lowercased() else { return false }
        let antes = URL(string: direccion)?.host?.lowercased() ?? ""
        let spacio = { (x: String) in x == "spacioam.com" || x.hasSuffix(".spacioam.com") }
        if h == antes { return false }
        if spacio(h) && (spacio(antes) || Navegador.pantallasCompletas.contains(u.path)) { return false }
        return true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { destapar() }
    /// iOS cerró el proceso de la página (memoria, o el audio de la voz en la página): se vuelve a cargar sola en vez de
    /// quedar en blanco o parecer que la app se cerró. Queda anotado en Ajustes («voz_ultimo_error»).
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        UserDefaults.standard.set("La página se cerró sola (iOS) y se volvió a abrir", forKey: "voz_ultimo_error")
        if webView.url != nil { webView.reload() } else { webView.load(URLRequest(url: Navegador.inicio)) }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { destapar() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { destapar() }
    private func destapar() {
        guard cargaTapada else { return }
        cargaTapada = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in Portal.shared.descubrir(hacia: self?.puntoRoca?()) }   // un instante para que pinte
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
