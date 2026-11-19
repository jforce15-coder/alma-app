import Foundation

/// Del texto en español a los fonemas que entiende Kokoro (Juan, 17-nov-2026: Claudio local y Maricarmen con una voz local
/// más natural). Lógica pura, con sus pruebas en Pruebas/VozKokoro. La usa VozKokoro.swift.
///
/// Por qué propio y no espeak-ng: Kokoro se entrenó con los fonemas de espeak-ng (GPL-3.0). Meter espeak en la app la
/// obligaría a ser GPL. El español se lee casi como se escribe, así que estas reglas dan lo mismo que espeak en ~98 % de las
/// palabras (se comparó con espeak-ng es-419 en ~4 000 palabras de los textos del Hub; lo que cambia son palabras en inglés,
/// que van en `excepciones` y en el catálogo de voces). Imitan a espeak a propósito (la «I» de «hay», el «ɛ» de «tengo»,
/// la «ð» de «el día»), porque así habla Kokoro mejor.
/// · Acento latino (es-419): seseo (c, z → s) y «ll» como «y». España (es): «θ» y «ʎ».
/// · La sílaba tónica: la tilde o la regla de siempre (vocal, n o s → llana; si no, aguda). Las palabras largas llevan acento
///   secundario cada dos sílabas antes de la tónica, como espeak. Artículos, preposiciones y pronombres cortos van sin acento.
/// · Entre palabras: b, d, g suaves (β ð ɣ) salvo tras una pausa o una nasal; n → m ante b, p, f y n → ŋ ante g.
/// · Números, horas, %, $ y siglas («PR») se dicen con palabras.
enum FonemasES {
    enum Acento: String, CaseIterable { case latino = "es-419", espana = "es" }

    // MARK: - Una frase

    /// La frase completa en fonemas de Kokoro: palabras separadas por espacio y los signos de pausa pegados a la palabra.
    /// `excepciones`: palabra (minúsculas) → fonemas, para lo que no se lee como se escribe (inglés, marcas).
    static func frase(_ texto: String, acento: Acento, excepciones: [String: String] = [:]) -> String {
        var piezas: [String] = []
        for t in fichas(normalizar(texto)) {
            if t.count == 1, let c = t.first, pausas.contains(c) {
                if !piezas.isEmpty { piezas[piezas.count - 1] += t }
                continue
            }
            var f = excepciones[t] ?? excepcionesFijas[t] ?? palabra(t, acento: acento)
            if atonas.contains(t) { f = f.replacingOccurrences(of: "ˈ", with: "").replacingOccurrences(of: "ˌ", with: "") }
            else if secundarias.contains(t) { f = f.replacingOccurrences(of: "ˈ", with: "ˌ") }
            f = abierta(f)
            if !f.isEmpty { piezas.append(f) }
        }
        return alofonos(piezas.joined(separator: " "))
    }

    static let pausas: Set<Character> = [",", ".", ";", ":", "!", "?", "—", "…"]
    static let atonas: Set<String> = ["el", "la", "los", "las", "lo", "le", "les", "de", "del", "a", "al", "en", "con", "por", "sin",
                                      "y", "e", "o", "u", "que", "quien", "se", "me", "te", "nos", "su", "sus", "mi", "mis", "tu", "tus", "si"]
    static let secundarias: Set<String> = ["para", "pero", "desde", "hacia", "como", "cuando", "donde", "mientras", "porque", "sobre",
                                           "entre", "hasta"]
    /// Lo que las reglas leerían mal y Claudio dice seguido. El catálogo de voces puede agregar más sin otra versión.
    static let excepcionesFijas: [String: String] = [
        "hub": "xˈaβ", "ok": "okˈei", "okay": "okˈei", "okey": "okˈei", "claude": "klˈod", "github": "ɡitxˈaβ",
        "testflight": "tˈest flˈait", "whatsapp": "wasˈap", "iphone": "ˈaifon", "ipad": "ˈaipad", "app": "ˈap",
        "méxico": "mˈɛxiko", "mexicano": "mexikˈano", "texas": "tˈexas", "oaxaca": "waxˈaka", "xavier": "xaβjˈeɾ",
        "opus": "ˈopus", "sonnet": "sˈonet", "email": "imˈeil", "online": "onlˈain", "wifi": "wˈaifai",
    ]

    /// Las piezas de la frase: palabras en minúsculas (sin signos raros) y los signos de pausa.
    static func fichas(_ t: String) -> [String] {
        var out: [String] = [], palabra = ""
        func cerrar() { if !palabra.isEmpty { out.append(palabra); palabra = "" } }
        for c in t.lowercased().precomposedStringWithCanonicalMapping {
            if let l = letra(c) { palabra.append(l); continue }
            cerrar()
            if pausas.contains(c) { out.append(String(c)) }
            else if c == "(" || c == ")" || c == "\n" { out.append(",") }
            else if c == "–" { out.append("—") }
        }
        cerrar()
        return out
    }

    /// Una letra que se lee (las de otros idiomas, a la española); nil si no es letra.
    private static func letra(_ c: Character) -> Character? {
        if "abcdefghijklmnopqrstuvwxyzáéíóúüñ".contains(c) { return c }
        switch c {
        case "à", "â", "ä", "ã": return "a"
        case "è", "ê", "ë": return "e"
        case "ì", "î", "ï": return "i"
        case "ò", "ô", "ö", "õ": return "o"
        case "ù", "û": return "u"
        case "ç": return "s"
        default: return nil
        }
    }

    // MARK: - Una palabra

    static let fuertes: Set<Character> = ["a", "e", "o", "á", "é", "ó"]
    static let vocales: Set<Character> = ["a", "e", "i", "o", "u", "á", "é", "í", "ó", "ú", "ü"]
    static let tilde: [Character: Character] = ["á": "a", "é": "e", "í": "i", "ó": "o", "ú": "u"]
    private static let eI: Set<Character> = ["e", "i", "é", "í"]
    private static let decrecientes: [String: String] = ["ai": "I", "ei": "A", "oi": "Y", "au": "W", "eu": "eʊ"]

    /// Los núcleos de las sílabas (dónde están las vocales que suenan juntas). La «u» de «que», «qui», «gue», «gui» no suena.
    /// Dos fuertes o una débil con tilde se separan; tras «pl», «br», «tr»… o una «r» al inicio, la i/u suena entera (am-pli-ar).
    static func nucleos(_ w: [Character]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var i = 0
        let n = w.count
        while i < n {
            let c = w[i]
            let muda = c == "u" && i > 0 && (w[i - 1] == "q" || w[i - 1] == "g") && i + 1 < n && eI.contains(w[i + 1])
            guard vocales.contains(c), !muda else { i += 1; continue }
            var j = i + 1
            while j < n && vocales.contains(w[j]) {
                let a = w[j - 1], b = w[j]
                if (fuertes.contains(a) && fuertes.contains(b)) || a == "í" || a == "ú" || b == "í" || b == "ú" { break }
                if j - 1 == i && (a == "i" || a == "u") && i > 0 && (w[i - 1] == "l" || w[i - 1] == "r") && (i == 1 || !vocales.contains(w[i - 2])) { break }
                j += 1
            }
            if j == n - 1 && w[j] == "y" { j += 1 }   // «hoy», «rey», «muy»
            out.append(i..<j)
            i = j
        }
        return out
    }

    /// Qué núcleo lleva el acento: el de la tilde; si no, llana si acaba en vocal, n o s; aguda si no.
    static func tonica(_ w: [Character], _ nuc: [Range<Int>]) -> Int {
        guard let ultimo = w.last, !nuc.isEmpty else { return -1 }
        if let k = nuc.firstIndex(where: { r in w[r].contains { tilde[$0] != nil } }) { return k }
        if nuc.count == 1 { return 0 }
        return "aeiouns".contains(ultimo) ? nuc.count - 2 : nuc.count - 1
    }

    /// Las vocales de un núcleo: la que suena fuerte lleva la marca; las débiles de alrededor, j / w. «ai», «ei», «oi», «au»
    /// y «eu» al final se dicen como espeak (I, A, Y, W, eʊ). Tras ɾ, ʝ o ʎ la «u» no se hace w (prueba, llueve).
    static func nucleo(_ g: [Character], marca: String, previo: Character?) -> String {
        let letras = g.map { $0 == "y" ? Character("i") : $0 }
        var pico = letras.firstIndex { tilde[$0] != nil } ?? letras.firstIndex { fuertes.contains($0) }
        if pico == nil { pico = letras.count - 1; if g.last == "y" && letras.count > 1 { pico = letras.count - 2 } }
        let p = pico ?? 0
        var s = ""
        for (k, c) in letras.enumerated() {
            let base = tilde[c] ?? (c == "ü" ? "u" : c)
            if k == p {
                if k + 2 == letras.count && (c == "a" || c == "e" || c == "o") {
                    let sig = tilde[letras[k + 1]] ?? (letras[k + 1] == "ü" ? "u" : letras[k + 1])
                    if let d = decrecientes[String(c) + String(sig)] { return s + marca + d }
                }
                s += marca + String(base)
            } else if k < p {
                let antes = s.last ?? previo
                if c == "ü" || (base == "u" && (antes == "ɾ" || antes == "ʝ" || antes == "j" || antes == "ʎ")) { s += "u" }
                else { s += base == "i" ? "j" : base == "u" ? "w" : String(base) }
            } else {
                s += base == "i" ? "j" : base == "u" ? "w" : String(base)
            }
        }
        return s
    }

    /// Una palabra (minúsculas) en fonemas, con la marca de acento antes de la vocal tónica.
    static func palabra(_ texto: String, acento: Acento) -> String {
        let espana = acento == .espana
        // La h no suena, pero separa vocales (a-hi-ja-do); la de «ch» se queda.
        var w: [Character] = []
        for c in texto { w.append(c == "h" && w.last != "c" ? "·" : c) }
        guard w.contains(where: { $0 != "·" }) else { return "" }
        let nuc = nucleos(w)
        let t = tonica(w, nuc)
        var inicio: [Int: Int] = [:]
        for (k, r) in nuc.enumerated() { inicio[r.lowerBound] = k }
        var out = ""
        var i = 0
        let n = w.count
        func ant() -> Character { i > 0 ? w[i - 1] : "#" }
        while i < n {
            let c = w[i]
            let nx: Character = i + 1 < n ? w[i + 1] : "#", nx2: Character = i + 2 < n ? w[i + 2] : "#"
            if let k = inicio[i] {
                let marca = k == t ? "ˈ" : (t >= 2 && k <= t - 2 && k % 2 == 0 ? "ˌ" : "")
                out += nucleo(Array(w[nuc[k]]), marca: marca, previo: out.last)
                i = nuc[k].upperBound
                continue
            }
            switch c {
            case "·": i += 1
            case "c":
                if nx == "h" { out += "ʧ"; i += 2 }
                else if nx == "k" { i += 1 }   // «ck» de ticket
                else if eI.contains(nx) {
                    if !espana && (ant() == "s" || ant() == "x") { i += 1 }   // piscina, excelente (con seseo, una sola s)
                    else { out += espana ? "θ" : "s"; i += 1 }
                } else { out += "k"; i += 1 }
            case "l" where nx == "l":
                if espana { out += "ʎ" } else if i > 0 && vocales.contains(ant()) && vocales.contains(nx2) { out += "jj" } else { out += "ʝ" }
                i += 2
            case "r":
                if nx == "r" { out += "r"; i += 2 }
                else { out += (i == 0 || "lns".contains(ant())) ? "r" : "ɾ"; i += 1 }
            case "q":
                out += "k"; i += 1
                if i < n && w[i] == "u" { i += 1 }
            case "g":
                if nx == "u" && eI.contains(nx2) { out += "ɡ"; i += 2 }
                else if eI.contains(nx) { out += "x"; i += 1 }
                else { out += "ɡ"; i += 1 }
            case "x": out += i == 0 ? "s" : "ks"; i += 1
            case "y": out += (i + 1 < n && vocales.contains(nx)) ? "ʝ" : "i"; i += 1
            case "z": out += espana ? "θ" : "s"; i += 1
            case "j": out += "x"; i += 1
            case "ñ": out += "ɲ"; i += 1
            case "v", "b": out += "b"; i += 1
            case "ü": out += "u"; i += 1
            case "w", "k", "d", "t", "p", "f", "l", "m", "n", "s": out.append(c); i += 1
            default: i += 1
            }
        }
        return out
    }

    /// La «e» tónica ante n + consonante suena abierta en espeak (tengo, gente, cuenta): ɛ.
    static func abierta(_ f: String) -> String {
        var c = Array(f)
        let cons: Set<Character> = ["b", "d", "f", "ɡ", "k", "l", "m", "n", "p", "ɾ", "r", "s", "t", "θ", "ʧ", "x", "ʝ"]
        var i = 0
        while i + 3 < c.count {
            if c[i] == "ˈ" && c[i + 1] == "e" && c[i + 2] == "n" && cons.contains(c[i + 3]) { c[i + 1] = "ɛ" }
            i += 1
        }
        return String(c)
    }

    // MARK: - Entre palabras

    /// n → m ante b, p, f; n → ŋ ante g; b, d, g suaves salvo al empezar, tras pausa o nasal, o ante consonante; la d final
    /// queda d (verdad).
    static func alofonos(_ texto: String) -> String {
        var c = Array(texto)
        let marcas: Set<Character> = [" ", "ˈ", "ˌ"]
        for i in c.indices where c[i] == "n" {
            var j = i + 1
            while j < c.count && marcas.contains(c[j]) { j += 1 }
            guard j < c.count else { continue }
            if "bpf".contains(c[j]) { c[i] = "m" } else if c[j] == "ɡ" { c[i] = "ŋ" }
        }
        let abren: Set<Character> = ["a", "e", "i", "o", "u", "I", "A", "Y", "W", "ɛ", "ɾ", "l", "r", "j", "w"]
        var previo: Character?
        for i in c.indices {
            let ch = c[i]
            if ch == "b" || ch == "d" || ch == "ɡ" {
                let sig: Character = i + 1 < c.count ? c[i + 1] : " "
                let sig2: Character = (sig == "ˈ" || sig == "ˌ") ? " " : sig
                let dura = previo == nil || pausas.contains(previo!) || "mnŋ".contains(previo!)
                    || (ch == "d" && (sig == " " || pausas.contains(sig)))
                    || (sig2 != " " && !abren.contains(sig2) && !pausas.contains(sig2))
                if !dura { c[i] = ch == "b" ? "β" : ch == "d" ? "ð" : "ɣ" }
            }
            if !marcas.contains(ch) { previo = ch }
        }
        return String(c)
    }

    // MARK: - Números, signos y siglas

    /// Lo que se dice con palabras: horas, porcentajes, dinero, números y siglas («PR» → «pe erre»).
    static func normalizar(_ t: String) -> String {
        var s = t
        s = cambiar(s, #"\b(\d{1,2}):(\d{2})\b"#) { g in
            let h = Int(g[1]) ?? 0, m = Int(g[2]) ?? 0
            return numero(h) + (m == 0 ? " en punto" : " y " + numero(m))
        }
        s = cambiar(s, #"\b\d{1,3}(?:[.,]\d{3})+\b"#) { g in g[0].replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "") }
        s = cambiar(s, #"\b(\d+)[.,](\d+)\b"#) { g in g[1] + " punto " + g[2] }
        s = cambiar(s, #"(\d+)\s?%"#) { g in g[1] + " por ciento" }
        s = cambiar(s, #"(?:US)?\$\s?(\d+)"#) { g in g[1] + " dólares" }
        s = cambiar(s, #"€\s?(\d+)|(\d+)\s?€"#) { g in (g[1].isEmpty ? g[2] : g[1]) + " euros" }
        s = cambiar(s, #"\bQ\s?(\d+)"#) { g in g[1] + " quetzales" }
        s = cambiar(s, #"#\s?(\d+)"#) { g in "número " + g[1] }
        s = cambiar(s, #"\d+"#) { g in
            let d = g[0]
            if d.count > 9 || (d.count > 1 && d.hasPrefix("0")) { return d.map { numero(Int(String($0)) ?? 0) }.joined(separator: " ") }
            return numero(Int(d) ?? 0)
        }
        s = cambiar(s, #"\b([A-ZÑ]{2,4})(s?)\b"#) { g in
            let p = g[1].lowercased()   // «OK», y las palabras gritadas («NO», «YA») no son siglas
            if excepcionesFijas[p] != nil || atonas.contains(p) || ["no", "sí", "si", "ya", "hoy", "muy", "más", "mas", "fin", "uno", "dos", "son", "hay"].contains(p) { return g[0] }
            var l = g[1].map { letras[$0] ?? String($0).lowercased() }
            if g[2] == "s", let u = l.popLast() { l.append(u + (("aeiou".contains(u.last ?? "x")) ? "s" : "es")) }
            return l.joined(separator: " ")
        }
        for (a, b) in [("&", " y "), ("+", " más "), ("=", " igual a "), ("@", " arroba "), ("/", " "), ("_", " "), ("-", " ")] {
            s = s.replacingOccurrences(of: a, with: b)
        }
        return s
    }

    /// El nombre de cada letra (para decir siglas).
    static let letras: [Character: String] = [
        "A": "a", "B": "be", "C": "se", "D": "de", "E": "e", "F": "efe", "G": "ge", "H": "ache", "I": "i", "J": "jota", "K": "ka",
        "L": "ele", "M": "eme", "N": "ene", "Ñ": "eñe", "O": "o", "P": "pe", "Q": "cu", "R": "erre", "S": "ese", "T": "te",
        "U": "u", "V": "ve", "W": "doble ve", "X": "equis", "Y": "ye", "Z": "seta",
    ]

    private static func cambiar(_ s: String, _ patron: String, _ por: ([String]) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: patron) else { return s }
        let ns = s as NSString
        var out = "", desde = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: desde, length: m.range.location - desde))
            let g = (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
            out += por(g)
            desde = m.range.location + m.range.length
        }
        return out + ns.substring(from: desde)
    }

    private static let unidades = ["cero", "uno", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve", "diez", "once", "doce",
                                   "trece", "catorce", "quince", "dieciséis", "diecisiete", "dieciocho", "diecinueve", "veinte", "veintiuno",
                                   "veintidós", "veintitrés", "veinticuatro", "veinticinco", "veintiséis", "veintisiete", "veintiocho", "veintinueve"]
    private static let decenas = ["", "", "", "treinta", "cuarenta", "cincuenta", "sesenta", "setenta", "ochenta", "noventa"]
    private static let centenas = ["", "ciento", "doscientos", "trescientos", "cuatrocientos", "quinientos", "seiscientos", "setecientos",
                                   "ochocientos", "novecientos"]

    /// Un número entero (hasta 999 999 999) con palabras: 1104 → «mil ciento cuatro», 21 000 → «veintiún mil».
    static func numero(_ n: Int) -> String {
        if n < 0 { return "menos " + numero(-n) }
        if n < 30 { return unidades[n] }
        if n < 100 { return decenas[n / 10] + (n % 10 == 0 ? "" : " y " + unidades[n % 10]) }
        if n == 100 { return "cien" }
        if n < 1000 { return centenas[n / 100] + (n % 100 == 0 ? "" : " " + numero(n % 100)) }
        if n < 1_000_000 {
            let miles = n / 1000, resto = n % 1000
            let m = miles == 1 ? "mil" : apocope(numero(miles)) + " mil"
            return m + (resto == 0 ? "" : " " + numero(resto))
        }
        if n < 1_000_000_000 {
            let mill = n / 1_000_000, resto = n % 1_000_000
            let m = mill == 1 ? "un millón" : apocope(numero(mill)) + " millones"
            return m + (resto == 0 ? "" : " " + numero(resto))
        }
        return String(n).map { numero(Int(String($0)) ?? 0) }.joined(separator: " ")
    }

    /// «uno» antes de «mil» o «millones»: «un», «veintiún», «treinta y un».
    private static func apocope(_ s: String) -> String {
        if s.hasSuffix("veintiuno") { return String(s.dropLast(4)) + "iún" }
        if s.hasSuffix("uno") { return String(s.dropLast(1)) }
        return s
    }
}
