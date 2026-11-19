import OneSignalFramework
import UIKit
import UserNotifications

/// Notificaciones push reales (Hub, Ticket #28; Juan, 16-nov-2026): con la app dormida o cerrada los avisos llegan igual y
/// Siri los anuncia. El Hub manda por OneSignal (Apps Script no habla con Apple directo) y la extensión NotifAlma los arma
/// como mensaje de Alma. Lo que decide, sin iOS, está en NotifPush.swift.
///   · El Hub dice en vozAvisos con qué registrarse (`push`: { app_id, externo }): la app de OneSignal del iPhone y el
///     external_id de este usuario (alma_ + su clave, nunca el correo). Sin eso (no hay llaves en el Hub), nada cambia.
///   · Se guarda para la próxima vez: al abrir, OneSignal arranca de una vez y recibe aunque el Hub no haya contestado.
///   · Permiso: si nunca se pidió, se pide (alerta, sonido y número); si ya está, OneSignal pide el token a Apple solo.
///   · En cada vozAvisos la app dice si su push está listo (`push`: { listo }); el Hub solo manda push si lo está.
///   · El número del ícono es de la app (temas por retomar): OneSignal no lo borra (OneSignal_disable_badge_clearing).
final class PushAlma {
    static let shared = PushAlma()
    private let claveApp = "push_app_id", claveExterno = "push_externo"
    private var appIniciada: String?

    /// Al abrir la app (AlmaApp.init): con una configuración guardada, OneSignal arranca ya.
    func arrancar() {
        let d = UserDefaults.standard
        callado = Companero.shared.callaAvisos
        guard let app = d.string(forKey: claveApp), let ext = d.string(forKey: claveExterno), !app.isEmpty, !ext.isEmpty else { return }
        iniciar(app: app, externo: ext)
    }

    /// Lo que mandó el Hub en vozAvisos. Sin `push`, nada (avisos locales como siempre).
    func configurar(_ hub: Any?) {
        guard let c = NotifPush.config(hub) else { return }
        let d = UserDefaults.standard
        let cambio = d.string(forKey: claveApp) != c.app || d.string(forKey: claveExterno) != c.externo
        d.set(c.app, forKey: claveApp); d.set(c.externo, forKey: claveExterno)
        if appIniciada == nil || cambio { iniciar(app: c.app, externo: c.externo) }
    }

    private func iniciar(app: String, externo: String) {
        // OneSignal se inicia una vez por arranque; si el Hub cambia de app de OneSignal, la nueva vale desde el próximo.
        if appIniciada == nil { OneSignal.initialize(app, withLaunchOptions: nil); appIniciada = app }
        if OneSignal.User.externalId != externo { OneSignal.login(externo) }
        aplicarCallado()
        UNUserNotificationCenter.current().getNotificationSettings { s in
            guard s.authorizationStatus == .notDetermined else { return }
            DispatchQueue.main.async { OneSignal.Notifications.requestPermission({ _ in }, fallbackToSettings: false) }
        }
    }

    /// iPad con el Modo compañero encendido (Juan, 19-nov-2026; UnaLlamada.callaAvisos): su push se apaga en OneSignal para
    /// que no le lleguen notificaciones con la app cerrada. Al apagar el modo vuelve, solo si lo apagó esto (la marca): así
    /// nunca se le pide permiso a nadie que no lo tenía.
    private let claveCallado = "push_callado_companero"
    private var callado = false
    func callar(_ on: Bool) {
        DispatchQueue.main.async { self.callado = on; self.aplicarCallado() }
    }
    private func aplicarCallado() {
        guard appIniciada != nil else { return }   // sin OneSignal iniciado, se aplica al iniciar
        let d = UserDefaults.standard, apagado = d.bool(forKey: claveCallado)
        if callado && !apagado { OneSignal.User.pushSubscription.optOut(); d.set(true, forKey: claveCallado) }
        else if !callado && apagado { OneSignal.User.pushSubscription.optIn(); d.set(false, forKey: claveCallado) }
    }

    /// Para vozAvisos: { listo } (permiso, suscripción de OneSignal y el external_id que mandó el Hub). Sin configuración, nada.
    var estado: [String: Any]? {
        guard appIniciada != nil else { return nil }
        let s = OneSignal.User.pushSubscription
        let listo = NotifPush.listo(permiso: OneSignal.Notifications.permission, suscripcion: s.id, optedIn: s.optedIn, externoApp: OneSignal.User.externalId,
                                    externoHub: UserDefaults.standard.string(forKey: claveExterno))
        return ["listo": listo]
    }
}
