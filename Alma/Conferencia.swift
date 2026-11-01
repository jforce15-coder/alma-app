import AVFoundation
import Speech
import UIKit

/// Modo conferencia (el botón entre Ajustes y la roca del inicio): un solo modo, inteligente. Alma escucha una reunión,
/// una conferencia, una llamada o un dictado SIN la llamada de ElevenLabs: los silencios no cuestan nada.
///   · El iPhone transcribe en el teléfono (gratis) y, a la vez, graba el audio en el teléfono en partes de 5 min.
///   · Cada tramo dicho (se corta en las pausas) queda con su hora; cada 90 s se manda al Hub (acción «conferencia»).
///   · El Hub decide con los primeros minutos: una persona → dictado (el audio se borra sin subirse); varias → reunión:
///     se suben las partes (también las de antes) y ElevenLabs las transcribe distinguiendo las voces.
///   · Si alguien dice «Alma, …», se enciende la llamada real con la señal, con lo último que se dijo como contexto; si solo
///     dijeron «Alma», ella contesta «Dime». Alma responde y, al colgar, vuelve a escuchar sola.
///   · Escuchar no le quita el sonido a las otras apps (la sesión se mezcla); solo la llamada real lo toma. El micrófono queda
///     encendido entre tramos: solo se cambia el reconocimiento.
///   · Encendida por «Alma» en el Modo Inicio: se apaga sola a los 7 min sin «Alma» y al salir de la app. Encendida con el
///     botón (o el anillo) sigue como siempre, también en segundo plano.
///   · Al apagarlo, el Hub lo clasifica (reunión, conferencia, llamada o memo · esfera · proyecto), resume los acuerdos y
///     lo deja en Pendientes. No se guarda audio: solo el texto.
final class Conferencia {
    static let shared = Conferencia()
    private(set) var activa = false
    /// Silenciada (el botón del micrófono en el inicio): el modo sigue encendido —el reloj de apagado, lo ya oído, el
    /// envío al Hub—, pero el micrófono no oye. Al apagar la conferencia se quita sola.
    private(set) var mudo = false
    var alEvento: (([String: Any]) -> Void)?

    private let reconocedor = SFSpeechRecognizer(locale: Locale(identifier: "es-MX"))
    private var motor = AVAudioEngine()          // se rehace si iOS reinicia el audio (mediaServicesWereReset)
    private var formatoMotor: AVAudioFormat?
    private var pedido: SFSpeechAudioBufferRecognitionRequest?   // con `candado`: también lo usa el hilo del micrófono
    /// El texto (de cualquiera de las versiones que propone el reconocedor) donde alguien dijo «Alma»; nil si nadie.
    private var conAlma: String?
    /// Encendida por «Alma» en el Modo Inicio (no con el botón): se apaga al salir de la app.
    private var porVoz = false
    /// Otra app (o una llamada de teléfono) tomó el audio: se espera a que lo devuelva.
    private var interrumpida = false
    private var tarea: SFSpeechRecognitionTask?
    private var vuelta = 0                      // cada reconocimiento nuevo; los avisos de uno viejo se ignoran
    private var id = ""
    private var actual = ""                     // lo que va del tramo, reconocido en vivo
    private var ultimoCambio = Date(), inicioTramo = Date(), inicio = Date()
    private var pendiente: [String] = []        // tramos por mandar al Hub
    private var reciente: [String] = []         // los últimos tramos: el contexto si llaman a Alma
    private var reloj: Timer?, envio: Timer?
    private var enLlamada = false
    /// El audio en el teléfono, por partes. Solo sale del teléfono si el Hub dice que es una reunión.
    private var archivo: AVAudioFile?, archivoDesde = Date(), parte = 0, archivoFormato: AVAudioFormat?
    /// Escucha por el micrófono de la voz (VozNativa, ya abierto con «Alma con el anillo») en vez de abrir otro.
    private var compartido = false
    private var partes: [Int: URL] = [:]        // partes cerradas que todavía no se suben
    private var reunion = false
    private var subidas = 0                     // partes que ya llegaron al Hub (se las espera antes de cerrar)
    private let candado = NSLock()
    /// Encendida por una llamada larga: si en `apagarTras` segundos nadie dice «Alma», se apaga sola. (Encendida a mano o con
    /// el anillo queda prendida hasta que la apaguen.) El reloj vuelve a empezar después de cada vez que la llaman.
    private var apagarTras: TimeInterval?, relojApagar: Timer?
    private func armarApagado() {
        relojApagar?.invalidate(); relojApagar = nil
        guard let t = apagarTras else { return }
        relojApagar = Timer.scheduledTimer(withTimeInterval: t, repeats: false) { [weak self] _ in
            guard let self, self.activa, !self.enLlamada else { return }
            self.apagar()
        }
    }

    private init() {
        let nc = NotificationCenter.default
        // Encendida por «Alma» (no con el botón): no sigue escuchando con la app en segundo plano.
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.activa, self.porVoz, !self.enLlamada else { return }
            self.apagar()
        }
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, self.activa, let t = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
            if t == AVAudioSession.InterruptionType.began.rawValue {
                guard !self.enLlamada, !self.mudo else { return }
                self.interrumpida = true; self.vuelta += 1; self.guardarTramo(); self.detener()
            } else { self.volverAEscuchar(tras: 0.5) }
        }
        // Si iOS no avisa que terminó la interrupción, al volver a la app se escucha otra vez.
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.interrumpida else { return }
            self.volverAEscuchar(tras: 0.5)
        }
        // iOS reinició el audio: el motor viejo ya no sirve; se hace otro y se vuelve a escuchar.
        nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.vuelta += 1; self.detener(); self.motor = AVAudioEngine(); self.formatoMotor = nil
            if self.activa { self.cerrarArchivo(); self.volverAEscuchar(tras: 1) }
        }
    }
    private func volverAEscuchar(tras t: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
            guard let self, self.activa else { return }
            self.interrumpida = false
            if !self.enLlamada, !self.mudo { self.escuchar() }
        }
    }

    var resumen: [String: Any] { ["tipo": "conferencia", "activa": activa, "voces": reunion, "minutos": activa ? Int(Date().timeIntervalSince(inicio) / 60) : 0, "mudo": mudo] }

    func poner(_ on: Bool) { if on { encender() } else { apagar() } }

    /// Silenciar o volver a escuchar sin apagar el modo. Con `on`: cierra el tramo (no se pierde), deja de oír (el
    /// reconocedor y el motor o el oyente de VozNativa, como al apagar) y conserva todo lo demás. Con `off`: escucha otra vez.
    func silenciar(_ on: Bool) {
        guard activa else { mudo = false; emitir(); return }
        guard on != mudo else { emitir(); return }
        mudo = on
        if on {
            vuelta += 1   // los avisos del reconocimiento que se corta se ignoran (que no reintente ni pase al siguiente tramo)
            if !enLlamada { reloj?.invalidate(); reloj = nil }   // en llamada, ese reloj es el que espera que cuelguen: se queda
            guardarTramo(); detener()
        } else {
            escuchar()   // si Alma está en una llamada, volverá a escuchar sola al colgar
        }
        emitir()
    }

    /// `pedido`: viene del Modo Inicio (EscuchaInicio.swift); «Alma, …» (o "" si solo la llamaron) se atiende de una vez.
    /// `contexto`: lo que se venía hablando (el Modo Inicio o la llamada larga): si llaman a Alma, lo lleva de contexto.
    /// `porVoz`: la encendió «Alma» en el Modo Inicio (no el botón): se apaga al salir de la app.
    func encender(pedido: String? = nil, contexto: [String] = [], alFallar: (() -> Void)? = nil, apagarTras: TimeInterval? = nil, porVoz: Bool = false) {
        guard !activa else { emitir(); return }
        self.apagarTras = apagarTras; self.porVoz = porVoz; interrumpida = false
        SFSpeechRecognizer.requestAuthorization { st in
            AVAudioSession.sharedInstance().requestRecordPermission { mic in
                DispatchQueue.main.async {
                    guard st == .authorized, mic, self.reconocedor?.isAvailable == true else {
                        self.alEvento?(["tipo": "conferencia", "activa": false, "error": "Activa el micrófono y el reconocimiento de voz para Alma en Ajustes del iPhone."]); alFallar?(); return
                    }
                    EscuchaInicio.shared.detener()   // el modo conferencia tiene su propio despertar
                    self.activa = true; self.mudo = false; self.id = "cf" + String(Int(Date().timeIntervalSince1970)); self.inicio = Date()
                    self.pendiente = []; self.reciente = Array(contexto.suffix(8)); self.enLlamada = false
                    self.reunion = false; self.parte = 0; self.subidas = 0; self.partes = [:]; self.cerrarArchivo(); self.borrarViejos()
                    // Sin señal al encender (tampoco al abrir la app): la única señal es la de la llamada a Alma.
                    if let pedido { self.despertar(pedido, texto: "") } else { self.escuchar() }
                    self.envio = Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { [weak self] _ in self?.mandar(fin: false) }
                    self.armarApagado()
                    self.emitir()
                }
            }
        }
    }

    private func apagar() {
        guard activa else { emitir(); return }
        mudo = false
        reloj?.invalidate(); reloj = nil; envio?.invalidate(); envio = nil
        relojApagar?.invalidate(); relojApagar = nil; apagarTras = nil; porVoz = false; interrumpida = false
        guardarTramo(); detener()
        cerrarArchivo()
        if reunion { subirPartes { [weak self] in self?.mandar(fin: true) } } else { mandar(fin: true); borrarPartes() }
        activa = false; enLlamada = false
        // Con «Alma con el anillo» el audio no se suelta: así el próximo doble toque llega aunque el teléfono esté bloqueado.
        if VozNativa.shared.anilloListo { VozNativa.shared.listaTrasConferencia() }
        else { VozNativa.soltarAudio() }   // sin anillo: se suelta el audio (si nadie más escucha) y las otras apps siguen
        emitir()
        EscuchaInicio.shared.liberar()   // de vuelta al Modo Inicio (otro minuto de escucha)
    }

    /// Escucha un tramo: abre el micrófono si hace falta (el de la voz si está abierto, o el propio con la sesión que se
    /// mezcla) y empieza un reconocimiento nuevo. Entre tramos el micrófono sigue encendido: solo se cambia el pedido.
    private func escuchar() {
        guard activa, !enLlamada, !mudo, !interrumpida else { return }
        let voz = VozNativa.shared
        if voz.microfonoListo, let formato = voz.formatoOyente {
            // El micrófono de la voz ya está abierto: se escucha por él (dos micrófonos a la vez dejan mudo a uno).
            if !compartido {
                detener(); compartido = true
                voz.ponerOyente("conferencia") { [weak self] b in self?.oir(b) }
            }
            rotarArchivo(formato)
        } else {
            if compartido { voz.quitarOyente("conferencia"); compartido = false }
            if !motor.isRunning {
                VozNativa.sesionEscucha()   // se mezcla: las otras apps siguen sonando
                let entrada = motor.inputNode, formato = entrada.outputFormat(forBus: 0)
                guard formato.sampleRate > 0 else { reintentar(); return }
                entrada.removeTap(onBus: 0)
                rotarArchivo(formato); formatoMotor = formato
                entrada.installTap(onBus: 0, bufferSize: 1024, format: formato) { [weak self] b, _ in self?.oir(b) }
                motor.prepare()
                do { try motor.start() } catch { reintentar(); return }
            } else if let f = formatoMotor { rotarArchivo(f) }
        }
        nuevoPedido()
        voz.precargarSiToca()   // la ficha del Hub queda pedida: si dicen «Alma», la llamada no la espera
        reloj?.invalidate()
        reloj = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.revisar() }
    }

    /// Lo que oye el micrófono (hilo del micrófono): va al reconocimiento del tramo y a la parte de audio en el teléfono.
    private func oir(_ b: AVAudioPCMBuffer) {
        candado.lock(); pedido?.append(b); try? archivo?.write(from: b); candado.unlock()
    }

    /// Parte de audio nueva cada 5 min (o si cambió el formato del micrófono).
    private func rotarArchivo(_ f: AVAudioFormat) {
        if archivo == nil || archivoFormato != f || Date().timeIntervalSince(archivoDesde) > 300 { cerrarArchivo(); abrirArchivo(f) }
    }

    /// Un reconocimiento nuevo para el tramo, con el micrófono como esté.
    private func nuevoPedido() {
        tarea?.cancel(); tarea = nil
        let p = SFSpeechAudioBufferRecognitionRequest(); p.shouldReportPartialResults = true
        if reconocedor?.supportsOnDeviceRecognition == true { p.requiresOnDeviceRecognition = true }
        if #available(iOS 16, *) { p.addsPunctuation = true }
        p.contextualStrings = ["Alma"]   // que el reconocedor espere oír «Alma» (no «palma» ni «al ma»)
        candado.lock(); let viejo = pedido; pedido = p; candado.unlock()
        viejo?.endAudio()
        vuelta += 1; let mia = vuelta
        actual = ""; conAlma = nil; inicioTramo = Date(); ultimoCambio = Date()
        tarea = reconocedor?.recognitionTask(with: p) { [weak self] r, e in
            DispatchQueue.main.async {
                guard let self, self.vuelta == mia, self.activa, !self.enLlamada, !self.mudo else { return }
                if let r {
                    let t = r.bestTranscription.formattedString
                    if t != self.actual { self.actual = t; self.ultimoCambio = Date() }
                    self.conAlma = Conferencia.versionConAlma(r)
                    // Al cerrar el tramo (o si falla) primero se mira si llamaron a Alma; solo si no, sigue el siguiente.
                    if r.isFinal, !self.llamaron() { self.siguienteTramo() }
                } else if e != nil, !self.llamaron() { self.siguienteTramo() }
            }
        }
    }

    private func reintentar() {
        reloj?.invalidate(); reloj = nil   // que revisar() no lo vuelva a intentar mientras tanto
        detener()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.escuchar() }
    }

    /// Cada cuarto de segundo: ¿llamaron a Alma?, ¿terminó una frase (pausa)?, ¿el tramo ya es largo?
    private func revisar() {
        guard activa, !enLlamada, !mudo, !interrumpida else { return }
        let quieto = Date().timeIntervalSince(ultimoCambio)
        // Solo «Alma» (sin pedido): despierta rápido (0,7 s quieto). Con pedido, espera 1,2 s para no cortar lo que piden.
        if let a = conAlma, let pide = Conferencia.pedidoAAlma(a), quieto > (pide.isEmpty ? 0.7 : 1.2) { despertar(pide, texto: a); return }
        // El micrófono de la voz se abrió (o se cerró) mientras escuchaba, o iOS apagó el propio: se cambia al que corresponde.
        let v = VozNativa.shared
        if compartido != v.microfonoListo, v.estado == .lista || v.estado == .apagada { siguienteTramo(); return }
        if !compartido && !motor.isRunning { siguienteTramo(); return }
        if (!actual.isEmpty && quieto > 2.5) || Date().timeIntervalSince(inicioTramo) > 50 { siguienteTramo() }
    }

    /// ¿Llamaron a Alma en este tramo? Entonces despierta y no se empieza otro.
    private func llamaron() -> Bool {
        guard let a = conAlma, let pide = Conferencia.pedidoAAlma(a) else { return false }
        despertar(pide, texto: a); return true
    }

    /// Busca «Alma» en todas las versiones que propone el reconocedor (no solo la más probable): devuelve esa versión.
    static func versionConAlma(_ r: SFSpeechRecognitionResult) -> String? {
        r.transcriptions.map { $0.formattedString }.first { pedidoAAlma($0) != nil }
    }

    /// Cómo puede oír el reconocedor «Alma» (en el texto sin acentos ni mayúsculas), siempre como palabra entera:
    ///   · «alma» y «halma» (la h no suena);
    ///   · «al ma» y «el ma» (la partió en dos);
    ///   · «palma», solo al empezar la frase («Palma, apunta…»): en medio de una frase casi siempre es la palabra palma.
    /// No se aceptan «alba», «salma», «calma» ni «palma» en medio de la frase: son palabras o nombres comunes y la
    /// despertarían sin que la llamen.
    private static let llamada = try! NSRegularExpression(pattern: "\\b(h?alma|[ae]l ma)\\b|(?:^|[.!?¿¡])\\W*(palma)\\b")

    /// Dónde nombraron a Alma por última vez en el texto llano (sin acentos ni mayúsculas); nil si nadie.
    private static func ultimaAlma(_ llano: String) -> Range<String.Index>? {
        guard let m = llamada.matches(in: llano, range: NSRange(llano.startIndex..., in: llano)).last else { return nil }
        return Range(m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 2), in: llano)
    }

    /// Lo que viene después de «Alma» (o "" si solo la llamaron); nil si nadie la nombró.
    static func pedidoAAlma(_ t: String) -> String? {
        let llano = t.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
        guard let r = ultimaAlma(llano) else { return nil }
        let i = llano.distance(from: llano.startIndex, to: r.upperBound)
        let resto = String(t.dropFirst(i)).trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
        return resto
    }

    /// Lo que se dijo antes de «Alma» en el mismo tramo ("" si nada).
    static func antesDeAlma(_ t: String) -> String {
        let llano = t.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
        guard let r = ultimaAlma(llano) else { return "" }
        let i = llano.distance(from: llano.startIndex, to: r.lowerBound)
        return String(t.prefix(i)).trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
    }

    /// El tramo terminó: se guarda y empieza otro (el micrófono no se reabre si sigue encendido).
    private func siguienteTramo() {
        guardarTramo(); escuchar()
    }

    private func guardarTramo() {
        let t = actual.trimmingCharacters(in: .whitespacesAndNewlines); actual = ""
        guard !t.isEmpty else { return }
        let h = DateFormatter(); h.dateFormat = "HH:mm"
        let l = "[\(h.string(from: inicioTramo))] \(t)"
        pendiente.append(l); reciente.append(l); if reciente.count > 8 { reciente.removeFirst(reciente.count - 8) }
    }

    private func detener() {
        VozNativa.shared.quitarOyente("conferencia")
        tarea?.cancel(); tarea = nil
        candado.lock(); let p = pedido; pedido = nil; candado.unlock()
        p?.endAudio()
        if motor.isRunning { motor.inputNode.removeTap(onBus: 0); motor.stop() }
        compartido = false; conAlma = nil
    }

    /// Alguien dijo «Alma, …»: la llamada real se enciende con la señal, con el contexto de la reunión. Si solo dijeron
    /// «Alma», no se manda texto: Alma contesta «Dime» (VozNativa.saludoCorto) y escucha. `texto`: la versión donde se oyó.
    private func despertar(_ pide: String, texto: String) {
        if !texto.isEmpty { actual = texto }   // el tramo queda con la versión donde se oyó «Alma»
        guardarTramo(); detener(); reloj?.invalidate(); relojApagar?.invalidate()
        enLlamada = true; emitir()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let ctx = reciente.suffix(6).joined(separator: "\n")
        VozNativa.shared.hablarDesdeConferencia(contexto: ctx, texto: pide.isEmpty ? "" : "Alma, " + pide)
        // al colgar, vuelve a escuchar sola
        reloj = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.enLlamada else { return }
            let e = VozNativa.shared.estado
            if (e == .lista || e == .apagada) && Date().timeIntervalSince(self.ultimoCambio) > 4 {
                self.enLlamada = false; self.reloj?.invalidate()
                // Encendida por «Alma» y la app quedó en segundo plano durante la llamada: no sigue escuchando.
                if self.porVoz && UIApplication.shared.applicationState == .background { self.apagar(); return }
                self.escuchar(); self.armarApagado(); self.emitir()
            }
        }
        ultimoCambio = Date()
    }

    // MARK: - El audio (en el teléfono)

    private var carpeta: URL { FileManager.default.temporaryDirectory.appendingPathComponent("conferencia", isDirectory: true) }

    private func abrirArchivo(_ f: AVAudioFormat) {
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let u = carpeta.appendingPathComponent("\(id)-\(parte).m4a")
        let ajustes: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: f.sampleRate, AVNumberOfChannelsKey: f.channelCount, AVEncoderBitRateKey: 48000]
        candado.lock(); archivo = try? AVAudioFile(forWriting: u, settings: ajustes, commonFormat: f.commonFormat, interleaved: f.isInterleaved); candado.unlock()
        archivoDesde = Date(); archivoFormato = f
    }

    /// Cierra la parte actual; si ya es reunión, se sube enseguida.
    private func cerrarArchivo() {
        candado.lock(); let a = archivo; archivo = nil; candado.unlock()
        guard let a else { return }
        partes[parte] = a.url; parte += 1
        if reunion { subirPartes(nil) }
    }

    private func subirPartes(_ listo: (() -> Void)?) {
        let lista = partes.sorted { $0.key < $1.key }
        guard !lista.isEmpty else { listo?(); return }
        let grupo = DispatchGroup()
        for (n, u) in lista {
            guard let d = try? Data(contentsOf: u), d.count > 2000 else { partes[n] = nil; try? FileManager.default.removeItem(at: u); continue }
            partes[n] = nil; grupo.enter()
            llamar(["id": id, "n": n, "audio": d.base64EncodedString(), "mime": "audio/mp4"], accion: "conferenciaAudio", timeout: 120) { [weak self] j in
                if j?["ok"] as? Bool == true { try? FileManager.default.removeItem(at: u); self?.subidas += 1 } else { self?.partes[n] = u }   // se reintenta
                grupo.leave()
            }
        }
        grupo.notify(queue: .main) { listo?() }
    }

    private func borrarPartes() { for (_, u) in partes { try? FileManager.default.removeItem(at: u) }; partes = [:] }
    private func borrarViejos() { try? FileManager.default.removeItem(at: carpeta) }

    // MARK: - El Hub

    private func mandar(fin: Bool) {
        if pendiente.isEmpty && !fin { return }
        let texto = pendiente.joined(separator: "\n"); let enviados = pendiente; pendiente = []
        let iso = ISO8601DateFormatter()
        var b: [String: Any] = ["que": fin ? "fin" : "trozo", "id": id, "texto": texto, "inicio": iso.string(from: inicio)]
        if fin { b["partes"] = reunion ? subidas : 0 }
        llamar(b, accion: "conferencia", timeout: 40) { [weak self] j in
            guard let self else { return }
            if (j?["ok"] as? Bool) != true { if !fin { self.pendiente.insert(contentsOf: enviados, at: 0) }; return }   // se reintenta en la próxima vuelta
            // El Hub decidió que son varias personas: desde ya, la reunión va con voces (también las partes de antes).
            if !fin, (j?["modo"] as? String) == "reunion", !self.reunion { self.reunion = true; self.subirPartes(nil); self.emitir() }
        }
    }

    private func llamar(_ cuerpo: [String: Any], accion: String, timeout: TimeInterval, _ listo: @escaping ([String: Any]?) -> Void) {
        guard let url = Llave.leer("voz_url"), let token = Llave.leer("voz_token"), let sesion = Llave.leer("voz_sesion"), let u = URL(string: url) else { listo(nil); return }
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.timeoutInterval = timeout
        r.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        var b = cuerpo; b["hub"] = 1; b["action"] = accion; b["token"] = token; b["session"] = sesion
        r.httpBody = try? JSONSerialization.data(withJSONObject: b)
        URLSession.shared.dataTask(with: r) { d, _, _ in
            let j = d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async { listo(j) }
        }.resume()
    }

    private func emitir() { var e = resumen; e["enLlamada"] = enLlamada; alEvento?(e) }
}
