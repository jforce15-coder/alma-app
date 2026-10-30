import AuthenticationServices
import LocalAuthentication
import Security
import UIKit
import WebKit

/// Lo que la página de inicio (hub.spacioam.com/alma/inicio.html) le pide a la app para entrar:
///   { accion: "estado" }                     → AlmaLogin.estado({ faceID, guardado })
///   { accion: "google" }                     → hoja segura de Safari con Google → AlmaLogin.google(cred)
///   { accion: "faceGuardar", email, llave }  → guarda la llave del login en el llavero, protegida con Face ID
///   { accion: "faceEntrar" }                 → pide Face ID y devuelve la llave → AlmaLogin.face(email, llave)
///   { accion: "faceBorrar" }
///   { accion: "navegador", pos }             → Alma se llevó a una de las 8 posiciones: barra de búsqueda lista ("" = volvió al centro)
/// Solo responde a páginas de hub.spacioam.com.
final class Puente: NSObject, WKScriptMessageHandler, ASWebAuthenticationPresentationContextProviding {
    static let nombre = "alma"
    weak var web: WKWebView?
    private var sesionGoogle: ASWebAuthenticationSession?

    func userContentController(_ uc: WKUserContentController, didReceive m: WKScriptMessage) {
        guard m.frameInfo.securityOrigin.host.lowercased() == "hub.spacioam.com",
              let d = m.body as? [String: Any], let accion = d["accion"] as? String else { return }
        switch accion {
        case "estado":
            responder("AlmaLogin.estado", [["faceID": Llavero.hayFaceID, "guardado": Llavero.hayGuardado]])
        case "google":
            google()
        case "faceGuardar":
            if let e = d["email"] as? String, let l = d["llave"] as? String { Llavero.guardar(email: e, llave: l) }
        case "faceEntrar":
            Llavero.leer { par in
                if let par { self.responder("AlmaLogin.face", [par.email, par.llave]) }
                else { self.responder("AlmaLogin.cancelado", [""]) }
            }
        case "faceBorrar":
            Llavero.borrar()
        case "anillo":
            anillo(d)
        case "conferencia":   // Ajustes → «Modo conferencia» (Conferencia.swift): { que: "on" | "off" | "estado" }
            let c = Conferencia.shared
            c.alEvento = { [weak self] e in self?.responder("AlmaConf.evento", [e]) }
            switch d["que"] as? String ?? "" { case "on": c.poner(true); case "off": c.poner(false); default: break }
            responder("AlmaConf.evento", [c.resumen])
        case "voz":
            voz(d)
        case "navegador":   // llevaste a Alma hacia un lado en el inicio: se abre el navegador con la búsqueda lista
            NotificationCenter.default.post(name: .modoNavegador, object: d["pos"] as? String ?? "")
        case "health":   // Health es nativo (Health/SaludVista.swift): se abre encima de la página
            NotificationCenter.default.post(name: .abrirSalud, object: nil)
            responder("AlmaHealth.abierto", [true])
        case "salud":
            Salud.shared.manejar(d["que"] as? String ?? "leer") { [weak self] datos in self?.responder("AlmaSalud.datos", [datos]) }
        default: break
        }
    }

    /// El anillo por Bluetooth (Anillo.swift): { accion: "anillo", que: "estado" | "buscar" | "elegir" | "olvidar" | "comando" | "registro", … }
    /// Lo que llega del anillo va a la página como AlmaAnillo.evento({ tipo, … }).
    private func anillo(_ d: [String: Any]) {
        let a = Anillo.shared
        a.alEvento = { [weak self] e in self?.responder("AlmaAnillo.evento", [e]) }
        switch d["que"] as? String ?? "" {
        case "buscar": a.buscar()
        case "elegir": if let id = d["id"] as? String { a.elegir(id) }
        case "olvidar": a.olvidar()
        case "comando": a.comando(d["nombre"] as? String ?? "", d)
        case "registro": responder("AlmaAnillo.registro", [a.tomarRegistro()])
        default: var e = a.estado; e["tipo"] = "estado"; responder("AlmaAnillo.evento", [e])
        }
    }

    /// Alma con el teléfono bloqueado (VozNativa.swift): { accion: "voz", que: "configurar" | "anillo" | "alternar" | "hablar" | "colgar" | "texto" | "mudo" | "estado", … }
    /// Lo que pasa (estado, lo que dices, lo que responde Alma) va a la página como AlmaVoz.evento({ tipo, … }).
    private func voz(_ d: [String: Any]) {
        let v = VozNativa.shared
        v.alEvento = { [weak self] e in self?.responder("AlmaVoz.evento", [e]) }
        switch d["que"] as? String ?? "" {
        case "configurar":
            if let u = d["url"] as? String, let t = d["token"] as? String, let s = d["sesion"] as? String { v.configurar(url: u, token: t, sesion: s) }
        case "anillo": v.ponerModoAnillo((d["on"] as? Bool) ?? false)
        case "alternar": v.alternar()
        case "hablar": v.hablarDesdePantalla()          // la roca del inicio abre la conversación
        case "colgar": v.colgar()
        case "texto": v.escribir(d["texto"] as? String ?? "")
        case "mudo": v.silenciar((d["on"] as? Bool) ?? false)
        default: break
        }
        responder("AlmaVoz.evento", [v.resumen])
    }

    /// Google no deja entrar dentro de un visor: la hoja segura de Safari va directo a elegir la cuenta de Google.
    /// Google vuelve a hub.spacioam.com/alma/google.html, que la devuelve al instante con alma://google?cred=…
    private func google() {
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: "946315464909-i0uptgcvbpqnspnjp5a0o4a7dnpi0ngi.apps.googleusercontent.com"),
            URLQueryItem(name: "response_type", value: "id_token"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "prompt", value: "select_account"),
            URLQueryItem(name: "redirect_uri", value: "https://hub.spacioam.com/alma/google.html"),
            URLQueryItem(name: "nonce", value: UUID().uuidString)
        ]
        let u = c.url!
        let s = ASWebAuthenticationSession(url: u, callbackURLScheme: "alma") { [weak self] url, error in
            DispatchQueue.main.async {
                self?.sesionGoogle = nil
                let q = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }
                if let cred = q?.first(where: { $0.name == "cred" })?.value, !cred.isEmpty {
                    self?.responder("AlmaLogin.google", [cred])
                } else {
                    let cancelo = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                    self?.responder("AlmaLogin.cancelado", [cancelo ? "" : "No pudimos entrar con Google. Intenta de nuevo o usa tu correo."])
                }
            }
        }
        s.presentationContextProvider = self
        s.prefersEphemeralWebBrowserSession = false
        sesionGoogle = s
        if !s.start() { responder("AlmaLogin.cancelado", ["No pudimos abrir Google."]) }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        web?.window ?? UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }

    /// Llama a una función de la página con argumentos en JSON (nada de texto armado a mano).
    private func responder(_ funcion: String, _ args: [Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: args), let json = String(data: data, encoding: .utf8) else { return }
        let js = "window.\(funcion.split(separator: ".").first ?? "") && \(funcion).apply(null, \(json))"
        DispatchQueue.main.async { self.web?.evaluateJavaScript(js) }
    }
}

/// La llave de «Entrar con Face ID»: en el llavero de este equipo, solo se lee después de pasar Face ID
/// (si cambian las caras registradas, se invalida sola).
enum Llavero {
    private static let base: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.spacioam.alma.faceid",
        kSecAttrAccount as String: "login"
    ]
    struct Par: Codable { let email: String; let llave: String }

    static var hayFaceID: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) }

    /// ¿Hay una llave guardada? Sin pedir Face ID: si existe, el llavero responde «necesita autenticación».
    static var hayGuardado: Bool {
        let c = LAContext(); c.interactionNotAllowed = true
        var q = base; q[kSecUseAuthenticationContext as String] = c; q[kSecReturnData as String] = false
        let s = SecItemCopyMatching(q as CFDictionary, nil)
        return s == errSecSuccess || s == errSecInteractionNotAllowed
    }

    static func guardar(email: String, llave: String) {
        guard hayFaceID, let datos = try? JSONEncoder().encode(Par(email: email, llave: llave)),
              let ac = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, nil) else { return }
        borrar()
        var q = base; q[kSecValueData as String] = datos; q[kSecAttrAccessControl as String] = ac
        SecItemAdd(q as CFDictionary, nil)
    }

    static func leer(_ fin: @escaping (Par?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let c = LAContext(); c.localizedReason = "Entrar a Alma"
            var q = base; q[kSecUseAuthenticationContext as String] = c; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
            var r: CFTypeRef?
            let s = SecItemCopyMatching(q as CFDictionary, &r)
            let par = s == errSecSuccess ? (r as? Data).flatMap { try? JSONDecoder().decode(Par.self, from: $0) } : nil
            DispatchQueue.main.async { fin(par) }
        }
    }

    static func borrar() { SecItemDelete(base as CFDictionary) }
}

/// WKUserContentController retiene a quien recibe los mensajes: este intermediario evita que el visor nunca se libere.
final class PuenteDebil: NSObject, WKScriptMessageHandler {
    weak var destino: WKScriptMessageHandler?
    init(_ d: WKScriptMessageHandler) { destino = d }
    func userContentController(_ uc: WKUserContentController, didReceive m: WKScriptMessage) { destino?.userContentController(uc, didReceive: m) }
}
