import AVFoundation
import Speech
import UIKit

/// «Modo Inicio» (Ajustes, «Inicio con escucha activa», encendido por defecto): con la app abierta en el inicio, el iPhone
/// escucha en el teléfono (gratis, sin enviar ni guardar audio) durante 1 minuto. Si dices «Alma, …», pasa al modo
/// conferencia (escucha y responde cuando la llaman; se apaga sola a los 7 min sin «Alma» o al salir de la app). Si el minuto pasa sin «Alma», no se manda nada, lo escuchado
/// se suelta y queda en espera (botón apagado) hasta que vuelvas a abrir la app o el inicio.
/// El puntito que respira bajo la roca dice que está escuchando. Al abrir la app no suena nada: la señal de Alma suena solo
/// cuando empieza una llamada (la roca, «Alma» o el anillo).
///   · Solo escuchar no le quita el sonido a las otras apps (TikTok, Facebook, la voz de Claude): la sesión se mezcla
///     (VozNativa.sesionEscucha). Al pasar el minuto (o al detenerse) se suelta el audio y las otras apps siguen.
///   · El micrófono queda encendido todo el minuto; entre frases solo se cambia el reconocimiento (no se reabre el audio).
///   · La página avisa cuándo el inicio está a la vista y quieto (sin chat, Pendientes ni llamada): poner(pagina:).
///   · Se detiene con la app en segundo plano, durante la llamada y con el modo conferencia (que tiene su propio despertar).
final class EscuchaInicio {
    static let shared = EscuchaInicio()
    var alEvento: (([String: Any]) -> Void)?

    private let reconocedor = SFSpeechRecognizer(locale: Locale(identifier: "es-MX"))
    private var motor = AVAudioEngine()          // se rehace si iOS reinicia el audio (mediaServicesWereReset)
    private var pedido: SFSpeechAudioBufferRecognitionRequest?
    private let candado = NSLock()               // `pedido` también lo usa el hilo del micrófono
    /// El texto (de cualquiera de las versiones que propone el reconocedor) donde alguien dijo «Alma»; nil si nadie.
    private var conAlma: String?
    private var tarea: SFSpeechRecognitionTask?
    private var vuelta = 0
    private var actual = "", ultimoCambio = Date(), desde = Date()
    private var reloj: Timer?
    private var pagina = false, enLlamada = false
    private var limite: Date?, agotado = false   // el minuto del Modo Inicio; agotado = ya pasó sin «Alma» (en espera)
    static let minuto: TimeInterval = 60
    /// Lo último que se dijo en este minuto (solo en memoria, nunca se manda): si te llaman con «Alma», va de contexto.
    private var previo: [String] = []
    /// Escucha por el micrófono de la voz (VozNativa, ya abierto con «Alma con el anillo») en vez de abrir otro.
    private var compartido = false
    private(set) var escuchando = false { didSet { if escuchando != oldValue { emitir() } } }

    var activada: Bool { UserDefaults.standard.bool(forKey: "escucha_inicio") }
    var resumen: [String: Any] { ["tipo": "escucha", "activada": activada, "escuchando": escuchando] }

    private init() {
        UserDefaults.standard.register(defaults: ["escucha_inicio": true])
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.detener() }
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.agotado = false; self?.evaluar() }   // abrir la app de nuevo = otro minuto
        // Otra app (o una llamada de teléfono) tomó el audio: se suelta todo y, cuando lo devuelve, se vuelve a escuchar.
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let t = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
            if t == AVAudioSession.InterruptionType.began.rawValue { if self.escuchando { self.parar() } }   // el minuto sigue contando
            else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.evaluar() } }
        }
        // iOS reinició el audio: el motor viejo ya no sirve; se hace otro y se vuelve a escuchar.
        nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.parar(); self.motor = AVAudioEngine()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.evaluar() }
        }
    }

    func activar(_ on: Bool) { UserDefaults.standard.set(on, forKey: "escucha_inicio"); agotado = false; evaluar() }
    func poner(pagina on: Bool) { if on && !pagina { agotado = false }; pagina = on; evaluar() }
    /// El modo conferencia terminó (o no pudo empezar): el inicio vuelve a su minuto de escucha.
    func liberar() { enLlamada = false; agotado = false; evaluar() }

    /// ¿Debe escuchar ahora? Si sí y no está escuchando, empieza; si no, se detiene.
    func evaluar() {
        let v = VozNativa.shared.estado
        let puede = activada && pagina && !agotado && !enLlamada && !Conferencia.shared.activa && !ModoCalle.shared.ocupaMicrofono && (v == .lista || v == .apagada) && UIApplication.shared.applicationState == .active
        if !puede { detener(); return }
        guard !escuchando else { return }
        SFSpeechRecognizer.requestAuthorization { st in
            AVAudioSession.sharedInstance().requestRecordPermission { mic in
                DispatchQueue.main.async { if st == .authorized, mic, self.reconocedor?.isAvailable == true { self.escuchar() } else { self.emitir() } }
            }
        }
    }

    /// Empieza a escuchar: abre el micrófono (el de la voz si ya está abierto, o el propio con la sesión que se mezcla) y la
    /// primera vuelta del reconocimiento.
    private func escuchar() {
        guard !escuchando, activada, pagina, !enLlamada, !Conferencia.shared.activa else { return }
        let voz = VozNativa.shared
        if voz.microfonoListo {
            // El micrófono de la voz ya está abierto: se escucha por él (dos micrófonos a la vez dejan mudo a uno).
            compartido = true
            voz.ponerOyente("inicio") { [weak self] b in self?.oir(b) }
        } else {
            compartido = false
            VozNativa.sesionEscucha()   // se mezcla: las otras apps siguen sonando
            let entrada = motor.inputNode, formato = entrada.outputFormat(forBus: 0)
            guard formato.sampleRate > 0 else { reintentar(); return }
            entrada.removeTap(onBus: 0)
            entrada.installTap(onBus: 0, bufferSize: 1024, format: formato) { [weak self] b, _ in self?.oir(b) }
            motor.prepare()
            do { try motor.start() } catch { reintentar(); return }
        }
        if limite == nil { limite = Date().addingTimeInterval(EscuchaInicio.minuto) }
        escuchando = true
        nuevaVuelta()
        voz.precargarSiToca()   // la ficha del Hub queda pedida: si dicen «Alma», la llamada no la espera
        reloj?.invalidate()
        reloj = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.revisar() }
    }

    /// Lo que oye el micrófono va al reconocimiento de la vuelta actual (hilo del micrófono).
    private func oir(_ b: AVAudioPCMBuffer) { candado.lock(); pedido?.append(b); candado.unlock() }

    /// Una vuelta nueva del reconocimiento con el micrófono ya abierto: solo se cambia el pedido (el audio no se reabre).
    private func nuevaVuelta() {
        tarea?.cancel(); tarea = nil
        let p = SFSpeechAudioBufferRecognitionRequest(); p.shouldReportPartialResults = true
        if reconocedor?.supportsOnDeviceRecognition == true { p.requiresOnDeviceRecognition = true }
        p.contextualStrings = ["Alma"]   // que el reconocedor espere oír «Alma» (no «palma» ni «al ma»)
        candado.lock(); let viejo = pedido; pedido = p; candado.unlock()
        viejo?.endAudio()
        vuelta += 1; let mia = vuelta
        actual = ""; conAlma = nil; ultimoCambio = Date(); desde = Date()
        tarea = reconocedor?.recognitionTask(with: p) { [weak self] r, e in
            DispatchQueue.main.async {
                guard let self, self.vuelta == mia, self.escuchando else { return }
                if let r {
                    let t = r.bestTranscription.formattedString
                    if t != self.actual { self.actual = t; self.ultimoCambio = Date() }
                    self.conAlma = Conferencia.versionConAlma(r)
                    // Al cerrar la vuelta (o si falla) primero se mira si la llamaron; solo si no, se empieza otra.
                    if r.isFinal, !self.llamaron() { self.otraVuelta() }
                } else if e != nil, !self.llamaron() { self.otraVuelta() }
            }
        }
    }

    /// Cada cuarto de segundo: ¿la llamaron? Lo que no la nombra solo queda en memoria este minuto (de contexto si la llaman; no se manda ni se guarda).
    private func revisar() {
        guard escuchando else { return }
        let quieto = Date().timeIntervalSince(ultimoCambio)
        // Solo «Alma» (sin pedido): despierta rápido (0,7 s quieto). Con pedido, espera 1,2 s para no cortar lo que piden.
        if let a = conAlma, let pide = Conferencia.pedidoAAlma(a), quieto > (pide.isEmpty ? 0.7 : 1.2) { despertar(pide, texto: a); return }
        if let l = limite, Date() >= l { agotar(); return }
        // El micrófono de la voz se abrió (o se cerró) mientras escuchaba, o iOS apagó el propio: se cambia al que corresponde.
        if compartido != VozNativa.shared.microfonoListo || (!compartido && !motor.isRunning) { otraVuelta(); return }
        if (!actual.isEmpty && quieto > 2.5) || Date().timeIntervalSince(desde) > 50 { otraVuelta() }
    }

    /// ¿Dijeron «Alma» en esta vuelta? Entonces despierta y no se empieza otra.
    private func llamaron() -> Bool {
        guard let a = conAlma, let pide = Conferencia.pedidoAAlma(a) else { return false }
        despertar(pide, texto: a); return true
    }

    private func otraVuelta() {
        let t = actual.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { previo.append(t); if previo.count > 4 { previo.removeFirst(previo.count - 4) } }
        // Mismo micrófono y sigue encendido: solo una vuelta nueva. Si cambió (o se apagó), se vuelve a abrir.
        if compartido == VozNativa.shared.microfonoListo && (compartido || motor.isRunning) { nuevaVuelta() }
        else { parar(); escuchar() }
    }
    private func reintentar() { parar(); DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.evaluar() } }

    private func parar() {
        reloj?.invalidate(); reloj = nil
        tarea?.cancel(); tarea = nil
        candado.lock(); let p = pedido; pedido = nil; candado.unlock()
        p?.endAudio()
        VozNativa.shared.quitarOyente("inicio")
        if motor.isRunning { motor.inputNode.removeTap(onBus: 0); motor.stop() }
        compartido = false; conAlma = nil
        escuchando = false
    }
    /// Deja de escuchar y suelta el audio (si nadie más lo usa): las otras apps siguen con lo suyo.
    func detener() { limite = nil; previo = []; guard escuchando || reloj != nil else { return }; parar(); VozNativa.soltarAudio() }

    /// Pasó el minuto sin que nadie dijera «Alma»: se suelta lo escuchado (no se manda ni se guarda nada) y queda en espera.
    private func agotar() { agotado = true; actual = ""; previo = []; detener() }

    /// Dijiste «Alma…»: pasa al modo conferencia, que atiende lo que pediste y sigue escuchando (hasta 7 min sin «Alma»).
    private func despertar(_ pide: String, texto: String) {
        // Lo que se dijo justo antes de «Alma» (en este minuto) va de contexto, como en el modo conferencia.
        var ctx = previo
        let antes = Conferencia.antesDeAlma(texto)
        if !antes.isEmpty { ctx.append(antes) }
        parar(); limite = nil; previo = []; enLlamada = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // Encendida por «Alma» (no con el botón): se apaga sola a los 7 min sin que la vuelvan a llamar y al salir de la app.
        Conferencia.shared.encender(pedido: pide, contexto: ctx, alFallar: { [weak self] in self?.liberar() }, apagarTras: 7 * 60, porVoz: true)
    }

    private func emitir() { alEvento?(resumen) }
}
