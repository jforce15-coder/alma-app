import AVFoundation
import Speech
import UIKit

/// Modo conferencia (Ajustes → «Modo conferencia»): Alma se queda escuchando una reunión, una conferencia o una llamada
/// SIN ElevenLabs. El iPhone transcribe en el teléfono (gratis y privado) y solo manda texto: los silencios no cuestan nada.
///   · Cada tramo dicho (se corta en las pausas) queda con su hora; cada 90 s se manda al Hub (acción «conferencia»).
///   · Si alguien dice «Alma, …», se enciende la llamada real sin señal ni saludo, con lo último que se dijo como contexto;
///     Alma responde y, al colgar, vuelve a escuchar sola.
///   · Al apagarlo, el Hub lo clasifica (reunión, conferencia, llamada o memo · esfera · proyecto), resume los acuerdos y
///     lo deja en Pendientes. No se guarda audio: solo el texto.
final class Conferencia {
    static let shared = Conferencia()
    private(set) var activa = false
    var alEvento: (([String: Any]) -> Void)?

    private let reconocedor = SFSpeechRecognizer(locale: Locale(identifier: "es-MX"))
    private let motor = AVAudioEngine()
    private var pedido: SFSpeechAudioBufferRecognitionRequest?
    private var tarea: SFSpeechRecognitionTask?
    private var vuelta = 0                      // cada reconocimiento nuevo; los avisos de uno viejo se ignoran
    private var id = ""
    private var actual = ""                     // lo que va del tramo, reconocido en vivo
    private var ultimoCambio = Date(), inicioTramo = Date(), inicio = Date()
    private var pendiente: [String] = []        // tramos por mandar al Hub
    private var reciente: [String] = []         // los últimos tramos: el contexto si llaman a Alma
    private var reloj: Timer?, envio: Timer?
    private var enLlamada = false

    var resumen: [String: Any] { ["tipo": "conferencia", "activa": activa, "minutos": activa ? Int(Date().timeIntervalSince(inicio) / 60) : 0] }

    func poner(_ on: Bool) { if on { encender() } else { apagar() } }

    private func encender() {
        guard !activa else { emitir(); return }
        SFSpeechRecognizer.requestAuthorization { st in
            AVAudioSession.sharedInstance().requestRecordPermission { mic in
                DispatchQueue.main.async {
                    guard st == .authorized, mic, self.reconocedor?.isAvailable == true else {
                        self.alEvento?(["tipo": "conferencia", "activa": false, "error": "Activa el micrófono y el reconocimiento de voz para Alma en Ajustes del iPhone."]); return
                    }
                    self.activa = true; self.id = "cf" + String(Int(Date().timeIntervalSince1970)); self.inicio = Date()
                    self.pendiente = []; self.reciente = []; self.enLlamada = false
                    self.escuchar()
                    self.envio = Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { [weak self] _ in self?.mandar(fin: false) }
                    self.emitir()
                }
            }
        }
    }

    private func apagar() {
        guard activa else { emitir(); return }
        reloj?.invalidate(); reloj = nil; envio?.invalidate(); envio = nil
        guardarTramo(); detener()
        mandar(fin: true)
        activa = false; enLlamada = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        emitir()
    }

    private func escuchar() {
        guard activa, !enLlamada else { return }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .default, options: VozNativa.opciones)
        try? s.setActive(true)
        let p = SFSpeechAudioBufferRecognitionRequest(); p.shouldReportPartialResults = true
        if reconocedor?.supportsOnDeviceRecognition == true { p.requiresOnDeviceRecognition = true }
        if #available(iOS 16, *) { p.addsPunctuation = true }
        pedido = p
        let entrada = motor.inputNode, formato = entrada.outputFormat(forBus: 0)
        guard formato.sampleRate > 0 else { reintentar(); return }
        entrada.removeTap(onBus: 0)
        entrada.installTap(onBus: 0, bufferSize: 1024, format: formato) { [weak p] b, _ in p?.append(b) }
        motor.prepare()
        do { try motor.start() } catch { reintentar(); return }
        vuelta += 1; let mia = vuelta
        actual = ""; inicioTramo = Date(); ultimoCambio = Date()
        tarea = reconocedor?.recognitionTask(with: p) { [weak self] r, e in
            DispatchQueue.main.async {
                guard let self, self.vuelta == mia, self.activa, !self.enLlamada else { return }
                if let r {
                    let t = r.bestTranscription.formattedString
                    if t != self.actual { self.actual = t; self.ultimoCambio = Date() }
                    if r.isFinal { self.siguienteTramo() }
                } else if e != nil { self.siguienteTramo() }
            }
        }
        reloj?.invalidate()
        reloj = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.revisar() }
    }

    private func reintentar() {
        detener()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.escuchar() }
    }

    /// Cada medio segundo: ¿llamaron a Alma?, ¿terminó una frase (pausa)?, ¿el tramo ya es largo?
    private func revisar() {
        guard activa, !enLlamada else { return }
        let quieto = Date().timeIntervalSince(ultimoCambio)
        if !actual.isEmpty, quieto > 1.2, let pide = Conferencia.pedidoAAlma(actual) { despertar(pide); return }
        if (!actual.isEmpty && quieto > 2.5) || Date().timeIntervalSince(inicioTramo) > 50 { siguienteTramo() }
    }

    /// Lo que viene después de «Alma» (o "" si solo la llamaron); nil si nadie la nombró.
    static func pedidoAAlma(_ t: String) -> String? {
        let llano = t.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
        guard let r = llano.range(of: "\\balma\\b", options: [.regularExpression, .backwards]) else { return nil }
        let i = llano.distance(from: llano.startIndex, to: r.upperBound)
        let resto = String(t.dropFirst(i)).trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
        return resto
    }

    private func siguienteTramo() {
        guardarTramo(); detener(); escuchar()
    }

    private func guardarTramo() {
        let t = actual.trimmingCharacters(in: .whitespacesAndNewlines); actual = ""
        guard !t.isEmpty else { return }
        let h = DateFormatter(); h.dateFormat = "HH:mm"
        let l = "[\(h.string(from: inicioTramo))] \(t)"
        pendiente.append(l); reciente.append(l); if reciente.count > 8 { reciente.removeFirst(reciente.count - 8) }
    }

    private func detener() {
        tarea?.cancel(); tarea = nil
        pedido?.endAudio(); pedido = nil
        motor.inputNode.removeTap(onBus: 0); if motor.isRunning { motor.stop() }
    }

    /// Alguien dijo «Alma, …»: la llamada real se enciende sin señal ni saludo, con el contexto de la reunión.
    private func despertar(_ pide: String) {
        guardarTramo(); detener(); reloj?.invalidate()
        enLlamada = true; emitir()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let ctx = reciente.suffix(6).joined(separator: "\n")
        VozNativa.shared.hablarDesdeConferencia(contexto: ctx, texto: pide.isEmpty ? "Alma" : "Alma, " + pide)
        // al colgar, vuelve a escuchar sola
        reloj = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.enLlamada else { return }
            let e = VozNativa.shared.estado
            if (e == .lista || e == .apagada) && Date().timeIntervalSince(self.ultimoCambio) > 4 {
                self.enLlamada = false; self.reloj?.invalidate(); self.escuchar(); self.emitir()
            }
        }
        ultimoCambio = Date()
    }

    // MARK: - El Hub

    private func mandar(fin: Bool) {
        if pendiente.isEmpty && !fin { return }
        let texto = pendiente.joined(separator: "\n"); let enviados = pendiente; pendiente = []
        let iso = ISO8601DateFormatter()
        llamar(["que": fin ? "fin" : "trozo", "id": id, "texto": texto, "inicio": iso.string(from: inicio)]) { [weak self] ok in
            if !ok && !fin { self?.pendiente.insert(contentsOf: enviados, at: 0) }   // se reintenta en la próxima vuelta
        }
    }

    private func llamar(_ cuerpo: [String: Any], _ listo: @escaping (Bool) -> Void) {
        guard let url = Llave.leer("voz_url"), let token = Llave.leer("voz_token"), let sesion = Llave.leer("voz_sesion"), let u = URL(string: url) else { listo(false); return }
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.timeoutInterval = 40
        r.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        var b = cuerpo; b["hub"] = 1; b["action"] = "conferencia"; b["token"] = token; b["session"] = sesion
        r.httpBody = try? JSONSerialization.data(withJSONObject: b)
        URLSession.shared.dataTask(with: r) { d, _, _ in
            let j = d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async { listo((j?["ok"] as? Bool) == true) }
        }.resume()
    }

    private func emitir() { var e = resumen; e["enLlamada"] = enLlamada; alEvento?(e) }
}
