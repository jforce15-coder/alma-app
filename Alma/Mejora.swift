import AVFoundation
import Speech
import SwiftUI

/// Dos toques a Alma con un cuadro de texto activo: Alma escucha lo que le pidas («hazlo más formal», «escribe que llego
/// a las 3») y lo escribe en el cuadro. Si no dices nada:
///   · con texto en el cuadro, lo mejora (ortografía, claridad) a los pocos segundos;
///   · con el cuadro vacío, pregunta «¿En qué te ayudo?» con su voz y escucha otro rato; si sigue sin oír nada, se apaga.
/// Lo que dices se reconoce en el teléfono; el Hub (mejorarCampo) escribe la respuesta.
final class MejoraCampo: ObservableObject {
    static let shared = MejoraCampo()
    enum Estado { case apagada, escuchando, pensando, diciendo }
    @Published private(set) var estado = Estado.apagada
    @Published private(set) var oido = ""
    @Published private(set) var aviso = ""
    /// Lo que Alma contestó en voz (cuando pediste ayuda y no algo escrito); se ve junto a la roca mientras habla.
    @Published private(set) var respuesta = ""

    private let reconocedor = SFSpeechRecognizer(locale: Locale(identifier: "es-MX"))
    private let motor = AVAudioEngine()
    private var pedido: SFSpeechAudioBufferRecognitionRequest?
    private var tarea: SFSpeechRecognitionTask?
    private var reloj: Timer?
    private var desde = Date(), ultimoCambio = Date()
    private var pregunto = false, hayTexto = false
    private var saludo: Data?
    private var reproductor: AVAudioPlayer?
    private let sintetizador = AVSpeechSynthesizer()
    private var fin: ((String?) -> Void)?

    /// fin(pedido): "" = sin pedido (mejorar lo que hay); nil = no hubo nada que hacer.
    func empezar(textoCampo: String, _ fin: @escaping (String?) -> Void) {
        guard estado == .apagada || estado == .diciendo, VozNativa.shared.estado != .hablando, VozNativa.shared.estado != .conectando else { return }
        reproductor?.stop(); respuesta = ""
        self.fin = fin; hayTexto = !textoCampo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty; pregunto = false; oido = ""
        if !hayTexto && saludo == nil { pedirSaludo() }
        SFSpeechRecognizer.requestAuthorization { st in
            AVAudioSession.sharedInstance().requestRecordPermission { mic in
                DispatchQueue.main.async {
                    guard st == .authorized, mic, self.reconocedor?.isAvailable == true else {
                        // sin permiso para escuchar: con texto, igual lo mejora; sin texto, no hay qué hacer
                        self.aviso = "Activa el micrófono y el reconocimiento de voz para Alma en Ajustes."
                        self.terminar(self.hayTexto ? "" : nil); return
                    }
                    VozNativa.shared.senal()
                    self.escuchar()
                }
            }
        }
    }

    /// Alma respondió (o falló): vuelve a su estado normal. Si contestó en voz, primero lo dice (y se ve) y luego se apaga.
    func listo(decir: String? = nil, audio: Data? = nil) {
        oido = ""
        guard let decir, !decir.isEmpty else { estado = .apagada; respuesta = ""; return }
        respuesta = decir; estado = .diciendo
        var dura = max(3.5, Double(decir.count) / 14)
        if let a = audio, let pl = try? AVAudioPlayer(data: a) {
            try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: VozNativa.opciones)
            reproductor = pl; pl.volume = 1; pl.play(); dura = pl.duration + 1.5
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + dura) { [weak self] in
            guard let self, self.estado == .diciendo, self.respuesta == decir else { return }
            self.estado = .apagada; self.respuesta = ""
        }
    }

    /// Qué decir junto a la roca.
    var textoAviso: String {
        switch estado {
        case .apagada: return ""
        case .escuchando: return oido.isEmpty ? (pregunto ? "¿En qué te ayudo?" : "Te escucho…") : oido
        case .pensando: return "Escribiendo…"
        case .diciendo: return respuesta
        }
    }

    private func escuchar() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .default, options: VozNativa.opciones)
        try? s.setActive(true)
        let p = SFSpeechAudioBufferRecognitionRequest(); p.shouldReportPartialResults = true
        if reconocedor?.supportsOnDeviceRecognition == true { p.requiresOnDeviceRecognition = true }
        pedido = p
        let entrada = motor.inputNode, formato = entrada.outputFormat(forBus: 0)
        guard formato.sampleRate > 0 else { terminar(hayTexto ? "" : nil); return }
        entrada.removeTap(onBus: 0)
        entrada.installTap(onBus: 0, bufferSize: 1024, format: formato) { [weak p] b, _ in p?.append(b) }
        motor.prepare()
        do { try motor.start() } catch { terminar(hayTexto ? "" : nil); return }
        tarea = reconocedor?.recognitionTask(with: p) { [weak self] r, _ in
            guard let self, let r else { return }
            DispatchQueue.main.async {
                let t = r.bestTranscription.formattedString
                if t != self.oido { self.oido = t; self.ultimoCambio = Date() }
            }
        }
        estado = .escuchando; desde = Date(); ultimoCambio = Date()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        reloj?.invalidate()
        reloj = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.revisar() }
    }

    /// Cada cuarto de segundo: ¿ya terminó de hablar? ¿lleva mucho sin decir nada?
    private func revisar() {
        guard estado == .escuchando else { return }
        let ahora = Date()
        if !oido.isEmpty {
            if ahora.timeIntervalSince(ultimoCambio) > 1.6 { terminar(oido) }
            return
        }
        let espera = hayTexto ? 3.5 : (pregunto ? 9 : 5)
        guard ahora.timeIntervalSince(desde) > espera else { return }
        if hayTexto { terminar("") }
        else if !pregunto { preguntar() }
        else { terminar(nil) }
    }

    /// «¿En qué te ayudo?»: deja de escuchar mientras habla (para no oírse a sí misma) y luego vuelve a escuchar.
    private func preguntar() {
        pregunto = true; detenerCaptura()
        var dura = 1.6
        if let d = saludo, let pl = try? AVAudioPlayer(data: d) {
            reproductor = pl; pl.volume = 1; pl.play(); dura = pl.duration + 0.25
        } else {
            let u = AVSpeechUtterance(string: "¿En qué te ayudo?"); u.voice = AVSpeechSynthesisVoice(language: "es-MX"); sintetizador.speak(u)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + dura) { [weak self] in
            guard let self, self.fin != nil else { return }
            self.escuchar()
        }
    }

    private func detenerCaptura() {
        reloj?.invalidate(); reloj = nil
        if motor.isRunning { motor.stop() }
        motor.inputNode.removeTap(onBus: 0)
        pedido?.endAudio(); tarea?.cancel(); pedido = nil; tarea = nil
    }

    private func terminar(_ dicho: String?) {
        detenerCaptura()
        let f = fin; fin = nil
        estado = dicho == nil ? .apagada : .pensando
        if dicho == nil { oido = "" }
        f?(dicho)
    }

    // MARK: - El Hub

    private func llamar(_ cuerpo: [String: Any], timeout: TimeInterval = 40, _ listo: @escaping ([String: Any]?) -> Void) {
        guard let url = Llave.leer("voz_url"), let token = Llave.leer("voz_token"), let sesion = Llave.leer("voz_sesion"), let u = URL(string: url) else { listo(nil); return }
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.timeoutInterval = timeout
        r.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        var b = cuerpo; b["hub"] = 1; b["action"] = "mejorarCampo"; b["token"] = token; b["session"] = sesion
        r.httpBody = try? JSONSerialization.data(withJSONObject: b)
        URLSession.shared.dataTask(with: r) { d, _, _ in
            let j = d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async { listo(j) }
        }.resume()
    }

    private func pedirSaludo() {
        llamar(["que": "saludo"], timeout: 15) { [weak self] j in
            if let a = j?["audio"] as? String, let d = Data(base64Encoded: a), !d.isEmpty { self?.saludo = d }
        }
    }

    /// Le pide al Hub qué hacer: el texto para el cuadro y/o lo que Alma te contesta en voz (con su audio).
    /// Va con la dirección de la página y, si hay, la captura de la pantalla: Alma ayuda con ese contexto.
    func escribir(texto: String, pedido: String, pagina: String, url: String, etiqueta: String, captura: String?,
                  _ listo: @escaping (_ campo: String?, _ decir: String?, _ audio: Data?) -> Void) {
        var b: [String: Any] = ["texto": texto, "pedido": pedido, "pagina": pagina, "url": url, "etiqueta": etiqueta]
        if let captura { b["captura"] = captura }
        llamar(b, timeout: 60) { j in
            guard (j?["ok"] as? Bool) == true else { listo(nil, nil, nil); return }
            let c = (j?["texto"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let d = (j?["decir"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let a = (j?["audio"] as? String).flatMap { Data(base64Encoded: $0) }
            listo(c, d, a)
        }
    }
}
