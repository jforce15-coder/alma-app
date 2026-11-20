import AVFoundation
import CoreLocation
import Foundation
import UIKit

extension Notification.Name {
    /// La Guía de camino empezó con la pantalla a la vista: sube el mapa (ContentView) y la llamada se baja.
    static let abrirGuiaCamino = Notification.Name("alma.guia.abrir")
}

/// Guía de camino (Hub #661; Juan, 17-nov-2026: «Alma debe dar direcciones por voz, preguntando el medio de transporte y
/// recordando preferencias para guiar paso a paso justo a tiempo, mostrando mapa en la app»).
///   · Alma usa la herramienta de cliente guiar_camino en la llamada (VozNativa.herramientaCliente). La app toma la
///     ubicación, le pide la ruta al Hub (acción guiaCamino, apps-script/guia.js: el medio, lo que se recuerda y Google
///     Maps) y contesta a Alma con cuánto tarda y el primer paso; Alma lo dice. Si el Hub responde necesita_modo, Alma
///     pregunta «¿Vas caminando, en carro, en bici o en bus?» y vuelve a llamarla.
///   · Justo a tiempo: el GPS sigue (también con el teléfono bloqueado y después de colgar) y cada paso se dice al oído
///     cuando Juan llega a su punto (GuiaCaminoReglas). La frase va con la voz de Alma (calleVoz del Hub, pedida un paso
///     antes para que ya esté lista); si no llega en 3 s, la dice la voz de mujer del iPhone (VozIphone) para no llegar
///     tarde. Si hay una llamada en curso, el paso espera a que cuelgue (90 s como mucho).
///   · Fuera del camino: se vuelve a pedir la ruta (20 s entre una y otra) y Alma dice «Te recalculé el camino…».
///   · La pantalla (MapaCamino.swift): dos paneles, el del medio y el mapa con la roca y su luz de rumbo.
///   · Ubicación: la primera vez iOS pregunta. Con el teléfono bloqueado solo se puede empezar si el permiso es «Siempre»;
///     si no, Alma le dice que desbloquee un momento.
final class GuiaCamino: NSObject, ObservableObject, CLLocationManagerDelegate, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    static let shared = GuiaCamino()

    @Published private(set) var activa = false
    @Published private(set) var destino = ""
    @Published private(set) var modoTexto = ""
    @Published private(set) var minutos = 0
    @Published private(set) var linea: [GuiaPunto] = []
    @Published private(set) var fin: GuiaPunto?
    @Published private(set) var proximo = ""
    @Published private(set) var faltan = ""
    @Published private(set) var aviso = ""
    @Published private(set) var llego = false
    // La pantalla estilo carro (Juan, 20-nov-2026): la flecha del próximo paso, el «Luego», lo que falta y la llegada.
    @Published private(set) var modo = ""
    @Published private(set) var giro = "recto"
    @Published private(set) var luego = ""
    @Published private(set) var luegoGiro = ""
    @Published private(set) var restante = ""
    @Published private(set) var minutosFaltan = 0
    @Published private(set) var llegada = ""
    @Published private(set) var posicion: CLLocation?
    /// El medio que muestra el selector de la pantalla (carro · bici · bus · metro · caminando). Tocar otro pide la ruta
    /// otra vez con ese medio (cambiarMedio).
    @Published private(set) var medio = ""

    private let gps = CLLocationManager()
    private var reglas: GuiaCaminoReglas?
    private var pedido = (destino: "", modo: "")
    private var ultima: CLLocation?
    private var esperan: [(CLLocation?) -> Void] = []
    private var recalculado = Date.distantPast
    private var recalculando = false
    private var audios: [String: Data] = [:]
    private var pendiente: (texto: String, desde: Date)?
    private var reproductor: AVAudioPlayer?
    private let iphone = AVSpeechSynthesizer()
    private var sesionPropia = false
    private var metrosTotal = 0.0
    private var medioElegido = ""
    private var rumboEncendido = false
    private static let hora: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "es_GT"); f.dateFormat = "H:mm"; return f }()

    private override init() {
        super.init()
        gps.delegate = self
        gps.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        gps.distanceFilter = 5
        gps.pausesLocationUpdatesAutomatically = false
        iphone.delegate = self
    }

    // MARK: - La herramienta de Alma

    /// guiar_camino { destino, modo?, detener? } → siempre contesta (texto JSON, ¿es error?).
    func herramienta(_ p: [String: Any], _ listo: @escaping (String, Bool) -> Void) {
        DispatchQueue.main.async { self.correr(p, listo) }
    }

    private func correr(_ p: [String: Any], _ listo: @escaping (String, Bool) -> Void) {
        let detener = (p["detener"] as? Bool) == true || (p["detener"] as? String) == "true"
        if detener {
            let habia = activa
            terminar()
            listo(GuiaCamino.json(habia ? ["ok": true, "detenida": true] : ["ok": true, "nota": "No había una guía en curso."]), false); return
        }
        let destino = (p["destino"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destino.isEmpty else { listo(GuiaCamino.json(["error": "Falta a dónde va: pregúntaselo."]), true); return }
        let modo = (p["modo"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        ubicacion { [weak self] loc in
            guard let self else { return }
            guard let loc else { listo(GuiaCamino.json(["error": self.sinUbicacion()]), true); return }
            self.pedirRuta(destino, modo: modo, desde: loc) { j in
                guard let j else { listo(GuiaCamino.json(["error": "El Hub no contestó a tiempo. Dile que lo intentas de nuevo en un momento."]), true); return }
                if (j["necesita_modo"] as? Bool) == true {
                    listo(GuiaCamino.json(["necesita_modo": true, "instruccion": "Pregúntale en una frase: «¿Vas caminando, en carro, en bici o en bus?» y vuelve a llamar guiar_camino con el mismo destino y su respuesta."]), false); return
                }
                guard (j["ok"] as? Bool) == true, self.empezar(j, destino: destino, modo: modo) else {
                    listo(GuiaCamino.json(["error": (j["error"] as? String) ?? "No pude armar la ruta."]), true); return
                }
                var r: [String: Any] = ["ok": true, "destino": self.destino, "medio": self.modoTexto, "minutos": self.minutos,
                                        "primer_paso": self.reglas?.pasos.first?.texto ?? "", "pasos": self.reglas?.pasos.count ?? 0,
                                        "mapa": UIApplication.shared.applicationState == .active ? "ya está en la pantalla" : "teléfono bloqueado: la guía va solo por voz",
                                        "instruccion": "Di en UNA frase cuánto tarda y el primer paso. Los demás los dice la app justo a tiempo: no los leas."]
                if let rec = j["recordado"] as? String {
                    r["recordado"] = rec == "lugar" ? "el medio que eligió la última vez para este lugar" : "el último medio que usó"
                }
                listo(GuiaCamino.json(r), false)
            }
        }
    }

    /// Para la ficha de la llamada: si hay una guía en curso, Alma lo sabe.
    var ficha: String {
        guard activa else { return "" }
        return "GUÍA DE CAMINO EN CURSO: hacia " + destino + " " + modoTexto + ". Si Juan pide parar, usa guiar_camino con detener: true."
    }

    // MARK: - La ruta

    @discardableResult
    private func empezar(_ j: [String: Any], destino pedido: String, modo: String) -> Bool {
        let ps: [GuiaPaso] = (j["pasos"] as? [[String: Any]] ?? []).compactMap { d in
            guard let t = d["texto"] as? String, let lat = GuiaCamino.num(d["lat"]), let lng = GuiaCamino.num(d["lng"]) else { return nil }
            return GuiaPaso(texto: t, punto: GuiaPunto(lat: lat, lng: lng), antes: GuiaCamino.num(d["antes"]), giro: d["giro"] as? String ?? "")
        }
        guard !ps.isEmpty, let f = j["fin"] as? [String: Any], let flat = GuiaCamino.num(f["lat"]), let flng = GuiaCamino.num(f["lng"]) else { return false }
        let m = j["modo"] as? String ?? "caminando"
        let l = GuiaCaminoReglas.decodificar(j["linea"] as? String ?? "")
        let nuevo = !activa
        reglas = GuiaCaminoReglas(pasos: ps, fin: GuiaPunto(lat: flat, lng: flng), modo: m, linea: l)
        self.pedido = (pedido, m)   // al recalcular va con el medio que salió (el dicho o el recordado)
        destino = j["destino"] as? String ?? pedido
        modoTexto = j["modo_texto"] as? String ?? m
        minutos = (j["minutos"] as? NSNumber)?.intValue ?? 0
        linea = reglas?.linea ?? []
        fin = GuiaPunto(lat: flat, lng: flng)
        self.modo = m
        medio = GuiaPantalla.medioVisto(hub: m, elegido: medioElegido)
        metrosTotal = (j["metros"] as? NSNumber)?.doubleValue ?? 0
        if metrosTotal <= 0, let a = linea.first { metrosTotal = GuiaCaminoReglas.restante(a, linea) }
        faltan = ""; aviso = ""; llego = false
        pantalla(desde: nil)
        activa = true
        audios = [:]
        gps.activityType = m == "carro" ? .automotiveNavigation : (m == "bus" ? .otherNavigation : .fitness)
        gps.allowsBackgroundLocationUpdates = true
        gps.showsBackgroundLocationIndicator = true
        gps.startUpdatingLocation()
        UIApplication.shared.isIdleTimerDisabled = UIApplication.shared.applicationState == .active
        if nuevo, UIApplication.shared.applicationState == .active { NotificationCenter.default.post(name: .abrirGuiaCamino, object: nil) }
        prepararVoz(1)
        return true
    }

    private func pedirRuta(_ destino: String, modo: String, desde l: CLLocation, _ listo: @escaping ([String: Any]?) -> Void) {
        var b: [String: Any] = ["destino": destino, "lat": l.coordinate.latitude, "lng": l.coordinate.longitude]
        if !modo.isEmpty { b["modo"] = modo }
        llamarHub(b, accion: "guiaCamino", timeout: 15, listo)
    }

    private func recalcular(desde l: CLLocation) {
        guard !recalculando, Date().timeIntervalSince(recalculado) > 20 else { return }
        recalculando = true; recalculado = Date(); aviso = "Recalculando…"
        pedirRuta(pedido.destino, modo: pedido.modo, desde: l) { [weak self] j in
            guard let self else { return }
            self.recalculando = false
            guard self.activa else { return }
            guard let j, (j["ok"] as? Bool) == true, self.empezar(j, destino: self.pedido.destino, modo: self.pedido.modo) else { self.aviso = "No pude recalcular; sigo con el camino de antes."; return }
            self.decir("Te recalculé el camino. " + (self.reglas?.pasos.first?.texto ?? ""))
        }
    }

    /// El selector del medio en la pantalla (Juan, 20-nov-2026): la misma ruta con otro medio. «metro» va al Hub como
    /// «metro» (lo toma como transporte público) y en la pantalla se queda el metro. Alma dice el primer paso nuevo.
    func cambiarMedio(_ m: String) {
        guard activa, !llego, m != medio, !recalculando, let l = ultima ?? posicion else { return }
        let antes = medio, antesElegido = medioElegido
        medioElegido = m; medio = m
        recalculando = true; recalculado = Date(); aviso = "Cambiando el medio…"
        pedirRuta(pedido.destino, modo: m, desde: l) { [weak self] j in
            guard let self else { return }
            self.recalculando = false
            guard self.activa else { return }
            guard let j, (j["ok"] as? Bool) == true, self.empezar(j, destino: self.pedido.destino, modo: m) else {
                self.medio = antes; self.medioElegido = antesElegido
                self.aviso = (j?["sin_ruta"] as? Bool) == true ? "No hay ruta con ese medio; sigo con el de antes." : "No pude cambiar el medio; sigo con el de antes."
                return
            }
            self.aviso = ""
            self.decir("Te llevo " + self.modoTexto + ". " + (self.reglas?.pasos.first?.texto ?? ""))
        }
    }

    /// Termina la guía. Al llegar, el mapa se queda unos segundos con «Llegaste».
    func terminar(llegando: Bool = false) {
        guard activa else { return }
        if llegando {
            llego = true; proximo = "Llegaste a " + destino; faltan = ""; giro = "llegar"; luego = ""; restante = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in if self?.llego == true { self?.terminar() } }
            gps.stopUpdatingLocation(); gps.allowsBackgroundLocationUpdates = false
            return
        }
        activa = false; llego = false; reglas = nil; pendiente = nil; audios = [:]; posicion = nil; medioElegido = ""
        rumbo(false)
        gps.stopUpdatingLocation()
        gps.allowsBackgroundLocationUpdates = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - Ubicación

    private func ubicacion(_ listo: @escaping (CLLocation?) -> Void) {
        let st = gps.authorizationStatus, visible = UIApplication.shared.applicationState == .active
        if st == .denied || st == .restricted { listo(nil); return }
        if let u = ultima, -u.timestamp.timeIntervalSinceNow < 15, u.horizontalAccuracy >= 0, u.horizontalAccuracy <= 100 { listo(u); return }
        if !visible && st != .authorizedAlways && !activa { listo(nil); return }   // iOS no deja empezar a medir con el teléfono bloqueado
        esperan.append(listo)
        if st == .notDetermined { gps.requestAlwaysAuthorization() } else { gps.startUpdatingLocation() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, !self.esperan.isEmpty else { return }
            let u = self.ultima.flatMap { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 300 ? $0 : nil }
            self.entregar(u)
        }
    }

    private func entregar(_ l: CLLocation?) {
        let e = esperan; esperan = []
        e.forEach { $0(l) }
        if !activa { gps.stopUpdatingLocation() }
    }

    private func sinUbicacion() -> String {
        switch gps.authorizationStatus {
        case .denied, .restricted:
            return "La app de Alma no tiene permiso de ubicación. Dile que lo active en Ajustes del iPhone → Alma → Ubicación."
        case .notDetermined:
            return "El iPhone está pidiendo permiso de ubicación: dile que toque «Permitir» y lo intentas otra vez."
        default:
            if UIApplication.shared.applicationState != .active && gps.authorizationStatus != .authorizedAlways {
                return "Con el teléfono bloqueado no puedo empezar la guía. Dile que lo desbloquee un momento (o que en Ajustes → Alma → Ubicación elija «Siempre») y lo intentas otra vez."
            }
            return "Todavía no tengo señal del GPS. Dile que lo intentas en unos segundos."
        }
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        let st = m.authorizationStatus
        if st == .authorizedAlways || st == .authorizedWhenInUse { if !esperan.isEmpty || activa { m.startUpdatingLocation() } }
        else if st == .denied || st == .restricted { entregar(nil) }
    }

    // MARK: - El rumbo del teléfono (la luz de rumbo de la roca en el mapa)

    /// Solo mientras la pantalla de la guía está a la vista: la brújula gasta batería.
    func rumbo(_ encender: Bool) {
        guard encender != rumboEncendido, CLLocationManager.headingAvailable() else { return }
        rumboEncendido = encender
        if encender { gps.headingFilter = 2; gps.startUpdatingHeading() } else { gps.stopUpdatingHeading() }
    }

    /// Con la pantalla acostada, iOS tiene que saber hacia dónde quedó la parte de arriba para que el rumbo no salga
    /// girado 90°.
    func orientarRumbo(_ o: UIInterfaceOrientation) {
        switch o {
        case .portraitUpsideDown: gps.headingOrientation = .portraitUpsideDown
        case .landscapeLeft: gps.headingOrientation = .landscapeRight    // la pantalla a la izquierda = el teléfono girado a la derecha
        case .landscapeRight: gps.headingOrientation = .landscapeLeft
        default: gps.headingOrientation = .portrait
        }
    }

    func locationManager(_ m: CLLocationManager, didUpdateHeading h: CLHeading) {
        guard let r = GuiaPantalla.rumbo(verdadero: h.trueHeading, magnetico: h.magneticHeading) else { return }
        RumboGuia.shared.brujula(r)
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .denied { entregar(nil) }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations ls: [CLLocation]) {
        guard let l = ls.last else { return }
        ultima = l
        if !esperan.isEmpty, l.horizontalAccuracy >= 0, l.horizontalAccuracy <= 100 { entregar(l) }
        guard activa, !llego, var r = reglas else { return }
        let p = GuiaPunto(lat: l.coordinate.latitude, lng: l.coordinate.longitude)
        let ev = r.ubicacion(p, precision: l.horizontalAccuracy)
        reglas = r
        faltan = r.faltan(desde: p).map(GuiaCaminoReglas.textoDistancia) ?? ""
        posicion = l
        pantalla(desde: p)
        if aviso == "Recalculando…" && !recalculando { aviso = "" }
        decirPendiente()
        switch ev {
        case .decir(let i, let t)?: decir(t); prepararVoz(i + 1)
        case .llegaste?: decir("Llegaste a " + destino + "."); terminar(llegando: true)
        case .recalcular?: recalcular(desde: l)
        case nil: break
        }
    }

    /// Lo que muestra la pantalla: el próximo paso (sin «en media cuadra»: la distancia va en grande), su flecha, el
    /// «Luego», lo que falta por el camino, los minutos y la hora de llegada.
    private func pantalla(desde p: GuiaPunto?) {
        guard let r = reglas else { return }
        proximo = r.proximoTexto.map(GuiaCaminoReglas.textoPantalla) ?? "Llegar a " + destino
        giro = r.proximoGiro
        luego = r.luegoTexto.map(GuiaCaminoReglas.textoPantalla) ?? (r.proximoTexto == nil ? "" : "Llegar a " + destino)
        luegoGiro = r.luegoGiro
        let falta = p.map { GuiaCaminoReglas.restante($0, r.linea) } ?? metrosTotal
        restante = falta > 0 ? GuiaCaminoReglas.textoDistancia(falta) : ""
        minutosFaltan = metrosTotal > 0 ? max(1, Int((Double(minutos) * min(1, falta / metrosTotal)).rounded())) : minutos
        llegada = GuiaCamino.hora.string(from: Date().addingTimeInterval(Double(minutosFaltan) * 60))
    }

    // MARK: - La voz

    private var hayLlamada: Bool { VozNativa.shared.estado == .hablando || VozNativa.shared.estado == .conectando }

    /// Pide de antemano la voz de Alma del paso i (o de «Llegaste», si ya no quedan pasos).
    private func prepararVoz(_ i: Int) {
        guard let r = reglas else { return }
        let t = i < r.pasos.count ? r.pasos[i].texto : "Llegaste a " + destino + "."
        guard audios[t] == nil else { return }
        llamarHub(["texto": t], accion: "calleVoz", timeout: 15) { [weak self] j in
            if let a = j?["audio"] as? String, let d = Data(base64Encoded: a) { self?.audios[t] = d }
        }
    }

    private func decir(_ t: String) {
        let t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if hayLlamada { pendiente = (t, Date()); return }   // no encima de Alma: se dice al colgar
        pendiente = nil
        if let d = audios[t], tocar(d) { return }
        // La voz de Alma no estaba lista: se pide, pero a los 3 s habla el iPhone (más vale a tiempo).
        var hecho = false
        llamarHub(["texto": t], accion: "calleVoz", timeout: 3) { [weak self] j in
            guard let self, !hecho else { return }
            hecho = true
            if let a = j?["audio"] as? String, let d = Data(base64Encoded: a), self.tocar(d) { self.audios[t] = d; return }
            self.hablarIphone(t)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, !hecho else { return }
            hecho = true; self.hablarIphone(t)
        }
    }

    private func decirPendiente() {
        guard let p = pendiente, !hayLlamada else { return }
        pendiente = nil
        if Date().timeIntervalSince(p.desde) < 90 { decir(p.texto) }
    }

    /// Si nadie más usa el audio (Modo calle, conferencia, el Modo Inicio, una llamada), la guía lo toma solo mientras
    /// habla y baja la música; si alguien lo usa, suena dentro de su sesión sin tocarla.
    private func tomarAudio() {
        let ocupado = ModoCalle.shared.ocupaMicrofono || Conferencia.shared.activa || EscuchaInicio.shared.escuchando || hayLlamada
        guard !ocupado, !sesionPropia else { return }
        let s = AVAudioSession.sharedInstance()
        do {
            try s.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try s.setActive(true); sesionPropia = true
        } catch { sesionPropia = false }
    }

    private func soltarAudio() {
        guard sesionPropia else { return }
        sesionPropia = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func tocar(_ d: Data) -> Bool {
        tomarAudio()
        guard let p = try? AVAudioPlayer(data: d) else { soltarAudio(); return false }
        reproductor = p; p.delegate = self; p.volume = 1
        guard p.play() else { reproductor = nil; soltarAudio(); return false }
        return true
    }

    private func hablarIphone(_ t: String) {
        tomarAudio()
        let u = AVSpeechUtterance(string: t)
        u.voice = VozIphone.elegida ?? AVSpeechSynthesisVoice(language: "es-MX")
        iphone.speak(u)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { reproductor = nil; soltarAudio() }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) { reproductor = nil; soltarAudio() }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { soltarAudio() }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { soltarAudio() }

    // MARK: - El Hub

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

    private static func num(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) }
        return nil
    }

    static func json(_ o: [String: Any]) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }
}
