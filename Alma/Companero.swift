import UIKit

/// Modo compañero (Hub #607 T-C1): manda al Hub (acción vivoPublicar) el estado y los subtítulos de la llamada que está en
/// este dispositivo, para que el otro los muestre sin audio. Las reglas de cuándo mandar: ColaVivo.swift.
final class Companero {
    static let shared = Companero()
    private var cola = ColaVivo()
    private var reloj: Timer?
    private var enviando = false
    private let dispositivo = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"

    /// Una sola llamada (UnaLlamada, ColaVivo.swift): lo que la página cuenta de este dispositivo. Se guarda el interruptor
    /// porque el Modo calle o un aviso pueden abrir con la página cerrada.
    private static let claveOn = "companero_on"
    private let candado = NSLock()
    private var otra = "", vista: Date?, telActivo = false
    /// `tel`: el iPhone está activo (una voz a la vez); en el iPad la página lo cuenta aunque el compañero esté apagado.
    func pagina(on: Bool, otra o: String, tel: Bool = false) {
        UserDefaults.standard.set(on, forKey: Companero.claveOn)
        candado.lock(); otra = String(o.prefix(30)); telActivo = tel; vista = Date(); candado.unlock()
    }
    /// nil = este dispositivo puede abrir la llamada; si no, por qué no (desde cualquier hilo).
    func noDeja(porVoz: Bool) -> String? {
        candado.lock(); let o = otra, v = vista, t = telActivo; candado.unlock()
        return UnaLlamada.motivo(companero: UserDefaults.standard.bool(forKey: Companero.claveOn), porVoz: porVoz, otra: o, visto: v, ahora: Date(),
                                 telefono: dispositivo == "iPhone", telActivo: t)
    }

    /// Una voz a la vez (Juan, 19-nov-2026: «si está activado el teléfono, usar por default el agente del teléfono»): el
    /// iPhone le avisa al Hub (vivoTelefono) cada minuto que está activo (la app abierta, o escuchando en el Modo calle o la
    /// conferencia) y, al irse al fondo sin escuchar, que ya no. El iPad y la computadora lo leen y no abren otra por voz.
    private var latido: Timer?
    private var ultimoActivo: Bool?
    func arrancar() {
        guard dispositivo == "iPhone" else { return }
        DispatchQueue.main.async {
            let nc = NotificationCenter.default
            nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.avisarTelefono(forzar: true) }
            nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.avisarTelefono(forzar: true) }
            self.latido = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.avisarTelefono(forzar: false) }
            self.avisarTelefono(forzar: true)
        }
    }
    private func avisarTelefono(forzar: Bool) {
        let activo = UIApplication.shared.applicationState != .background || Conferencia.shared.activa || ModoCalle.shared.encendido
        // Al fondo y sin escuchar: se avisa una vez que ya no está activo; después, nada hasta que vuelva.
        if !activo && ultimoActivo == false && !forzar { return }
        ultimoActivo = activo
        guard let url = Llave.leer("voz_url"), let token = Llave.leer("voz_token"), let sesion = Llave.leer("voz_sesion"), let u = URL(string: url) else { return }
        let b: [String: Any] = ["hub": 1, "action": "vivoTelefono", "token": token, "session": sesion, "dispositivo": dispositivo, "activo": activo]
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type"); r.timeoutInterval = 10
        r.httpBody = try? JSONSerialization.data(withJSONObject: b)
        URLSession.shared.dataTask(with: r).resume()
    }

    func empezo(_ conv: String) { DispatchQueue.main.async { self.cola.empezo(conv); self.revisar() }; Retransmision.shared.empezo() }   // y la voz, por la red de cerca (Hub #727)
    func estado(_ e: String) { DispatchQueue.main.async { self.cola.cambiar(e); self.revisar() }; if e == "fin" { Retransmision.shared.termino() } }
    func sub(alma: Bool, _ t: String) { DispatchQueue.main.async { self.cola.sub(alma: alma, t); self.revisar() } }

    private func revisar() {
        if reloj == nil { reloj = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.mandar() } }
        mandar()
    }
    private func mandar() {
        guard !enviando else { return }
        guard let b0 = cola.sacar(Date()) else { if cola.conv.isEmpty { reloj?.invalidate(); reloj = nil }; return }
        guard let url = Llave.leer("voz_url"), let token = Llave.leer("voz_token"), let sesion = Llave.leer("voz_sesion"), let u = URL(string: url) else { return }
        var b = b0; b["hub"] = 1; b["action"] = "vivoPublicar"; b["token"] = token; b["session"] = sesion; b["dispositivo"] = dispositivo
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type"); r.timeoutInterval = 10
        r.httpBody = try? JSONSerialization.data(withJSONObject: b)
        enviando = true
        URLSession.shared.dataTask(with: r) { [weak self] data, _, _ in
            let j = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async {
                guard let self else { return }
                self.enviando = false
                if let m = j?["mirando"] as? Bool { self.cola.mirando = m; AudioLlamada.shared.companeroMira(m) }
            }
        }.resume()
    }
}
