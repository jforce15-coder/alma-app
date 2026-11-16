import Foundation
import Intents
import UserNotifications

/// Notificación de comunicación: Siri la anuncia con su voz («Alma dice…»). La usan la app (NotifArmar.swift, notificaciones
/// locales) y la extensión de notificaciones (NotifAlma, las push del Hub, Ticket #28): el remitente es Alma, con su foto
/// (la esfera de Alma, alma-foto.png dentro de cada una). Requiere la capacidad Communication Notifications (project.yml) y
/// NSUserActivityTypes con INSendMessageIntent. Sin la capacidad o si iOS no la acepta, devuelve nil y queda la normal.
enum NotifComunicacion {
    static func alma() -> INPerson {
        let foto = Bundle.main.url(forResource: "alma-foto", withExtension: "png").flatMap { try? Data(contentsOf: $0) }.map { INImage(imageData: $0) }
        return INPerson(personHandle: INPersonHandle(value: "alma", type: .unknown), nameComponents: nil, displayName: "Alma",
                        image: foto, contactIdentifier: nil, customIdentifier: "alma")
    }

    private static func mensaje(_ n: UNMutableNotificationContent) -> (INSendMessageIntent, INInteraction) {
        let texto = [n.subtitle, n.body].filter { !$0.isEmpty }.joined(separator: "\n")
        let intent = INSendMessageIntent(recipients: nil, outgoingMessageType: .outgoingMessageText, content: texto, speakableGroupName: nil,
                                         conversationIdentifier: n.threadIdentifier, serviceName: nil, sender: alma(), attachments: nil)
        let i = INInteraction(intent: intent, response: nil)
        i.direction = .incoming
        return (intent, i)
    }

    /// En la app (NotifArmar.swift): como siempre, dona y actualiza enseguida. nil = se queda la normal.
    static func armarYa(_ n: UNMutableNotificationContent) -> UNNotificationContent? {
        let (intent, i) = mensaje(n)
        i.donate(completion: nil)
        return try? n.updating(from: intent)
    }

    /// En la extensión: dona, espera a que iOS la registre y actualiza. `listo` recibe el contenido nuevo o nil.
    static func armar(_ n: UNMutableNotificationContent, listo: @escaping (UNNotificationContent?) -> Void) {
        let (intent, i) = mensaje(n)
        i.donate { _ in listo(try? n.updating(from: intent)) }
    }
}
