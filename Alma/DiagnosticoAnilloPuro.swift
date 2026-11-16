import Foundation

/// Diagnóstico del anillo (Bluetooth), la parte pura (Juan, 16-nov-2026, ticket #29 paso 1). Sin iOS: se prueba sola en
/// Pruebas/DiagnosticoAnillo. La parte de Bluetooth y la pantalla están en DiagnosticoAnillo.swift.
/// Hoy el anillo llega como control de música (reproducir/pausar) y otra app de audio se lo quita. Antes de leerlo directo
/// hay que saber qué manda por Bluetooth: esto arma el registro que va al Hub (ANILLO_BLE_<clave>, action «anillo», campo ble).
///   · Sin datos personales: el nombre del dispositivo se quita si parece el de una persona; el fabricante y el modelo sí van.
///   · «Solo teclado»: iOS no deja leer el servicio HID (0x1812) desde una app. Si el anillo no tiene nada más, se dice claro.
///   · Servicios propios (UUID de 128 bits o 16 bits de fabricante, FE00–FFFF) sí se pueden leer: se anotan.
///   · El registro cabe en una propiedad del script (9 KB): se recorta quitando los datos más viejos primero.
enum DiagAnillo {
    /// Tope del registro que va al Hub (el Hub vuelve a recortar a 8500).
    static let maxBytes = 8000
    /// Datos que se guardan en el teléfono mientras dura el diagnóstico (en pantalla se ven los últimos).
    static let maxEventos = 600
    /// Bytes en hex por dato (32 bytes): un toque cabe de sobra.
    static let maxHex = 64
    /// Después de una marca, cuánto se espera un dato para decir que ese gesto «mandó algo».
    static let ventanaMarca: Double = 3
    static let gestos = ["1 toque", "2 toques", "largo"]
    static let quitado = "(nombre quitado)"

    struct Caracteristica: Equatable {
        var uuid: String
        var props: [String]
        var valor: String? = nil   // hex de lo leído
    }
    struct Servicio: Equatable {
        var uuid: String
        var caracteristicas: [Caracteristica] = []
    }
    /// Lo que el anillo mandó solo (notify/indicate). t = segundos desde que se conectó.
    struct Evento: Equatable {
        var t: Double
        var servicio: String
        var caracteristica: String
        var hex: String
    }
    /// Lo que Juan marcó en pantalla («1 toque», «2 toques», «largo»).
    struct Marca: Equatable {
        var t: Double
        var gesto: String
    }
    struct Dispositivo: Equatable {
        var nombre: String = ""
        var fabricante: String = ""
        var modelo: String = ""
        var firmware: String = ""
        var senal: Int = 0
        var porHID = false   // iOS lo dio como conectado con el servicio HID (0x1812) o lo anuncia
    }
    enum Veredicto: String { case soloHID = "solo_hid", propio, estandar, nada }

    // MARK: - UUID

    static let baseSIG = "-0000-1000-8000-00805F9B34FB"

    /// La forma corta: 16 bits si es de la base del Bluetooth SIG; si no, igual (los propios se ven completos).
    static func corto(_ uuid: String) -> String {
        let u = uuid.uppercased()
        if u.count == 36, u.hasSuffix(baseSIG), u.hasPrefix("0000") { return String(u.dropFirst(4).prefix(4)) }
        return u
    }

    /// ¿Es un servicio propio del fabricante (se puede leer)? 128 bits fuera de la base SIG, 32 bits, o 16 bits FE00–FFFF.
    static func esPropio(_ uuid: String) -> Bool {
        let u = corto(uuid)
        if u.count == 4, let n = UInt16(u, radix: 16) { return n >= 0xFE00 }
        return true
    }

    static func nombreServicio(_ uuid: String) -> String {
        switch corto(uuid) {
        case "1812": return "Teclado o control (HID)"
        case "180F": return "Batería"
        case "180A": return "Información del dispositivo"
        case "1800": return "Acceso genérico"
        case "1801": return "Atributos genéricos"
        case "1813": return "Parámetros de búsqueda"
        case "180D": return "Ritmo cardíaco"
        case "1805": return "Hora"
        default: return esPropio(uuid) ? "Propio del fabricante" : "Estándar"
        }
    }

    // MARK: - Bytes

    static func hex(_ b: [UInt8]) -> String {
        String(b.map { String(format: "%02x", $0) }.joined().prefix(maxHex))
    }

    /// Texto legible de la información del dispositivo (fabricante, modelo, firmware); nil si no es texto.
    static func texto(_ b: [UInt8]) -> String? {
        guard !b.isEmpty, let s = String(bytes: b.filter { $0 != 0 }, encoding: .utf8) else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.unicodeScalars.allSatisfy({ $0.value >= 0x20 }) else { return nil }
        return String(limpio(t).prefix(40))
    }

    /// Hex con espacios para leerlo en pantalla: «01 02 a0».
    static func hexEspaciado(_ h: String) -> String {
        var out: [String] = [], s = Substring(h)
        while s.count >= 2 { out.append(String(s.prefix(2))); s = s.dropFirst(2) }
        return out.joined(separator: " ")
    }

    // MARK: - Sin datos personales

    /// Lo que delata que es un aparato y no una persona (palabras de marca o de tipo).
    static let deAparato = ["RING", "ANILLO", "COLMI", "YAWELL", "OURA", "ULTRAHUMAN", "RINGCONN", "CIRCULAR", "BLE", "HID",
                            "KEYBOARD", "TECLADO", "REMOTE", "CONTROL", "MUSIC", "SMART", "BAND", "WATCH", "TIKTOK", "PAGE",
                            "SELFIE", "SHUTTER", "MOUSE", "BT", "GATT", "SENSOR"]

    /// Correos, enlaces y números largos (teléfonos) fuera de cualquier texto.
    static func limpio(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", with: "(correo)", options: .regularExpression)
        t = t.replacingOccurrences(of: "https?://\\S+", with: "(enlace)", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\+?\\d[\\d \\-]{6,}\\d", with: "(número)", options: .regularExpression)
        return t
    }

    /// El nombre del dispositivo, sin el de una persona: «iPhone de Juan», «Juan's Ring», «Ana» → «(nombre quitado)»;
    /// «COLMI R02_1A2B», «Smart Ring», «QRing» se quedan. Ante la duda, se quita.
    static func nombreSeguro(_ nombre: String) -> String {
        let s = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "" }
        let u = " " + s.uppercased() + " "
        if u.contains(" DE ") || u.contains(" DEL ") || s.contains("@") { return quitado }
        if s.range(of: "['’]s\\b", options: [.regularExpression, .caseInsensitive]) != nil { return quitado }
        if s.range(of: "\\d{7,}", options: .regularExpression) != nil { return quitado }
        let palabras = s.uppercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let aparato = palabras.contains { p in deAparato.contains { p.contains($0) } }
        let conNumero = s.rangeOfCharacter(from: .decimalDigits) != nil
        if aparato || conNumero { return String(s.prefix(40)) }
        // Solo letras, como un nombre propio («Ana», «Juan Pérez», «iPhone»): fuera.
        return quitado
    }

    // MARK: - Qué es este anillo

    static func veredicto(_ servicios: [Servicio], porHID: Bool) -> Veredicto {
        if servicios.contains(where: { esPropio($0.uuid) }) { return .propio }
        if porHID || servicios.contains(where: { corto($0.uuid) == "1812" }) { return .soloHID }
        return servicios.isEmpty ? .nada : .estandar
    }

    static let textoSoloHID = "Este anillo solo habla como teclado; iOS no deja leerlo directo."

    static func textoVeredicto(_ v: Veredicto, _ servicios: [Servicio], porHID: Bool) -> String {
        switch v {
        case .soloHID: return textoSoloHID
        case .propio:
            let propios = servicios.filter { esPropio($0.uuid) }.map { corto($0.uuid) }
            let avisa = servicios.filter { esPropio($0.uuid) }.flatMap { $0.caracteristicas }.contains { $0.props.contains("notify") || $0.props.contains("indicate") }
            var t = "Este anillo tiene servicios propios que sí se pueden leer (" + propios.joined(separator: ", ") + ")."
            t += avisa ? " Toca el anillo y mira si llegan datos." : " Ninguno avisa solo: puede que los toques no lleguen por aquí."
            if porHID { t += " Además habla como teclado: esa parte iOS no deja leerla." }
            return t
        case .estandar: return "Este anillo solo muestra servicios comunes (batería, información). Los toques no llegan por aquí."
        case .nada: return "No se encontró ningún servicio. Acerca el anillo y vuelve a intentar."
        }
    }

    /// Cuántas marcas no tuvieron ningún dato en los 3 s siguientes (el gesto no llegó por Bluetooth).
    static func marcasSinDatos(_ marcas: [Marca], _ eventos: [Evento]) -> Int {
        marcas.filter { m in !eventos.contains { $0.t >= m.t - 0.5 && $0.t <= m.t + ventanaMarca } }.count
    }

    // MARK: - El registro para el Hub

    static func redondo(_ t: Double) -> Double { (t * 100).rounded() / 100 }

    static func registro(_ d: Dispositivo, servicios: [Servicio], eventos: [Evento], marcas: [Marca], fecha: Date, app: String) -> [String: Any] {
        let v = veredicto(servicios, porHID: d.porHID)
        var disp: [String: Any] = [:]
        disp["nombre"] = nombreSeguro(d.nombre)
        disp["fabricante"] = String(limpio(d.fabricante).prefix(40))
        disp["modelo"] = String(limpio(d.modelo).prefix(40))
        disp["firmware"] = String(limpio(d.firmware).prefix(40))
        disp["senal"] = d.senal
        disp["porHID"] = d.porHID
        var servs: [[String: Any]] = []
        for s in servicios.prefix(20) {
            var cars: [[String: Any]] = []
            for c in s.caracteristicas.prefix(20) {
                var o: [String: Any] = ["uuid": corto(c.uuid), "props": c.props.joined(separator: ",")]
                if let x = c.valor { o["valor"] = String(x.prefix(maxHex)) }
                cars.append(o)
            }
            servs.append(["uuid": corto(s.uuid), "nombre": nombreServicio(s.uuid), "propio": esPropio(s.uuid), "car": cars])
        }
        var evs: [[String: Any]] = []
        for e in eventos.suffix(maxEventos) {
            evs.append(["t": redondo(e.t), "s": corto(e.servicio), "c": corto(e.caracteristica), "hex": String(e.hex.prefix(maxHex))])
        }
        var mks: [[String: Any]] = []
        for m in marcas.suffix(40) { mks.append(["t": redondo(m.t), "gesto": m.gesto]) }
        var r: [String: Any] = [:]
        r["v"] = 1
        r["f"] = ISO8601DateFormatter().string(from: fecha)
        r["app"] = app
        r["dispositivo"] = disp
        r["veredicto"] = ["clave": v.rawValue, "texto": textoVeredicto(v, servicios, porHID: d.porHID)]
        r["servicios"] = servs
        r["eventos"] = evs
        r["marcas"] = mks
        r["sin_datos"] = marcasSinDatos(marcas, eventos)
        r["recortados"] = 0
        return r
    }

    static func tamano(_ r: [String: Any]) -> Int {
        (try? JSONSerialization.data(withJSONObject: r))?.count ?? Int.max
    }

    /// Que quepa en `maxBytes`: primero se van los datos más viejos (de a 10 %), luego los valores leídos, luego servicios.
    /// Las marcas y el veredicto se quedan siempre.
    static func recortar(_ r: [String: Any], maxBytes: Int = maxBytes) -> [String: Any] {
        var r = r
        var eventos = r["eventos"] as? [[String: Any]] ?? []
        var quitados = r["recortados"] as? Int ?? 0
        while tamano(r) > maxBytes, !eventos.isEmpty {
            let n = Swift.max(1, eventos.count / 10)
            eventos.removeFirst(Swift.min(n, eventos.count)); quitados += n
            r["eventos"] = eventos; r["recortados"] = quitados
        }
        if tamano(r) > maxBytes, var servicios = r["servicios"] as? [[String: Any]] {
            servicios = servicios.map { s in
                var s = s
                s["car"] = (s["car"] as? [[String: Any]] ?? []).map { c in var c = c; c.removeValue(forKey: "valor"); return c }
                return s
            }
            r["servicios"] = servicios
            while tamano(r) > maxBytes, !servicios.isEmpty { servicios.removeLast(); r["servicios"] = servicios }
        }
        return r
    }

    /// Una línea del registro en vivo: «14:03:22.41 · FFF0 · FFF7 · 01 02 a0».
    static func linea(hora: Date, servicio: String, caracteristica: String, hex h: String) -> String {
        reloj.string(from: hora) + " · " + corto(servicio) + " · " + corto(caracteristica) + " · " + hexEspaciado(h)
    }
    static let reloj: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SS"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    /// La fuerza de la señal en palabras (RSSI en dBm).
    static func senal(_ rssi: Int) -> String {
        if rssi == 0 || rssi >= 127 { return "Conectado al iPhone" }
        return (rssi > -60 ? "Señal fuerte" : rssi > -80 ? "Señal media" : "Señal débil") + " (\(rssi))"
    }
}
