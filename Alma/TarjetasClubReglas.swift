import Foundation

/// Tarjetas de clubes (Juan, 17-nov-2026): «guardar en mi perfil las tarjetas de clubes de compra o de cliente frecuente
/// (como las del supermercado) y que, al pedirlas por voz, se muestren en pantalla para enseñárselas al dependiente».
/// Ajuste del mismo día: también boletos de avión, tren, conciertos y eventos (TipoTarjeta), con su fecha y un detalle.
/// Aquí va solo la lógica pura (sin iOS), probada sola en Pruebas/TarjetasClub: el código de barras de cada formato, cómo
/// se encuentra la tarjeta que pidió por su nombre y qué se le contesta a Alma. La pantalla y el llavero: TarjetasClub.swift.

/// Qué es (Juan, 17-nov-2026, ajuste: «sumar el soporte para tickets de avión, tren, conciertos y eventos ocasionales para
/// mostrarlos por voz»). Una tarjeta de club no vence; un boleto lleva su fecha y deja de ofrecerse un día después.
enum TipoTarjeta: String, Codable, CaseIterable {
    case club, avion, tren, concierto, evento

    var nombre: String {
        switch self {
        case .club: return "Tarjeta de club"
        case .avion: return "Boleto de avión"
        case .tren: return "Boleto de tren"
        case .concierto: return "Boleto de concierto"
        case .evento: return "Boleto de evento"
        }
    }
    var boleto: Bool { self != .club }
    /// «la tarjeta de La Torre», «el boleto de Vuelo a Madrid»: como Alma lo dice.
    func cual(_ nombre: String) -> String { (boleto ? "el boleto de " : "la tarjeta de ") + nombre }
    /// Palabras con que se pide por voz cuando no se dice el nombre («mi boleto de avión», «la entrada del concierto»).
    var palabras: Set<String> {
        switch self {
        case .club: return ["tarjeta", "club", "cliente", "frecuente", "puntos", "super", "supermercado"]
        case .avion: return ["avion", "vuelo", "aerolinea", "abordar", "embarque", "aeropuerto"]
        case .tren: return ["tren", "estacion"]
        case .concierto: return ["concierto", "show", "festival"]
        case .evento: return ["evento", "partido", "teatro", "museo", "cine", "feria", "obra"]
        }
    }
}

/// Una tarjeta de club o un boleto guardado en el iPhone.
struct TarjetaClub: Codable, Identifiable, Equatable {
    var id: String
    /// El nombre del club como Juan lo dice («La Torre», «PriceSmart»).
    var nombre: String
    /// El número o el texto que lleva el código.
    var numero: String
    var formato: FormatoCodigo
    /// Opcional: a nombre de quién está (algunas cajas lo piden).
    var titular: String = ""
    var tipo: TipoTarjeta = .club
    /// Solo boletos: el día (yyyy-MM-dd), opcional.
    var fecha: String = ""
    /// Solo boletos: asiento, puerta, sección… (opcional).
    var detalle: String = ""
}

extension TarjetaClub {
    /// Las tarjetas guardadas antes de los boletos no traen tipo, fecha ni detalle: se leen igual (como tarjeta de club).
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        nombre = try c.decode(String.self, forKey: .nombre)
        numero = try c.decode(String.self, forKey: .numero)
        formato = try c.decode(FormatoCodigo.self, forKey: .formato)
        titular = try c.decodeIfPresent(String.self, forKey: .titular) ?? ""
        tipo = (try? c.decodeIfPresent(TipoTarjeta.self, forKey: .tipo)) ?? .club
        fecha = try c.decodeIfPresent(String.self, forKey: .fecha) ?? ""
        detalle = try c.decodeIfPresent(String.self, forKey: .detalle) ?? ""
    }
}

/// Cómo se dibuja el número para que la caja lo lea.
enum FormatoCodigo: String, Codable, CaseIterable {
    case ean13, ean8, code128, code39, qr, pdf417, aztec
    /// Solo el número, sin código (tarjetas que el cajero teclea).
    case numero

    var nombre: String {
        switch self {
        case .ean13: return "EAN-13"
        case .ean8: return "EAN-8"
        case .code128: return "Code 128"
        case .code39: return "Code 39"
        case .qr: return "QR"
        case .pdf417: return "PDF417"
        case .aztec: return "Aztec"
        case .numero: return "Solo el número"
        }
    }
    /// Los que se dibujan en dos dimensiones (cuadrados).
    var cuadrado: Bool { self == .qr || self == .aztec }
}

enum ReglasTarjetas {

    // MARK: - Formato

    /// El formato que mejor encaja con un número tecleado: EAN si son 13, 12 (UPC-A) u 8 dígitos con su dígito de control
    /// bien; si no, Code 128, que lee casi cualquier caja.
    static func formatoSugerido(_ numero: String) -> FormatoCodigo {
        let d = limpio(numero)
        guard !d.isEmpty, d.allSatisfy(\.isASCIIDigit) else { return .code128 }
        if d.count == 13, eanValido(d) { return .ean13 }
        if d.count == 12, eanValido("0" + d) { return .ean13 }   // UPC-A es un EAN-13 que empieza en 0
        if d.count == 8, eanValido(d) { return .ean8 }
        return .code128
    }

    /// El número sin espacios ni guiones (como lo teclean o lo copian de la tarjeta).
    static func limpio(_ s: String) -> String {
        s.filter { !$0.isWhitespace && $0 != "-" }
    }

    /// Lo que de verdad lleva el código de ese formato (UPC-A de 12 dígitos pasa a EAN-13 con un 0 adelante).
    static func contenido(_ numero: String, _ f: FormatoCodigo) -> String {
        switch f {
        case .ean13: let d = limpio(numero); return d.count == 12 ? "0" + d : d
        case .ean8: return limpio(numero)
        case .code39: return numero.trimmingCharacters(in: .whitespaces).uppercased()
        default: return numero.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// ¿Ese número se puede dibujar en ese formato? (para avisar al guardar, no después en la caja)
    static func sePuede(_ numero: String, _ f: FormatoCodigo) -> Bool {
        let c = contenido(numero, f)
        guard !c.isEmpty else { return false }
        switch f {
        case .ean13: return barrasEAN13(c) != nil
        case .ean8: return barrasEAN8(c) != nil
        case .code39: return barrasCode39(c) != nil
        case .code128: return c.allSatisfy { $0.isASCII && ($0.asciiValue ?? 0) >= 32 && ($0.asciiValue ?? 0) < 127 } && c.count <= 80
        case .qr, .pdf417, .aztec: return c.utf8.count <= 1000
        case .numero: return true
        }
    }

    // MARK: - EAN

    /// El dígito de control de un EAN (8 o 13) a partir de los dígitos sin él.
    static func digitoControl(_ cuerpo: String) -> Int? {
        let n = cuerpo.compactMap { $0.wholeNumberValue }
        guard n.count == cuerpo.count, !n.isEmpty else { return nil }
        let suma = n.reversed().enumerated().reduce(0) { $0 + $1.element * ($1.offset % 2 == 0 ? 3 : 1) }
        return (10 - suma % 10) % 10
    }

    static func eanValido(_ d: String) -> Bool {
        guard d.count >= 8, d.allSatisfy(\.isASCIIDigit), let ultimo = d.last?.wholeNumberValue else { return false }
        return digitoControl(String(d.dropLast())) == ultimo
    }

    private static let L = ["0001101", "0011001", "0010011", "0111101", "0100011", "0110001", "0101111", "0111011", "0110111", "0001011"]
    private static func R(_ n: Int) -> String { String(L[n].map { $0 == "0" ? "1" : "0" }) }
    private static func G(_ n: Int) -> String { String(R(n).reversed()) }
    private static let paridad = ["LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG", "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL"]

    /// Las 95 franjas de un EAN-13 (true = barra negra), o nil si el número no es un EAN-13 válido.
    static func barrasEAN13(_ d: String) -> [Bool]? {
        guard d.count == 13, eanValido(d) else { return nil }
        let n = d.compactMap { $0.wholeNumberValue }
        let p = Array(paridad[n[0]])
        var s = "101"
        for i in 1...6 { s += p[i - 1] == "L" ? L[n[i]] : G(n[i]) }
        s += "01010"
        for i in 7...12 { s += R(n[i]) }
        s += "101"
        return s.map { $0 == "1" }
    }

    /// Las 67 franjas de un EAN-8, o nil si no es válido.
    static func barrasEAN8(_ d: String) -> [Bool]? {
        guard d.count == 8, eanValido(d) else { return nil }
        let n = d.compactMap { $0.wholeNumberValue }
        var s = "101"
        for i in 0...3 { s += L[n[i]] }
        s += "01010"
        for i in 4...7 { s += R(n[i]) }
        s += "101"
        return s.map { $0 == "1" }
    }

    // MARK: - Code 39

    /// Cada carácter: 9 elementos (barra, espacio, barra…), 1 = ancho. Siempre 3 anchos.
    static let tablaCode39: [Character: String] = [
        "0": "000110100", "1": "100100001", "2": "001100001", "3": "101100000", "4": "000110001",
        "5": "100110000", "6": "001110000", "7": "000100101", "8": "100100100", "9": "001100100",
        "A": "100001001", "B": "001001001", "C": "101001000", "D": "000011001", "E": "100011000",
        "F": "001011000", "G": "000001101", "H": "100001100", "I": "001001100", "J": "000011100",
        "K": "100000011", "L": "001000011", "M": "101000010", "N": "000010011", "O": "100010010",
        "P": "001010010", "Q": "000000111", "R": "100000110", "S": "001000110", "T": "000010110",
        "U": "110000001", "V": "011000001", "W": "111000000", "X": "010010001", "Y": "110010000",
        "Z": "011010000", "-": "010000101", ".": "110000100", " ": "011000100", "$": "010101000",
        "/": "010100010", "+": "010001010", "%": "000101010", "*": "010010100"]

    /// Las franjas de un Code 39 con sus asteriscos de inicio y fin (ancho = 3 módulos), o nil si trae algo que no cabe.
    static func barrasCode39(_ texto: String) -> [Bool]? {
        let t = texto.uppercased()
        guard !t.isEmpty, !t.contains("*"), t.allSatisfy({ tablaCode39[$0] != nil }) else { return nil }
        var r: [Bool] = []
        for (k, c) in ("*" + t + "*").enumerated() {
            if k > 0 { r.append(false) }   // el espacio angosto entre caracteres
            for (i, e) in tablaCode39[c]!.enumerated() {
                r += Array(repeating: i % 2 == 0, count: e == "1" ? 3 : 1)
            }
        }
        return r
    }

    // MARK: - Encontrar la que pidió

    // MARK: - Fechas de los boletos

    private static let meses = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]

    /// Hoy en el teléfono, como yyyy-MM-dd.
    static func hoy(_ ahora: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: ahora)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Un boleto ya pasó al día siguiente de su fecha (el de un vuelo de madrugada sigue sirviendo ese día). Una tarjeta
    /// de club o un boleto sin fecha nunca pasa.
    static func paso(_ t: TarjetaClub, hoy: String) -> Bool {
        guard t.tipo.boleto, t.fecha.count == 10 else { return false }
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        guard let d = f.date(from: t.fecha) else { return false }
        return f.string(from: d.addingTimeInterval(86_400)) < hoy
    }

    /// «20 nov» (con el año si no es este).
    static func fechaCorta(_ f: String, hoy: String) -> String {
        let p = f.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]) else { return "" }
        return "\(p[2]) \(meses[p[1] - 1])" + (hoy.hasPrefix(String(format: "%04d", p[0])) ? "" : " \(p[0])")
    }

    /// Qué tipo pidió, si lo dijo («mi boleto de avión» → avión). Nil si no dijo ninguno de boleto.
    static func tipoPedido(_ pedido: String) -> TipoTarjeta? {
        let w = Set(pedido.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es")).lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : " " }.reduce(into: "") { $0.append($1) }.split(separator: " ").map(String.init))
        return TipoTarjeta.allCases.first { $0.boleto && !$0.palabras.isDisjoint(with: w) }
    }

    enum Encontrada: Equatable {
        case una(TarjetaClub)
        case varias([TarjetaClub])
        case ninguna
    }

    /// Palabras que se dicen alrededor del nombre y no lo distinguen («mi tarjeta del club de La Torre»).
    private static let relleno: Set<String> = ["tarjeta", "tarjetas", "club", "clubes", "de", "del", "la", "el", "los", "las", "mi", "mis",
                                                "cliente", "frecuente", "puntos", "socio", "membresia", "card", "the", "my", "rewards",
                                                "boleto", "boletos", "ticket", "tickets", "entrada", "entradas", "pase", "a", "al", "para", "en"]

    static func normal(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ").filter { !relleno.contains(String($0)) }.joined(separator: " ")
    }

    /// La tarjeta o el boleto que pidió por voz. Primero entre lo vigente (los boletos que ya pasaron no se ofrecen); si ahí
    /// no está, entre todo. Si no dijo un nombre que encaje pero sí el tipo («mi boleto de avión»), el de ese tipo: con
    /// varios, el más próximo por fecha.
    static func buscar(_ pedido: String, en tarjetas: [TarjetaClub], hoy: String = ReglasTarjetas.hoy()) -> Encontrada {
        let vigentes = tarjetas.filter { !paso($0, hoy: hoy) }
        let r = buscarNombre(pedido, en: vigentes)
        if r != .ninguna { return r }
        if let tipo = tipoPedido(pedido) {
            let deTipo = vigentes.filter { $0.tipo == tipo }
            if deTipo.count == 1 { return .una(deTipo[0]) }
            let conFecha = deTipo.filter { !$0.fecha.isEmpty }.sorted { $0.fecha < $1.fecha }
            if deTipo.count > 1, conFecha.count == deTipo.count, conFecha[0].fecha != conFecha[1].fecha { return .una(conFecha[0]) }
            if deTipo.count > 1 { return .varias(deTipo) }
        }
        return vigentes.count == tarjetas.count ? .ninguna : buscarNombre(pedido, en: tarjetas.filter { paso($0, hoy: hoy) })
    }

    /// Por el nombre: primero el nombre igual, luego el que contiene lo que dijo (o al revés), luego por palabras sueltas.
    /// Sin nombre y con una sola guardada, esa.
    static func buscarNombre(_ pedido: String, en tarjetas: [TarjetaClub]) -> Encontrada {
        guard !tarjetas.isEmpty else { return .ninguna }
        let q = normal(pedido)
        if q.isEmpty { return tarjetas.count == 1 ? .una(tarjetas[0]) : .varias(tarjetas) }
        let sinEspacio = { (s: String) in s.replacingOccurrences(of: " ", with: "") }
        let iguales = tarjetas.filter { sinEspacio(normal($0.nombre)) == sinEspacio(q) }
        if iguales.count == 1 { return .una(iguales[0]) }
        if iguales.count > 1 { return .varias(iguales) }
        let contienen = tarjetas.filter {
            let n = sinEspacio(normal($0.nombre)); let p = sinEspacio(q)
            return !n.isEmpty && (n.contains(p) || p.contains(n))
        }
        if contienen.count == 1 { return .una(contienen[0]) }
        if contienen.count > 1 { return .varias(contienen) }
        let palabras = Set(q.split(separator: " ").map(String.init).filter { $0.count >= 3 })
        let porPalabra = tarjetas.filter { !palabras.isDisjoint(with: normal($0.nombre).split(separator: " ").map(String.init)) }
        if porPalabra.count == 1 { return .una(porPalabra[0]) }
        if porPalabra.count > 1 { return .varias(porPalabra) }
        return .ninguna
    }

    // MARK: - Lo que se le contesta a Alma

    static func lista(_ t: [TarjetaClub]) -> String {
        let n = t.map(\.nombre)
        if n.count <= 1 { return n.first ?? "" }
        return n.dropLast().joined(separator: ", ") + " y " + n.last!
    }

    /// Qué se hace y qué se le dice a Alma (la herramienta mostrar_tarjeta_club). `mostrar` es la tarjeta que se pone en
    /// pantalla (nil si no se muestra nada); `pendiente` = se mostrará al abrir la app (el teléfono estaba bloqueado).
    static func respuesta(pedido: String, tarjetas: [TarjetaClub], pantalla: Bool, hoy: String = ReglasTarjetas.hoy()) -> (texto: String, mostrar: TarjetaClub?, pendiente: Bool, error: Bool) {
        if tarjetas.isEmpty {
            return ("No tiene ninguna tarjeta ni boleto guardado en este iPhone. Dile en una frase que lo agregue en Ajustes → Tarjetas y boletos (puede escanearlo con la cámara) y que luego te lo pida.", nil, false, true)
        }
        switch buscar(pedido, en: tarjetas, hoy: hoy) {
        case .una(let t):
            let cual = t.tipo.cual(t.nombre)
            if pantalla {
                return ("Listo: \(cual) ya está en la pantalla, con el brillo al máximo, para enseñarlo. Dilo en una frase corta; no leas el número.", t, false, false)
            }
            return ("El teléfono está bloqueado: \(cual) aparece en cuanto abra la app. Dilo en una frase corta; no leas el número.", t, true, false)
        case .varias(let v):
            return ("Hay varias que encajan: \(lista(v)). Pregúntale cuál, en una frase, y vuelve a llamar con ese nombre.", nil, false, true)
        case .ninguna:
            let vigentes = tarjetas.filter { !paso($0, hoy: hoy) }
            return ("No tiene guardado «\(pedido)». Lo que tiene: \(vigentes.isEmpty ? "solo boletos que ya pasaron" : lista(vigentes)). Díselo en una frase; si quiere otro, se agrega en Ajustes → Tarjetas y boletos.", nil, false, true)
        }
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
