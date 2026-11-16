import Foundation

/// La música de las otras apps mientras Alma habla (Juan, 16-nov-2026). Lógica pura, sin iOS: se prueba sola en
/// Pruebas/AudioCalle. Las opciones de iOS (AVAudioSession.CategoryOptions) salen de aquí en ModoCalle.swift y VozNativa.swift.
///   · Modo calle esperando «Alma» (y la conferencia escuchando): el audio se mezcla; Spotify sigue a su volumen.
///   · Mientras Alma atiende (oye tu pedido, piensa, te contesta o escucha tu respuesta a un aviso): la música baja (duck) y lo
///     hablado (un podcast) se pausa; nada se pausa del todo. Al volver a esperar, se mezcla otra vez.
///   · La llamada de ElevenLabs que abre el Modo calle (o la conferencia, con el interruptor) usa las mismas opciones: Spotify
///     baja, no se pausa. Las demás llamadas siguen como siempre: no se mezclan (la música se pausa).
///   · Interruptor «Bajar la música cuando Alma hable» (Ajustes): encendido de fábrica en el Modo calle, apagado en
///     conferencia. Apagado, Alma habla encima de la música (se mezcla) y la llamada la pausa, como antes.
///   · Un aviso con la app abierta (sin el Modo calle) baja la música mientras usa el micrófono, como siempre.
///   · Con «Alma con el anillo» no se toca nada: el anillo necesita el audio que no se mezcla («Reproduciendo»).
///   · Volver a mezclar: primero solo se cambian las opciones (sin soltar el audio). Con la app a la vista, además se suelta el
///     audio avisando a las otras apps (notifyOthersOnDeactivation), que es lo que hace que iOS les devuelva el volumen.
///     Con el teléfono bloqueado no se suelta: iOS no deja volver a abrir el micrófono y el Modo calle se quedaría sordo.
///     Límite: si iOS no sube la música solo con el cambio de opciones, se queda baja hasta que abras la app o apagues el
///     Modo calle.
enum OpcionAudio: String, CaseIterable {
    case mezclar               // mixWithOthers
    case bajarOtras            // duckOthers (también mezcla)
    case pausarHablado         // interruptSpokenAudioAndMixWithOthers: pausa un podcast, mezcla la música
    case parlante              // defaultToSpeaker
    case audifonos             // allowBluetoothA2DP: la salida en alta calidad
    case manosLibres           // allowBluetooth (HFP): el micrófono de los audífonos, solo en la llamada
}

enum AudioCalle {
    /// UserDefaults del interruptor «Bajar la música cuando Alma hable».
    static let claveCalle = "calle_musica_baja"
    static let claveConferencia = "conf_musica_baja"
    /// De fábrica: encendido en el Modo calle, apagado en conferencia.
    static func bajaEnCalle(_ guardado: Bool?) -> Bool { guardado ?? true }
    static func bajaEnConferencia(_ guardado: Bool?) -> Bool { guardado ?? false }

    /// Dónde está Alma: el Modo calle encendido, un aviso con la app abierta (sin Modo calle), un aviso o la llamada en
    /// conferencia, o nada de eso.
    enum Donde: String { case calle, aviso, conferencia, nada }
    /// El momento: esperar (escucha de fondo), atender (oye el pedido, piensa, habla o escucha la respuesta) o la llamada.
    enum Momento: String { case espera, atiende, llamada }

    /// La fase del Modo calle (ModoCalle.Fase) → el momento.
    static func momento(fase: String) -> Momento {
        switch fase {
        case "oyendo", "pensando", "hablando": return .atiende
        case "llamada": return .llamada
        default: return .espera      // quieta, esperando, verificando, pausa
        }
    }

    /// ¿Baja la música en este lugar? (el interruptor de cada uno; el aviso con la app abierta, siempre).
    static func baja(_ d: Donde, calle: Bool, conferencia: Bool) -> Bool {
        switch d {
        case .calle: return calle
        case .aviso: return true
        case .conferencia: return conferencia
        case .nada: return false
        }
    }

    static let escucha: Set<OpcionAudio> = [.mezclar, .parlante, .audifonos]
    static let bajando: Set<OpcionAudio> = [.bajarOtras, .pausarHablado, .parlante, .audifonos]
    static let llamadaSola: Set<OpcionAudio> = [.parlante, .manosLibres, .audifonos]
    static let llamadaBajando: Set<OpcionAudio> = [.bajarOtras, .pausarHablado, .parlante, .manosLibres, .audifonos]

    /// Las opciones de cada momento. nil: no se toca el audio (con «Alma con el anillo» lo maneja la voz).
    static func opciones(_ m: Momento, donde d: Donde, baja: Bool, anillo: Bool) -> Set<OpcionAudio>? {
        if anillo { return nil }
        switch m {
        case .espera: return d == .aviso ? bajando : escucha   // el aviso con la app abierta baja mientras tenga el micrófono
        case .atiende: return baja ? bajando : escucha
        case .llamada: return baja ? llamadaBajando : llamadaSola
        }
    }

    /// Cómo se pasa de unas opciones a otras.
    enum Cambio: Equatable { case nada, cambiar, soltarYCambiar }
    /// ¿Hace falta soltar el audio para que las otras apps vuelvan a su volumen? Solo al dejar de bajarlas (o al dejar una
    /// llamada que no se mezcla) hacia la escucha que se mezcla, y solo con la app a la vista (bloqueado no se suelta).
    static func cambio(de antes: Set<OpcionAudio>?, a ahora: Set<OpcionAudio>, appActiva: Bool) -> Cambio {
        guard let antes else { return .cambiar }
        if antes == ahora { return .nada }
        let tapaba = antes.contains(.bajarOtras) || !antes.contains(.mezclar)
        let destapa = ahora.contains(.mezclar) && !ahora.contains(.bajarOtras)
        return tapaba && destapa && appActiva ? .soltarYCambiar : .cambiar
    }
}
