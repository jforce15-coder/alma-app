import Foundation

/// La voz gratis de Claudio local y Maricarmen (Juan, 18-nov-2026: «Claudio de iPhone, me gusta la gratis. De momento
/// implementémosla mientras desarrollamos la voz de Claudio más conversacional. La de Maricarmen, implementemos también
/// temporalmente la que tú me diste»). TEMPORAL, para probar en vivo mientras se hace la voz definitiva.
/// · El modelo: Pocket TTS de Kyutai en español (6 capas), en la versión ONNX de KevinAHM (CC-BY-4.0). Se baja la primera
///   vez desde Hugging Face, en una versión fija y con la suma de comprobación de cada archivo (como Kokoro).
/// · Las voces: «Claudio (gratis)» y «Maricarmen (gratis)» son clones de las voces diseñadas para cada uno (claudio_A y
///   maricarmen_A). Lo que sale de clonarlas (las embeddings del codificador de Pocket, con el BOS delante) va dentro de la
///   app (Recursos/Voces): el teléfono no clona nada.
/// · Kokoro sigue de respaldo: si la voz gratis falla, esa frase y las que siguen van con Kokoro (y si tarda, con la voz
///   del iPhone, como siempre).
/// Lógica pura, con sus pruebas en Pruebas/VozPocket: el tokenizador (SentencePiece unigram, leído del tokenizer.model),
/// cómo se prepara el texto y los números del modelo. Lo que toca iOS y onnxruntime: VozPocket.swift.
enum VozPocketReglas {

    // MARK: - El modelo (se baja la primera vez; no va dentro de la app)

    static let revision = "58a6d00cf13d239b6748cb0769f35c580a8f606c"
    static let base = "https://huggingface.co/KevinAHM/pocket-tts-onnx/resolve/\(revision)/onnx/spanish/"

    struct Archivo: Equatable {
        let nombre: String
        let bytes: Int
        let sha256: String
        var url: String { VozPocketReglas.base + nombre }
    }

    /// Lo que se baja (~125 MB): el modelo principal y el del flujo en 8 bits, el decodificador de audio en 8 bits, la tabla
    /// del texto, el tokenizador y bundle.json (los estados del modelo). El codificador de voz no hace falta.
    static let archivos: [Archivo] = [
        Archivo(nombre: "flow_lm_main_int8.onnx", bytes: 76_341_079, sha256: "9b020318976e0437bcc78ad0f4a49bf1de6e6e2193c6b0380398038601f9a270"),
        Archivo(nombre: "flow_lm_flow_int8.onnx", bytes: 9_962_530, sha256: "4cc630a8fc1d28e3b432349e492f5f81696aab88b1067b5282b15427fde19efe"),
        Archivo(nombre: "mimi_decoder_int8.onnx", bytes: 22_684_077, sha256: "309efd11b65c58cd176e554d09241f3e2c9aaabd8cbf74b8f01bdd3ec8f7d8e5"),
        Archivo(nombre: "text_conditioner.onnx", bytes: 16_388_344, sha256: "836ad5231fffe6d8fd23c8340d6d91676f466cd35057afd06b7db6ab69baae11"),
        Archivo(nombre: "tokenizer.model", bytes: 60_895, sha256: "aac2b96478e3e3068712bd5c45dc196f84b7341ea72587c33a2094957f0c1b0c"),
        Archivo(nombre: "bundle.json", bytes: 24_365, sha256: "c9f18b5fc326c2a99f645588b79ef27ef3c9c6c3066f8df73bccb7f7c1f855b3"),
    ]
    static var bytesTotales: Int { archivos.reduce(0) { $0 + $1.bytes } }
    /// «125 MB», para la pantalla.
    static var megas: Int { Int((Double(bytesTotales) / 1_000_000).rounded()) }

    static let hz = 24000
    static let muestrasPorCuadro = 1920          // 80 ms de audio por cuadro (12,5 por segundo)
    static let cuadrosPorSegundo = 12.5
    static let latente = 32
    static let condicion = 1024
    static let temperatura: Float = 0.7
    /// El modelo avisa que terminó cuando eos_logit pasa de esto.
    static let umbralFin: Float = -4.0
    static let maxTokensPorTrozo = 50
    /// El aviso de fin no vale antes de un cuadro por token (~80 ms por token; una frase dura más): con el modelo en 8 bits
    /// a veces avisa de fin al empezar y la frase salía cortada (medido: 2 de 12 frases de Claudio sin esto).
    static func finValido(paso: Int, tokens: Int) -> Bool { paso >= tokens }

    // MARK: - Las voces

    struct Voz: Equatable {
        let id: String        // también el nombre del archivo en Recursos/Voces (.bin, float32, filas de 1024)
        let nombre: String
        let personaje: VozKokoroReglas.Personaje
    }
    static let claudio = Voz(id: "claudio_gratis", nombre: "Claudio (gratis)", personaje: .claudio)
    static let maricarmen = Voz(id: "maricarmen_gratis", nombre: "Maricarmen (gratis)", personaje: .maricarmen)
    static func voz(_ p: VozKokoroReglas.Personaje) -> Voz { p == .claudio ? claudio : maricarmen }

    /// Las embeddings de una voz: float32 en filas de 1024 (la primera es el BOS). Otro tamaño o algo que no sea número: nil.
    static func embeddings(_ d: Data) -> [Float]? {
        guard d.count > 0, d.count % (condicion * 4) == 0 else { return nil }
        var f = [Float](repeating: 0, count: d.count / 4)
        _ = f.withUnsafeMutableBytes { d.copyBytes(to: $0) }
        return f.allSatisfy { $0.isFinite } ? f : nil
    }

    static let credito = "Voz gratis: Pocket TTS de Kyutai, en ONNX de KevinAHM (CC-BY 4.0)."

    // MARK: - El texto

    /// Como el modelo lo espera (pocket_tts_onnx.py, _prepare_text_prompt): sin saltos de línea, con mayúscula al inicio y
    /// punto final si termina en letra o número. `despues`: cuántos cuadros más se generan tras el aviso de fin (frases
    /// de hasta 4 palabras, 3 + 2; las demás, 1 + 2).
    static func preparar(_ texto: String) -> (texto: String, despues: Int) {
        var t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "  ", with: " ")
        guard let primera = t.first else { return ("", 0) }
        let palabras = t.split(whereSeparator: { $0.isWhitespace }).count
        if !primera.isUppercase { t = primera.uppercased() + t.dropFirst() }
        if let u = t.last, u.isLetter || u.isNumber { t += "." }
        return (t, (palabras <= 4 ? 3 : 1) + 2)
    }

    /// Cuántos cuadros como mucho para `tokens` tokens (3 tokens por segundo más 2 s de margen).
    static func maxCuadros(tokens: Int) -> Int {
        Int(((Double(tokens) / 3.0 + 2.0) * cuadrosPorSegundo).rounded(.up))
    }

    /// Un texto en trozos de hasta 50 tokens para el modelo: corta en comas o punto y coma; un pedazo que aún es largo, en
    /// palabras. Nada vacío.
    static func trozos(_ texto: String, cuenta: (String) -> Int) -> [String] {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return [] }
        if cuenta(t) <= maxTokensPorTrozo { return [t] }
        var pedazos: [String] = []
        var actual = ""
        for ch in t {
            actual.append(ch)
            if ch == "," || ch == ";" || ch == ":" { pedazos.append(actual); actual = "" }
        }
        if !actual.isEmpty { pedazos.append(actual) }
        var finos: [String] = []
        for p in pedazos.map({ $0.trimmingCharacters(in: .whitespaces) }) where !p.isEmpty {
            if cuenta(p) <= maxTokensPorTrozo { finos.append(p); continue }
            var linea = ""
            for w in p.split(separator: " ") {
                let prueba = linea.isEmpty ? String(w) : linea + " " + w
                if !linea.isEmpty && cuenta(prueba) > maxTokensPorTrozo { finos.append(linea); linea = String(w) } else { linea = prueba }
            }
            if !linea.isEmpty { finos.append(linea) }
        }
        var out: [String] = []
        var junto = ""
        for f in finos {
            let prueba = junto.isEmpty ? f : junto + " " + f
            if !junto.isEmpty && cuenta(prueba) > maxTokensPorTrozo { out.append(junto); junto = f } else { junto = prueba }
        }
        if !junto.isEmpty { out.append(junto) }
        return out
    }

    // MARK: - Los estados del modelo (bundle.json)

    struct Estado: Equatable {
        let entrada: String, salida: String
        let tipo: String           // float32, int64 o bool
        let forma: [Int]
        let relleno: String        // nan, ones, zeros o empty
        let indice: Int
    }

    /// Los estados del modelo principal y del decodificador, en el orden de sus salidas. Si bundle.json no trae lo
    /// esperado: nil.
    static func estados(_ json: Data) -> (flujo: [Estado], mimi: [Estado])? {
        guard let d = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              (d["sample_rate"] as? NSNumber)?.intValue == hz,
              (d["latent_dim"] as? NSNumber)?.intValue == latente,
              (d["conditioning_dim"] as? NSNumber)?.intValue == condicion else { return nil }
        func lista(_ k: String) -> [Estado]? {
            guard let a = d[k] as? [[String: Any]], !a.isEmpty else { return nil }
            var out: [Estado] = []
            for e in a {
                guard let i = e["input_name"] as? String, let o = e["output_name"] as? String, let t = e["dtype"] as? String,
                      ["float32", "int64", "bool"].contains(t), let f = e["shape"] as? [NSNumber], let r = e["fill"] as? String,
                      let n = (e["index"] as? NSNumber)?.intValue else { return nil }
                out.append(Estado(entrada: i, salida: o, tipo: t, forma: f.map { $0.intValue }, relleno: r, indice: n))
            }
            out.sort { $0.indice < $1.indice }
            return out.enumerated().allSatisfy({ $0.offset == $0.element.indice }) ? out : nil
        }
        guard let f = lista("flow_lm_state_manifest"), let m = lista("mimi_state_manifest") else { return nil }
        return (f, m)
    }

    // MARK: - El ruido (normal, con media 0 y varianza = temperatura)

    /// `n` números normales (Box-Muller) con desviación √temperatura.
    static func ruido<G: RandomNumberGenerator>(_ n: Int, temperatura: Float = temperatura, usando g: inout G) -> [Float] {
        let s = temperatura > 0 ? temperatura.squareRoot() : 0
        guard s > 0 else { return [Float](repeating: 0, count: n) }
        var out: [Float] = []
        out.reserveCapacity(n + 1)
        while out.count < n {
            let u1 = Float.random(in: Float.ulpOfOne...1, using: &g), u2 = Float.random(in: 0..<1, using: &g)
            let r = (-2 * log(u1)).squareRoot()
            out.append(r * cos(2 * .pi * u2) * s)
            out.append(r * sin(2 * .pi * u2) * s)
        }
        return Array(out.prefix(n))
    }
}

// MARK: - El tokenizador (SentencePiece unigram, leído del tokenizer.model)

/// Lo mismo que sentencepiece.Encode con el tokenizador de Pocket en español: normalización «identity», «▁» delante y en
/// cada espacio, el camino de mayor puntaje (Viterbi) y, para lo que no está en el vocabulario, sus bytes (<0xNN>).
struct TokenizadorPocket {
    private var piezas: [String: (id: Int64, puntaje: Float)] = [:]
    private var bytes: [UInt8: Int64] = [:]
    private var largoMax = 1
    private var puntajeDesconocido: Float = -10
    let cuantas: Int

    /// Lee el archivo .model (protobuf ModelProto: el campo 1 son las piezas con su texto, puntaje y tipo). nil si no sirve.
    init?(modelo d: Data) {
        let b = [UInt8](d)
        var i = 0, n = 0
        var minimo = Float.greatestFiniteMagnitude
        func varint(_ b: [UInt8], _ i: inout Int) -> UInt64? {
            var r: UInt64 = 0, s: UInt64 = 0
            while i < b.count {
                let c = b[i]; i += 1
                r |= UInt64(c & 0x7f) << s
                if c < 0x80 { return r }
                s += 7
                if s > 63 { return nil }
            }
            return nil
        }
        while i < b.count {
            guard let k = varint(b, &i) else { return nil }
            let campo = k >> 3, tipo = k & 7
            switch tipo {
            case 0: guard varint(b, &i) != nil else { return nil }
            case 1: i += 8
            case 5: i += 4
            case 2:
                guard let largo = varint(b, &i), i + Int(largo) <= b.count else { return nil }
                let fin = i + Int(largo)
                if campo == 1 {
                    var j = i
                    var texto = "", puntaje: Float = 0, clase: UInt64 = 1
                    while j < fin {
                        guard let kk = varint(b, &j) else { return nil }
                        let cc = kk >> 3, tt = kk & 7
                        switch tt {
                        case 2:
                            guard let m = varint(b, &j), j + Int(m) <= fin else { return nil }
                            if cc == 1 { texto = String(decoding: b[j..<(j + Int(m))], as: UTF8.self) }
                            j += Int(m)
                        case 5:
                            guard j + 4 <= fin else { return nil }
                            if cc == 2 {
                                let bits = UInt32(b[j]) | UInt32(b[j + 1]) << 8 | UInt32(b[j + 2]) << 16 | UInt32(b[j + 3]) << 24
                                puntaje = Float(bitPattern: bits)
                            }
                            j += 4
                        case 0:
                            guard let v = varint(b, &j) else { return nil }
                            if cc == 3 { clase = v }
                        case 1: j += 8
                        default: return nil
                        }
                    }
                    let id = Int64(n)
                    switch clase {
                    case 1, 4:   // normal y definida por el usuario (esa con puntaje 0)
                        piezas[texto] = (id, clase == 4 ? 0 : puntaje)
                        largoMax = max(largoMax, texto.unicodeScalars.count)
                        if clase == 1 { minimo = min(minimo, puntaje) }
                    case 6:      // <0xNN>
                        if texto.count == 6, texto.hasPrefix("<0x"), let v = UInt8(texto.dropFirst(3).prefix(2), radix: 16) { bytes[v] = id }
                    default: break
                    }
                    n += 1
                }
                i = fin
            default: return nil
            }
            if i > b.count { return nil }
        }
        guard n > 0, !piezas.isEmpty, bytes.count == 256 else { return nil }
        cuantas = n
        puntajeDesconocido = minimo - 10
    }

    func codificar(_ texto: String) -> [Int64] {
        guard !texto.isEmpty else { return [] }
        let t = Array(("▁" + texto.replacingOccurrences(of: " ", with: "▁")).unicodeScalars)
        let n = t.count
        var mejor = [Float](repeating: -.greatestFiniteMagnitude, count: n + 1)
        var desde = [Int](repeating: -1, count: n + 1)
        var pieza = [Int64](repeating: -1, count: n + 1)   // -1: un carácter desconocido (va en bytes)
        mejor[0] = 0
        for i in 0..<n where mejor[i] > -.greatestFiniteMagnitude {
            var unoEncontrado = false
            var s = String.UnicodeScalarView()
            for l in 1...min(largoMax, n - i) {
                s.append(t[i + l - 1])
                guard let p = piezas[String(s)] else { continue }
                if l == 1 { unoEncontrado = true }
                let v = mejor[i] + p.puntaje
                if v > mejor[i + l] { mejor[i + l] = v; desde[i + l] = i; pieza[i + l] = p.id }
            }
            if !unoEncontrado {
                let v = mejor[i] + puntajeDesconocido
                if v > mejor[i + 1] { mejor[i + 1] = v; desde[i + 1] = i; pieza[i + 1] = -1 }
            }
        }
        var grupos: [[Int64]] = []
        var j = n
        while j > 0 {
            let i = desde[j]
            guard i >= 0 else { return [] }
            if pieza[j] >= 0 { grupos.append([pieza[j]]) } else {
                var s = String.UnicodeScalarView(); s.append(contentsOf: t[i..<j])
                grupos.append(Array(String(s).utf8).compactMap { bytes[$0] })
            }
            j = i
        }
        return grupos.reversed().flatMap { $0 }
    }
}
