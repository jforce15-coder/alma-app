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

    /// Registra la categoría con el botón «Abrir» (sale al expandir la notificación).
    func registrarCategorias() {
        let abrir = UNNotificationAction(identifier: "alma.abrir", title: "Abrir", options: [.foreground])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: "alma.aviso", actions: [abrir], intentIdentifiers: [],
                                   hiddenPreviewsBodyPlaceholder: AjustesNotif.generico, options: [])])
    }

    /// `titulo` y `lineas` (del Hub, vozAvisos): lo que terminó en segundo plano llega con la respuesta, no solo el aviso
    /// («Alma · Operación de hoy», el aviso de subtítulo y hasta 3 líneas del resultado). Sin ellos, como antes.
    /// Sin Notification Service Extension: no hay imagen ni botones por aviso; lo completo está en la tarjeta de Pendientes.
    /// `seDice`: Alma lo va a decir en voz alta (Modo calle, conferencia o la app abierta). Entonces la notificación va callada
    /// (EstadoCalle.notificacionCallada): sin sonido y pasiva, para que Siri no la lea con la voz del iPhone encima de Alma.
    /// `tipo` (Hub #551, `notif_tipo` del aviso): se arma con los ajustes de su tipo (AjustesNotif.swift, NotifArmar.swift).
    /// Sin tipo (los avisos propios de la app, como la pausa del Modo calle), como antes.
    func mostrar(id: String, texto: String, titulo: String = "", lineas: [String] = [], seDice: Bool = false, tipo: String? = nil) {
        guard !texto.isEmpty else { return }
        let clase = AjustesNotif.tipo(tipo)
        let plan = clase.map { AjustesNotif.plan(tipo: $0, ajuste: AjustesNotif.leer()[$0] ?? .deFabrica($0), momento: momentoAhora(seDice: seDice), id: id) }
        if plan?.mostrar == false { return }   // los tres lugares apagados: este tipo no llega
        conPermiso {
            let n = UNMutableNotificationContent()
            n.title = "Alma"; n.sound = .default; n.threadIdentifier = "alma.retomar"
            let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
            let ls = lineas.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(3)
            let tit = titulo.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ls.isEmpty {
                if !tit.isEmpty { n.title = "Alma · " + String(tit.prefix(60)) }
                n.subtitle = String(t.prefix(120))
                n.body = ls.map { "· " + $0 }.joined(separator: "\n")
            } else {
                // Notificación expandible: en el banner se ve el resumen (subtítulo) y al mantenerla presionada se abre el texto completo.
                let primera = t.components(separatedBy: CharacterSet(charactersIn: ".!?\n")).first ?? t
                if t.count > 90, !primera.isEmpty, primera.count <= 90 { n.subtitle = primera }
                n.body = String(t.prefix(1000))
            }
            if EstadoCalle.notificacionCallada(seDice: seDice) { n.sound = nil; n.interruptionLevel = .passive }
            n.categoryIdentifier = "alma.aviso"; n.userInfo = ["id": id, "seDice": seDice]
            if let clase, let plan { self.publicar(n, id: id, plan: plan, tipo: clase); return }
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: n, trigger: nil))
        }
    }

    /// El número del ícono: temas por retomar.
    func globo(_ n: Int) {
        conPermiso(pedir: n > 0) { UNUserNotificationCenter.current().setBadgeCount(max(0, n)) }
    }

    /// Con la app abierta, la notificación igual se ve arriba (y suena). Si Alma la dice en voz alta, solo queda en la lista:
    /// ni banner ni sonido, así nada se encima a su voz.
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler fin: @escaping (UNNotificationPresentationOptions) -> Void) {
        let u = n.request.content.userInfo
        if let banner = u["banner"] as? Bool {   // armada con los ajustes de su tipo (NotifArmar.swift)
            var o: UNNotificationPresentationOptions = []
            if banner { o.insert(.banner) }
            if (u["sonido"] as? Bool) == true { o.insert(.sound) }
            if (u["lista"] as? Bool) != false { o.insert(.list) }
            fin(o); return
        }
        if (u["seDice"] as? Bool) == true { fin([.list]); return }
        fin([.banner, .sound, .list])
    }
}
