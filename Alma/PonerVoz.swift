import AVFoundation

/// Suena lo que pidió poner_voz (Hub #779; las reglas en PonerVozReglas.swift): las voces locales, cada una con su frase, o
/// un audio por enlace. Entrega PCM de 16 bits mono a `hz` por `trozo`: con el agente de ElevenLabs, VozNativa lo pone en la
/// salida de la llamada (la cancelación de eco lo resta del micrófono); con Claudio local, sale como su propio audio. Al
/// terminar de entregar, `fin` con lo que se le contesta a Claudio. Todo en el hilo principal.
final class PonerVoz {
    private var habla: HablaPorFrases?
    private var tarea: URLSessionDataTask?
    private var vuelta = 0
    /// Si no sonó nada: la frase para Juan (Claudio local la dice; con ElevenLabs la dice el agente con el resultado).
    private(set) var paraJuan = ""

    func cancelar() { vuelta += 1; habla?.cancelar(); habla = nil; tarea?.cancel(); tarea = nil }

    func correr(_ p: [String: Any], hz: Int, trozo: @escaping (Data) -> Void, fin: @escaping (String, Bool) -> Void) {
        cancelar()
        paraJuan = ""
        let v = VocesLocales.shared
        v.actualizarCatalogo()
        var personajes: [String: String] = [:]
        for pj in VozKokoroReglas.Personaje.allCases { let a = v.ajustes(pj); personajes[pj.rawValue] = a.motor == .pocket ? VozPocketReglas.voz(pj).id : a.motor == .kokoro ? a.voz : "iphone" }
        let texto = { (k: String) in (p[k] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        let enlace = texto("enlace")
        switch PonerVozReglas.pedido(voz: texto("voz"), enlace: enlace, voces: v.voces, personajes: personajes) {
        case .nada(let t):
            paraJuan = enlace.isEmpty ? PonerVozReglas.noEstaParaJuan(v.voces) : PonerVozReglas.enlaceParaJuan
            fin(t, true)
        case .lista:
            paraJuan = PonerVozReglas.listaParaJuan(v.voces)
            fin(PonerVozReglas.lista(v.voces, personajes: personajes), false)
        case .enlace(let u): bajar(u, hz: hz, trozo: trozo, fin: fin)
        case .voces(let ms): voces(ms, frase: texto("frase"), hz: hz, trozo: trozo, fin: fin)
        }
    }

    /// Una voz tras otra, con un respiro entre ellas. La que no está en el iPhone no suena (se baja para la próxima).
    private func voces(_ ms: [PonerVozReglas.Muestra], frase: String, hz: Int, trozo: @escaping (Data) -> Void, fin: @escaping (String, Bool) -> Void) {
        vuelta += 1
        let mia = vuelta, v = VocesLocales.shared
        var sonaron: [String] = [], faltan: [String] = [], sinModelo = false, i = 0
        func siguiente() {
            guard mia == vuelta else { return }
            guard i < ms.count else {
                habla = nil
                let r = PonerVozReglas.resultado(sonaron: sonaron, faltan: faltan, sinModelo: sinModelo)
                if r.error { paraJuan = PonerVozReglas.noSonoParaJuan(sinModelo: sinModelo) }
                fin(r.texto, r.error); return
            }
            let m = ms[i]; i += 1
            let motor: MotorVoz
            if m.pocket {
                let p: VozKokoroReglas.Personaje = m.id == VozPocketReglas.claudio.id ? .claudio : .maricarmen
                guard let g = v.motorGratis(p, respaldo: nil) else { faltan.append(m.nombre); v.descargarGratis(celular: true); siguiente(); return }
                motor = g
            } else if m.kokoro {
                guard v.modeloListo else { sinModelo = true; faltan.append(m.nombre); v.descargarModelo(celular: false); siguiente(); return }
                guard v.vozLista(m.id), let t = v.tabla(m.id) else { faltan.append(m.nombre); v.descargarVoz(m.id, celular: true); siguiente(); return }
                let acento = v.voces.first { $0.id == m.id }?.acento ?? .latino
                motor = MotorKokoro(ajustes: VozKokoroReglas.Ajustes(motor: .kokoro, voz: m.id, velocidad: 1.0, acento: acento), tabla: t, excepciones: v.pronunciaciones)
            } else {
                motor = MotorIphone(voz: VozIphone.elegida ?? AVSpeechSynthesisVoice(language: "es-MX"), ajustes: ClaudioLocalReglas.Ajustes())
            }
            // Sin respaldo: si Kokoro falla, esa voz no suena (otra voz diciendo «Soy Dora» engañaría).
            let h = HablaPorFrases(principal: nil, respaldo: motor, hz: hz)
            habla = h
            var bytes = 0
            h.decir(PonerVozReglas.frase(m, pedida: frase), trozo: { d in bytes += d.count; trozo(d) }, fin: {
                if bytes > 0 { sonaron.append(m.nombre); trozo(PonerVozReglas.silencio(hz: hz)) } else { faltan.append(m.nombre) }
                siguiente()
            })
        }
        siguiente()
    }

    /// Un audio por enlace: se baja, se pasa a PCM de 16 bits mono a `hz` (hasta minuto y medio) y se entrega en trozos.
    private func bajar(_ u: URL, hz: Int, trozo: @escaping (Data) -> Void, fin: @escaping (String, Bool) -> Void) {
        vuelta += 1
        let mia = vuelta
        var r = URLRequest(url: u); r.timeoutInterval = 20
        tarea = URLSession.shared.dataTask(with: r) { [weak self] data, resp, _ in
            var pcm: Data?
            if let data, (resp as? HTTPURLResponse)?.statusCode == 200, data.count <= PonerVozReglas.maxBytes {
                pcm = PonerVoz.decodificar(data, ext: u.pathExtension, hz: hz)
            }
            DispatchQueue.main.async {
                guard let self, self.vuelta == mia else { return }
                self.tarea = nil
                guard let pcm, !pcm.isEmpty else { self.paraJuan = PonerVozReglas.enlaceParaJuan; fin(PonerVozReglas.enlaceFallo, true); return }
                for t in VozKokoroReglas.trozos(pcm, hz: hz) { trozo(t) }
                fin(PonerVozReglas.enlaceListo(segundos: Double(pcm.count / 2) / Double(hz)), false)
            }
        }
        tarea?.resume()
    }

    static func decodificar(_ data: Data, ext: String, hz: Int) -> Data? {
        let e = ext.lowercased().filter { $0.isLetter || $0.isNumber }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("poner-voz-" + UUID().uuidString + "." + (e.isEmpty ? "mp3" : e))
        guard (try? data.write(to: tmp)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard let f = try? AVAudioFile(forReading: tmp),
              let salida = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(hz), channels: 1, interleaved: true),
              let c = AVAudioConverter(from: f.processingFormat, to: salida) else { return nil }
        c.downmix = true
        let tope = AVAudioFramePosition(f.processingFormat.sampleRate * PonerVozReglas.maxSegundos)
        let total = AVAudioFrameCount(max(0, min(f.length, tope)))
        guard total > 0, let entrada = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: total),
              (try? f.read(into: entrada, frameCount: total)) != nil, entrada.frameLength > 0 else { return nil }
        let cap = AVAudioFrameCount(Double(entrada.frameLength) * Double(hz) / f.processingFormat.sampleRate) + 4096
        guard let out = AVAudioPCMBuffer(pcmFormat: salida, frameCapacity: cap) else { return nil }
        var dado = false
        var err: NSError?
        _ = c.convert(to: out, error: &err) { _, st in
            if dado { st.pointee = .endOfStream; return nil }
            dado = true; st.pointee = .haveData; return entrada
        }
        guard err == nil, out.frameLength > 0, let p = out.int16ChannelData else { return nil }
        return Data(bytes: p[0], count: Int(out.frameLength) * 2)
    }
}
