import AVFoundation

/// Coro de espera (Juan, 17-nov-2026): lo toca un AVAudioPlayerNode del MISMO motor que la voz de Alma (VozNativa), así la
/// cancelación de eco lo resta del micrófono igual que su voz. Cuándo y a qué volumen: CoroReglas. Primero suena el tecleo
/// de ElevenLabs; al entrar el coro, `tecleo` baja la voz del agente (por ahí llega el tecleo) y al salir la devuelve.
/// El archivo (Recursos/Sonidos/alma-trabaja.wav, 48 kHz mono, −24 LUFS) es un loop sin costura de 39 s: se repite solo.
/// `permitido`: hay una conversación de ElevenLabs (no la voz local de Claudio, de respaldo ni Maricarmen).
final class CoroTrabajo {
    let nodo = AVAudioPlayerNode()
    private(set) var buffer: AVAudioPCMBuffer?
    private var reglas = CoroReglas()
    var permitido = false { didSet { if !permitido { corta() } } }
    /// Alma suena ahora / Juan habla ahora (los da VozNativa).
    var almaHabla: () -> Bool = { false }
    var juanHabla: () -> Bool = { false }
    /// Pone el volumen de la voz del agente (el tecleo). `normal`: el de siempre.
    var tecleo: (Float) -> Void = { _ in }
    var normal: Float = 1
    private var tecleoBajo = false
    /// ¿Se oye el coro? (el micrófono lo trata como el eco de la voz de Alma: solo pasa lo que suena más fuerte)
    private(set) var audible = false
    /// La rampa en curso (CoroReglas.nivel: ease-in/ease-out).
    private var nivel: Float = 0, objetivo: Float = 0, desde: Float = 0, inicio = Date(), dur: TimeInterval = 0
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

    func termina(_ id: String) { if reglas.termina(id) { bajarTecleo(false) } }   // Alma va a contestar: su voz completa

    /// Interrupción, cambio de agente o colgar: sale rápido (0,35 s) pero con curva, no en seco (Juan, 19-nov-2026).
    func corta() {
        reglas.corta()
        bajarTecleo(false)
        guard sonando else {
            reloj?.invalidate(); reloj = nil
            nivel = 0; objetivo = 0; audible = false; nodo.volume = 0
            return
        }
        rampa(hacia: 0, en: CoroReglas.corte, ahora: Date())
        arrancarReloj()
    }

    private func rampa(hacia: Float, en t: TimeInterval, ahora: Date) {
        desde = nivel; objetivo = hacia; inicio = ahora; dur = t
    }

    private func parar() {
        nodo.stop(); sonando = false; audible = false; nivel = 0; objetivo = 0; nodo.volume = 0
        if reglas.cuantas == 0 { reloj?.invalidate(); reloj = nil }
    }

    private func bajarTecleo(_ on: Bool) {
        guard on != tecleoBajo else { return }
        tecleoBajo = on
        tecleo(CoroReglas.volumenTecleo(coroSuena: on, almaHabla: false, normal: normal))
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
            nodo.volume = 0; nivel = 0; objetivo = 0
            nodo.scheduleBuffer(b, at: nil, options: [.loops], completionHandler: nil)
            nodo.play(); sonando = true
        }
        guard sonando else {
            if reglas.cuantas == 0 { reloj?.invalidate(); reloj = nil }
            return
        }
        let alma = almaHabla()
        bajarTecleo(debe && !alma)   // el tecleo se baja mientras suena la espera; Alma hablando se oye completa
        let nuevo: Float = debe ? CoroReglas.lineal(CoroReglas.objetivoDb(almaHabla: alma, juanHabla: juanHabla())) : 0
        if let m = nodo.engine, !m.isRunning { parar(); return }   // colgó y el motor ya paró: no hay nada que bajar
        // La salida en curso (0 → corte o salida) no se cambia por otra salida: solo una herramienta nueva la revierte.
        if nuevo != objetivo { rampa(hacia: nuevo, en: CoroReglas.duracion(desde: nivel, hacia: nuevo), ahora: ahora) }
        nivel = CoroReglas.nivel(desde: desde, hacia: objetivo, duracion: dur, transcurrido: ahora.timeIntervalSince(inicio))
        nodo.volume = nivel
        audible = nivel > 0.01
        if nivel <= 0.0001 && objetivo <= 0.0001 && !debe { parar() }   // terminó de salir
    }
}

/// El coro cuando la voz es la de una página dentro de la app (js/alma-voz.js, por el puente): la página lleva la cuenta de
/// las herramientas, el umbral y el ducking, y aquí solo se toca con el volumen y la rampa que pide (v = 0: sale y para).
/// La rampa usa la misma curva ease-in/ease-out que el coro nativo (CoroReglas.nivel), no la lineal de AVAudioPlayer.
final class CoroPagina {
    static let shared = CoroPagina()
    private var p: AVAudioPlayer?
    private var reloj: Timer?
    private var desde: Float = 0, hacia: Float = 0, inicio = Date(), dur: TimeInterval = 0

    func poner(_ v: Float, en t: TimeInterval) {
        let vol = max(0, min(1, v)), d = max(0, min(2, t))
        if vol <= 0.0001 {
            guard let p, p.isPlaying else { return }
            rampa(p, hacia: 0, en: d)
            return
        }
        if p == nil, let u = Bundle.main.url(forResource: "alma-trabaja", withExtension: "wav") {
            p = try? AVAudioPlayer(contentsOf: u); p?.numberOfLoops = -1; p?.prepareToPlay()
        }
        guard let p else { return }
        if !p.isPlaying { p.volume = 0; p.play() }
        rampa(p, hacia: vol, en: d)
    }

    private func rampa(_ p: AVAudioPlayer, hacia v: Float, en t: TimeInterval) {
        desde = p.volume; hacia = v; inicio = Date(); dur = t
        guard reloj == nil else { return }
        let r = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(r, forMode: .common); reloj = r
    }

    private func tick() {
        guard let p else { reloj?.invalidate(); reloj = nil; return }
        let pasado = Date().timeIntervalSince(inicio)
        p.volume = CoroReglas.nivel(desde: desde, hacia: hacia, duracion: dur, transcurrido: pasado)
        guard pasado >= dur else { return }
        reloj?.invalidate(); reloj = nil
        if hacia <= 0.0001 { p.stop(); p.currentTime = 0 }
    }
}
