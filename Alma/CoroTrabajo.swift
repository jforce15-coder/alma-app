import AVFoundation

/// Coro «Alma está trabajando» (Juan, 17-nov-2026): lo toca un AVAudioPlayerNode del MISMO motor que la voz de Alma
/// (VozNativa), así la cancelación de eco lo resta del micrófono igual que su voz. Cuándo y a qué volumen: CoroReglas.
/// El archivo (Recursos/Sonidos/alma-trabaja.wav, 48 kHz mono, −24 LUFS) es un loop sin costura de 39 s: se repite solo.
/// Solo suena si `permitido`: la conversación no trae el tecleo de ElevenLabs (Alma con las herramientas gemelas sin sonido,
/// tool_ids_app del Hub, o Claudio, que ya no lo tiene). Si no, se oirían los dos.
final class CoroTrabajo {
    let nodo = AVAudioPlayerNode()
    private(set) var buffer: AVAudioPCMBuffer?
    private var reglas = CoroReglas()
    var permitido = false { didSet { if !permitido { corta() } } }
    /// Alma suena ahora / Juan habla ahora (los da VozNativa).
    var almaHabla: () -> Bool = { false }
    var juanHabla: () -> Bool = { false }
    /// ¿Se oye el coro? (el micrófono lo trata como el eco de la voz de Alma: solo pasa lo que suena más fuerte)
    private(set) var audible = false
    private var nivel: Float = 0, objetivo: Float = 0, velocidad: Float = 1
    private var sonando = false
    private var reloj: Timer?
    private static let dt: TimeInterval = 0.025

    /// El formato del archivo (para conectar el nodo al motor). Lo carga la primera vez.
    var formato: AVAudioFormat? { cargar(); return buffer?.format }

    private func cargar() {
        guard buffer == nil, let u = Bundle.main.url(forResource: "alma-trabaja", withExtension: "wav"),
              let f = try? AVAudioFile(forReading: u),
              let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)) else { return }
        do { try f.read(into: b); buffer = b } catch { buffer = nil }
    }

    func empieza(_ id: String, nombre: String) {
        guard permitido, reglas.empieza(id, nombre: nombre, ahora: Date()) else { return }
        arrancarReloj()
    }

    func termina(_ id: String) { reglas.termina(id) }

    /// Interrupción, cambio de agente o colgar: se corta ya (sin rampa).
    func corta() {
        reglas.corta()
        reloj?.invalidate(); reloj = nil
        if sonando { nodo.stop() }
        sonando = false; nivel = 0; objetivo = 0; audible = false; nodo.volume = 0
    }

    private func arrancarReloj() {
        guard reloj == nil else { return }
        let t = Timer(timeInterval: CoroTrabajo.dt, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common); reloj = t
    }

    private func tick() {
        let ahora = Date()
        reglas.vencer(ahora)
        let debe = permitido && reglas.debeSonar(ahora)
        if debe && !sonando {
            guard let b = buffer, let motor = nodo.engine, motor.isRunning else { return }
            nodo.volume = 0; nivel = 0
            nodo.scheduleBuffer(b, at: nil, options: [.loops], completionHandler: nil)
            nodo.play(); sonando = true
        }
        guard sonando else {
            if reglas.cuantas == 0 { reloj?.invalidate(); reloj = nil }
            return
        }
        let nuevo: Float = debe ? CoroReglas.lineal(CoroReglas.objetivoDb(almaHabla: almaHabla(), juanHabla: juanHabla())) : 0
        if nuevo != objetivo {
            velocidad = abs(nuevo - nivel) / Float(max(0.01, CoroReglas.duracion(desde: nivel, hacia: nuevo)))
            objetivo = nuevo
        }
        nivel = CoroReglas.paso(nivel: nivel, objetivo: objetivo, velocidad: velocidad, dt: CoroTrabajo.dt)
        nodo.volume = nivel
        audible = nivel > 0.01
        if nivel <= 0.0001 && !debe {   // terminó de salir
            nodo.stop(); sonando = false; audible = false
            if reglas.cuantas == 0 { reloj?.invalidate(); reloj = nil }
        }
    }
}

/// El coro cuando la voz es la de una página dentro de la app (js/alma-voz.js, por el puente): la página lleva la cuenta de
/// las herramientas, el umbral y el ducking, y aquí solo se toca con el volumen y la rampa que pide (v = 0: sale y para).
final class CoroPagina {
    static let shared = CoroPagina()
    private var p: AVAudioPlayer?

    func poner(_ v: Float, en t: TimeInterval) {
        let vol = max(0, min(1, v)), dur = max(0, min(2, t))
        if vol <= 0.0001 {
            guard let p, p.isPlaying else { return }
            p.setVolume(0, fadeDuration: dur)
            DispatchQueue.main.asyncAfter(deadline: .now() + dur + 0.05) { [weak self] in
                if let q = self?.p, q.volume <= 0.0001 { q.stop(); q.currentTime = 0 }
            }
            return
        }
        if p == nil, let u = Bundle.main.url(forResource: "alma-trabaja", withExtension: "wav") {
            p = try? AVAudioPlayer(contentsOf: u); p?.numberOfLoops = -1; p?.prepareToPlay()
        }
        guard let p else { return }
        if !p.isPlaying { p.volume = 0; p.play() }
        p.setVolume(vol, fadeDuration: dur)
    }
}
