import AVFoundation
import Speech
import UIKit

/// «Modo Inicio» (Ajustes, «Inicio con escucha activa», encendido por defecto): con la app abierta en el inicio, el iPhone
/// escucha en el teléfono (gratis, sin enviar ni guardar audio) durante 1 minuto. Si dices «Alma, …», pasa al modo
/// conferencia (escucha sin fin y responde cuando la llaman). Si el minuto pasa sin «Alma», no se manda nada, lo escuchado
/// se suelta y queda en espera (botón apagado) hasta que vuelvas a abrir la app o el inicio.
/// El puntito que respira bajo la roca dice que está escuchando.
///   · La página avisa cuándo el inicio está a la vista y quieto (sin chat, Pendientes ni llamada): poner(pagina:).
///   · Se detiene con la app en segundo plano, durante la llamada y con el modo conferencia (que tiene su propio despertar).
final class EscuchaInicio {
    static let shared = EscuchaInicio()
    var alEvento: (([String: Any]) -> Void)?

    private let reconocedor = SFSpeechRecognizer(locale: Locale(identifier: "es-MX"))
    private let motor = AVAudioEngine()
    private var pedido: SFSpeechAudioBufferRecognitionRequest?
    private var tarea: SFSpeechRecognitionTask?
    private var vuelta = 0
    private var actual = "", ultimoCambio = Date(), desde = Date()
    private var reloj: Timer?
    private var pagina = false, enLlamada = false
    private var limite: Date?, agotado = false   // el minuto del Modo Inicio; agotado = ya pasó sin «Alma» (en espera)
    static let minuto: TimeInterval = 60
    private var escuchando = false { didSet { if escuchando != oldValue { emitir() } } }

    var activada: Bool { UserDefaults.standard.bool(forKey: "escucha_inicio") }
    var resumen: [String: Any] { ["tipo": "escucha", "activada": activada, "escuchando": escuchando] }

    private init() {
        UserDefaults.standard.register(defaults: ["escucha_inicio": true])
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.detener() }
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.agotado = false; self?.evaluar() }   // abrir la app de nuevo = otro minuto
    }

    func activar(_ on: Bool) { UserDefaults.standard.set(on, forKey: "escucha_inicio"); agotado = false; evaluar() }
    func poner(pagina on: Bool) { if on && !pagina { agotado = false }; pagina = on; evaluar() }
    /// El modo conferencia terminó (o no pudo empezar): el inicio vuelve a su minuto de escucha.
    func liberar() { enLlamada = false; agotado = false; evaluar() }

    /// ¿Debe escuchar ahora? Si sí y no está escuchando, empieza; si no, se detiene.
    func evaluar() {
        let v = VozNativa.shared.estado
        let puede = activada && pagina && !agotado && !enLlamada && !Conferencia.shared.activa && (v == .lista || v == .apagada) && UIApplication.shared.applicationState == .active
        if !puede { detener(); return }
        guard !escuchando else { return }
        SFSpeechRecognizer.requestAuthorization { st in
            AVAudioSession.sharedInstance().requestRecordPermission { mic in
                DispatchQueue.main.async { if st == .authorized, mic, self.reconocedor?.isAvailable == true { self.escuchar() } else { self.emitir() } }
            }
        }
    }

    private func escuchar() {
        guard !escuchando, activada, pagina, !enLlamada, !Conferencia.shared.activa else { return }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .default, options: VozNativa.opciones)
        try? s.setActive(true)
        let p = SFSpeechAudioBufferRecognitionRequest(); p.shouldReportPartialResults = true
        if reconocedor?.supportsOnDeviceRecognition == true { p.requiresOnDeviceRecognition = true }
        pedido = p
        let entrada = motor.inputNode, formato = entrada.outputFormat(forBus: 0)
        guard formato.sampleRate > 0 else { reintentar(); return }
        entrada.removeTap(onBus: 0)
        entrada.installTap(onBus: 0, bufferSize: 1024, format: formato) { [weak p] b, _ in p?.append(b) }
        motor.prepare()
        do { try motor.start() } catch { reintentar(); return }
        vuelta += 1; let mia = vuelta
        if limite == nil { limite = Date().addingTimeInterval(EscuchaInicio.minuto) }
        actual = ""; ultimoCambio = Date(); desde = Date()
        tarea = reconocedor?.recognitionTask(with: p) { [weak self] r, e in
            DispatchQueue.main.async {
                guard let self, self.vuelta == mia, self.escuchando else { return }
                if let r {
                    let t = r.bestTranscription.formattedString
                    if t != self.actual { self.actual = t; self.ultimoCambio = Date() }
                    if r.isFinal { self.otraVuelta() }
                } else if e != nil { self.otraVuelta() }
            }
        }
        escuchando = true
        reloj?.invalidate()
        reloj = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.revisar() }
    }

    /// Cada medio segundo: ¿la llamaron? Lo que no la nombra se suelta en las pausas (no se guarda nada).
    private func revisar() {
        guard escuchando else { return }
        let quieto = Date().timeIntervalSince(ultimoCambio)
        if !actual.isEmpty, quieto > 1.2, let pide = Conferencia.pedidoAAlma(actual) { despertar(pide); return }
        if let l = limite, Date() >= l { agotar(); return }
        if (!actual.isEmpty && quieto > 2.5) || Date().timeIntervalSince(desde) > 50 { otraVuelta() }
    }

    private func otraVuelta() { parar(); escuchar() }
    private func reintentar() { parar(); DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.evaluar() } }

    private func parar() {
        reloj?.invalidate(); reloj = nil
        tarea?.cancel(); tarea = nil
        pedido?.endAudio(); pedido = nil
        motor.inputNode.removeTap(onBus: 0); if motor.isRunning { motor.stop() }
        escuchando = false
    }
    func detener() { limite = nil; guard escuchando || reloj != nil else { return }; parar() }

    /// Pasó el minuto sin que nadie dijera «Alma»: se suelta lo escuchado (no se manda ni se guarda nada) y queda en espera.
    private func agotar() { agotado = true; actual = ""; detener() }

    /// Dijiste «Alma…»: pasa al modo conferencia, que atiende lo que pediste y sigue escuchando sin fin.
    private func despertar(_ pide: String) {
        parar(); limite = nil; enLlamada = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Conferencia.shared.encender(pedido: pide) { [weak self] in self?.liberar() }
    }

    private func emitir() { alEvento?(resumen) }
}
