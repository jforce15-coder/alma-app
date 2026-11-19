import Foundation

/// La música vuelve (Hub #822, Juan, 18-nov-2026: «si lo pongo en modo calle o hago algún cambio en el app deja de sonar la
/// música; después de una interacción con Alma nunca se reanuda; y cuando le pido poner música no detecta el dispositivo»).
/// Lógica pura, sin iOS: se prueba sola en Pruebas/MusicaVuelve. La usa VigiaMusica (MusicaVuelveVigia.swift).
///   · Cada segundo se mira si suena la música de otra app (Spotify).
///   · Si para justo después de que Alma tomó o cambió su audio (hasta 4 s), o mientras Alma atiende (llamada, el Modo calle
///     oyendo, pensando o hablando, un aviso), la paró Alma. Si paró sola en otro momento (Juan la pausó), no se toca.
///   · Cuando Alma termina (1,5 s sin atender), se le pide al Hub que Spotify siga donde iba (acción musicaVuelve). Así
///     Spotify tampoco se queda dormido y sigue apareciendo como dispositivo para «pon música».
///   · Una vuelta como mucho cada 20 s; una pausa de más de 15 min ya no se retoma (para entonces ya no se espera).
///   · El Hub no la retoma si Alma la pausó porque Juan se lo pidió, si ya suena o si lo que quedó en pausa no es el teléfono.
struct MusicaVuelve {
    static let cada: TimeInterval = 1
    static let ventanaToma: TimeInterval = 4
    static let esperaLibre: TimeInterval = 1.5
    static let entreVueltas: TimeInterval = 20
    static let vence: TimeInterval = 15 * 60

    enum Accion: Equatable {
        case nada
        case paro(motivo: String)          // la música paró por Alma: se anota y se espera a que Alma termine
        case pedir(motivo: String)         // Alma ya terminó: pedirle al Hub que Spotify siga
    }

    private(set) var sonaba = false
    private(set) var ultimaToma: (cuando: Date, motivo: String)?
    private(set) var parada: (cuando: Date, motivo: String)?
    private var libreDesde: Date?
    private var ultimaVuelta = Date.distantPast

    /// Alma tomó, cambió o soltó su audio (abrió la llamada, encendió el Modo calle, cambió las opciones…).
    mutating func tomo(_ motivo: String, ahora: Date) { ultimaToma = (ahora, motivo) }

    mutating func mirar(suena: Bool, almaOcupada: Bool, ahora: Date) -> Accion {
        let antes = sonaba
        sonaba = suena
        if suena { parada = nil; libreDesde = nil; return .nada }
        if antes {   // acaba de parar: ¿fue Alma?
            libreDesde = almaOcupada ? nil : ahora
            if let t = ultimaToma, ahora.timeIntervalSince(t.cuando) <= MusicaVuelve.ventanaToma {
                parada = (ahora, t.motivo); return .paro(motivo: t.motivo)
            }
            if almaOcupada { parada = (ahora, "mientras Alma atendía"); return .paro(motivo: "mientras Alma atendía") }
            return .nada   // paró sola (Juan la pausó): no se toca
        }
        guard let p = parada else { return .nada }
        if ahora.timeIntervalSince(p.cuando) > MusicaVuelve.vence { parada = nil; return .nada }
        if almaOcupada { libreDesde = nil; return .nada }
        let libre = libreDesde ?? ahora
        libreDesde = libre
        guard ahora.timeIntervalSince(libre) >= MusicaVuelve.esperaLibre, ahora.timeIntervalSince(ultimaVuelta) >= MusicaVuelve.entreVueltas else { return .nada }
        ultimaVuelta = ahora; parada = nil; libreDesde = nil
        return .pedir(motivo: p.motivo)
    }

    /// Lo que va al registro de la voz según lo que contestó el Hub (sin nombres de dispositivos: estos pasos van al Hub).
    static func texto(_ j: [String: Any]?) -> String {
        guard let j else { return "La música no volvió: el Hub no contestó" }
        if (j["hecho"] as? Bool) == true { return "La música vuelve: Spotify sigue donde iba" }
        switch j["motivo"] as? String ?? "" {
        case "ya_suena": return "La música ya volvió sola"
        case "la_pauso_alma": return "La música queda en pausa: Alma la pausó porque se lo pediste"
        case "sin_dispositivo": return "La música no volvió: Spotify ya no aparece (ábrelo y dale play)"
        case "otro_dispositivo": return "La música no volvió: lo que quedó en pausa no es el teléfono"
        case "sin_spotify": return "La música no volvió: Spotify no está conectado al Hub"
        default: return "La música no volvió: " + String(((j["error"] as? String) ?? "Spotify no lo hizo").prefix(80))
        }
    }
}
