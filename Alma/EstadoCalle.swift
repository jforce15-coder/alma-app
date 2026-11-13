import Foundation

/// La lógica pura del encendido del Modo calle y de las notificaciones habladas fuera de él (Juan, 6-nov-2026, TestFlight
/// 148: «la app arranca con el Modo calle encendido y no se puede apagar»). Sin iOS: se prueba sola en Pruebas/EstadoCalle.
///   · Al abrir la app el Modo calle queda como Juan lo dejó: apagado de fábrica; encendido solo si él lo encendió (Ajustes,
///     Siri o un atajo) y no lo apagó después. La prueba («Probar el Modo calle») nunca cuenta como dejarlo encendido.
///   · Una notificación hablada con la app abierta o en conferencia no es el Modo calle: la página no pinta el botón del
///     caminante ni la línea «Modo calle · …» por ella (antes se veía como si el Modo calle se hubiera encendido solo).
///   · Apagar el Modo calle apaga de verdad: también lo que el micrófono hacía por un aviso o por el botón, y la fila de
///     avisos de esta vuelta (quedan como notificación y en Pendientes).
///   · La voz de un aviso: primero la que llegó con el aviso (vozAvisos ya la trae), luego la que se pide aparte, y la del
///     iPhone solo si no hay red o el Hub no mandó audio; el porqué queda en el diagnóstico. Si el Hub tarda pero hay
///     internet, se pide otra vez antes de la voz del iPhone (#509).
enum EstadoCalle {
    /// UserDefaults: true si Juan dejó el Modo calle encendido.
    static let clave = "calle_encendido"

    /// Quién lo enciende o lo apaga.
    enum Origen { case ajustes, siri, enlace, conferencia, prueba, falla }

    /// ¿Se enciende al abrir la app? Solo si quedó guardado encendido.
    static func alAbrir(guardado: Bool?) -> Bool { guardado == true }

    /// Lo que se guarda (nil: no se toca lo guardado). La prueba no cuenta; si no pudo encender, queda apagado (así no
    /// insiste con el mismo error cada vez que se abre la app).
    static func guardar(_ origen: Origen, on: Bool) -> Bool? {
        switch origen {
        case .prueba: return nil
        case .falla: return false
        default: return on
        }
    }

    /// La fase que ve la página. Sin el Modo calle, un aviso hablado (app abierta o conferencia) se ve «quieta».
    static func faseParaPagina(_ fase: String, encendido: Bool, aviso: Bool) -> String {
        (!encendido && aviso) ? "quieta" : fase
    }

    /// Qué detiene «apagar».
    struct Apagar: Equatable {
        var modo = false        // el detector, el micrófono del Modo calle y su audio de fondo
        var temporal = false    // el micrófono abierto por un aviso o por el botón del caminante
        var aviso = false       // la voz del aviso que se está diciendo y la fila de esta vuelta
    }
    static func apagar(encendido: Bool, temporal: Bool, aviso: Bool) -> Apagar {
        Apagar(modo: encendido, temporal: temporal, aviso: aviso || encendido)
    }

    /// Cómo suena un aviso.
    enum VozAviso: Equatable {
        case conElAviso          // el audio de ElevenLabs llegó con el aviso: suena ya
        case pedirAviso          // se pide al Hub la frase y su audio (avisoHablar)
        case soloFrase           // el Hub ya dio la frase pero no el audio: se pide la voz aparte (calleVoz) o habla el iPhone
    }
    static func vozAviso(audio: Bool, hablar: String, vozMotivo: String?, hubSinAviso: Bool) -> VozAviso {
        if audio { return .conElAviso }
        if hubSinAviso { return .soloFrase }
        if !hablar.isEmpty && vozMotivo != nil { return .soloFrase }   // el Hub ya intentó la voz con el aviso
        return .pedirAviso
    }

    /// Cuánto se espera al Hub por la voz de un aviso (#509, 13-nov-2026: «a veces sale la voz del iPhone»). Antes 12 s
    /// (avisoHablar) y 8 s (calleVoz): el Hub arma la frase, lee Pendientes y llama a ElevenLabs, y se pasaba. Un aviso no
    /// tiene prisa: nadie espera una respuesta.
    static let esperaAviso: TimeInterval = 30
    static let esperaVozAviso: TimeInterval = 20

    /// ¿Se vuelve a pedir la voz al Hub? Solo si hay internet (tardó, pero el Hub siguió y dejó el audio en su caché) y
    /// quedan intentos. Sin internet, la voz del iPhone de una vez.
    static func reintentarVoz(sinRed: Bool, quedan: Int) -> Bool { !sinRed && quedan > 0 }

    /// Los errores de URLSession que son «no hay internet» (no «tardó»): sin red, sin datos, avión, el host no se encuentra.
    static func esSinRed(_ codigo: Int) -> Bool {
        [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff,
         NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed, NSURLErrorCannotConnectToHost, NSURLErrorCallIsActive].contains(codigo)
    }
}
