import AVFoundation
import CryptoKit
import UIKit
import onnxruntime

/// La voz local de Claudio local y Maricarmen (Juan, 17-nov-2026). Las reglas están en VozKokoroReglas.swift y
/// FonemasES.swift (lógica pura, con pruebas); aquí lo que toca iOS:
/// · MotorVoz: una frase de texto → audio PCM de 16 bits. Dos motores: Kokoro (el modelo ONNX en el teléfono, con
///   onnxruntime, el mismo que ya trae sherpa-onnx para el Modo calle) y la voz del iPhone (AVSpeechSynthesizer).
/// · HablaPorFrases: dice un texto frase por frase con el motor del personaje; si Kokoro falla, no está o tarda, esa frase y
///   las que siguen van con la voz del iPhone, sin cortar la conversación.
/// · VocesLocales: los ajustes de cada personaje, la descarga del modelo y de las voces (con su suma de comprobación) y el
///   catálogo que se cambia sin otra versión de la app.
protocol MotorVoz: AnyObject {
    var nombre: String { get }
    /// Dice una frase: entrega el audio (PCM 16 bits mono a `hz`) en trozos y al final `fin(true)`; `fin(false)` si no pudo.
    /// Todo en el hilo principal.
    func sintetizar(_ frase: String, hz: Int, trozo: @escaping (Data) -> Void, fin: @escaping (Bool) -> Void)
    func cancelar()
}

// MARK: - La voz del iPhone

final class MotorIphone: MotorVoz {
    let nombre = "iphone"
    private let voz: AVSpeechSynthesisVoice?
    private let velocidad: Float, tono: Float, volumen: Float
    private let sintetizador = AVSpeechSynthesizer()
    private var convertidor: AVAudioConverter?
    private var vuelta = 0

    init(voz: AVSpeechSynthesisVoice?, ajustes a: ClaudioLocalReglas.Ajustes) {
        self.voz = voz; velocidad = a.velocidad; tono = a.tono; volumen = a.volumen
    }

    func sintetizar(_ frase: String, hz: Int, trozo: @escaping (Data) -> Void, fin: @escaping (Bool) -> Void) {
        vuelta += 1
        let mia = vuelta
        guard !frase.isEmpty, let formato = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(hz), channels: 1, interleaved: true) else { fin(true); return }
        let u = AVSpeechUtterance(string: frase)
        u.voice = voz; u.rate = velocidad; u.pitchMultiplier = tono; u.volume = volumen
        u.preUtteranceDelay = 0; u.postUtteranceDelay = 0
        let hecho = Bandera()
        sintetizador.write(u) { [weak self] b in
            guard let pcm = b as? AVAudioPCMBuffer else { return }
            let datos = pcm.frameLength > 0 ? self?.convertir(pcm, a: formato) : nil
            DispatchQueue.main.async {
                guard let self, self.vuelta == mia, !hecho.on else { return }
                if let d = datos, !d.isEmpty { trozo(d); return }
                guard pcm.frameLength == 0 else { return }
                hecho.on = true
                fin(true)
            }
        }
    }

    func cancelar() { vuelta += 1; sintetizador.stopSpeaking(at: .immediate) }

    /// Un trozo de la voz del iPhone (22 kHz o lo que traiga) a PCM de 16 bits en `hz`.
    private func convertir(_ b: AVAudioPCMBuffer, a formato: AVAudioFormat) -> Data? {
        if convertidor == nil || convertidor?.inputFormat != b.format || convertidor?.outputFormat != formato { convertidor = AVAudioConverter(from: b.format, to: formato) }
        guard let c = convertidor else { return nil }
        let cap = AVAudioFrameCount(Double(b.frameLength) * formato.sampleRate / b.format.sampleRate) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: formato, frameCapacity: cap) else { return nil }
        var dado = false
        c.convert(to: out, error: nil) { _, st in
            if dado { st.pointee = .noDataNow; return nil }
            dado = true; st.pointee = .haveData; return b
        }
        guard out.frameLength > 0, let p = out.int16ChannelData else { return nil }
        return Data(bytes: p[0], count: Int(out.frameLength) * 2)
    }
}

/// Un sí/no que se marca desde otro hilo y se lee en el principal.
final class Bandera { var on = false }

// MARK: - Kokoro

final class MotorKokoro: MotorVoz {
    let nombre = "kokoro"
    let ajustes: VozKokoroReglas.Ajustes
    private let tabla: [Float]
    private let excepciones: [String: String]
    private var vuelta = 0
    /// Lo que se anota: cuánto tardó cada frase (para saber si el teléfono va bien con Kokoro).
    var paso: ((String) -> Void)?

    init(ajustes: VozKokoroReglas.Ajustes, tabla: [Float], excepciones: [String: String]) {
        self.ajustes = ajustes; self.tabla = tabla; self.excepciones = excepciones
    }

    func sintetizar(_ frase: String, hz: Int, trozo: @escaping (Data) -> Void, fin: @escaping (Bool) -> Void) {
        vuelta += 1
        let mia = vuelta
        let tk = VozKokoroReglas.tokens(FonemasES.frase(frase, acento: ajustes.acento, excepciones: excepciones))
        guard !tk.isEmpty else { fin(true); return }   // solo signos: nada que decir
        let estilo = VozKokoroReglas.estilo(tabla, tokens: tk.count), velocidad = ajustes.velocidad
        let modelo = VocesLocales.shared.modeloURL.path
        let t0 = Date()
        KokoroOnnx.cola.async {
            let r: (Data?, String)
            do {
                let m = try KokoroOnnx.abrir(modelo).generar(tokens: tk, estilo: estilo, velocidad: velocidad)
                r = (VozKokoroReglas.pcm16(m, a: hz), "")
            } catch { r = (nil, "\(error)") }
            let (datos, falla) = r
            DispatchQueue.main.async { [weak self] in
                guard let self, self.vuelta == mia else { return }
                guard let d = datos, !d.isEmpty else { self.paso?("Kokoro no pudo: " + (falla.isEmpty ? "sin audio" : falla)); fin(false); return }
                self.paso?(String(format: "Kokoro: %.1f s de voz en %.1f s", Double(d.count / 2) / Double(hz), Date().timeIntervalSince(t0)))
                for t in VozKokoroReglas.trozos(d, hz: hz) { trozo(t) }
                fin(true)
            }
        }
    }

    func cancelar() { vuelta += 1 }
}

/// El modelo de Kokoro abierto con onnxruntime (la API de C). Uno para toda la app, siempre en `cola`.
final class KokoroOnnx {
    enum Falla: Error, CustomStringConvertible {
        case sinApi, onnx(String), sinSalida
        var description: String {
            switch self { case .sinApi: return "onnxruntime no está"; case .onnx(let m): return m; case .sinSalida: return "el modelo no devolvió audio" }
        }
    }

    static let cola = DispatchQueue(label: "alma.kokoro", qos: .userInitiated)
    private static var abierto: KokoroOnnx?

    /// El modelo listo para usar (lo abre la primera vez, ~1 s). Solo desde `cola`.
    static func abrir(_ ruta: String) throws -> KokoroOnnx {
        if let k = abierto, k.ruta == ruta { return k }
        abierto = nil
        let k = try KokoroOnnx(ruta)
        abierto = k
        return k
    }
    /// Suelta la memoria del modelo (iOS pide memoria o se borró el modelo); se vuelve a abrir al hablar.
    static func soltar() { cola.async { abierto = nil } }

    let ruta: String
    private let api: UnsafePointer<OrtApi>
    private var env: OpaquePointer?
    private var sesion: OpaquePointer?
    private var memoria: OpaquePointer?

    private init(_ ruta: String) throws {
        self.ruta = ruta
        guard let base = OrtGetApiBase(), let dame = base.pointee.GetApi, let a = dame(UInt32(ORT_API_VERSION)) else { throw Falla.sinApi }
        api = a
        try revisar(api.pointee.CreateEnv!(ORT_LOGGING_LEVEL_WARNING, "kokoro", &env))
        var opciones: OpaquePointer?
        try revisar(api.pointee.CreateSessionOptions!(&opciones))
        defer { api.pointee.ReleaseSessionOptions!(opciones) }
        try revisar(api.pointee.CreateSession!(env, ruta, opciones, &sesion))
        try revisar(api.pointee.CreateCpuMemoryInfo!(OrtArenaAllocator, OrtMemTypeDefault, &memoria))
    }

    deinit {
        if let m = memoria { api.pointee.ReleaseMemoryInfo!(m) }
        if let s = sesion { api.pointee.ReleaseSession!(s) }
        if let e = env { api.pointee.ReleaseEnv!(e) }
    }

    /// Fonemas (sin los ceros de los bordes), la fila del estilo (256) y la velocidad → la voz (−1…1, 24 kHz).
    func generar(tokens: [Int64], estilo: [Float], velocidad: Float) throws -> [Float] {
        let ids = [0] + tokens + [0]
        let pIds = UnsafeMutablePointer<Int64>.allocate(capacity: ids.count)
        let pEstilo = UnsafeMutablePointer<Float>.allocate(capacity: estilo.count)
        let pVel = UnsafeMutablePointer<Float>.allocate(capacity: 1)
        pIds.initialize(from: ids, count: ids.count)
        pEstilo.initialize(from: estilo, count: estilo.count)
        pVel.initialize(to: velocidad)
        var vIds: OpaquePointer?, vEstilo: OpaquePointer?, vVel: OpaquePointer?, salida: OpaquePointer?
        defer {
            for v in [vIds, vEstilo, vVel, salida] { if let v { api.pointee.ReleaseValue!(v) } }
            pIds.deallocate(); pEstilo.deallocate(); pVel.deallocate()
        }
        let fIds: [Int64] = [1, Int64(ids.count)], fEstilo: [Int64] = [1, Int64(estilo.count)], fVel: [Int64] = [1]
        try revisar(api.pointee.CreateTensorWithDataAsOrtValue!(memoria, pIds, ids.count * 8, fIds, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, &vIds))
        try revisar(api.pointee.CreateTensorWithDataAsOrtValue!(memoria, pEstilo, estilo.count * 4, fEstilo, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &vEstilo))
        try revisar(api.pointee.CreateTensorWithDataAsOrtValue!(memoria, pVel, 4, fVel, 1, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &vVel))
        // Los nombres del modelo de onnx-community (fijo por su suma de comprobación).
        try "input_ids".withCString { n1 in
            try "style".withCString { n2 in
                try "speed".withCString { n3 in
                    try "waveform".withCString { o1 in
                        let entradas: [UnsafePointer<CChar>?] = [n1, n2, n3]
                        let valores: [OpaquePointer?] = [vIds, vEstilo, vVel]
                        let salidas: [UnsafePointer<CChar>?] = [o1]
                        try revisar(api.pointee.Run!(sesion, nil, entradas, valores, 3, salidas, 1, &salida))
                    }
                }
            }
        }
        guard let valor = salida else { throw Falla.sinSalida }
        var info: OpaquePointer?
        try revisar(api.pointee.GetTensorTypeAndShape!(valor, &info))
        defer { if let info { api.pointee.ReleaseTensorTypeAndShapeInfo!(info) } }
        var n = 0
        try revisar(api.pointee.GetTensorShapeElementCount!(info, &n))
        var datos: UnsafeMutableRawPointer?
        try revisar(api.pointee.GetTensorMutableData!(valor, &datos))
        guard let p = datos, n > 0 else { throw Falla.sinSalida }
        return Array(UnsafeBufferPointer(start: p.assumingMemoryBound(to: Float.self), count: n))
    }

    private func revisar(_ s: OpaquePointer?) throws {
        guard let s else { return }
        let m = api.pointee.GetErrorMessage!(s).map { String(cString: $0) } ?? "error de onnxruntime"
        api.pointee.ReleaseStatus!(s)
        throw Falla.onnx(m)
    }
}

// MARK: - Hablar por frases, con respaldo

/// Dice un texto frase por frase: con Kokoro si el personaje lo tiene y está listo; si falla, no está o tarda más de lo que
/// aguanta la conversación, esa frase y las que siguen con la voz del iPhone. Todo en el hilo principal.
final class HablaPorFrases {
    private let principal: MotorVoz?
    private let respaldo: MotorVoz
    private let hz: Int
    /// Lo que se anota (también cuánto tarda Kokoro por frase).
    var paso: ((String) -> Void)? { didSet { (principal as? MotorKokoro)?.paso = paso } }
    /// Hasta cuándo suena lo que ya se entregó (para saber cuándo volver a escuchar).
    private(set) var finCola: Date?

    private var frases: [String] = []
    private var indice = 0, intento = 0, lentas = 0
    private var conPrincipal = false, esPrincipal = false
    private var inicioFrase = Date(), audioFrase = 0.0
    private var reloj: Timer?
    private var alTrozo: ((Data) -> Void)?, alFin: (() -> Void)?

    init(principal: MotorVoz?, respaldo: MotorVoz, hz: Int) {
        self.principal = principal; self.respaldo = respaldo; self.hz = hz
    }

    var conKokoro: Bool { principal != nil && lentas < VozKokoroReglas.maxLentas }

    func decir(_ texto: String, trozo: @escaping (Data) -> Void, fin: @escaping () -> Void) {
        cancelar()
        frases = VozKokoroReglas.frases(texto)
        indice = 0
        conPrincipal = conKokoro
        alTrozo = trozo; alFin = fin
        siguiente()
    }

    func cancelar() {
        intento += 1
        reloj?.invalidate(); reloj = nil
        principal?.cancelar(); respaldo.cancelar()
        alTrozo = nil; alFin = nil
    }

    private func siguiente() {
        reloj?.invalidate(); reloj = nil
        intento += 1
        let mio = intento
        guard indice < frases.count else { let f = alFin; alTrozo = nil; alFin = nil; f?(); return }
        let motor: MotorVoz = conPrincipal ? (principal ?? respaldo) : respaldo
        esPrincipal = motor === principal
        inicioFrase = Date(); audioFrase = 0
        if esPrincipal {
            let enCola = max(0, (finCola ?? Date()).timeIntervalSinceNow)
            let limite = VozKokoroReglas.limite(primeraFrase: indice == 0, enCola: enCola)
            reloj = Timer.scheduledTimer(withTimeInterval: limite, repeats: false) { [weak self] _ in self?.vencio(mio, limite) }
        }
        motor.sintetizar(frases[indice], hz: hz, trozo: { [weak self] d in self?.llego(d, mio) }, fin: { [weak self] ok in self?.termino(ok, mio) })
    }

    private func llego(_ d: Data, _ mio: Int) {
        guard mio == intento else { return }
        let dura = Double(d.count / 2) / Double(hz)
        audioFrase += dura
        finCola = VozKokoroReglas.finCola(finCola, ahora: Date(), dura: dura)
        alTrozo?(d)
    }

    private func termino(_ ok: Bool, _ mio: Int) {
        guard mio == intento else { return }
        if esPrincipal {
            if !ok { conPrincipal = false; paso?("Kokoro falló: sigue la voz del iPhone"); siguiente(); return }
            if VozKokoroReglas.lenta(segundos: Date().timeIntervalSince(inicioFrase), audio: audioFrase) && indice > 0 {
                lentas += 1
                if lentas >= VozKokoroReglas.maxLentas { conPrincipal = false; paso?("Kokoro va lento en este teléfono: en esta conversación sigue la voz del iPhone") }
            } else { lentas = 0 }
        }
        indice += 1
        siguiente()
    }

    private func vencio(_ mio: Int, _ limite: Double) {
        guard mio == intento else { return }
        principal?.cancelar()
        conPrincipal = false
        lentas += 1
        paso?(String(format: "Kokoro tardó más de %.1f s: esta frase y las que siguen, con la voz del iPhone", limite))
        siguiente()
    }
}

// MARK: - Los ajustes, el modelo y las voces en el teléfono

final class VocesLocales: ObservableObject {
    static let shared = VocesLocales()

    enum Estado: Equatable { case falta, bajando(Double), listo, error(String) }
    @Published private(set) var modelo: Estado = .falta
    @Published private(set) var voces: [VozKokoroReglas.Voz] = VozKokoroReglas.incluidas
    @Published private(set) var bajandoVoz: Set<String> = []
    @Published private(set) var errorVoz: String?
    @Published private(set) var porPersonaje: [VozKokoroReglas.Personaje: VozKokoroReglas.Ajustes] = [:]
    private(set) var pronunciaciones: [String: String] = [:]
    private var tablas: [String: [Float]] = [:]
    private var observaProgreso: NSKeyValueObservation?
    private var tareaModelo: URLSessionDownloadTask?

    let carpeta: URL
    var modeloURL: URL { carpeta.appendingPathComponent("model_quantized.onnx") }
    func archivoVoz(_ id: String) -> URL { carpeta.appendingPathComponent("voces", isDirectory: true).appendingPathComponent(id + ".bin") }
    private var catalogoLocal: URL { carpeta.appendingPathComponent("catalogo.json") }
    private static let clavePropias = "voz_local_propias"

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        carpeta = base.appendingPathComponent("Kokoro", isDirectory: true)
        try? FileManager.default.createDirectory(at: carpeta.appendingPathComponent("voces", isDirectory: true), withIntermediateDirectories: true)
        var c = carpeta
        var v = URLResourceValues(); v.isExcludedFromBackup = true
        try? c.setResourceValues(v)
        for p in VozKokoroReglas.Personaje.allCases {
            porPersonaje[p] = VozKokoroReglas.leer(UserDefaults.standard.dictionary(forKey: "voz_local_" + p.rawValue), p)
        }
        modelo = modeloListo ? .listo : .falta
        cargarCatalogo(try? Data(contentsOf: catalogoLocal))
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
            KokoroOnnx.soltar()
        }
    }

    // MARK: Ajustes

    func ajustes(_ p: VozKokoroReglas.Personaje) -> VozKokoroReglas.Ajustes { porPersonaje[p] ?? VozKokoroReglas.deFabrica(p) }

    func poner(_ a: VozKokoroReglas.Ajustes, para p: VozKokoroReglas.Personaje) {
        porPersonaje[p] = a
        UserDefaults.standard.set(VozKokoroReglas.guardar(a), forKey: "voz_local_" + p.rawValue)
        if a.motor == .kokoro && !vozLista(a.voz) { descargarVoz(a.voz, celular: true) }
    }

    // MARK: Lo que pide ClaudioLocal

    var modeloListo: Bool {
        ((try? FileManager.default.attributesOfItem(atPath: modeloURL.path)[.size]) as? NSNumber)?.intValue == VozKokoroReglas.modeloBytes
    }
    func vozLista(_ id: String) -> Bool { FileManager.default.fileExists(atPath: archivoVoz(id).path) }

    /// El motor Kokoro del personaje, si lo tiene elegido y ya está todo en el teléfono; si no, nil (la voz del iPhone). Si
    /// falta algo, se baja por Wi-Fi para la próxima vez.
    func motor(para p: VozKokoroReglas.Personaje) -> MotorKokoro? {
        let a = ajustes(p)
        guard a.motor == .kokoro else { return nil }
        actualizarCatalogo()
        guard VozKokoroReglas.usarKokoro(a, modeloListo: modeloListo, vozLista: vozLista(a.voz), lentas: 0), let t = tabla(a.voz) else {
            if !modeloListo { descargarModelo(celular: false) }
            if !vozLista(a.voz) { descargarVoz(a.voz, celular: false) }
            return nil
        }
        return MotorKokoro(ajustes: a, tabla: t, excepciones: pronunciaciones)
    }

    func tabla(_ id: String) -> [Float]? {
        if let t = tablas[id] { return t }
        guard let d = try? Data(contentsOf: archivoVoz(id)), let t = VozKokoroReglas.estilos(d) else { return nil }
        tablas[id] = t
        return t
    }

    // MARK: El modelo

    /// Baja el modelo (~92 MB). Con `celular` false, solo por Wi-Fi (cuando lo pide una conversación, no Juan).
    func descargarModelo(celular: Bool) {
        if modeloListo { modelo = .listo; return }
        if case .bajando = modelo { return }
        guard let u = URL(string: VozKokoroReglas.modeloURL) else { return }
        modelo = .bajando(0)
        var r = URLRequest(url: u)
        r.allowsExpensiveNetworkAccess = celular; r.allowsConstrainedNetworkAccess = celular; r.timeoutInterval = 60
        let destino = modeloURL
        let tarea = URLSession.shared.downloadTask(with: r) { [weak self] tmp, resp, err in
            let problema: String? = {
                guard let tmp, (resp as? HTTPURLResponse)?.statusCode == 200 else {
                    return err.map { ($0 as NSError).code == NSURLErrorNotConnectedToInternet ? "sin internet" : $0.localizedDescription } ?? "no se pudo bajar"
                }
                guard VocesLocales.sha256(tmp) == VozKokoroReglas.modeloSHA else { return "el archivo no coincide con su suma de comprobación" }
                try? FileManager.default.removeItem(at: destino)
                return (try? FileManager.default.moveItem(at: tmp, to: destino)) == nil ? "no se pudo guardar" : nil
            }()
            DispatchQueue.main.async {
                guard let self else { return }
                self.observaProgreso = nil; self.tareaModelo = nil
                self.modelo = self.modeloListo ? .listo : .error(problema ?? "no se pudo bajar")
            }
        }
        observaProgreso = tarea.progress.observe(\.fractionCompleted) { [weak self] p, _ in
            let f = p.fractionCompleted
            DispatchQueue.main.async { if case .bajando = self?.modelo { self?.modelo = .bajando(f) } }
        }
        tareaModelo = tarea
        tarea.resume()
    }

    /// Borra el modelo y las voces bajadas (se vuelven a bajar al elegir Kokoro).
    func borrar() {
        tareaModelo?.cancel(); tareaModelo = nil; observaProgreso = nil
        KokoroOnnx.soltar()
        try? FileManager.default.removeItem(at: modeloURL)
        try? FileManager.default.removeItem(at: carpeta.appendingPathComponent("voces", isDirectory: true))
        try? FileManager.default.createDirectory(at: carpeta.appendingPathComponent("voces", isDirectory: true), withIntermediateDirectories: true)
        tablas = [:]
        modelo = .falta
    }

    // MARK: Las voces

    /// Baja una voz del catálogo y la guarda como .bin (si era .npy, se convierte). Con suma de comprobación si la trae.
    func descargarVoz(_ id: String, celular: Bool) {
        guard !bajandoVoz.contains(id), let v = voces.first(where: { $0.id == id }), let u = URL(string: v.url) else { return }
        bajandoVoz.insert(id); errorVoz = nil
        var r = URLRequest(url: u)
        r.allowsExpensiveNetworkAccess = celular; r.allowsConstrainedNetworkAccess = celular; r.timeoutInterval = 30
        let destino = archivoVoz(id)
        URLSession.shared.dataTask(with: r) { [weak self] data, resp, _ in
            let problema: String? = {
                guard let data, (resp as? HTTPURLResponse)?.statusCode == 200 else { return "no se pudo bajar la voz \(id)" }
                if let s = v.sha256, SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() != s { return "la voz \(id) no coincide con su suma" }
                guard let t = VozKokoroReglas.estilos(data) else { return "la voz \(id) no es un estilo de Kokoro (510 × 256)" }
                let bin = t.withUnsafeBufferPointer { Data(buffer: $0) }
                return (try? bin.write(to: destino, options: .atomic)) == nil ? "no se pudo guardar la voz \(id)" : nil
            }()
            DispatchQueue.main.async {
                guard let self else { return }
                self.bajandoVoz.remove(id)
                self.tablas[id] = nil
                self.errorVoz = problema
            }
        }.resume()
    }

    /// Una voz propia por enlace (https a un .bin o .npy de 510 × 256): queda en el catálogo de este teléfono.
    func agregarVoz(enlace: String, nombre: String, acento: FonemasES.Acento) -> String? {
        let e = enlace.trimmingCharacters(in: .whitespacesAndNewlines)
        guard e.hasPrefix("https://"), let u = URL(string: e) else { return "El enlace debe empezar con https://" }
        let base = u.deletingPathExtension().lastPathComponent.lowercased().filter { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "_" || $0 == "-" }
        let id = String(("propia_" + base).prefix(40))
        guard VozKokoroReglas.idValido(id) else { return "El nombre del archivo no sirve" }
        var propias = UserDefaults.standard.array(forKey: Self.clavePropias) as? [[String: Any]] ?? []
        propias.removeAll { ($0["id"] as? String) == id }
        propias.append(["id": id, "url": e, "nombre": nombre.isEmpty ? id : nombre, "acento": acento.rawValue])
        UserDefaults.standard.set(propias, forKey: Self.clavePropias)
        cargarCatalogo(try? Data(contentsOf: catalogoLocal))
        descargarVoz(id, celular: true)
        return nil
    }

    // MARK: El catálogo (cambia sin otra versión de la app)

    private var catalogoPedido: Date?
    /// Lo pide a lo mucho cada 6 horas; lo guarda para usarlo sin internet.
    func actualizarCatalogo() {
        if let c = catalogoPedido, Date().timeIntervalSince(c) < 6 * 3600 { return }
        catalogoPedido = Date()
        guard let u = URL(string: VozKokoroReglas.catalogoURL) else { return }
        var r = URLRequest(url: u); r.timeoutInterval = 15; r.cachePolicy = .reloadIgnoringLocalCacheData
        let local = catalogoLocal
        URLSession.shared.dataTask(with: r) { [weak self] data, resp, _ in
            guard let data, (resp as? HTTPURLResponse)?.statusCode == 200, (try? JSONSerialization.jsonObject(with: data)) != nil else { return }
            try? data.write(to: local, options: .atomic)
            DispatchQueue.main.async { self?.cargarCatalogo(data) }
        }.resume()
    }

    private func cargarCatalogo(_ json: Data?) {
        let c = VozKokoroReglas.catalogo(json)
        var vs = c.voces
        let propias = UserDefaults.standard.array(forKey: Self.clavePropias) as? [[String: Any]] ?? []
        if let pj = try? JSONSerialization.data(withJSONObject: ["voces": propias]) {
            for v in VozKokoroReglas.catalogo(pj).voces where !VozKokoroReglas.incluidas.contains(where: { $0.id == v.id }) {
                if let i = vs.firstIndex(where: { $0.id == v.id }) { vs[i] = v } else { vs.append(v) }
            }
        }
        voces = vs
        pronunciaciones = c.pronunciaciones
    }

    // MARK: Suma de comprobación (por partes: el modelo pesa ~92 MB)

    static func sha256(_ u: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: u) else { return nil }
        defer { try? h.close() }
        var s = SHA256()
        while true {
            guard let d = (try? h.read(upToCount: 1 << 20)) ?? nil, !d.isEmpty else { break }
            s.update(data: d)
        }
        return s.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
