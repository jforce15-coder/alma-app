import Foundation

/// Audio de la llamada (Juan, 17-nov-2026: «En Modo Companion, por defecto preferir el micrófono del teléfono, pero permitir
/// al usuario seleccionar la fuente de audio (salida) y micrófono (entrada) entre las opciones disponibles: iPad, iPhone,
/// bocinas externas, lentes o audífonos»). Lógica pura, sin iOS: se prueba sola en Pruebas/AudioLlamada.
///   · Micrófono: «Automático» de fábrica. En automático, con el Modo compañero activo (el Hub dijo que el otro dispositivo
///     está mirando esta llamada, o lo dijo hace poco), se usa el micrófono de este teléfono aunque haya audífonos o lentes
///     conectados (los audífonos siguen sonando en alta calidad). Sin compañero, iOS decide como siempre.
///   · Juan puede fijar uno: «Este iPhone» (o «Este iPad») o uno de la lista (audífonos, lentes, el del carro, uno con cable).
///     Se recuerda por tipo y nombre; si ese no está conectado, vale lo automático (nunca queda sin micrófono).
///   · Salida: «Automático» (lo que elige iOS o el botón de iOS: audífonos, lentes, bocinas Bluetooth o AirPlay) o «Bocina de
///     este iPhone» (fija la bocina del teléfono aunque haya otra cosa conectada).
///   · El micrófono y el sonido de una llamada son del dispositivo donde está la llamada (glosario: Modo compañero). Para
///     hablar por el iPad, la llamada se hace desde el iPad: ahí su micrófono y su bocina salen en la lista.
/// Los tipos son los rawValue de AVAudioSession.Port (MicrophoneBuiltIn, BluetoothHFP, Speaker…).
enum AudioLlamadaReglas {
    struct Puerto: Equatable { let tipo: String; let nombre: String }
    enum Clase: String { case dispositivo, audifonos, lentes, bocina, carro, cable, otro }

    static let claveEntrada = "llamada_entrada", claveSalida = "llamada_salida", claveCompanero = "llamada_companero_visto"
    static let automatico = "auto", esteDispositivo = "telefono"
    /// Si el Hub dijo «mirando» en una llamada de hace menos de esto, la siguiente ya empieza con el micrófono del teléfono
    /// (sin esperar el primer aviso del Hub, que llega un segundo después de conectar).
    static let companeroReciente: TimeInterval = 600

    static let microfonoPropio = "MicrophoneBuiltIn"
    static let bocinaPropia = "Speaker", auricularPropio = "Receiver"

    /// Qué es cada puerto, para el ícono y la etiqueta.
    static func clase(_ p: Puerto, lentes: Bool) -> Clase {
        if lentes { return .lentes }
        switch p.tipo {
        case microfonoPropio, bocinaPropia, auricularPropio: return .dispositivo
        case "CarAudio": return .carro
        case "MicrophoneWired", "Headphones", "USBAudio", "LineIn", "LineOut": return .cable
        case "AirPlay", "HDMI": return .bocina
        case "BluetoothHFP", "BluetoothA2DPOutput", "BluetoothLEOutput":
            let n = p.nombre.lowercased()
            let deOido = ["airpods", "buds", "beats", "headphone", "headset", "earphone", "audífono", "audifono", "auricular", "pods", "wh-", "wf-"]
            if deOido.contains(where: { n.contains($0) }) { return .audifonos }
            // Un micrófono Bluetooth es de manos libres (audífonos); una salida sin nombre conocido, una bocina.
            return p.tipo == "BluetoothHFP" ? .audifonos : .bocina
        default: return .otro
        }
    }

    /// El Modo compañero cuenta como activo si el Hub lo dijo en esta llamada o hace poco.
    static func companeroActivo(ahora mirando: Bool?, ultimoVisto: Date?, hoy: Date) -> Bool {
        if let m = mirando { return m }
        guard let u = ultimoVisto else { return false }
        return hoy.timeIntervalSince(u) < companeroReciente
    }

    /// Lo que se guarda al elegir un micrófono de la lista.
    static func guardar(_ p: Puerto) -> String { p.tipo == microfonoPropio ? esteDispositivo : p.tipo + "|" + p.nombre }

    /// El micrófono que se pide a iOS. nil: no se pide ninguno (iOS decide, como antes).
    static func entrada(preferencia: String?, companero: Bool, disponibles: [Puerto]) -> Puerto? {
        let propio = disponibles.first { $0.tipo == microfonoPropio }
        let pref = preferencia ?? automatico
        if pref == esteDispositivo { return propio }
        if pref != automatico {
            let partes = pref.split(separator: "|", maxSplits: 1).map(String.init)
            if partes.count == 2 {
                if let p = disponibles.first(where: { $0.tipo == partes[0] && $0.nombre == partes[1] }) { return p }
                if let p = disponibles.first(where: { $0.nombre == partes[1] }) { return p }   // el mismo aparato, otro perfil
            }
            // El elegido no está conectado: lo automático.
        }
        return companero ? propio : nil
    }

    /// ¿Se cambia el micrófono ahora? Juan, 19-nov-2026: en conferencia con audífonos Bluetooth de manos libres (BluetoothHFP),
    /// el Modo compañero pasó el micrófono al del iPhone a media llamada; iOS movió todo el audio y 11 s después se cayó la
    /// conexión. Con la salida en BluetoothHFP y la llamada ya en curso, lo automático no toca el micrófono (sigue el de los
    /// audífonos). Al abrir el micrófono o si Juan elige uno, sí se cambia.
    static let manosLibres = "BluetoothHFP"
    static func cambiaMicrofono(preferencia: String?, salida: String, aMedia: Bool) -> Bool {
        !(aMedia && (preferencia ?? automatico) == automatico && salida == manosLibres)
    }

    /// ¿Esta opción de la lista es la elegida? (para la palomita).
    static func elegida(_ p: Puerto?, preferencia: String?) -> Bool {
        let pref = preferencia ?? automatico
        guard let p else { return pref == automatico }
        return pref == guardar(p)
    }

    /// La línea de «Automático» en la lista: qué hace ahora.
    static func explicaAutomatico(companero: Bool, dispositivo: String) -> String {
        companero ? "Modo compañero: el micrófono de este \(dispositivo)" : "iOS elige (los audífonos, si están conectados)"
    }

    /// ¿La salida tiene que ir a la bocina del teléfono?
    static func bocinaFija(_ preferencia: String?) -> Bool { preferencia == esteDispositivo }
}
