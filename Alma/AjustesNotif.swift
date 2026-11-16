import Foundation

/// Ajustes de notificaciones por tipo (Hub #551, Juan 16-nov-2026: «como WhatsApp en iOS», diseño B). iOS solo deja configurar
/// por app; por tipo se logra aquí, al armar cada notificación local con los ajustes que el Hub manda en vozAvisos
/// (`notif_ajustes`, y `notif_tipo` en cada aviso). Lógica pura, sin iOS: se prueba sola en Pruebas/AjustesNotif.
///   · Tipos: urgentes, huéspedes, equipo, socios y pendientes de Alma (el Hub decide cuál: notifTipo_, notifajustes.js).
///   · Dónde se ve (los tres teléfonos): los tres apagados = no se muestra. Solo centro = pasiva (sin banner, sin sonido, no
///     enciende la pantalla). Sin «Bloqueada» y con el teléfono bloqueado = espera a que lo desbloquees. Sin «Banner» y
///     desbloqueado = pasiva. Sin «Centro» = se quita del centro un momento después de verse.
///   · Sonido o no; urgente (time-sensitive) solo lo de Urgentes cuando Siri lo puede anunciar.
///   · Número en el ícono: el Hub ya lo cuenta por tipo (`numero` en vozAvisos); la notificación no lo toca.
///   · Agrupar: automático (como antes, todo junto), por tipo (un hilo por tipo) o no (cada una sola).
///   · Vista previa: siempre · solo desbloqueado (con el teléfono bloqueado llega tapada y se destapa al desbloquear) ·
///     nunca («Alma te dejó un mensaje»).
///   · Siri (notificación de comunicación, con su voz): solo si el tipo lo tiene encendido y la app NO está activa en primer
///     plano, ni en conferencia, ni en Modo calle, ni Alma la va a decir. Si Alma está activa, habla Alma y la notificación
///     se arma sin Siri: nunca se oye dos veces.
enum TipoNotif: String, CaseIterable {
    case urgentes, huespedes, equipo, socios, pendientes
}

struct AjusteNotif: Equatable {
    enum Vista: String { case siempre, desbloqueado, nunca }
    enum Agrupar: String { case auto, tipo, no }
    var bloqueada = true, centro = true, banner = true
    var sonido = true, numero = true, siri = false
    var vista: Vista = .siempre
    var agrupar: Agrupar = .auto

    /// De fábrica, como el Hub (notifFabrica_): todo llega como antes; Siri, de entrada, solo lo urgente.
    static func deFabrica(_ t: TipoNotif) -> AjusteNotif { var a = AjusteNotif(); a.siri = t == .urgentes; return a }

    /// Lo que manda el Hub para un tipo; lo que falta o no sirve, de fábrica.
    static func desde(_ d: [String: Any]?, tipo: TipoNotif) -> AjusteNotif {
        var a = deFabrica(tipo)
        guard let d else { return a }
        func b(_ k: String, _ v: Bool) -> Bool { (d[k] as? Bool) ?? v }
        a.bloqueada = b("bloqueada", a.bloqueada); a.centro = b("centro", a.centro); a.banner = b("banner", a.banner)
        a.sonido = b("sonido", a.sonido); a.numero = b("numero", a.numero); a.siri = b("siri", a.siri)
        if let v = Vista(rawValue: d["vista"] as? String ?? "") { a.vista = v }
        if let g = Agrupar(rawValue: d["agrupar"] as? String ?? "") { a.agrupar = g }
        return a
    }

    /// ¿Llega? Con los tres lugares apagados, no.
    var llega: Bool { bloqueada || centro || banner }
}

/// Dónde está la app cuando llega la notificación.
struct MomentoNotif: Equatable {
    var appActiva = false      // abierta, en primer plano
    var conferencia = false
    var calle = false          // Modo calle encendido
    var bloqueado = false      // el teléfono bloqueado (sin datos protegidos)
    var seDice = false         // Alma la va a decir en voz alta (EstadoCalle.notificacionCallada)
}

/// Cómo se arma una notificación.
struct PlanNotif: Equatable {
    enum Nivel: String { case pasiva, activa, urgente }
    enum Contenido: String { case completo, generico, tapado }   // tapado: genérica ahora, completa al desbloquear
    var mostrar = true
    var esperarDesbloqueo = false
    var nivel: Nivel = .activa
    var sonido = true
    var numero = true
    var hilo = AjustesNotif.hiloDeSiempre
    var contenido: Contenido = .completo
    var siri = false
    var quitarDelCentro = false
    /// Con la app abierta (willPresent): banner, sonido y lista.
    var bannerAbierta = true
    var listaAbierta = true
}

enum AjustesNotif {
    static let generico = "Alma te dejó un mensaje"
    static let hiloDeSiempre = "alma.retomar"
    /// UserDefaults: los últimos ajustes que mandó el Hub (JSON), para usarlos aunque el Hub no conteste.
    static let clave = "notif_ajustes"
    /// Sin «Centro»: cuánto se deja la notificación antes de quitarla del centro.
    static let quitarEn: TimeInterval = 12

    static func tipo(_ s: String?) -> TipoNotif? { TipoNotif(rawValue: (s ?? "").lowercased()) }

    /// Los 5 tipos con lo que mandó el Hub (de fábrica lo que falte).
    static func todos(_ hub: [String: Any]?) -> [TipoNotif: AjusteNotif] {
        var r: [TipoNotif: AjusteNotif] = [:]
        for t in TipoNotif.allCases { r[t] = AjusteNotif.desde(hub?[t.rawValue] as? [String: Any], tipo: t) }
        return r
    }

    /// ¿La anuncia Siri? Solo con el tipo encendido y la app fuera de primer plano, de conferencia y del Modo calle, y si Alma
    /// no la va a decir. Así Siri y Alma no se pisan.
    static func siri(_ a: AjusteNotif, _ m: MomentoNotif) -> Bool {
        a.siri && !m.appActiva && !m.conferencia && !m.calle && !m.seDice
    }

    static func plan(tipo: TipoNotif, ajuste a: AjusteNotif, momento m: MomentoNotif, id: String) -> PlanNotif {
        var p = PlanNotif()
        guard a.llega else { p.mostrar = false; p.sonido = false; p.numero = false; p.bannerAbierta = false; p.listaAbierta = false; return p }
        p.siri = siri(a, m)
        p.numero = a.numero
        switch a.agrupar {
        case .auto: p.hilo = hiloDeSiempre
        case .tipo: p.hilo = "alma." + tipo.rawValue
        case .no: p.hilo = "alma.sola." + id
        }
        if m.seDice {
            p.nivel = .pasiva                                       // la dice Alma: callada, sin Siri
        } else if !a.banner && !a.bloqueada {
            p.nivel = .pasiva                                       // solo centro
        } else if m.bloqueado && !a.bloqueada && !p.siri {
            p.esperarDesbloqueo = true                              // no en la pantalla bloqueada: espera al desbloqueo
            p.nivel = a.banner ? .activa : .pasiva
        } else if !m.bloqueado && !a.banner {
            p.nivel = .pasiva                                       // desbloqueado y sin banner: directo al centro
        } else {
            p.nivel = tipo == .urgentes && p.siri ? .urgente : .activa
        }
        p.sonido = a.sonido && p.nivel != .pasiva
        switch a.vista {
        case .siempre: p.contenido = .completo
        case .nunca: p.contenido = .generico
        case .desbloqueado: p.contenido = m.bloqueado && !p.esperarDesbloqueo ? .tapado : .completo
        }
        p.quitarDelCentro = !a.centro
        p.bannerAbierta = a.banner && !m.seDice
        p.listaAbierta = a.centro || m.seDice
        return p
    }

    /// «Probar con Siri» (Ajustes → Notificaciones, Juan 16-nov-2026): una notificación local a los 15 s, armada como mensaje
    /// de Alma (comunicación), con Siri aunque el tipo no lo tenga encendido y sin depender de dónde esté la app: así Juan
    /// bloquea el teléfono, se pone los AirPods y oye si los anuncios funcionan. Desde el Hub web (acción notifPrueba) llega
    /// con el próximo vozAvisos y sale en 1 s.
    static let textoPrueba = "Prueba: si Siri te lee esto, los anuncios funcionan."
    static let pruebaEn: TimeInterval = 15
    static let pruebaDesdeHub: TimeInterval = 1
    static let idPrueba = "alma.prueba.siri"
    static func planPrueba() -> PlanNotif {
        var p = PlanNotif()
        p.siri = true; p.nivel = .urgente; p.sonido = true; p.contenido = .completo
        p.hilo = "alma.prueba"; p.esperarDesbloqueo = false; p.quitarDelCentro = false
        return p
    }

    /// Lo que se guarda para la próxima vez (JSON de lo que mandó el Hub; nil si no vino nada).
    static func paraGuardar(_ hub: Any?) -> Data? {
        guard let d = hub as? [String: Any], !d.isEmpty, JSONSerialization.isValidJSONObject(d) else { return nil }
        return try? JSONSerialization.data(withJSONObject: d)
    }
    static func guardados(_ data: Data?) -> [TipoNotif: AjusteNotif] {
        guard let data, let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return todos(nil) }
        return todos(d)
    }
    static func guardar(_ hub: Any?) { if let d = paraGuardar(hub) { UserDefaults.standard.set(d, forKey: clave) } }
    static func leer() -> [TipoNotif: AjusteNotif] { guardados(UserDefaults.standard.data(forKey: clave)) }
}
