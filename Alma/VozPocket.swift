import CryptoKit
import Foundation
import onnxruntime

/// La voz gratis (Pocket TTS en español; las reglas en VozPocketReglas.swift) en el teléfono, con onnxruntime (el mismo
/// que ya usan Kokoro y el Modo calle). TEMPORAL (Juan, 18-nov-2026), mientras se hace la voz definitiva.
/// · MotorPocket: una frase → audio por trozos, mientras se genera (la primera parte suena antes de que termine la frase).
///   Si falla, esa frase y las que siguen van con Kokoro (su respaldo); si tarda, HablaPorFrases pasa a la voz del iPhone.
/// · PocketOnnx: los cuatro modelos abiertos (uno para toda la app, siempre en `cola`) y el estado de cada voz ya
///   preparado (se arma una vez con las embeddings que trae la app).
final class MotorPocket: MotorVoz {
    let nombre = "pocket"
    let voz: VozPocketReglas.Voz
    private let carpeta: URL
    private let respaldo: MotorVoz?
    private var cayo = false
    private var vuelta = 0
    private var corte = Corte()
    /// Lo que se anota: cuánto tardó cada frase (para saber si el teléfono va bien con la voz gratis).
    var paso: ((String) -> Void)? { didSet { (respaldo as? MotorKokoro)?.paso = paso } }

    init(voz: VozPocketReglas.Voz, carpeta: URL, respaldo: MotorVoz?) {
        self.voz = voz; self.carpeta = carpeta; self.respaldo = respaldo
    }

    /// Las voces con el modelo ya abierto y su estado armado (en el hilo principal).
    static var calientes: Set<String> = []
    /// Aún no se abre el modelo con esta voz: la primera frase puede tardar unos segundos más.
    var fria: Bool { !MotorPocket.calientes.contains(voz.id) }

    /// Abre el modelo y arma la voz antes de la primera frase (así la primera no espera ~1-2 s).
    func preparar() {
        let c = carpeta, v = voz
        PocketOnnx.cola.async {
            let ok = (try? PocketOnnx.abrir(c).estadoVoz(v)) != nil
            DispatchQueue.main.async { if ok { MotorPocket.calientes.insert(v.id) } else { MotorPocket.calientes.remove(v.id) } }
        }
    }

    func sintetizar(_ frase: String, hz: Int, trozo: @escaping (Data) -> Void, fin: @escaping (Bool) -> Void) {
        if cayo, let r = respaldo { r.sintetizar(frase, hz: hz, trozo: trozo, fin: fin); return }
        vuelta += 1
        corte.cortar()
        let mia = vuelta, c = Corte(), carpeta = carpeta, v = voz
        corte = c
        let t0 = Date()
        PocketOnnx.cola.async {
            var falla = "", segundos = 0.0
            do {
                try PocketOnnx.abrir(carpeta).decir(frase, voz: v, sigue: { !c.cortado }) { audio in
                    segundos += Double(audio.count) / Double(VozPocketReglas.hz)
                    let d = VozKokoroReglas.pcm16(audio, de: VozPocketReglas.hz, a: hz)
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.vuelta == mia, !c.cortado else { return }
                        for t in VozKokoroReglas.trozos(d, hz: hz) { trozo(t) }
                    }
                }
            } catch { falla = "\(error)" }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.vuelta == mia, !c.cortado else { return }
                if falla.isEmpty {
                    self.paso?(String(format: "Voz gratis: %.1f s de voz en %.1f s", segundos, Date().timeIntervalSince(t0)))
                    fin(true); return
                }
                self.paso?("La voz gratis no pudo: " + falla)
                guard let r = self.respaldo else { fin(false); return }
                self.cayo = true
                self.paso?("Sigue Kokoro (respaldo de la voz gratis)")
                r.sintetizar(frase, hz: hz, trozo: trozo, fin: fin)
            }
        }
    }

    func cancelar() { vuelta += 1; corte.cortar(); respaldo?.cancelar() }
}

/// Un «ya no» que se marca en el hilo principal y se lee en la cola del modelo.
final class Corte {
    private let l = NSLock()
    private var v = false
    var cortado: Bool { l.lock(); defer { l.unlock() }; return v }
    func cortar() { l.lock(); v = true; l.unlock() }
}

/// Los modelos de Pocket abiertos con onnxruntime (la API de C). Uno para toda la app, siempre en `cola`.
final class PocketOnnx {
    enum Falla: Error, CustomStringConvertible {
        case sinApi, onnx(String), falta(String), sinSalida(String)
        var description: String {
            switch self {
            case .sinApi: return "onnxruntime no está"
            case .onnx(let m): return m
            case .falta(let m): return "falta " + m
            case .sinSalida(let m): return "el modelo no devolvió " + m
            }
        }
    }

    static let cola = DispatchQueue(label: "alma.pocket", qos: .userInitiated)
    private static var abierto: PocketOnnx?

    /// Los modelos listos para usar (los abre la primera vez). Solo desde `cola`.
    static func abrir(_ carpeta: URL) throws -> PocketOnnx {
        if let p = abierto, p.carpeta == carpeta { return p }
        abierto = nil
        let p = try PocketOnnx(carpeta)
        abierto = p
        return p
    }
    /// Suelta la memoria (iOS pide memoria o se borró el modelo); se vuelve a abrir al hablar.
    static func soltar() { cola.async { abierto = nil }; MotorPocket.calientes = [] }

    let carpeta: URL
    private let api: UnsafePointer<OrtApi>
    private var env: OpaquePointer?
    private var texto: OpaquePointer?, principal: OpaquePointer?, flujo: OpaquePointer?, decodificador: OpaquePointer?
    private var asignador: UnsafeMutablePointer<OrtAllocator>?
    private let tokenizador: TokenizadorPocket
    private let estFlujo: [VozPocketReglas.Estado], estMimi: [VozPocketReglas.Estado]
    /// Los nombres en C (viven lo que vive el modelo).
    private var nombres: [String: UnsafeMutablePointer<CChar>] = [:]
    /// El estado del modelo principal con cada voz ya leída (no se toca: cada frase parte de una copia que hace el modelo).
    private var voces: [String: [OpaquePointer]] = [:]
    private var generador = SystemRandomNumberGenerator()

    private init(_ carpeta: URL) throws {
        self.carpeta = carpeta
        func leer(_ n: String) throws -> Data {
            guard let d = try? Data(contentsOf: carpeta.appendingPathComponent(n)) else { throw Falla.falta(n) }
            return d
        }
        guard let tk = TokenizadorPocket(modelo: try leer("tokenizer.model")) else { throw Falla.falta("el tokenizador") }
        guard let e = VozPocketReglas.estados(try leer("bundle.json")) else { throw Falla.falta("bundle.json") }
        tokenizador = tk; estFlujo = e.flujo; estMimi = e.mimi
        guard let base = OrtGetApiBase(), let dame = base.pointee.GetApi, let a = dame(UInt32(ORT_API_VERSION)) else { throw Falla.sinApi }
        api = a
        try revisar(api.pointee.CreateEnv!(ORT_LOGGING_LEVEL_WARNING, "pocket", &env))
        var opciones: OpaquePointer?
        try revisar(api.pointee.CreateSessionOptions!(&opciones))
        defer { api.pointee.ReleaseSessionOptions!(opciones) }
        // Un paso del modelo es una matriz chica: más hilos que los núcleos rápidos del iPhone solo estorban.
        try revisar(api.pointee.SetIntraOpNumThreads!(opciones, 2))
        try revisar(api.pointee.SetInterOpNumThreads!(opciones, 1))
        func sesion(_ n: String) throws -> OpaquePointer? {
            var s: OpaquePointer?
            try revisar(api.pointee.CreateSession!(env, carpeta.appendingPathComponent(n).path, opciones, &s))
            return s
        }
        texto = try sesion("text_conditioner.onnx")
        principal = try sesion("flow_lm_main_int8.onnx")
        flujo = try sesion("flow_lm_flow_int8.onnx")
        decodificador = try sesion("mimi_decoder_int8.onnx")
        try revisar(api.pointee.GetAllocatorWithDefaultOptions!(&asignador))
    }

    deinit {
        for vs in voces.values { for v in vs { api.pointee.ReleaseValue!(v) } }
        for s in [texto, principal, flujo, decodificador] { if let s { api.pointee.ReleaseSession!(s) } }
        if let e = env { api.pointee.ReleaseEnv!(e) }
        for p in nombres.values { free(p) }
    }

    // MARK: Una frase

    /// Dice `frase` con `voz`: entrega el audio (−1…1 a 24 kHz) en partes mientras lo genera. `sigue` false: para.
    func decir(_ frase: String, voz: VozPocketReglas.Voz, sigue: () -> Bool, audio: ([Float]) -> Void) throws {
        let base = try estadoVoz(voz)
        let cuenta = { (s: String) in self.tokenizador.codificar(VozPocketReglas.preparar(s).texto).count }
        for parte in VozPocketReglas.trozos(frase, cuenta: cuenta) {
            guard sigue() else { return }
            let (t, despues) = VozPocketReglas.preparar(parte)
            let ids = tokenizador.codificar(t)
            guard !ids.isEmpty else { continue }
            try generar(ids, base: base, despues: despues, sigue: sigue, audio: audio)
        }
    }

    private func generar(_ ids: [Int64], base: [OpaquePointer], despues: Int, sigue: () -> Bool, audio: ([Float]) -> Void) throws {
        let L = VozPocketReglas.latente, C = VozPocketReglas.condicion
        // El texto → sus embeddings → el modelo principal las lee (desde el estado de la voz).
        let vIds = try tensor(ids, [1, ids.count])
        let emb = try correr(texto, ["token_ids"], [vIds], ["embeddings"])
        release(vIds)
        let vacia = try tensor([Float](), [1, 0, L]), sinTexto = try tensor([Float](), [1, 0, C])
        defer { release(vacia); release(sinTexto) }
        var r = try correr(principal, ["sequence", "text_embeddings"] + estFlujo.map(\.entrada), [vacia, emb[0]] + base,
                           ["conditioning", "eos_logit"] + estFlujo.map(\.salida))
        release(emb[0]); release(r[0]); release(r[1])
        var estado = Array(r[2...])
        defer { for v in estado { release(v) } }

        var mimi = try estadoInicial(estMimi)
        defer { for v in mimi { release(v) } }
        let vs = try tensor([Float(0)], [1, 1]), vt = try tensor([Float(1)], [1, 1])
        defer { release(vs); release(vt) }

        var actual = [Float](repeating: .nan, count: L)
        var pendientes: [Float] = [], cuantos = 0, decodificados = 0
        var fin: Int?
        func decodificar() throws {
            guard cuantos > 0 else { return }
            let lat = try tensor(pendientes, [1, cuantos, L])
            let d = try correr(decodificador, ["latent"] + estMimi.map(\.entrada), [lat] + mimi, ["audio_frame"] + estMimi.map(\.salida))
            release(lat)
            for v in mimi { release(v) }
            mimi = Array(d[1...])
            let a = try leer(d[0]); release(d[0])
            decodificados += cuantos
            pendientes.removeAll(keepingCapacity: true); cuantos = 0
            if !a.isEmpty { audio(a) }
        }

        for paso in 0..<VozPocketReglas.maxCuadros(tokens: ids.count) {
            guard sigue() else { return }
            let seq = try tensor(actual, [1, 1, L])
            r = try correr(principal, ["sequence", "text_embeddings"] + estFlujo.map(\.entrada), [seq, sinTexto] + estado,
                           ["conditioning", "eos_logit"] + estFlujo.map(\.salida))
            release(seq)
            for v in estado { release(v) }
            estado = Array(r[2...])
            let eos = try leer(r[1]).first ?? -100
            release(r[1])
            if eos > VozPocketReglas.umbralFin && fin == nil && VozPocketReglas.finValido(paso: paso, tokens: ids.count) { fin = paso }
            if let f = fin, paso >= f + despues { release(r[0]); break }
            // Un paso del flujo (lsd 1): del ruido al latente de este cuadro.
            var x = VozPocketReglas.ruido(L, usando: &generador)
            let vx = try tensor(x, [1, L])
            let fl = try correr(flujo, ["c", "s", "t", "x"], [r[0], vs, vt, vx], ["flow_dir"])
            release(vx); release(r[0])
            let dir = try leer(fl[0]); release(fl[0])
            guard dir.count == L else { throw Falla.sinSalida("el flujo") }
            for k in 0..<L { x[k] += dir[k] }
            actual = x
            pendientes += x; cuantos += 1
            // El primer audio sale con 2 cuadros (160 ms); después, de 6 en 6 (casi medio segundo).
            if cuantos >= (decodificados == 0 ? 2 : 6) { try decodificar() }
        }
        guard sigue() else { return }
        try decodificar()
    }

    // MARK: La voz

    /// El estado del modelo principal después de leer las embeddings de la voz (se arma una vez por voz).
    @discardableResult
    func estadoVoz(_ voz: VozPocketReglas.Voz) throws -> [OpaquePointer] {
        if let e = voces[voz.id] { return e }
        guard let u = Bundle.main.url(forResource: voz.id, withExtension: "bin"), let d = try? Data(contentsOf: u),
              let emb = VozPocketReglas.embeddings(d) else { throw Falla.falta("la voz " + voz.nombre) }
        let C = VozPocketReglas.condicion
        let vEmb = try tensor(emb, [1, emb.count / C, C]), vacia = try tensor([Float](), [1, 0, VozPocketReglas.latente])
        let inicial = try estadoInicial(estFlujo)
        defer { release(vEmb); release(vacia); for v in inicial { release(v) } }
        let r = try correr(principal, ["sequence", "text_embeddings"] + estFlujo.map(\.entrada), [vacia, vEmb] + inicial,
                           ["conditioning", "eos_logit"] + estFlujo.map(\.salida))
        release(r[0]); release(r[1])
        let e = Array(r[2...])
        voces[voz.id] = e
        return e
    }

    // MARK: Tensores

    private func estadoInicial(_ es: [VozPocketReglas.Estado]) throws -> [OpaquePointer] {
        var out: [OpaquePointer] = []
        do {
            for e in es {
                let n = e.forma.reduce(1, *)
                switch e.tipo {
                case "int64": out.append(try tensor([Int64](repeating: e.relleno == "ones" ? 1 : 0, count: n), e.forma))
                case "bool": out.append(try tensor([UInt8](repeating: e.relleno == "ones" ? 1 : 0, count: n), e.forma, tipo: ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL))
                default:
                    let v: Float = e.relleno == "nan" ? .nan : e.relleno == "ones" ? 1 : 0
                    out.append(try tensor([Float](repeating: v, count: n), e.forma))
                }
            }
        } catch { for v in out { release(v) }; throw error }
        return out
    }

    private func tensor(_ datos: [Float], _ forma: [Int]) throws -> OpaquePointer {
        try tensor(datos, forma, tipo: ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT)
    }
    private func tensor(_ datos: [Int64], _ forma: [Int]) throws -> OpaquePointer {
        try tensor(datos, forma, tipo: ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64)
    }
    /// Un tensor que es de onnxruntime (él guarda la memoria), con los datos copiados.
    private func tensor<T>(_ datos: [T], _ forma: [Int], tipo: ONNXTensorElementDataType) throws -> OpaquePointer {
        let f = forma.map { Int64($0) }
        var v: OpaquePointer?
        try revisar(api.pointee.CreateTensorAsOrtValue!(asignador, f, f.count, tipo, &v))
        guard let valor = v else { throw Falla.sinSalida("un tensor") }
        if !datos.isEmpty {
            var p: UnsafeMutableRawPointer?
            do { try revisar(api.pointee.GetTensorMutableData!(valor, &p)) } catch { release(valor); throw error }
            guard let p else { release(valor); throw Falla.sinSalida("un tensor") }
            datos.withUnsafeBytes { p.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        }
        return valor
    }

    private func leer(_ v: OpaquePointer) throws -> [Float] {
        var info: OpaquePointer?
        try revisar(api.pointee.GetTensorTypeAndShape!(v, &info))
        defer { if let info { api.pointee.ReleaseTensorTypeAndShapeInfo!(info) } }
        var n = 0
        try revisar(api.pointee.GetTensorShapeElementCount!(info, &n))
        guard n > 0 else { return [] }
        var p: UnsafeMutableRawPointer?
        try revisar(api.pointee.GetTensorMutableData!(v, &p))
        guard let p else { throw Falla.sinSalida("números") }
        return Array(UnsafeBufferPointer(start: p.assumingMemoryBound(to: Float.self), count: n))
    }

    private func release(_ v: OpaquePointer) { api.pointee.ReleaseValue!(v) }

    private func c(_ s: String) -> UnsafePointer<CChar>? {
        if let p = nombres[s] { return UnsafePointer(p) }
        guard let p = strdup(s) else { return nil }
        nombres[s] = p
        return UnsafePointer(p)
    }

    /// Corre un modelo: entradas por nombre → las salidas pedidas (nuevas: quien las recibe las suelta).
    private func correr(_ s: OpaquePointer?, _ entradas: [String], _ valores: [OpaquePointer], _ salidas: [String]) throws -> [OpaquePointer] {
        let ne = entradas.map { c($0) }, ns = salidas.map { c($0) }
        let vs: [OpaquePointer?] = valores
        var out = [OpaquePointer?](repeating: nil, count: salidas.count)
        try revisar(api.pointee.Run!(s, nil, ne, vs, vs.count, ns, ns.count, &out))
        let listas = out.compactMap { $0 }
        guard listas.count == salidas.count else { for v in listas { release(v) }; throw Falla.sinSalida(salidas.joined(separator: ", ")) }
        return listas
    }

    private func revisar(_ s: OpaquePointer?) throws {
        guard let s else { return }
        let m = api.pointee.GetErrorMessage!(s).map { String(cString: $0) } ?? "error de onnxruntime"
        api.pointee.ReleaseStatus!(s)
        throw Falla.onnx(m)
    }
}

// MARK: - La descarga (en VocesLocales, junto a la de Kokoro)

extension VocesLocales {
    var carpetaGratis: URL { carpeta.deletingLastPathComponent().appendingPathComponent("PocketTTS", isDirectory: true) }

    /// Todos los archivos en el teléfono, con su tamaño exacto (la suma se revisa al bajarlos).
    var gratisLista: Bool {
        VozPocketReglas.archivos.allSatisfy {
            ((try? FileManager.default.attributesOfItem(atPath: carpetaGratis.appendingPathComponent($0.nombre).path)[.size]) as? NSNumber)?.intValue == $0.bytes
        }
    }

    /// La voz gratis del personaje (con Kokoro de respaldo si está listo), o nil si aún no se bajó.
    func motorGratis(_ p: VozKokoroReglas.Personaje, respaldo: MotorVoz?) -> MotorPocket? {
        guard gratisLista else { return nil }
        let m = MotorPocket(voz: VozPocketReglas.voz(p), carpeta: carpetaGratis, respaldo: respaldo)
        m.preparar()
        return m
    }

    /// Baja la voz gratis (~125 MB), archivo por archivo y con su suma. Con `celular` false, solo por Wi-Fi.
    func descargarGratis(celular: Bool) {
        if gratisLista { gratis = .listo; return }
        if case .bajando = gratis { return }
        let dir = carpetaGratis
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var c = dir
        var rv = URLResourceValues(); rv.isExcludedFromBackup = true
        try? c.setResourceValues(rv)
        gratis = .bajando(0)
        let faltan = VozPocketReglas.archivos.filter {
            ((try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent($0.nombre).path)[.size]) as? NSNumber)?.intValue != $0.bytes
        }
        let total = Double(VozPocketReglas.bytesTotales)
        var hechos = Double(VozPocketReglas.bytesTotales - faltan.reduce(0) { $0 + $1.bytes })
        func siguiente(_ resto: [VozPocketReglas.Archivo]) {
            guard let a = resto.first else { gratis = gratisLista ? .listo : .error("no se pudo bajar"); return }
            guard let u = URL(string: a.url) else { gratis = .error("enlace malo"); return }
            var r = URLRequest(url: u)
            r.allowsExpensiveNetworkAccess = celular; r.allowsConstrainedNetworkAccess = celular; r.timeoutInterval = 60
            let destino = dir.appendingPathComponent(a.nombre)
            let tarea = URLSession.shared.downloadTask(with: r) { [weak self] tmp, resp, err in
                let problema: String? = {
                    guard let tmp, (resp as? HTTPURLResponse)?.statusCode == 200 else {
                        return err.map { ($0 as NSError).code == NSURLErrorNotConnectedToInternet ? "sin internet" : $0.localizedDescription } ?? "no se pudo bajar"
                    }
                    guard VocesLocales.sha256(tmp) == a.sha256 else { return "\(a.nombre) no coincide con su suma de comprobación" }
                    try? FileManager.default.removeItem(at: destino)
                    return (try? FileManager.default.moveItem(at: tmp, to: destino)) == nil ? "no se pudo guardar" : nil
                }()
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.observaGratis = nil
                    if let p = problema { self.gratis = .error(p); return }
                    hechos += Double(a.bytes)
                    siguiente(Array(resto.dropFirst()))
                }
            }
            observaGratis = tarea.progress.observe(\.fractionCompleted) { [weak self] p, _ in
                let f = (hechos + p.fractionCompleted * Double(a.bytes)) / total
                DispatchQueue.main.async { if let s = self, case .bajando = s.gratis { s.gratis = .bajando(f) } }
            }
            tarea.resume()
        }
        siguiente(faltan)
    }

    /// Borra la voz gratis del teléfono (se vuelve a bajar al elegirla).
    func borrarGratis() {
        PocketOnnx.soltar()
        try? FileManager.default.removeItem(at: carpetaGratis)
        gratis = .falta
    }
}
