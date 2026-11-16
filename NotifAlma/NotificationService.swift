import Foundation
import UserNotifications

/// Extensión de notificaciones (Ticket #28): cada push del Hub pasa por aquí antes de verse, con la app cerrada o dormida.
/// La arma igual que la app arma las locales (NotifPush.contenido) y con el plan de su tipo (NotifPush.plan, con el ajuste
/// que viajó en el push): hilo, sonido, urgente (time-sensitive) o pasiva, y vista previa. Si el tipo tiene Siri, la convierte
/// en mensaje de Alma (NotifComunicacion, con su foto) para que Siri la anuncie con los AirPods.
/// Lo que no trae los datos de Alma (`data.alma`) o no se alcanza a armar a tiempo, se deja tal cual llegó.
final class NotificationService: UNNotificationServiceExtension {
    private var entregar: ((UNNotificationContent) -> Void)?
    private var talCual: UNNotificationContent?
    private let candado = NSLock()   // el plazo de iOS y la donación a Siri pueden terminar a la vez: se entrega una sola

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        entregar = contentHandler; talCual = request.content
        guard let d = NotifPush.datos(request.content.userInfo), let n = request.content.mutableCopy() as? UNMutableNotificationContent else {
            terminar(request.content); return
        }
        let p = NotifPush.plan(d)
        if p.contenido == .completo {
            let c = NotifPush.contenido(texto: request.content.body, titulo: d.titulo, lineas: d.lineas)
            n.title = c.titulo; n.subtitle = c.subtitulo; n.body = c.cuerpo
        } else {
            n.title = "Alma"; n.subtitle = ""; n.body = AjustesNotif.generico
        }
        n.threadIdentifier = p.hilo
        n.sound = p.sonido ? .default : nil
        n.interruptionLevel = p.nivel == .pasiva ? .passive : (p.nivel == .urgente ? .timeSensitive : .active)
        n.categoryIdentifier = "alma.aviso"
        n.userInfo["id"] = d.id; n.userInfo["tipo"] = d.tipo.rawValue; n.userInfo["push"] = true
        // Con la app abierta (raro: el Hub solo manda push con la app dormida), como las locales armadas por tipo.
        n.userInfo["banner"] = p.bannerAbierta; n.userInfo["lista"] = p.listaAbierta; n.userInfo["sonido"] = p.sonido
        guard p.siri else { terminar(n); return }
        NotifComunicacion.armar(n) { [weak self] c in self?.terminar(c ?? n) }
    }

    /// iOS da unos 30 s: si no alcanzó, sale como llegó.
    override func serviceExtensionTimeWillExpire() {
        if let talCual { terminar(talCual) }
    }

    private func terminar(_ c: UNNotificationContent) {
        candado.lock(); let e = entregar; entregar = nil; candado.unlock()
        e?(c)
    }
}
