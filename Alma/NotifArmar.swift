import Intents
import UIKit
import UserNotifications

/// Arma cada notificación con los ajustes de su tipo (Hub #551). Lo que se decide está en AjustesNotif.swift (lógica pura,
/// con pruebas); aquí solo se aplica con las piezas de iOS:
///   · nivel → interruptionLevel (pasiva, activa o time-sensitive), sonido, hilo (threadIdentifier);
///   · vista previa «nunca» o tapada → «Alma te dejó un mensaje»; tapada se destapa al desbloquear (misma notificación);
///   · sin «Bloqueada» con el teléfono bloqueado → espera en una fila y sale al desbloquear;
///   · sin «Centro» → se quita del centro un momento después de verse;
///   · Siri → notificación de comunicación: se dona un INSendMessageIntent de Alma y el contenido se actualiza con él
///     (content.updating(from:)). Requiere la capacidad Communication Notifications (Alma.entitlements, project.yml) y
///     NSUserActivityTypes con INSendMessageIntent. Sin la capacidad, iOS la muestra como una notificación normal.
extension Notificaciones {
    /// Dónde está la app ahora (en el hilo principal).
    func momentoAhora(seDice: Bool) -> MomentoNotif {
        MomentoNotif(appActiva: UIApplication.shared.applicationState == .active, conferencia: Conferencia.shared.activa,
                     calle: ModoCalle.shared.encendido, bloqueado: !UIApplication.shared.isProtectedDataAvailable, seDice: seDice)
    }

    func publicar(_ n: UNMutableNotificationContent, id: String, plan p: PlanNotif, tipo: TipoNotif) {
        n.threadIdentifier = p.hilo
        n.sound = p.sonido ? .default : nil
        n.interruptionLevel = p.nivel == .pasiva ? .passive : (p.nivel == .urgente ? .timeSensitive : .active)
        n.userInfo["tipo"] = tipo.rawValue
        n.userInfo["banner"] = p.bannerAbierta; n.userInfo["lista"] = p.listaAbierta; n.userInfo["sonido"] = p.sonido
        // La versión completa, callada: la que reemplaza a la tapada cuando desbloqueas.
        let completa = (n.mutableCopy() as? UNMutableNotificationContent) ?? n
        completa.sound = nil; completa.interruptionLevel = .passive
        if p.contenido != .completo { n.title = "Alma"; n.subtitle = ""; n.body = AjustesNotif.generico }
        let salida: UNNotificationContent = p.siri ? (comunicacion(n) ?? n) : n
        if p.esperarDesbloqueo { AlDesbloquear.shared.poner(id: id, contenido: salida, quitar: p.quitarDelCentro); return }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: salida, trigger: nil)) { _ in
            if p.contenido == .tapado { AlDesbloquear.shared.poner(id: id, contenido: completa, quitar: p.quitarDelCentro, soloSiSigue: true) }
            if p.quitarDelCentro { Notificaciones.quitarDespues(id) }
        }
    }

    /// Notificación de comunicación: Siri la anuncia con su voz («Alma dice…»).
    private func comunicacion(_ n: UNMutableNotificationContent) -> UNNotificationContent? {
        let alma = INPerson(personHandle: INPersonHandle(value: "alma", type: .unknown), nameComponents: nil, displayName: "Alma",
                            image: nil, contactIdentifier: nil, customIdentifier: "alma")
        let texto = [n.subtitle, n.body].filter { !$0.isEmpty }.joined(separator: "\n")
        let intent = INSendMessageIntent(recipients: nil, outgoingMessageType: .outgoingMessageText, content: texto, speakableGroupName: nil,
                                         conversationIdentifier: n.threadIdentifier, serviceName: nil, sender: alma, attachments: nil)
        let i = INInteraction(intent: intent, response: nil)
        i.direction = .incoming
        i.donate(completion: nil)
        return try? n.updating(from: intent)
    }

    static func quitarDespues(_ id: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + AjustesNotif.quitarEn) {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        }
    }
}

/// Lo que espera al desbloqueo: lo que no va en la pantalla bloqueada y lo tapado que se destapa.
final class AlDesbloquear {
    static let shared = AlDesbloquear()
    /// soloSiSigue: destapar solo si la tapada sigue en el centro (si ya la abriste o la borraste, no vuelve).
    private var fila: [(id: String, contenido: UNNotificationContent, quitar: Bool, soloSiSigue: Bool)] = []
    private var observando = false

    func poner(id: String, contenido: UNNotificationContent, quitar: Bool, soloSiSigue: Bool = false) {
        DispatchQueue.main.async {
            self.fila.removeAll { $0.id == id }
            self.fila.append((id: id, contenido: contenido, quitar: quitar, soloSiSigue: soloSiSigue))
            self.observar()
            if UIApplication.shared.isProtectedDataAvailable { self.soltar() }   // ya lo desbloqueaste
        }
    }

    private func observar() {
        guard !observando else { return }
        observando = true
        for nombre in [UIApplication.protectedDataDidBecomeAvailableNotification, UIApplication.didBecomeActiveNotification] {
            NotificationCenter.default.addObserver(forName: nombre, object: nil, queue: .main) { [weak self] _ in self?.soltar() }
        }
    }

    private func soltar() {
        guard UIApplication.shared.isProtectedDataAvailable, !fila.isEmpty else { return }
        let l = fila; fila = []
        UNUserNotificationCenter.current().getDeliveredNotifications { entregadas in
            let siguen = Set(entregadas.map { $0.request.identifier })
            for x in l where !x.soloSiSigue || siguen.contains(x.id) {
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: x.id, content: x.contenido, trigger: nil)) { _ in
                    if x.quitar { Notificaciones.quitarDespues(x.id) }
                }
            }
        }
    }
}
