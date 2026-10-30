import UserNotifications

/// Avisos de Alma en el iPhone: cuando terminó en segundo plano algo que necesita algo de ti, llega una notificación.
/// El número en el ícono es cuántos temas hay por retomar; al tocar la notificación se abre la app y, con dos toques del
/// anillo (o el botón de voz), Alma empieza por el más importante.
final class Notificaciones: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notificaciones()
    private var pedido = false

    /// El permiso se pide una vez, la primera vez que hay algo que avisar.
    private func conPermiso(pedir: Bool = true, _ hacer: @escaping () -> Void) {
        let c = UNUserNotificationCenter.current()
        c.getNotificationSettings { s in
            switch s.authorizationStatus {
            case .authorized, .provisional, .ephemeral: hacer()
            case .notDetermined:
                guard pedir, !self.pedido else { return }; self.pedido = true
                c.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in if ok { hacer() } }
            default: break
            }
        }
    }

    func mostrar(id: String, texto: String) {
        guard !texto.isEmpty else { return }
        conPermiso {
            let n = UNMutableNotificationContent()
            n.title = "Alma"; n.body = texto; n.sound = .default; n.threadIdentifier = "alma.retomar"
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: n, trigger: nil))
        }
    }

    /// El número del ícono: temas por retomar.
    func globo(_ n: Int) {
        conPermiso(pedir: n > 0) { UNUserNotificationCenter.current().setBadgeCount(max(0, n)) }
    }

    /// Con la app abierta, la notificación igual se ve arriba (y suena).
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler fin: @escaping (UNNotificationPresentationOptions) -> Void) {
        fin([.banner, .sound, .list])
    }
}
