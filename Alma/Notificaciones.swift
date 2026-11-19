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
    /// Lo completo está en la tarjeta de Pendientes. Con la app dormida el aviso llega por push (Ticket #28, NotifAlma).
    /// `seDice`: Alma lo va a decir en voz alta (Modo calle, conferencia o la app abierta). Entonces la notificación va callada
    /// (EstadoCalle.notificacionCallada): sin sonido y pasiva, para que Siri no la lea con la voz del iPhone encima de Alma.
    /// `tipo` (Hub #551, `notif_tipo` del aviso): se arma con los ajustes de su tipo (AjustesNotif.swift, NotifArmar.swift).
    /// Sin tipo (los avisos propios de la app, como la pausa del Modo calle), como antes.
    /// `siNoEsta` (avisos del Hub, Ticket #28): si una con el mismo id ya está en el centro (la trajo el push), no se arma otra.
    /// `orbita` (Hub #583 T1.3): el id del anillo o del tema del que habla; al tocarla se abre el chat con ese id.
    func mostrar(id: String, texto: String, titulo: String = "", lineas: [String] = [], seDice: Bool = false, tipo: String? = nil, siNoEsta: Bool = false, orbita: String? = nil) {
        guard !texto.isEmpty else { return }
        guard !Companero.shared.callaAvisos else { return }   // iPad con el Modo compañero (Juan, 19-nov-2026): llegan al teléfono
        let clase = AjustesNotif.tipo(tipo)
        let plan = clase.map { AjustesNotif.plan(tipo: $0, ajuste: AjustesNotif.leer()[$0] ?? .deFabrica($0), momento: momentoAhora(seDice: seDice), id: id) }
        if plan?.mostrar == false { return }   // los tres lugares apagados: este tipo no llega
        let armar: () -> Void = {
            let n = UNMutableNotificationContent()
            // Notificación expandible: en el banner se ve el resumen (subtítulo) y al mantenerla presionada se abre el texto completo.
            // Lo mismo que arma la extensión con las push (NotifPush.contenido).
            let c = NotifPush.contenido(texto: texto, titulo: titulo, lineas: lineas)
            n.title = c.titulo; n.subtitle = c.subtitulo; n.body = c.cuerpo
            n.sound = .default; n.threadIdentifier = "alma.retomar"
            if EstadoCalle.notificacionCallada(seDice: seDice) { n.sound = nil; n.interruptionLevel = .passive }
            n.categoryIdentifier = "alma.aviso"; n.userInfo = ["id": id, "seDice": seDice]
            if let o = NotifPush.idOrbita(orbita) { n.userInfo["orbita"] = o; n.userInfo["titulo"] = titulo }
            if let clase, let plan { self.publicar(n, id: id, plan: plan, tipo: clase); return }
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: n, trigger: nil))
        }
        conPermiso {
            guard siNoEsta else { armar(); return }
            UNUserNotificationCenter.current().getDeliveredNotifications { l in
                let enCentro = Set(l.map { $0.request.identifier })
                guard NotifPush.mostrarLocal(["id": id], enCentro: enCentro) else { return }
                DispatchQueue.main.async { armar() }
            }
        }
    }

    /// Tocar la notificación (Hub #583 T1.3): si habla de un anillo o un tema, queda pedida la apertura del chat con su id
    /// (ContentView la toma: al inicio y SANav.chat con orbita, lo mismo que tocar el anillo). Push o local, igual.
    /// Con la app cerrada iOS la entrega al abrir: por eso queda guardada en `porAbrir` hasta que la pantalla la tome.
    static var porAbrir: (orbita: String, texto: String)?
    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse, withCompletionHandler fin: @escaping () -> Void) {
        let u = r.notification.request.content.userInfo
        if r.actionIdentifier != UNNotificationDismissActionIdentifier, let o = NotifPush.orbita(u) {
            let titulo = NotifPush.datos(u)?.titulo ?? (u["titulo"] as? String ?? "")
            let texto = NotifPush.pregunta(titulo: titulo)
            DispatchQueue.main.async {
                Notificaciones.porAbrir = (o, texto)
                NotificationCenter.default.post(name: .abrirChatOrbita, object: nil)
            }
        }
        fin()
    }

    /// El número del ícono: temas por retomar.
    func globo(_ n: Int) {
        conPermiso(pedir: n > 0) { UNUserNotificationCenter.current().setBadgeCount(max(0, n)) }
    }

    /// Con la app abierta, la notificación igual se ve arriba (y suena). Si Alma la dice en voz alta, solo queda en la lista:
    /// ni banner ni sonido, así nada se encima a su voz.
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler fin: @escaping (UNNotificationPresentationOptions) -> Void) {
        if Companero.shared.callaAvisos { fin([]); return }   // iPad con el Modo compañero: ni banner ni sonido (Juan, 19-nov-2026)
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

extension Notification.Name {
    /// Tocaron una notificación de un anillo o un tema (Hub #583 T1.3): ContentView abre el chat con ese id.
    static let abrirChatOrbita = Notification.Name("alma.notif.abrirChat")
}
