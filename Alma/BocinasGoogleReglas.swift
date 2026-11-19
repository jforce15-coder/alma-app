import Foundation

/// Bocinas de Google Home en la llamada (Juan, 19-nov-2026: «Permitir elegir la salida de audio hacia bocinas o grupos de
/// bocinas de Google Home Mini cuando el usuario esté en casa, en lugar de solo los audífonos o el móvil»). Lógica pura,
/// sin red ni iOS: se prueba sola en Pruebas/BocinasGoogle. Lo que habla con las bocinas: BocinasGoogle.swift.
///   · «En casa» = el teléfono ve las bocinas en su Wi-Fi (se anuncian como _googlecast._tcp). Fuera de casa no aparecen y
///     la llamada sale por el teléfono como siempre, aunque la bocina siga elegida.
///   · Se elige una bocina o un grupo de bocinas (los grupos que armaste en la app Google Home se anuncian igual).
///   · La voz de Alma va por el Wi-Fi a la bocina (Google Cast) como un audio WAV en vivo que sirve el teléfono; mientras
///     suena allá, en el teléfono no suena (sería doble). El micrófono sigue en el teléfono.
///   · La bocina guarda unos segundos de colchón: Alma se oye allá un poco después, y el micrófono la ignora ese rato más.
enum BocinasGoogleReglas {
    struct Bocina: Equatable, Identifiable {
        let id: String
        let nombre: String
        let modelo: String
        let grupo: Bool
    }

    static let servicio = "_googlecast._tcp"
    /// El receptor de audio de fábrica de Google Cast (no hace falta registrar una app).
    static let appReceptor = "CC1AD845"
    static let hz = 24000
    /// Lo que tarda la bocina en sonar desde que el teléfono le manda la voz (su colchón), en segundos.
    static let retraso: TimeInterval = 2.5
    /// Si en este tiempo no la ve en el Wi-Fi, no está en casa: sale por el teléfono.
    static let esperaBuscar: TimeInterval = 5
    /// Si en este tiempo la bocina no empieza a sonar, se deja y sale por el teléfono.
    static let esperaSonar: TimeInterval = 12
    static let prefijo = "google|"

    enum Estado: Equatable {
        case apagada
        case buscando(String)
        case conectando(String)
        case sonando(String)
        case noEsta(String)
        case fallo(String, String)

        /// La línea que se ve debajo de la bocina elegida.
        var linea: String? {
            switch self {
            case .apagada: return nil
            case .buscando(let n): return "Buscando «\(n)» en tu Wi-Fi…"
            case .conectando(let n): return "Conectando con «\(n)»…"
            case .sonando: return "Alma suena aquí ahora"
            case .noEsta(let n): return "No veo «\(n)» en este Wi-Fi: Alma sale por el teléfono"
            case .fallo(let n, let por): return "No pude sonar en «\(n)» (\(por)): Alma sale por el teléfono"
            }
        }
    }

    // MARK: - Lo que anuncia cada bocina en el Wi-Fi

    /// Una bocina a partir de su anuncio (fn: el nombre que le pusiste en Google Home, md: el modelo, id: su número).
    static func bocina(servicio: String, txt: [String: String]) -> Bocina? {
        let id = (txt["id"] ?? "").trimmingCharacters(in: .whitespaces)
        let nombre = (txt["fn"] ?? "").trimmingCharacters(in: .whitespaces)
        let modelo = (txt["md"] ?? "").trimmingCharacters(in: .whitespaces)
        let clave = id.isEmpty ? servicio : id
        guard !clave.isEmpty else { return nil }
        return Bocina(id: clave, nombre: nombre.isEmpty ? servicio : nombre, modelo: modelo, grupo: modelo.lowercased().contains("group"))
    }

    /// Primero los grupos y luego las bocinas, cada uno por nombre.
    static func ordenar(_ l: [Bocina]) -> [Bocina] {
        l.sorted { a, b in a.grupo != b.grupo ? a.grupo : a.nombre.localizedCaseInsensitiveCompare(b.nombre) == .orderedAscending }
    }

    static func explica(_ b: Bocina) -> String { b.grupo ? "Grupo de bocinas" : (b.modelo.isEmpty ? "Bocina de Google" : b.modelo) }

    // MARK: - Lo que se recuerda (la salida elegida)

    static func guardar(_ b: Bocina) -> String { prefijo + b.id + "|" + b.nombre }

    /// La bocina elegida (nil: la salida es del teléfono o de iOS).
    static func elegida(_ pref: String?) -> (id: String, nombre: String)? {
        guard let p = pref, p.hasPrefix(prefijo) else { return nil }
        let resto = p.dropFirst(prefijo.count).split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let id = resto.first, !id.isEmpty else { return nil }
        return (id, resto.count > 1 && !resto[1].isEmpty ? resto[1] : "la bocina")
    }

    // MARK: - Google Cast: cada mensaje va con 4 bytes de largo y un CastMessage (protobuf) adentro

    struct Mensaje: Equatable {
        let origen: String
        let destino: String
        let espacio: String
        let texto: String
    }

    static let espacioConexion = "urn:x-cast:com.google.cast.tp.connection"
    static let espacioLatido = "urn:x-cast:com.google.cast.tp.heartbeat"
    static let espacioReceptor = "urn:x-cast:com.google.cast.receiver"
    static let espacioMedia = "urn:x-cast:com.google.cast.media"

    static func empacar(_ m: Mensaje) -> Data {
        var c = Data()
        c.append(0x08); c.append(0x00)                    // protocol_version = CASTV2_1_0
        campo(&c, 0x12, m.origen)
        campo(&c, 0x1a, m.destino)
        campo(&c, 0x22, m.espacio)
        c.append(0x28); c.append(0x00)                    // payload_type = STRING
        campo(&c, 0x32, m.texto)
        let n = UInt32(c.count)
        var d = Data([UInt8(n >> 24 & 0xff), UInt8(n >> 16 & 0xff), UInt8(n >> 8 & 0xff), UInt8(n & 0xff)])
        d.append(c); return d
    }

    private static func campo(_ d: inout Data, _ etiqueta: UInt8, _ s: String) {
        let b = Data(s.utf8); d.append(etiqueta); varint(&d, UInt64(b.count)); d.append(b)
    }
    private static func varint(_ d: inout Data, _ v: UInt64) {
        var x = v
        while x >= 0x80 { d.append(UInt8(x & 0x7f) | 0x80); x >>= 7 }
        d.append(UInt8(x))
    }

    /// Saca los mensajes completos del principio de `datos` (lo que queda a medias se deja para la próxima vuelta).
    static func desempacar(_ datos: inout Data) -> [Mensaje] {
        var fuera: [Mensaje] = []
        while datos.count >= 4 {
            let b = [UInt8](datos.prefix(4))
            let n = Int(b[0]) << 24 | Int(b[1]) << 16 | Int(b[2]) << 8 | Int(b[3])
            guard n >= 0, n < 1_000_000 else { datos.removeAll(); break }
            guard datos.count >= 4 + n else { break }
            let cuerpo = [UInt8](datos.subdata(in: datos.startIndex + 4 ..< datos.startIndex + 4 + n))
            datos = Data(datos.dropFirst(4 + n))
            if let m = leer(cuerpo) { fuera.append(m) }
        }
        return fuera
    }

    private static func leer(_ b: [UInt8]) -> Mensaje? {
        var i = 0, origen = "", destino = "", espacio = "", texto = ""
        func leerVarint() -> UInt64? {
            var v: UInt64 = 0, s: UInt64 = 0
            while i < b.count {
                let x = b[i]; i += 1
                v |= UInt64(x & 0x7f) << s
                if x & 0x80 == 0 { return v }
                s += 7; if s > 63 { return nil }
            }
            return nil
        }
        while i < b.count {
            guard let llave = leerVarint() else { return nil }
            let num = llave >> 3, tipo = llave & 7
            switch tipo {
            case 0: guard leerVarint() != nil else { return nil }
            case 2:
                guard let n = leerVarint(), i + Int(n) <= b.count else { return nil }
                let s = String(decoding: b[i ..< i + Int(n)], as: UTF8.self); i += Int(n)
                switch num { case 2: origen = s; case 3: destino = s; case 4: espacio = s; case 6: texto = s; default: break }
            case 5: i += 4
            case 1: i += 8
            default: return nil
            }
        }
        return espacio.isEmpty ? nil : Mensaje(origen: origen, destino: destino, espacio: espacio, texto: texto)
    }

    static func json(_ o: [String: Any]) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }
    static func objeto(_ s: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] ?? [:]
    }

    /// Del RECEIVER_STATUS: la conexión (transportId) y la sesión del receptor de audio, si ya está abierto.
    static func receptor(_ o: [String: Any]) -> (transporte: String, sesion: String)? {
        guard o["type"] as? String == "RECEIVER_STATUS", let st = o["status"] as? [String: Any],
              let apps = st["applications"] as? [[String: Any]] else { return nil }
        for a in apps where a["appId"] as? String == appReceptor {
            if let t = a["transportId"] as? String, let s = a["sessionId"] as? String { return (t, s) }
        }
        return nil
    }

    /// Del MEDIA_STATUS: PLAYING, BUFFERING, PAUSED o IDLE (con su porqué si se cayó).
    static func reproductor(_ o: [String: Any]) -> (estado: String, porque: String?)? {
        guard o["type"] as? String == "MEDIA_STATUS", let l = o["status"] as? [[String: Any]], let s = l.first,
              let e = s["playerState"] as? String else { return nil }
        return (e, s["idleReason"] as? String)
    }

    /// El pedido para que la bocina toque la voz en vivo que sirve el teléfono.
    static func cargar(url: String, pedido: Int) -> [String: Any] {
        ["type": "LOAD", "requestId": pedido, "autoplay": true, "currentTime": 0,
         "media": ["contentId": url, "contentType": "audio/wav", "streamType": "LIVE",
                   "metadata": ["metadataType": 0, "title": "Alma", "subtitle": "Llamada con Alma"]]]
    }

    /// La dirección del audio. Con IPv6 va entre corchetes y sin la zona («%en0»).
    static func url(host: String, puerto: UInt16) -> String {
        var h = host
        if let p = h.firstIndex(of: "%") { h = String(h[..<p]) }
        if h.contains(":") { h = "[" + h + "]" }
        return "http://\(h):\(puerto)/alma.wav"
    }

    // MARK: - El audio en vivo

    /// La cabecera de un WAV sin fin (PCM de 16 bits, mono): el tamaño va al máximo, como una radio por internet.
    static func cabeceraWav(hz: Int = hz) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { d.append(contentsOf: [UInt8(v & 0xff), UInt8(v >> 8 & 0xff), UInt8(v >> 16 & 0xff), UInt8(v >> 24 & 0xff)]) }
        func u16(_ v: UInt16) { d.append(contentsOf: [UInt8(v & 0xff), UInt8(v >> 8 & 0xff)]) }
        d.append(contentsOf: Array("RIFF".utf8)); u32(0xFFFF_FFFF); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(hz)); u32(UInt32(hz * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(0xFFFF_FFFF)
        return d
    }

    /// La respuesta HTTP del teléfono a la bocina.
    static func respuestaHttp(pedido: String) -> (cabecera: Data, sigue: Bool) {
        let cabeza = "HTTP/1.1 200 OK\r\nContent-Type: audio/wav\r\nCache-Control: no-cache\r\nAccept-Ranges: none\r\nConnection: close\r\n\r\n"
        let soloCabeza = pedido.hasPrefix("HEAD")
        var d = Data(cabeza.utf8)
        if !soloCabeza { d.append(cabeceraWav()) }
        return (d, !soloCabeza)
    }

    /// La voz (PCM de 16 bits a `de` Hz) a 24 kHz, con interpolación lineal.
    static func remuestrear(_ x: [Int16], de: Int, a: Int = hz) -> [Int16] {
        guard de > 0, a > 0, !x.isEmpty else { return [] }
        if de == a { return x }
        let n = Int((Double(x.count) * Double(a) / Double(de)).rounded())
        guard n > 0 else { return [] }
        var y = [Int16](repeating: 0, count: n)
        let paso = Double(de) / Double(a)
        for i in 0..<n {
            let p = Double(i) * paso, k = Int(p), f = p - Double(k)
            let a0 = Double(x[min(k, x.count - 1)]), a1 = Double(x[min(k + 1, x.count - 1)])
            y[i] = Int16(clamping: Int((a0 + (a1 - a0) * f).rounded()))
        }
        return y
    }

    /// Cuántas muestras tocan ahora para ir al ritmo del reloj (con un colchón al empezar).
    static func porMandar(segundos: Double, enviadas: Int, colchon: Double = 0.3, hz: Int = hz) -> Int {
        max(0, Int((segundos + colchon) * Double(hz)) - enviadas)
    }

    /// Mientras Alma suena en la bocina, el micrófono la ignora este rato más (llega tarde) y con el umbral de «sin eco»:
    /// la cancelación de eco del teléfono no ve lo que suena en otra bocina.
    static func colitaEco(enBocina: Bool) -> TimeInterval { enBocina ? retraso + 0.5 : 0 }
}
