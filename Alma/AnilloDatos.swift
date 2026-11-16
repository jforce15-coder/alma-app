import Foundation

/// Lo que el anillo QRing (Colmi R08) manda, leído sin iOS: se prueba solo en Pruebas/AnilloDatos.
/// Paquetes de 16 bytes: [comando, 14 bytes de datos, suma]. Lo conocido viene de Gadgetbridge y colmi_r02_client.
/// AnilloAlma.swift lo usa para las herramientas de la voz (anillo_estado, anillo_medidas, anillo_medir_ahora,
/// anillo_ajustes, anillo_buscar), la pantalla Dispositivos y la Lectura del anillo que va al Hub.
enum AnilloDatos {
    enum Medida: String { case ritmo, oxigeno }

    enum Lectura: Equatable {
        case bateria(nivel: Int, cargando: Bool)
        case ritmoAjustes(activo: Bool, minutos: Int)
        /// En vivo (0x69). valor 0 = todavía midiendo.
        case medida(Medida, valor: Int)
        case medidaError(codigo: Int)
        /// Pasos (0x43): el primer paquete dice si las kcal vienen en decenas.
        case pasosInicio(kcalPorDiez: Bool)
        case pasosSinDatos
        /// Un cuarto de hora: indice y total para saber cuándo terminó.
        case pasosParte(kcal: Int, pasos: Int, metros: Int, indice: Int, total: Int)
        /// Historial del ritmo (0x15): cabecera con cuántos paquetes y cada cuántos minutos.
        case ritmoHistInicio(paquetes: Int, minutos: Int)
        case ritmoHistSinDatos
        case ritmoHistParte(indice: Int, valores: [Int])
        case hora
        case otro(comando: Int)
    }

    static func leer(_ b: [UInt8]) -> Lectura {
        guard let c = b.first else { return .otro(comando: -1) }
        let u16 = { (i: Int) -> Int in b.count > i + 1 ? Int(b[i]) | Int(b[i + 1]) << 8 : 0 }
        switch c {
        case 0x03 where b.count > 2: return .bateria(nivel: Int(b[1]), cargando: b[2] != 0)
        case 0x16 where b.count > 3 && b[1] == 0x01: return .ritmoAjustes(activo: b[2] == 0x01, minutos: Int(b[3]))
        case 0x69 where b.count > 3:
            if b[2] != 0 { return .medidaError(codigo: Int(b[2])) }
            return .medida(b[1] == 0x03 ? .oxigeno : .ritmo, valor: Int(b[3]))
        case 0x43 where b.count > 1:
            if b[1] == 0xF0 { return .pasosInicio(kcalPorDiez: b.count > 3 && b[3] == 0x01) }
            if b[1] == 0xFF { return .pasosSinDatos }
            guard b.count > 12 else { return .otro(comando: Int(c)) }
            return .pasosParte(kcal: u16(7), pasos: u16(9), metros: u16(11), indice: Int(b[5]), total: Int(b[6]))
        case 0x15 where b.count > 1:
            if b[1] == 0xFF { return .ritmoHistSinDatos }
            if b[1] == 0x00 { return .ritmoHistInicio(paquetes: b.count > 2 ? Int(b[2]) : 0, minutos: b.count > 3 ? Int(b[3]) : 5) }
            // el 1 trae la hora (4 bytes) y 9 valores; los demás, 13 valores. El byte 15 es la suma.
            let desde = b[1] == 0x01 ? 6 : 2, hasta = min(b.count, 15)
            return .ritmoHistParte(indice: Int(b[1]), valores: desde < hasta ? b[desde..<hasta].map { Int($0) } : [])
        case 0x01: return .hora
        default: return .otro(comando: Int(c))
        }
    }

    /// Los pasos de un día, sumando sus cuartos de hora.
    struct PasosDia: Equatable {
        var kcal = 0, pasos = 0, metros = 0, porDiez = false, listo = false
        /// true cuando ya llegó el último paquete (o el anillo dijo que no hay datos).
        mutating func sumar(_ l: Lectura) -> Bool {
            switch l {
            case .pasosInicio(let d): self = PasosDia(); porDiez = d; return false
            case .pasosSinDatos: self = PasosDia(); listo = true; return true
            case .pasosParte(let k, let p, let m, let i, let t):
                kcal += porDiez ? k * 10 : k; pasos += p; metros += m
                if i + 1 >= t { listo = true; return true }
                return false
            default: return false
            }
        }
        /// Con el protocolo nuevo el anillo manda las calorías en decenas (Gadgetbridge). Si la suma no es creíble como kcal
        /// de un día (más de 20 000), venían en calorías: se pasan a kcal. Por confirmar contra la app QRing (docs/anillo-qring.md).
        var kcalMostrar: Int { kcal > 20000 ? kcal / 1000 : kcal }
    }

    /// El historial del ritmo de un día: un valor cada `minutos` desde la medianoche (0 = sin lectura).
    struct RitmoHist: Equatable {
        var paquetes = 0, minutos = 5, valores: [Int] = [], listo = false
        mutating func sumar(_ l: Lectura) -> Bool {
            switch l {
            case .ritmoHistInicio(let p, let m): self = RitmoHist(); paquetes = p; minutos = max(1, m); return p <= 1 ? fin() : false
            case .ritmoHistSinDatos: self = RitmoHist(); return fin()
            case .ritmoHistParte(let i, let v):
                valores += v
                return i + 1 >= paquetes ? fin() : false
            default: return false
            }
        }
        private mutating func fin() -> Bool { listo = true; return true }

        struct Resumen: Equatable { let min: Int, max: Int, prom: Int, ultimo: Int, ultimoMin: Int, lecturas: Int }
        /// Solo valores creíbles (25 a 250). nil si no hay ninguno.
        var resumen: Resumen? {
            let buenos = valores.enumerated().filter { (25...250).contains($0.element) }
            guard let u = buenos.last else { return nil }
            let vs = buenos.map { $0.element }
            return Resumen(min: vs.min()!, max: vs.max()!, prom: Int((Double(vs.reduce(0, +)) / Double(vs.count)).rounded()),
                           ultimo: u.element, ultimoMin: u.offset * minutos, lecturas: vs.count)
        }
    }

    /// Lo último que se supo del anillo, cada dato con su hora (segundos desde 1970). Se guarda en el teléfono.
    struct Memoria: Codable, Equatable {
        struct Dato: Codable, Equatable { var v: Int; var t: Double }
        var bateria: Dato?, cargando: Bool?
        var pasos: Dato?, kcal: Dato?, metros: Dato?
        var ritmo: Dato?, oxigeno: Dato?
        var ritmoMin: Int?, ritmoMax: Int?, ritmoProm: Int?, ritmoUltimoMin: Int?, ritmoLecturas: Int?, ritmoDiaT: Double?
        var ritmoActivo: Bool?, ritmoMinutos: Int?, ajustesT: Double?
        var firmware: String?
        var sync: Double?
    }

    /// «hace un momento», «hace 5 min», «hace 2 h», «ayer a las 18:40», «el 14-nov a las 9:05».
    static func hace(_ t: Double?, ahora: Double, zona: TimeZone = .current) -> String? {
        guard let t else { return nil }
        let s = max(0, ahora - t)
        if s < 120 { return "hace un momento" }
        if s < 3600 { return "hace \(Int((s / 60).rounded())) min" }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zona
        let a = Date(timeIntervalSince1970: ahora), d = Date(timeIntervalSince1970: t)
        let dias = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: a)).day ?? 0
        if dias == 0 { return "hace \(Int((s / 3600).rounded())) h" }
        let c = cal.dateComponents([.day, .month, .hour, .minute], from: d)
        let hm = String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
        if dias == 1 { return "ayer a las " + hm }
        let meses = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]
        return "el \(c.day ?? 1)-\(meses[max(0, min(11, (c.month ?? 1) - 1))]) a las " + hm
    }

    /// Minuto del día → «14:35».
    static func horaDelDia(_ minuto: Int) -> String { String(format: "%d:%02d", (minuto / 60) % 24, minuto % 60) }

    /// Un entero de lo que manda ElevenLabs (número o texto).
    static func entero(_ v: Any?) -> Int? {
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }
    static func booleano(_ v: Any?) -> Bool? {
        if let b = v as? Bool { return b }
        if let s = v as? String { return ["true", "sí", "si", "1"].contains(s.lowercased()) ? true : ["false", "no", "0"].contains(s.lowercased()) ? false : nil }
        return nil
    }
    /// El monitoreo del ritmo acepta de 5 a 60 minutos.
    static func minutosValidos(_ n: Int) -> Int { max(5, min(60, n)) }

    /// La medición en vivo: ¿ya hay un valor que decir? Se esperan 3 lecturas buenas del ritmo (las primeras bailan) y 2 del
    /// oxígeno; con el tiempo cumplido vale la última buena.
    static func medicionLista(_ valores: [Int], tipo: Medida, tiempoCumplido: Bool) -> Int? {
        let rango = tipo == .ritmo ? 30...220 : 70...100
        let buenos = valores.filter { rango.contains($0) }
        if buenos.count >= (tipo == .ritmo ? 3 : 2) || (tiempoCumplido && !buenos.isEmpty) { return buenos.last }
        return nil
    }

    /// Lo que va al Hub (action anilloResumen): solo números conocidos con su hora. Nada de nombres ni del aparato.
    static func resumenHub(_ m: Memoria, conectado: Bool) -> [String: Any] {
        var r: [String: Any] = ["conectado": conectado]
        let d = { (x: Memoria.Dato?) -> [String: Any]? in x.map { ["v": $0.v, "t": Int($0.t)] as [String: Any] } }
        if var b = d(m.bateria) { if let c = m.cargando { b["cargando"] = c }; r["bateria"] = b }
        if let x = d(m.pasos) { r["pasos"] = x }
        if let x = d(m.kcal) { r["kcal"] = x }
        if let x = d(m.metros) { r["metros"] = x }
        if let x = d(m.ritmo) { r["ritmo"] = x }
        if let x = d(m.oxigeno) { r["oxigeno"] = x }
        if let t = m.ritmoDiaT, m.ritmoMin != nil {
            var rd: [String: Any] = ["t": Int(t)]
            if let v = m.ritmoMin { rd["min"] = v }; if let v = m.ritmoMax { rd["max"] = v }; if let v = m.ritmoProm { rd["prom"] = v }
            if let v = m.ritmoUltimoMin { rd["ultimo_min"] = v }; if let v = m.ritmoLecturas { rd["lecturas"] = v }
            r["ritmo_dia"] = rd
        }
        if let a = m.ritmoActivo, let t = m.ajustesT { r["ajustes"] = ["activo": a, "minutos": m.ritmoMinutos ?? 0, "t": Int(t)] }
        if let f = m.firmware, !f.isEmpty { r["firmware"] = String(f.filter { $0.isLetter || $0.isNumber || "._-".contains($0) }.prefix(20)) }
        if let s = m.sync { r["sync"] = Int(s) }
        return r
    }

    /// ¿Se manda al Hub? Como mucho cada 10 min, y solo si hay algo nuevo desde el último envío.
    static let cadaCuanto: Double = 600
    static func tocaSubir(ultimaSubida: Double?, ultimoDato: Double?, ahora: Double) -> Bool {
        guard let d = ultimoDato else { return false }
        guard let u = ultimaSubida else { return true }
        return d > u && ahora - u >= cadaCuanto
    }
    static func ultimoDato(_ m: Memoria) -> Double? {
        [m.bateria?.t, m.pasos?.t, m.ritmo?.t, m.oxigeno?.t, m.ritmoDiaT, m.ajustesT, m.sync].compactMap { $0 }.max()
    }

    /// La línea de la ficha de la llamada: así Alma sabe que puede usar sus herramientas del anillo.
    static func ficha(conectado: Bool, m: Memoria, ahora: Double) -> String {
        var t = "ANILLO DE JUAN (QRing): " + (conectado ? "conectado" : "no conectado ahora")
        if let b = m.bateria { t += " · batería \(b.v) %" + (hace(b.t, ahora: ahora).map { " (\($0))" } ?? "") }
        return t + ". Para su batería, pasos, ritmo, oxígeno o ajustes usa tus herramientas del anillo; nunca inventes un dato."
    }
}

/// Los lentes de audio de Juan (iTOUCH AURA, sin cámara). Lógica pura: se prueba en Pruebas/AnilloDatos.
/// Son audífonos Bluetooth clásicos (A2DP/HFP): iOS no da su batería a las apps; solo se sabe si están conectados como
/// salida de audio (AVAudioSession) y, si algún día exponen un servicio BLE de batería (180F), se lee de ahí.
enum LentesDatos {
    static let nombres = ["AURA", "ITOUCH"]
    static func sonLentes(_ nombre: String) -> Bool { let n = nombre.uppercased(); return nombres.contains { n.contains($0) } }
    /// Horas aproximadas de música según el fabricante (4–6 h con la batería llena); con un porcentaje, la parte que queda.
    static func horasMusica(bateria: Int?) -> String {
        guard let b = bateria else { return "4–6 h de música con la carga llena" }
        let a = 4.0 * Double(b) / 100, z = 6.0 * Double(b) / 100
        return String(format: "%.0f–%.0f h de música", a.rounded(.down), z.rounded())
    }
}
