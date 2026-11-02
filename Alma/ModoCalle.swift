import AVFoundation
import Speech
import SherpaOnnx
import UIKit

/// Modo calle (issue #50): el teléfono bloqueado en la bolsa, audífonos puestos, caminando.
///   · Mientras espera, solo un detector liviano en el teléfono escucha la palabra «Alma» (sherpa-onnx, código abierto y
///     gratis, DetectorAlma). No transcribe todo, no graba, no sube nada y no gasta tokens. El audio se mezcla con las otras
///     apps: TikTok, la música o Claude siguen sonando.
///   · El detector deja pasar de más a propósito (para no perderse un «Alma»). Cada vez que cree oírla, el dictado del iPhone
///     (en el teléfono) revisa en silencio los últimos 2 s: solo si de verdad dice «Alma» suena la señal. Si no, nada.
///   · Después de «Alma»: el dictado escucha solo la frase que sigue, hasta una pausa (1,2 s; 12 s como mucho), y la manda al
///     Hub (acción «calle»). Alma contesta corto y hablado («Listo, …»). Si hace falta conversar, se abre la llamada real de
///     ElevenLabs y, al colgar, el Modo calle vuelve a esperar.
///   · Avisos hablados: lo importante que llega del Hub (vozAvisos) Alma lo dice al oído y escucha 8 s la respuesta, sin
///     «Alma». También con la app abierta (inicio o conferencia). Los niveles están en NivelAvisos.
///   · Se enciende con la app a la vista (iOS no deja abrir el micrófono con el teléfono bloqueado) y sigue bloqueado.
///   · No va junto con el modo conferencia ni con el Modo Inicio: encender uno apaga el otro.
///   · Medición (T3): cada sesión guarda minutos, batería al empezar y al terminar, despertares y falsos despertares; al
///     apagarlo se manda el resumen al Hub (acción «calleUso») y queda en el teléfono (`calle_usos`).
final class ModoCalle: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    static let shared = ModoCalle()
    var alEvento: (([String: Any]) -> Void)?

    /// quieta: sin micrófono · esperando: solo el detector · verificando: el dictado revisa si dijeron «Alma» ·
    /// oyendo: escucha la frase · pensando: espera al Hub · hablando: Alma contesta · llamada: la llamada real ·
    /// pausa: iOS quitó el micrófono (otra llamada, por ejemplo) y se espera para volver.
    enum Fase: String { case quieta, esperando, verificando, oyendo, pensando, hablando, llamada, pausa }
    private(set) var encendido = false
    private(set) var fase: Fase = .quieta { didSet { if fase != oldValue { emitir() } } }
    /// Un aviso hablado con la app abierta (sin el Modo calle): usa el micrófono solo mientras lo dice y escucha la respuesta.
    private var temporal = false
    /// ¿Ocupa el micrófono? Entonces el Modo Inicio no abre otro y el audio no se suelta.
    var ocupaMicrofono: Bool { encendido || temporal }

    // MARK: - El micrófono

    private var motor = AVAudioEngine()          // se rehace si iOS reinicia el audio (mediaServicesWereReset)
    private var micAbierto = false
    /// Escucha por el micrófono de la voz (VozNativa, ya abierto con «Alma con el anillo») en vez de abrir otro.
    private var compartido = false
    private let candado = NSLock()               // lo de abajo también lo usa el hilo del micrófono
    private var alimentarDetector = false
    private var previo: [AVAudioPCMBuffer] = []  // los últimos 2 s (solo en memoria): con ellos se revisa si dijeron «Alma»
    private var previoSeg = 0.0
    private var pedido: SFSpeechAudioBufferRecognitionRequest?
    private var convertidor: AVAudioConverter?   // solo en el hilo del micrófono
    private var formatoConvertidor: AVAudioFormat?
    private let formato16k = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    // MARK: - El detector (en su propia cola)

    private let colaDetector = DispatchQueue(label: "com.spacioam.alma.calle", qos: .userInitiated)
    private var detector: DetectorAlma?          // solo en colaDetector
    private var detectorListo = false            // en el hilo principal

    // MARK: - El dictado de la frase

    private let reconocedor = SFSpeechRecognizer(locale: Locale(identifier: "es-MX"))
    private var tarea: SFSpeechRecognitionTask?
    private var vuelta = 0
    private var textoAlma: String?               // la versión del dictado donde se oyó «Alma»
    private var textoMejor = ""
    private var ultimoCambio = Date(), desde = Date()
    private var avisoActual: String?             // se responde a un aviso: se escucha sin «Alma»
    private var reloj: Timer?
    private var reintentos = 0
    private var hubSinCalle = false              // el Hub todavía no tiene la acción «calle»: se usa el chat
    private var llamadaVista = false, llamadaDesde = Date()

    // MARK: - La voz

    private let sintetizador = AVSpeechSynthesizer()
    private var reproductor: AVAudioPlayer?
    private var trasHablar: (() -> Void)?

    // MARK: - Medición (T3)

    private struct Uso {
        var inicio = Date()
        var bateriaInicio: Int?
        var gatillos = 0, despertares = 0, descartes = 0, falsos = 0, pedidos = 0, llamadas = 0, avisos = 0, errores = 0
    }
    private var uso = Uso()

    // MARK: - Avisos hablados

    private var colaAvisos: [(id: String, texto: String)] = []
    private var relojAvisos: Timer?

    private override init() {
        super.init()
        sintetizador.delegate = self
        let nc = NotificationCenter.default
        // Otra app (o una llamada de teléfono) tomó el audio: se suelta y, cuando lo devuelve, se vuelve a esperar «Alma».
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, self.ocupaMicrofono, self.fase != .llamada, let t = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
            if t == AVAudioSession.InterruptionType.began.rawValue {
                if self.temporal { self.terminarTemporal(); return }
                self.cerrarEscucha(); self.callar(); self.cerrarMicrofono(); self.fase = .pausa
            } else { self.reabrir(tras: 0.6) }
        }
        // Se conectaron o quitaron los audífonos (o iOS reacomodó el audio): el motor se detiene solo; se vuelve a abrir.
        nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] n in
            guard let self, let e = n.object as? AVAudioEngine, e === self.motor, self.micAbierto, !self.compartido else { return }
            self.reabrir(tras: 0.3)
        }
        // iOS reinició el audio: el motor viejo ya no sirve; se hace otro.
        nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.micAbierto = false; self.motor = AVAudioEngine()
            if self.ocupaMicrofono { self.reabrir(tras: 1) }
        }
        // Al volver a la app con el Modo calle en pausa (iOS no dejó volver a abrir el micrófono bloqueado), se reintenta.
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.encendido, self.fase == .pausa else { return }
            self.reintentos = 0; self.reabrir(tras: 0.3)
        }
    }

    // MARK: - Encender y apagar

    var resumen: [String: Any] {
        var r: [String: Any] = ["tipo": "calle", "activa": encendido, "fase": fase.rawValue]
        if encendido {
            r["minutos"] = Int(Date().timeIntervalSince(uso.inicio) / 60)
            r["despertares"] = uso.despertares; r["falsos"] = uso.falsos; r["pedidos"] = uso.pedidos
        }
        r["usos"] = Array((UserDefaults.standard.array(forKey: "calle_usos") ?? []).suffix(5))
        return r
    }

    func poner(_ on: Bool) { if on { encender() } else { apagar() } }

    /// alma://calle?on=1 · alma://calle?on=0 · alma://calle (cambia): para un atajo de iOS.
    func abrirEnlace(_ u: URL) {
        let on = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "on" })?.value
        if on == "1" { poner(true) } else if on == "0" { poner(false) } else { poner(!encendido) }
    }

    /// Ajustar el detector sin otra versión de la app (para calibrar en la calle): la línea de «Alma» en sonidos del
    /// modelo, el umbral y el puntaje. Vacío = lo de fábrica (DetectorAlma).
    func calibrar(linea: String?, umbral: Double?, puntaje: Double?) {
        let d = UserDefaults.standard
        if let l = linea { if l.trimmingCharacters(in: .whitespaces).isEmpty { d.removeObject(forKey: "calle_kws_linea") } else { d.set(l, forKey: "calle_kws_linea") } }
        if let u = umbral { if u <= 0 { d.removeObject(forKey: "calle_kws_umbral") } else { d.set(u, forKey: "calle_kws_umbral") } }
        if let p = puntaje { if p <= 0 { d.removeObject(forKey: "calle_kws_puntaje") } else { d.set(p, forKey: "calle_kws_puntaje") } }
        // El detector se vuelve a cargar con lo nuevo.
        detectorListo = false
        colaDetector.async { [weak self] in self?.detector = nil }
        if encendido { apagar(); encender() }
    }

    private func encender() {
        guard !encendido else { emitir(); return }
        guard UIApplication.shared.applicationState != .background else {
            fallar("Abre Alma para encender el Modo calle: con el teléfono bloqueado iOS no deja abrir el micrófono."); return
        }
        SFSpeechRecognizer.requestAuthorization { st in
            AVAudioSession.sharedInstance().requestRecordPermission { mic in
                DispatchQueue.main.async {
                    guard st == .authorized, mic, self.reconocedor?.isAvailable == true else {
                        self.fallar("Activa el micrófono y el reconocimiento de voz para Alma en Ajustes del iPhone."); return
                    }
                    self.cargarDetector { ok in
                        guard ok else { self.fallar("Esta versión de Alma no trae el detector de «Alma». Actualiza la app."); return }
                        self.arrancar()
                    }
                }
            }
        }
    }

    private func cargarDetector(_ listo: @escaping (Bool) -> Void) {
        if detectorListo { listo(true); return }
        let (linea, umbral, puntaje) = DetectorAlma.ajustes()
        colaDetector.async { [weak self] in
            let d = DetectorAlma(linea: linea, umbral: umbral, puntaje: puntaje)
            self?.detector = d
            let ok = d != nil
            DispatchQueue.main.async { self?.detectorListo = ok; listo(ok) }
        }
    }

    private func arrancar() {
        guard !encendido else { return }
        if temporal { terminarTemporal() }
        encendido = true   // antes de apagar los otros modos: así no sueltan el audio ni vuelven a escuchar
        if Conferencia.shared.activa { Conferencia.shared.poner(false) }
        EscuchaInicio.shared.detener()
        uso = Uso()
        UIDevice.current.isBatteryMonitoringEnabled = true
        uso.bateriaInicio = ModoCalle.bateria()
        reintentos = 0
        guard abrirMicrofono() else {
            encendido = false; cerrarMicrofono(); UIDevice.current.isBatteryMonitoringEnabled = false
            fallar("No pude abrir el micrófono. Intenta de nuevo."); return
        }
        volverAEsperar()
        emitir()
    }

    private func apagar() {
        guard encendido else { emitir(); return }
        encendido = false
        reloj?.invalidate(); reloj = nil
        cerrarEscucha(); callar(); cerrarMicrofono()
        if fase == .llamada { VozNativa.shared.desdeCalle = false }   // la llamada sigue; al colgar ya no vuelve al Modo calle
        fase = .quieta
        // El detector se suelta (unos MB de memoria) hasta la próxima vez.
        detectorListo = false
        colaDetector.async { [weak self] in self?.detector = nil }
        cerrarUso()
        UIDevice.current.isBatteryMonitoringEnabled = false
        VozNativa.soltarAudio()            // avisa a las otras apps (notifyOthersOnDeactivation) si nadie más escucha
        EscuchaInicio.shared.evaluar()     // de vuelta al Modo Inicio si está a la vista
        emitir()
    }

    private func fallar(_ m: String) {
        if encendido { uso.errores += 1 }
        alEvento?(["tipo": "calle", "activa": encendido, "fase": fase.rawValue, "error": m])
    }

    // MARK: - Abrir y cerrar el micrófono

    /// Abre el micrófono (el de la voz si ya está abierto, o el propio con la sesión que se mezcla). Con la app a la vista
    /// se usa VozNativa.sesionEscucha (suelta antes una sesión que no se mezcla, avisando a las otras apps); bloqueado solo
    /// se cambia la categoría: soltar el audio con el teléfono bloqueado haría que iOS no deje volver a abrir el micrófono.
    private func abrirMicrofono() -> Bool {
        let voz = VozNativa.shared
        candado.lock(); convertidor = nil; formatoConvertidor = nil; candado.unlock()
        if voz.microfonoListo {
            compartido = true
            voz.ponerOyente("calle") { [weak self] b in self?.oir(b) }
            micAbierto = true; return true
        }
        compartido = false
        let s = AVAudioSession.sharedInstance()
        if temporal {
            // Aviso con la app abierta: las otras apps bajan el volumen mientras Alma habla y escucha; vuelven al soltar el audio.
            try? s.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker, .allowBluetoothA2DP])
            try? s.setActive(true)
        } else if UIApplication.shared.applicationState == .active {
            VozNativa.sesionEscucha()
        } else {
            try? s.setCategory(.playAndRecord, mode: .default, options: VozNativa.opcionesEscucha)
            try? s.setActive(true)
        }
        let entrada = motor.inputNode, f = entrada.outputFormat(forBus: 0)
        guard f.sampleRate > 0, f.channelCount > 0 else { return false }
        entrada.removeTap(onBus: 0)
        // Trozos de ~85 ms: menos despertares del procesador que con trozos chicos.
        entrada.installTap(onBus: 0, bufferSize: 4096, format: f) { [weak self] b, _ in self?.oir(b) }
        motor.prepare()
        do { try motor.start() } catch { entrada.removeTap(onBus: 0); return false }
        micAbierto = true
        return true
    }

    private func cerrarMicrofono() {
        candado.lock(); alimentarDetector = false; let p = pedido; pedido = nil; previo = []; previoSeg = 0; candado.unlock()
        p?.endAudio()
        if compartido { VozNativa.shared.quitarOyente("calle"); compartido = false }
        else if micAbierto { motor.inputNode.removeTap(onBus: 0); if motor.isRunning { motor.stop() } }
        micAbierto = false
    }

    /// Vuelve a abrir el micrófono (audífonos que cambian, una interrupción que terminó).
    private func reabrir(tras t: TimeInterval) {
        guard ocupaMicrofono, fase != .llamada else { return }
        if fase == .verificando || fase == .oyendo {
            cerrarEscucha()
            if temporal { terminarTemporal(); return }
            fase = .esperando
        }
        cerrarMicrofono()
        DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
            guard let self, self.ocupaMicrofono, self.fase != .llamada, !self.micAbierto else { return }
            if self.abrirMicrofono() {
                self.reintentos = 0
                if self.fase == .esperando || self.fase == .pausa { self.volverAEsperar() }
            } else { self.reintentar() }
        }
    }

    /// iOS no devolvió el micrófono: se reintenta unas veces; si no, queda en pausa y avisa.
    private func reintentar() {
        guard encendido else { if temporal { terminarTemporal() }; return }
        reintentos += 1
        fase = .pausa
        if reintentos <= 5 { reabrir(tras: 2); return }
        fallar("El Modo calle se detuvo: iOS no devolvió el micrófono.")
        Notificaciones.shared.mostrar(id: "calle-pausa", texto: "El Modo calle está en pausa. Abre Alma para que vuelva a esperar «Alma».")
    }

    // MARK: - Lo que oye el micrófono (hilo del micrófono)

    private func oir(_ b: AVAudioPCMBuffer) {
        guard let copia = ModoCalle.copiar(b) else { return }
        let seg = Double(copia.frameLength) / copia.format.sampleRate
        candado.lock()
        previo.append(copia); previoSeg += seg
        while previoSeg > 2.0, previo.count > 1 { let x = previo.removeFirst(); previoSeg -= Double(x.frameLength) / x.format.sampleRate }
        let p = pedido, alDetector = alimentarDetector
        let m = alDetector ? a16k(copia) : nil
        candado.unlock()
        p?.append(copia)
        if let m { colaDetector.async { [weak self] in self?.decodificar(m) } }
    }

    /// Copia el trozo: iOS reusa los suyos y aquí se guardan los últimos 2 s.
    private static func copiar(_ b: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard b.frameLength > 0, let src = b.floatChannelData,
              let c = AVAudioPCMBuffer(pcmFormat: b.format, frameCapacity: b.frameLength), let dst = c.floatChannelData else { return nil }
        c.frameLength = b.frameLength
        let n = Int(b.frameLength), canales = Int(b.format.channelCount)
        if b.format.isInterleaved { dst[0].update(from: src[0], count: n * canales) }
        else { for k in 0..<canales { dst[k].update(from: src[k], count: n) } }
        return c
    }

    /// A 16 kHz y un canal, como lo pide el detector (con `candado`).
    private func a16k(_ b: AVAudioPCMBuffer) -> [Float]? {
        if convertidor == nil || formatoConvertidor != b.format {
            convertidor = AVAudioConverter(from: b.format, to: formato16k); formatoConvertidor = b.format
            convertidor?.downmix = true
        }
        guard let conv = convertidor else { return nil }
        let cap = AVAudioFrameCount(Double(b.frameLength) * 16000 / b.format.sampleRate) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: formato16k, frameCapacity: cap) else { return nil }
        var dado = false
        conv.convert(to: out, error: nil) { _, st in
            if dado { st.pointee = .noDataNow; return nil }
            dado = true; st.pointee = .haveData; return b
        }
        guard out.frameLength > 0, let ch = out.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
    }

    /// El detector (en su cola): ¿sonó algo como «Alma»?
    private func decodificar(_ m: [Float]) {
        guard let d = detector, d.oir(m) else { return }
        DispatchQueue.main.async { [weak self] in self?.gatillo() }
    }

    // MARK: - «Alma» y la frase

    /// El detector cree que oyó «Alma»: el dictado lo revisa en silencio con los últimos 2 s.
    private func gatillo() {
        guard encendido, fase == .esperando else { return }
        uso.gatillos += 1
        empezarEscucha(conAlma: true, aviso: nil)
    }

    /// Empieza el dictado (en el teléfono). `conAlma`: primero revisa si dijeron «Alma» (con lo de los últimos 2 s);
    /// `aviso`: responde a un aviso y no hace falta «Alma».
    private func empezarEscucha(conAlma: Bool, aviso: String?) {
        tarea?.cancel(); tarea = nil
        let p = SFSpeechAudioBufferRecognitionRequest(); p.shouldReportPartialResults = true
        if reconocedor?.supportsOnDeviceRecognition == true { p.requiresOnDeviceRecognition = true }
        if #available(iOS 16, *) { p.addsPunctuation = true }
        p.contextualStrings = ["Alma"]   // que el reconocedor espere oír «Alma» (no «palma» ni «al ma»)
        candado.lock()
        alimentarDetector = false
        if conAlma { for b in previo { p.append(b) } }
        let viejo = pedido; pedido = p
        candado.unlock()
        viejo?.endAudio()
        colaDetector.async { [weak self] in self?.detector?.reiniciar() }
        vuelta += 1; let mia = vuelta
        textoAlma = nil; textoMejor = ""; avisoActual = aviso; ultimoCambio = Date(); desde = Date()
        fase = conAlma ? .verificando : .oyendo
        tarea = reconocedor?.recognitionTask(with: p) { [weak self] r, e in
            DispatchQueue.main.async {
                guard let self, self.vuelta == mia else { return }
                if let r {
                    let t = r.bestTranscription.formattedString
                    if t != self.textoMejor { self.textoMejor = t; self.ultimoCambio = Date() }
                    if let a = Conferencia.versionConAlma(r) { self.textoAlma = a }
                    if self.fase == .verificando, self.textoAlma != nil { self.confirmar() }
                    if r.isFinal { self.revisar(cerro: true) }
                } else if e != nil { self.revisar(cerro: true) }
            }
        }
        reloj?.invalidate()
        reloj = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.revisar(cerro: false) }
    }

    /// El dictado confirmó «Alma»: suena la señal y se escucha lo que pide.
    private func confirmar() {
        fase = .oyendo; desde = Date(); ultimoCambio = Date()
        uso.despertares += 1
        VozNativa.shared.senal()
    }

    /// Cada 0,2 s: ¿terminó la frase (pausa de 1,2 s)? ¿no era «Alma»? ¿nadie dijo nada?
    private func revisar(cerro: Bool) {
        let quieto = Date().timeIntervalSince(ultimoCambio), lleva = Date().timeIntervalSince(desde)
        switch fase {
        case .verificando:
            if cerro || lleva > 2.5 { cerrarEscucha(); uso.descartes += 1; volverAEsperar() }   // no era «Alma»: nada suena
        case .oyendo:
            let pide: String
            if avisoActual != nil { pide = textoMejor.trimmingCharacters(in: .whitespacesAndNewlines) }
            else { pide = textoAlma.flatMap { Conferencia.pedidoAAlma($0) } ?? "" }
            if !pide.isEmpty && (quieto > 1.2 || cerro || lleva > 12) { listo(pide); return }
            let espera: TimeInterval = avisoActual != nil ? 8 : 5
            if pide.isEmpty && (lleva > espera || cerro) { sinPedido() }
        default: break
        }
    }

    private func cerrarEscucha() {
        reloj?.invalidate(); reloj = nil
        vuelta += 1
        tarea?.cancel(); tarea = nil
        candado.lock(); let p = pedido; pedido = nil; candado.unlock()
        p?.endAudio()
    }

    /// Sonó la señal, pero no pidieron nada (o nadie respondió al aviso).
    private func sinPedido() {
        cerrarEscucha()
        if avisoActual != nil { avisoActual = nil }   // el aviso queda en Pendientes
        else { uso.falsos += 1; VozNativa.shared.sonar("alma-fin") }
        volverAEsperar()
    }

    /// La frase terminó: va al Hub.
    private func listo(_ pide: String) {
        cerrarEscucha()
        let aviso = avisoActual; avisoActual = nil
        if encendido { uso.pedidos += 1 }
        fase = .pensando
        preguntar(pide, aviso: aviso)
    }

    /// De vuelta a esperar «Alma» (o, si era un aviso con la app abierta, se suelta el micrófono).
    private func volverAEsperar() {
        if temporal { terminarTemporal(); return }
        guard encendido else { return }
        if !micAbierto { guard abrirMicrofono() else { reintentar(); return } }
        fase = .esperando
        colaDetector.async { [weak self] in self?.detector?.reiniciar() }
        // Un respiro: que el final de la voz de Alma (o la señal) no despierte al detector.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.encendido, self.fase == .esperando else { return }
            self.candado.lock(); self.alimentarDetector = true; self.candado.unlock()
            self.procesarAvisos()
        }
    }

    // MARK: - El Hub

    /// La frase al Hub: acción «calle» → { ok, hablar, conversar, audio? }. Si el Hub todavía no la tiene, va al chat con
    /// Alma (opEnviar, canal «calle») y se dice corto lo que contestó.
    private func preguntar(_ texto: String, aviso: String?) {
        if hubSinCalle { porChat(texto, aviso: aviso); return }
        var b: [String: Any] = ["texto": texto, "canal": "calle"]
        if let aviso { b["aviso_id"] = aviso }
        llamarHub(b, accion: "calle", timeout: 30) { [weak self] j in
            guard let self, self.ocupaMicrofono else { return }
            if let j, (j["ok"] as? Bool) == true {
                self.responder(hablar: j["hablar"] as? String ?? "", conversar: (j["conversar"] as? Bool) ?? false, audio: j["audio"] as? String, pedido: texto)
            } else if (j?["error"] as? String) == "accion" {
                self.hubSinCalle = true; self.porChat(texto, aviso: aviso)
            } else {
                if self.encendido { self.uso.errores += 1 }
                let e = (j?["error"] as? String).map { ModoCalle.corto($0, palabras: 20) } ?? ""
                self.responder(hablar: j == nil ? "No pude hablar con el Hub. Intenta otra vez." : (e.isEmpty ? "No pude hacerlo ahora." : e), conversar: false, audio: nil, pedido: texto)
            }
        }
    }

    private func porChat(_ texto: String, aviso: String?) {
        var t = texto
        if let aviso, let a = UserDefaults.standard.dictionary(forKey: "avisos_textos")?[aviso] as? String { t = "Sobre el aviso «\(a)»: \(texto)" }
        var b: [String: Any] = ["texto": t, "canal": "calle"]
        if let email = ModoCalle.correoDeSesion() { b["email"] = email }
        llamarHub(b, accion: "opEnviar", timeout: 90) { [weak self] j in
            guard let self, self.ocupaMicrofono else { return }
            let alma = (j?["alma"] as? [String: Any])?["texto"] as? String ?? ""
            if (j?["ok"] as? Bool) == true {
                self.responder(hablar: alma.isEmpty ? "Listo." : ModoCalle.corto(alma, palabras: 40), conversar: false, audio: nil, pedido: texto)
            } else {
                if self.encendido { self.uso.errores += 1 }
                self.responder(hablar: j == nil ? "No pude hablar con el Hub. Intenta otra vez." : "No pude hacerlo ahora.", conversar: false, audio: nil, pedido: texto)
            }
        }
    }

    private func responder(hablar: String, conversar: Bool, audio: String?, pedido: String) {
        let frase = hablar.isEmpty && !conversar && audio == nil ? "Listo." : hablar
        decir(frase, audio: audio) { [weak self] in
            guard let self, self.ocupaMicrofono else { return }
            if conversar { self.abrirLlamada(pedido) } else { self.volverAEsperar() }
        }
    }

    private func llamarHub(_ cuerpo: [String: Any], accion: String, timeout: TimeInterval, _ listo: @escaping ([String: Any]?) -> Void) {
        guard let url = Llave.leer("voz_url"), let token = Llave.leer("voz_token"), let sesion = Llave.leer("voz_sesion"), let u = URL(string: url) else {
            DispatchQueue.main.async { listo(nil) }; return
        }
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.timeoutInterval = timeout
        r.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        var b = cuerpo; b["hub"] = 1; b["action"] = accion; b["token"] = token; b["session"] = sesion; b["app"] = "alma"
        r.httpBody = try? JSONSerialization.data(withJSONObject: b)
        URLSession.shared.dataTask(with: r) { d, _, _ in
            let j = d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async { listo(j) }
        }.resume()
    }

    /// El correo de la sesión firmada (va dentro, en base64): el chat con Alma (opEnviar) lo pide.
    private static func correoDeSesion() -> String? {
        guard let s = Llave.leer("voz_sesion"), let i = s.lastIndex(of: ".") else { return nil }
        var b = String(s[..<i]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        guard let d = Data(base64Encoded: b), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        if let p = j["p"] as? [String: Any], let e = p["email"] as? String, !e.isEmpty { return e }
        return j["e"] as? String
    }

    /// Lo que se dice al oído: sin marcas del chat, la primera parte y corto (cortado en una frase si se puede).
    static func corto(_ t: String, palabras: Int) -> String {
        var s = t.replacingOccurrences(of: "[*_#`>]", with: "", options: .regularExpression)
        s = s.components(separatedBy: "\n\n").first ?? s
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        let p = s.split(separator: " ")
        guard p.count > palabras else { return s }
        let recorte = p.prefix(palabras).joined(separator: " ")
        if let fin = recorte.lastIndex(where: { ".!?".contains($0) }), recorte.distance(from: recorte.startIndex, to: fin) > 20 {
            return String(recorte[...fin])
        }
        return recorte + "…"
    }

    // MARK: - Hablar

    /// Alma contesta al oído: con su voz si el Hub mandó el audio; si no, con la voz del iPhone (es-MX, ritmo natural).
    private func decir(_ texto: String, audio: String?, luego: @escaping () -> Void) {
        fase = .hablando
        candado.lock(); alimentarDetector = false; candado.unlock()
        trasHablar = luego
        if let a = audio, let d = Data(base64Encoded: a), let p = try? AVAudioPlayer(data: d) {
            reproductor = p; p.delegate = self; p.volume = 1
            if p.play() { return }
            reproductor = nil
        }
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { terminoDeHablar(); return }
        let u = AVSpeechUtterance(string: t)
        u.voice = AVSpeechSynthesisVoice(language: "es-MX") ?? AVSpeechSynthesisVoice(language: "es-ES")
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        sintetizador.speak(u)
    }

    private func callar() {
        trasHablar = nil
        if sintetizador.isSpeaking { sintetizador.stopSpeaking(at: .immediate) }
        reproductor?.stop(); reproductor = nil
    }

    private func terminoDeHablar() {
        reproductor = nil
        let f = trasHablar; trasHablar = nil
        f?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.terminoDeHablar() }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.terminoDeHablar() }
    }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { self.terminoDeHablar() }
    }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async { self.terminoDeHablar() }
    }

    // MARK: - La llamada real

    /// Hace falta conversar: se abre la llamada de ElevenLabs (la de siempre, VozNativa) con lo que pidió y, al colgar,
    /// el Modo calle vuelve a esperar «Alma».
    private func abrirLlamada(_ pedido: String) {
        cerrarMicrofono()
        fase = .llamada
        if encendido { uso.llamadas += 1 }
        let v = VozNativa.shared
        v.desdeCalle = encendido
        v.hablarAlOir(pedido)
        llamadaVista = false; llamadaDesde = Date()
        reloj?.invalidate()
        reloj = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.revisarLlamada() }
    }

    private func revisarLlamada() {
        guard fase == .llamada else { reloj?.invalidate(); reloj = nil; return }
        let e = VozNativa.shared.estado
        if e == .hablando || e == .conectando { llamadaVista = true; return }
        guard llamadaVista || Date().timeIntervalSince(llamadaDesde) > 5 else { return }
        reloj?.invalidate(); reloj = nil
        VozNativa.shared.desdeCalle = false
        if encendido || temporal { volverAEsperar() } else { fase = .quieta }
    }

    // MARK: - Avisos hablados

    /// Llegó un aviso importante (VozNativa.novedades, ya filtrado por NivelAvisos): Alma lo dice al oído con el Modo calle
    /// o con la app abierta; si no, queda solo la notificación. Nunca interrumpe una llamada: espera y lo dice después.
    func avisoHablado(id: String, texto: String) {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, encendido || UIApplication.shared.applicationState == .active else { return }
        let dichos = UserDefaults.standard.stringArray(forKey: "avisos_dichos") ?? []
        guard !dichos.contains(id), !colaAvisos.contains(where: { $0.id == id }) else { return }
        colaAvisos.append((id, t))
        procesarAvisos()
    }

    private func procesarAvisos() {
        guard let a = colaAvisos.first else { relojAvisos?.invalidate(); relojAvisos = nil; return }
        let app = UIApplication.shared.applicationState == .active
        if !encendido && !app && !temporal { colaAvisos = []; relojAvisos?.invalidate(); relojAvisos = nil; return }   // ya no: queda la notificación
        let v = VozNativa.shared.estado
        let vozLibre = v == .lista || v == .apagada
        let puede = encendido ? (fase == .esperando && vozLibre) : (!temporal && fase == .quieta && app && vozLibre && MejoraCampo.shared.estado == .apagada)
        guard puede else {
            if relojAvisos == nil { relojAvisos = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.procesarAvisos() } }
            return
        }
        relojAvisos?.invalidate(); relojAvisos = nil
        colaAvisos.removeFirst()
        marcarDicho(a)
        if encendido {
            uso.avisos += 1
            decirAviso(a) { [weak self] in self?.empezarEscucha(conAlma: false, aviso: a.id) }
            return
        }
        if Conferencia.shared.activa {
            // El modo conferencia ya escucha (y atiende «Alma, …»): solo se dice; la respuesta se la das a ella.
            decirAviso(a) { [weak self] in self?.fase = .quieta; self?.procesarAvisos() }
            return
        }
        temporal = true
        EscuchaInicio.shared.detener()
        guard abrirMicrofono() else { temporal = false; fase = .quieta; cerrarMicrofono(); VozNativa.soltarAudio(); return }
        decirAviso(a) { [weak self] in
            guard let self, self.temporal else { return }
            self.empezarEscucha(conAlma: false, aviso: a.id)
        }
    }

    /// Lo dice con la voz de Alma si el Hub la manda (acción «calle» con el aviso); si no, con la voz del iPhone, corto.
    private func decirAviso(_ a: (id: String, texto: String), luego: @escaping () -> Void) {
        let limpio = ModoCalle.corto(a.texto, palabras: 22)
        guard !hubSinCalle else { decir(limpio, audio: nil, luego: luego); return }
        fase = .pensando
        llamarHub(["texto": "__aviso__", "aviso_id": a.id, "canal": "calle"], accion: "calle", timeout: 12) { [weak self] j in
            guard let self else { return }
            if (j?["error"] as? String) == "accion" { self.hubSinCalle = true }
            let ok = (j?["ok"] as? Bool) == true
            let hablar = ok ? ((j?["hablar"] as? String) ?? "") : ""
            self.decir(hablar.isEmpty ? limpio : hablar, audio: ok ? j?["audio"] as? String : nil, luego: luego)
        }
    }

    private func marcarDicho(_ a: (id: String, texto: String)) {
        let d = UserDefaults.standard
        d.set(Array(((d.stringArray(forKey: "avisos_dichos") ?? []) + [a.id]).suffix(60)), forKey: "avisos_dichos")
        var textos = d.dictionary(forKey: "avisos_textos") ?? [:]
        textos[a.id] = String(a.texto.prefix(300))
        if textos.count > 20 { for k in textos.keys.prefix(textos.count - 20) where k != a.id { textos[k] = nil } }
        d.set(textos, forKey: "avisos_textos")
    }

    /// El aviso con la app abierta terminó: se suelta el micrófono (y las otras apps vuelven a su volumen).
    private func terminarTemporal() {
        cerrarEscucha(); callar(); cerrarMicrofono()
        temporal = false; fase = .quieta
        VozNativa.soltarAudio()
        EscuchaInicio.shared.evaluar()
        procesarAvisos()
    }

    // MARK: - Medición (T3)

    private static func bateria() -> Int? {
        let l = UIDevice.current.batteryLevel
        return l < 0 ? nil : Int((l * 100).rounded())
    }

    /// Al apagar: el resumen de la sesión queda en el teléfono (`calle_usos`, las últimas 30) y va al Hub («calleUso»).
    private func cerrarUso() {
        let fin = Date(), seg = fin.timeIntervalSince(uso.inicio), horas = max(seg / 3600, 1.0 / 60)
        let iso = ISO8601DateFormatter()
        func porHora(_ n: Int) -> Double { (Double(n) / horas * 10).rounded() / 10 }
        var r: [String: Any] = [
            "inicio": iso.string(from: uso.inicio), "fin": iso.string(from: fin), "minutos": Int((seg / 60).rounded()),
            "gatillos": uso.gatillos, "despertares": uso.despertares, "descartes": uso.descartes, "falsos": uso.falsos,
            "pedidos": uso.pedidos, "llamadas": uso.llamadas, "avisos": uso.avisos, "errores": uso.errores,
            "despertaresHora": porHora(uso.despertares), "falsosHora": porHora(uso.falsos), "gatillosHora": porHora(uso.gatillos),
            "detector": DetectorAlma.nombre, "enviado": false
        ]
        let fin100 = ModoCalle.bateria()
        if let b = uso.bateriaInicio { r["bateriaInicio"] = b }
        if let b = fin100 { r["bateriaFin"] = b }
        if let a = uso.bateriaInicio, let b = fin100 { r["bateriaGastada"] = a - b; r["bateriaHora"] = porHora(a - b) }
        var lista = UserDefaults.standard.array(forKey: "calle_usos") as? [[String: Any]] ?? []
        lista.append(r)
        UserDefaults.standard.set(Array(lista.suffix(30)), forKey: "calle_usos")
        mandarUsos()
    }

    /// Manda al Hub los resúmenes que todavía no llegaron (si el Hub no tiene «calleUso», quedan en el teléfono).
    private func mandarUsos() {
        let lista = UserDefaults.standard.array(forKey: "calle_usos") as? [[String: Any]] ?? []
        let faltan = lista.filter { ($0["enviado"] as? Bool) != true }
        guard !faltan.isEmpty else { return }
        let usos = faltan.map { u -> [String: Any] in var x = u; x["enviado"] = nil; return x }
        llamarHub(["usos": usos], accion: "calleUso", timeout: 30) { j in
            guard (j?["ok"] as? Bool) == true else { return }
            let enviados = Set(faltan.compactMap { $0["inicio"] as? String })
            let todo = (UserDefaults.standard.array(forKey: "calle_usos") as? [[String: Any]] ?? []).map { u -> [String: Any] in
                var x = u; if let i = u["inicio"] as? String, enviados.contains(i) { x["enviado"] = true }; return x
            }
            UserDefaults.standard.set(todo, forKey: "calle_usos")
        }
    }

    private func emitir() { alEvento?(resumen) }
}

/// El detector de la palabra «Alma» en el teléfono: sherpa-onnx (Apache-2.0) con el modelo de palabras clave
/// zipformer zh-en 3M (2025-12-20; ~5 MB, va dentro de la app en Recursos «Calle»). El modelo escribe el inglés con sonidos
/// (fonemas ARPAbet): «Alma» se escribe «AE1 L M AH0», la combinación que mejor la oyó en voces en español de México (las
/// pruebas están en el PR). El umbral es bajo a propósito: deja pasar de más y el dictado del iPhone confirma.
final class DetectorAlma {
    static let nombre = "sherpa-onnx kws zipformer zh-en 3M 2025-12-20"
    static let encoder = "encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx"
    static let decoder = "decoder-epoch-13-avg-2-chunk-16-left-64.onnx"
    static let joiner = "joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx"
    static let lineaDeFabrica = "AE1 L M AH0 @ALMA"
    static let umbralDeFabrica: Float = 0.01
    static let puntajeDeFabrica: Float = 8.0

    /// Lo de fábrica, o lo que se calibró (ModoCalle.calibrar).
    static func ajustes() -> (String, Float, Float) {
        let d = UserDefaults.standard
        let l = d.string(forKey: "calle_kws_linea") ?? lineaDeFabrica
        let u = d.object(forKey: "calle_kws_umbral") != nil ? Float(d.double(forKey: "calle_kws_umbral")) : umbralDeFabrica
        let p = d.object(forKey: "calle_kws_puntaje") != nil ? Float(d.double(forKey: "calle_kws_puntaje")) : puntajeDeFabrica
        return (l, u, p)
    }

    private let kws: SherpaOnnxKeywordSpotterWrapper

    /// nil si faltan los archivos del modelo o la línea trae un sonido que el modelo no conoce (sherpa-onnx cerraría la app).
    init?(linea: String, umbral: Float, puntaje: Float) {
        guard let carpeta = Bundle.main.url(forResource: "Calle", withExtension: nil) else { return nil }
        let ruta: (String) -> String = { carpeta.appendingPathComponent($0).path }
        for n in [DetectorAlma.encoder, DetectorAlma.decoder, DetectorAlma.joiner, "tokens.txt"] where !FileManager.default.fileExists(atPath: ruta(n)) {
            return nil
        }
        guard let tokens = try? String(contentsOfFile: ruta("tokens.txt"), encoding: .utf8) else { return nil }
        let conocidos = Set(tokens.split(whereSeparator: { $0.isNewline }).compactMap { $0.split(separator: " ").first.map(String.init) })
        let lineas = linea.split(whereSeparator: { $0.isNewline }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lineas.isEmpty else { return nil }
        for l in lineas {
            for w in l.split(separator: " ") where !(w.hasPrefix("@") || w.hasPrefix(":") || w.hasPrefix("#")) {
                guard conocidos.contains(String(w)) else { return nil }
            }
        }
        let texto = lineas.joined(separator: "\n")
        let transducer = sherpaOnnxOnlineTransducerModelConfig(encoder: ruta(DetectorAlma.encoder), decoder: ruta(DetectorAlma.decoder), joiner: ruta(DetectorAlma.joiner))
        let modelo = sherpaOnnxOnlineModelConfig(tokens: ruta("tokens.txt"), transducer: transducer, numThreads: 1)
        let rasgos = sherpaOnnxFeatureConfig(sampleRate: 16000, featureDim: 80)
        var config = sherpaOnnxKeywordSpotterConfig(featConfig: rasgos, modelConfig: modelo, keywordsFile: "", maxActivePaths: 4,
                                                    numTrailingBlanks: 1, keywordsScore: puntaje, keywordsThreshold: umbral,
                                                    keywordsBuf: texto, keywordsBufSize: texto.utf8.count)
        let k = SherpaOnnxKeywordSpotterWrapper(config: &config)
        guard k.spotter != nil, k.stream != nil else { return nil }
        kws = k
    }

    /// Audio a 16 kHz: ¿dijeron «Alma»?
    func oir(_ m: [Float]) -> Bool {
        kws.acceptWaveform(samples: m)
        var hallada = false
        while kws.isReady() {
            kws.decode()
            if !kws.getResult().keyword.isEmpty { kws.reset(); hallada = true }
        }
        return hallada
    }

    func reiniciar() { kws.reset() }
}

/// Niveles de las notificaciones, con dos selectores en Ajustes: «Notificaciones habladas» (hablado) y «Notificaciones del
/// teléfono» (telefono). Cada nivel incluye los anteriores:
///   0 Silencio · 1 Solo urgente · 2 Lo que pide algo de ti · 3 Todo (de fábrica).
/// Cada aviso del Hub (vozAvisos) trae `nivel`: 1 urgente · 2 accion · 3 aviso (sin nivel = 2).
/// Bajar el nivel dura un rato (1 h, 4 h o hasta mañana a las 7:00) y después vuelve solo a «Todo»: se revisa cada vez
/// que se lee (al abrir la app, en la vuelta de los avisos y al mostrar Ajustes), aunque la app se haya cerrado.
enum NivelAvisos {
    static let tipos = ["hablado", "telefono"]
    private static func clave(_ tipo: String) -> String { "aviso_nivel_" + tipo }

    static func nivel(_ tipo: String) -> Int {
        let d = UserDefaults.standard, k = clave(tipo)
        if let h = d.object(forKey: k + "_hasta") as? Date, h <= Date() { d.removeObject(forKey: k); d.removeObject(forKey: k + "_hasta") }
        return (d.object(forKey: k) as? Int) ?? 3
    }

    static func hasta(_ tipo: String) -> Date? {
        _ = nivel(tipo)
        return UserDefaults.standard.object(forKey: clave(tipo) + "_hasta") as? Date
    }

    /// `por`: "1h" · "4h" (de fábrica) · "manana" (hasta las 7:00). Nivel 3 = Todo, sin plazo.
    static func poner(_ tipo: String, nivel n: Int, por: String) {
        guard tipos.contains(tipo) else { return }
        let d = UserDefaults.standard, k = clave(tipo), v = max(0, min(3, n))
        if v >= 3 { d.removeObject(forKey: k); d.removeObject(forKey: k + "_hasta"); return }
        d.set(v, forKey: k); d.set(fin(por), forKey: k + "_hasta")
    }

    static func fin(_ por: String, desde: Date = Date()) -> Date {
        switch por {
        case "1h": return desde.addingTimeInterval(3600)
        case "manana":
            return Calendar.current.nextDate(after: desde, matching: DateComponents(hour: 7, minute: 0), matchingPolicy: .nextTime) ?? desde.addingTimeInterval(4 * 3600)
        default: return desde.addingTimeInterval(4 * 3600)
        }
    }

    /// El nivel de un aviso del Hub: 1 urgente · 2 accion · 3 aviso (sin nivel = 2).
    static func deAviso(_ a: [String: Any]) -> Int {
        if let n = a["nivel"] as? NSNumber { return max(1, min(3, n.intValue)) }
        switch (a["nivel"] as? String ?? "").lowercased() {
        case "1", "urgente": return 1
        case "3", "aviso": return 3
        default: return 2
        }
    }

    static var resumen: [String: Any] {
        var r: [String: Any] = ["tipo": "avisos"]
        for t in tipos {
            var x: [String: Any] = ["nivel": nivel(t)]
            if let h = hasta(t) { x["hasta"] = Int(h.timeIntervalSince1970 * 1000); x["minutos"] = max(0, Int((h.timeIntervalSinceNow / 60).rounded(.up))) }
            r[t] = x
        }
        return r
    }
}
