import Foundation

/// Voz local con Kokoro para Claudio local y Maricarmen (Juan, 17-nov-2026: «que suene cada vez más conversacional y, más
/// adelante, con voces propias»). Lógica pura, con sus pruebas en Pruebas/VozKokoro. Lo que toca iOS: VozKokoro.swift
/// (los motores y la descarga) y VocesLocalesVista.swift (el ajuste).
/// · Motor por personaje: Kokoro (Apache-2.0, 82M, en el teléfono) o la voz del iPhone. Kokoro solo si el modelo y la voz
///   ya se bajaron; si falla o tarda, esa frase y las que siguen van con la voz del iPhone, sin cortar la conversación.
/// · Habla por frases: la primera suena mientras se arma la siguiente.
/// · La voz se cambia sin otra versión de la app: un archivo de estilo (.bin o .npy, 510 × 256 números) que se baja de un
///   catálogo (voces/catalogo.json en este repo) o de un enlace. Las de fábrica, provisionales: em_alex (Claudio) y
///   ef_dora (Maricarmen).
enum VozKokoroReglas {

    // MARK: - El modelo (se baja la primera vez; no va dentro de la app)

    /// Kokoro-82M v1.0 en ONNX (onnx-community, cuantizado a 8 bits), en una versión fija y con su suma de comprobación.
    static let revision = "1939ad2a8e416c0acfeecc08a694d14ef25f2231"
    static let modeloURL = "https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/\(revision)/onnx/model_quantized.onnx"
    static let modeloSHA = "fbae9257e1e05ffc727e951ef9b9c98418e6d79f1c9b6b13bd59f5c9028a1478"
    static let modeloBytes = 92_361_116
    static let hzModelo = 24000
    /// El catálogo de voces que se puede cambiar sin otra versión de la app (un PR a alma-app).
    static let catalogoURL = "https://raw.githubusercontent.com/jforce15-coder/alma-app/main/voces/catalogo.json"

    // MARK: - Personajes y su voz

    enum Personaje: String, CaseIterable { case claudio, maricarmen }
    /// pocket: la voz gratis (VozPocketReglas.swift, temporal), con Kokoro de respaldo.
    enum Motor: String, CaseIterable { case pocket, kokoro, iphone }

    struct Ajustes: Equatable {
        var motor: Motor
        var voz: String
        var velocidad: Float
        var acento: FonemasES.Acento
    }

    static let velocidades: ClosedRange<Float> = 0.7...1.4

    /// De fábrica: la voz gratis (Juan, 18-nov-2026, temporal) y, de respaldo, Kokoro con la voz provisional. Claudio en
    /// latino (seseo) y Maricarmen de España (Weebo 3).
    static func deFabrica(_ p: Personaje) -> Ajustes {
        switch p {
        case .claudio: return Ajustes(motor: .pocket, voz: "em_alex", velocidad: 1.05, acento: .latino)
        case .maricarmen: return Ajustes(motor: .pocket, voz: "ef_dora", velocidad: 1.0, acento: .espana)
        }
    }

    /// Una sola vez al llegar la voz gratis: lo guardado con Kokoro pasa a la voz gratis (Kokoro queda de respaldo, con la
    /// misma voz, acento y velocidad). Lo de la voz del iPhone se respeta.
    static let claveGratis = "voz_local_gratis_v1"
    static func aGratis(_ d: [String: Any]?) -> [String: Any]? {
        guard var d, (d["motor"] as? String) == Motor.kokoro.rawValue else { return d }
        d["motor"] = Motor.pocket.rawValue
        return d
    }

    /// Lo guardado en el teléfono (UserDefaults), con límites; lo que falte o no sirva, de fábrica.
    static func leer(_ d: [String: Any]?, _ p: Personaje) -> Ajustes {
        var a = deFabrica(p)
        guard let d else { return a }
        if let m = (d["motor"] as? String).flatMap { Motor(rawValue: $0) } { a.motor = m }
        if let v = d["voz"] as? String, idValido(v) { a.voz = v }
        if let v = (d["velocidad"] as? NSNumber)?.floatValue, v.isFinite { a.velocidad = min(velocidades.upperBound, max(velocidades.lowerBound, v)) }
        if let c = (d["acento"] as? String).flatMap { FonemasES.Acento(rawValue: $0) } { a.acento = c }
        return a
    }
    static func guardar(_ a: Ajustes) -> [String: Any] {
        ["motor": a.motor.rawValue, "voz": a.voz, "velocidad": a.velocidad, "acento": a.acento.rawValue]
    }

    // MARK: - El catálogo de voces

    struct Voz: Equatable, Identifiable {
        let id: String, nombre: String, url: String
        let sha256: String?
        let acento: FonemasES.Acento
        let mujer: Bool
    }

    private static func hf(_ id: String) -> String { "https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/\(revision)/voices/\(id).bin" }
    /// Las que trae Kokoro en español (provisionales hasta tener las propias).
    static let incluidas: [Voz] = [
        Voz(id: "em_alex", nombre: "Alex (hombre)", url: hf("em_alex"), sha256: "27809e9eafdcbcfff90a3016c697568676531de2a2c39cee29c96c7bd6b83e95", acento: .latino, mujer: false),
        Voz(id: "ef_dora", nombre: "Dora (mujer)", url: hf("ef_dora"), sha256: "f66ec66bd295acb18372e37008533a9a3228483ccd294e7538d5d9294ac9a532", acento: .latino, mujer: true),
        Voz(id: "em_santa", nombre: "Santa (hombre, grave)", url: hf("em_santa"), sha256: "ad43b774e1ca24d05c6161297d8aeb770ac3d29bb95daf516727af5f7d543683", acento: .latino, mujer: false),
    ]

    /// Un id de voz: letras, números, «_» o «-», hasta 40 (también es el nombre del archivo en el teléfono).
    static func idValido(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 40 && s.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "_" || $0 == "-" }
    }

    /// Las de fábrica más las del catálogo remoto (una con el mismo id la reemplaza). Lo que no sirva se ignora: solo https,
    /// id válido y, si trae suma, de 64 letras hexadecimales.
    static func catalogo(_ json: Data?) -> (voces: [Voz], pronunciaciones: [String: String]) {
        var voces = incluidas
        var pron: [String: String] = [:]
        guard let json, let d = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return (voces, pron) }
        for v in d["voces"] as? [[String: Any]] ?? [] {
            guard let id = v["id"] as? String, idValido(id), let url = v["url"] as? String, url.hasPrefix("https://") else { continue }
            let sha = (v["sha256"] as? String)?.lowercased()
            if let s = sha, s.count != 64 || !s.allSatisfy({ $0.isHexDigit }) { continue }
            let nueva = Voz(id: id, nombre: (v["nombre"] as? String).map { String($0.prefix(60)) } ?? id, url: url, sha256: sha,
                            acento: (v["acento"] as? String).flatMap { FonemasES.Acento(rawValue: $0) } ?? .latino, mujer: (v["genero"] as? String) == "mujer")
            if let i = voces.firstIndex(where: { $0.id == id }) { voces[i] = nueva } else { voces.append(nueva) }
        }
        for (k, v) in d["pronunciaciones"] as? [String: String] ?? [:] where !k.isEmpty && !v.isEmpty && v.count <= 120 {
            pron[k.lowercased()] = v
        }
        return (voces, pron)
    }

    // MARK: - El archivo de la voz (estilo)

    static let filas = 510, ancho = 256

    /// El estilo de una voz: 510 filas de 256 números (float32). Sirve el .bin de Kokoro (los números tal cual) o un .npy de
    /// numpy ('<f4', forma (510, 1, 256) o (510, 256)). Otro tamaño o tipo: nil.
    static func estilos(_ d: Data) -> [Float]? {
        let total = filas * ancho
        var cuerpo = d
        if d.count >= 10, d.prefix(6) == Data([0x93, 0x4E, 0x55, 0x4D, 0x50, 0x59]) {   // \x93NUMPY
            let mayor = d[d.startIndex + 6]
            let largoEnc = mayor == 1 ? 2 : 4
            guard d.count >= 8 + largoEnc else { return nil }
            var h = 0
            for k in 0..<largoEnc { h |= Int(d[d.startIndex + 8 + k]) << (8 * k) }
            let ini = 8 + largoEnc
            guard d.count >= ini + h, let enc = String(data: d.subdata(in: d.startIndex + ini..<d.startIndex + ini + h), encoding: .ascii),
                  enc.contains("'<f4'"), !enc.contains("'fortran_order': True") else { return nil }
            cuerpo = d.subdata(in: d.startIndex + ini + h..<d.endIndex)
        }
        guard cuerpo.count == total * 4 else { return nil }
        var f = [Float](repeating: 0, count: total)
        _ = f.withUnsafeMutableBytes { cuerpo.copyBytes(to: $0) }
        guard f.allSatisfy({ $0.isFinite }) else { return nil }
        return f
    }

    /// La fila del estilo que va con una frase de `tokens` fonemas (como Kokoro: la fila = cuántos fonemas).
    static func estilo(_ tabla: [Float], tokens: Int) -> [Float] {
        let fila = min(filas - 1, max(0, tokens))
        return Array(tabla[(fila * ancho)..<((fila + 1) * ancho)])
    }

    // MARK: - Fonemas → números del modelo

    /// Los fonemas que conoce Kokoro v1.0 (config.json) y su número.
    static let vocab: [Unicode.Scalar: Int64] = [
        ";": 1, ":": 2, ",": 3, ".": 4, "!": 5, "?": 6, "—": 9, "…": 10, "\"": 11, "(": 12, ")": 13, "“": 14, "”": 15, " ": 16,
        "\u{0303}": 17, "ʣ": 18, "ʥ": 19, "ʦ": 20, "ʨ": 21, "ᵝ": 22, "ꭧ": 23, "A": 24, "I": 25, "O": 31, "Q": 33, "S": 35,
        "T": 36, "W": 39, "Y": 41, "ᵊ": 42, "a": 43, "b": 44, "c": 45, "d": 46, "e": 47, "f": 48, "h": 50, "i": 51, "j": 52,
        "k": 53, "l": 54, "m": 55, "n": 56, "o": 57, "p": 58, "q": 59, "r": 60, "s": 61, "t": 62, "u": 63, "v": 64, "w": 65,
        "x": 66, "y": 67, "z": 68, "ɑ": 69, "ɐ": 70, "ɒ": 71, "æ": 72, "β": 75, "ɔ": 76, "ɕ": 77, "ç": 78, "ɖ": 80, "ð": 81,
        "ʤ": 82, "ə": 83, "ɚ": 85, "ɛ": 86, "ɜ": 87, "ɟ": 90, "ɡ": 92, "ɥ": 99, "ɨ": 101, "ɪ": 102, "ʝ": 103, "ɯ": 110, "ɰ": 111,
        "ŋ": 112, "ɳ": 113, "ɲ": 114, "ɴ": 115, "ø": 116, "ɸ": 118, "θ": 119, "œ": 120, "ɹ": 123, "ɾ": 125, "ɻ": 126,
        "ʁ": 128, "ɽ": 129, "ʂ": 130, "ʃ": 131, "ʈ": 132, "ʧ": 133, "ʊ": 135, "ʋ": 136, "ʌ": 138, "ɣ": 139, "ɤ": 140, "χ": 142,
        "ʎ": 143, "ʒ": 147, "ʔ": 148, "ˈ": 156, "ˌ": 157, "ː": 158, "ʰ": 162, "ʲ": 164, "↓": 169, "→": 171, "↗": 172,
        "↘": 173, "ᵻ": 177,
    ]
    /// Cuántos fonemas caben en una pasada (510 con los dos ceros de los bordes).
    static let maxTokens = 508

    /// Los números de los fonemas (sin los ceros de los bordes; los pone el motor). Lo desconocido se salta.
    static func tokens(_ fonemas: String) -> [Int64] {
        Array(fonemas.unicodeScalars.compactMap { vocab[$0] }.prefix(maxTokens))
    }

    // MARK: - Por frases

    /// El texto en frases cortas para empezar a hablar rápido: corta en . ! ? ; : … y saltos de línea; una frase larga se
    /// corta en la última coma (o espacio) antes de `max` letras. Nada vacío.
    static func frases(_ texto: String, max: Int = 180) -> [String] {
        var out: [String] = []
        var actual = ""
        let fin: Set<Character> = [".", "!", "?", ";", ":", "…", "\n"]
        let c = Array(texto)
        for (i, ch) in c.enumerated() {
            actual.append(ch)
            let siguiente: Character? = i + 1 < c.count ? c[i + 1] : nil
            if fin.contains(ch) && (siguiente == nil || siguiente!.isWhitespace || siguiente == "\"" || siguiente == "”") {
                // «3.5» o «etc.» pegado a más texto no corta; con espacio después sí
                partir(&out, actual, max: max); actual = ""
            }
        }
        partir(&out, actual, max: max)
        return out
    }

    private static func partir(_ out: inout [String], _ s: String, max: Int) {
        var resto = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while resto.count > max {
            let cabeza = String(resto.prefix(max))
            let corte = cabeza.lastIndex(of: ",").map { cabeza.index(after: $0) } ?? cabeza.lastIndex(of: " ") ?? cabeza.endIndex
            let pedazo = String(cabeza[..<corte]).trimmingCharacters(in: .whitespaces)
            if pedazo.isEmpty { break }
            out.append(pedazo)
            resto = String(resto.dropFirst(pedazo.count)).trimmingCharacters(in: .whitespaces)
            if resto.hasPrefix(",") { resto = String(resto.dropFirst()).trimmingCharacters(in: .whitespaces) }
        }
        if resto.contains(where: { $0.isLetter || $0.isNumber }) { out.append(resto) }
    }

    // MARK: - Cuándo se usa y cuándo cae a la voz del iPhone

    /// Kokoro solo si el personaje lo tiene (o tiene la voz gratis, que lo usa de respaldo), el modelo y su voz ya están en
    /// el teléfono y no salió lento en esta llamada.
    static func usarKokoro(_ a: Ajustes, modeloListo: Bool, vozLista: Bool, lentas: Int) -> Bool {
        (a.motor == .kokoro || a.motor == .pocket) && modeloListo && vozLista && lentas < maxLentas
    }
    /// Tras estas frases lentas seguidas en una conversación, el resto va con la voz del iPhone (que no se trabe).
    static let maxLentas = 2

    /// Cuánto se espera el audio de una frase de Kokoro antes de decirla con la voz del iPhone: la primera, `primera` s (la
    /// primera vez incluye abrir el modelo); las demás, lo que aún falta por sonar más un respiro.
    static let primera = 3.5, respiro = 1.0
    static func limite(primeraFrase: Bool, enCola: Double) -> Double {
        primeraFrase ? primera : Swift.max(primera, enCola + respiro)
    }

    /// Lenta: tardó más en armarse que lo que dura (se oirían huecos entre frases).
    static func lenta(segundos: Double, audio: Double) -> Bool { audio <= 0 || segundos > audio * 1.1 }

    /// Hasta cuándo suena lo que va en cola: cada trozo empieza cuando termina el anterior (o ahora, si ya no sonaba nada).
    static func finCola(_ fin: Date?, ahora: Date, dura: Double) -> Date {
        Swift.max(fin ?? ahora, ahora).addingTimeInterval(dura)
    }

    // MARK: - El audio

    /// De los números del modelo (−1…1 a 24 kHz) a PCM de 16 bits a `hz` (24 kHz igual; 16 kHz con la voz de ElevenLabs).
    static func pcm16(_ m: [Float], de: Int = hzModelo, a hz: Int) -> Data {
        guard !m.isEmpty, de > 0, hz > 0 else { return Data() }
        let n = de == hz ? m.count : Int((Double(m.count) * Double(hz) / Double(de)).rounded(.down))
        var out = [Int16](repeating: 0, count: n)
        for i in 0..<n {
            let v: Float
            if de == hz { v = m[i] } else {
                let x = Double(i) * Double(de) / Double(hz), k = Int(x), t = Float(x - Double(k))
                v = k + 1 < m.count ? m[k] * (1 - t) + m[k + 1] * t : m[Swift.min(k, m.count - 1)]
            }
            out[i] = Int16(Swift.max(-1, Swift.min(1, v)) * 32767)
        }
        return out.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// En trozos de un cuarto de segundo, como llega la voz del socket (el halo late con ella).
    static func trozos(_ a: Data, hz: Int) -> [Data] {
        let b = Swift.max(2, hz / 2)   // 0,25 s de 16 bits
        return stride(from: 0, to: a.count, by: b).map { a.subdata(in: a.index(a.startIndex, offsetBy: $0)..<a.index(a.startIndex, offsetBy: Swift.min(a.count, $0 + b))) }
    }

    /// Un WAV para probar la voz en Ajustes.
    static func wav(_ pcm: Data, hz: Int) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + pcm.count)); d.append(contentsOf: Array("WAVEfmt ".utf8))
        u32(16); u16(1); u16(1); u32(UInt32(hz)); u32(UInt32(hz * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(pcm.count)); d.append(pcm)
        return d
    }

    /// Lo que se ve en el registro: «Kokoro · em_alex · latino».
    static func descripcion(_ a: Ajustes, usa: Bool) -> String {
        if a.motor == .pocket { return usa ? "voz gratis (Pocket) · Kokoro de respaldo" : "la voz gratis aún no está lista" }
        guard a.motor == .kokoro else { return "voz del iPhone" }
        return usa ? "Kokoro · \(a.voz) · \(a.acento == .espana ? "España" : "latino")" : "Kokoro aún no está listo: voz del iPhone"
    }

    // MARK: - Escuchar las voces (Hub #780; Juan, 18-nov-2026: «no solo para escuchar los audios contigo»)

    /// El nombre corto de una voz, sin lo que va entre paréntesis: «Alex (hombre)» → «Alex».
    static func nombreCorto(_ v: Voz) -> String {
        let n = v.nombre.components(separatedBy: " (").first?.trimmingCharacters(in: .whitespaces) ?? ""
        return n.isEmpty ? v.id : n
    }
    /// La frase con la que se presenta cada voz en «Escuchar las voces»: corta (una sola frase de Kokoro) y con su nombre.
    static func muestra(_ v: Voz) -> String {
        "Hola, Juan. Soy \(nombreCorto(v)), una de las voces locales. Así sonaría Claudio o Maricarmen contigo."
    }
    /// Cómo suena en la muestra: Kokoro con esa voz, su acento y velocidad normal (no los ajustes de un personaje).
    static func ajustesMuestra(_ v: Voz) -> Ajustes { Ajustes(motor: .kokoro, voz: v.id, velocidad: 1.0, acento: v.acento) }
    /// Debajo del nombre: acento, hombre o mujer y si falta bajarla.
    static func detalleMuestra(_ v: Voz, lista: Bool, bajando: Bool) -> String {
        let base = (v.acento == .espana ? "España" : "Latino") + " · " + (v.mujer ? "mujer" : "hombre")
        return base + (bajando ? " · bajando…" : lista ? "" : " · se baja al tocar")
    }
}
