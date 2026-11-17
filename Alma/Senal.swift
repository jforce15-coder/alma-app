import Foundation
import Network

/// La señal de internet del teléfono (Hub #657): la vigila todo el tiempo para que la voz de respaldo de Alma entre solo
/// cuando hay problemas de conexión y salga sola cuando la señal vuelve (RespaldoReglas.swift).
/// También guarda lo que Juan pidió sin internet y lo manda al Hub (acción calle) en cuanto vuelve la señal.
final class Senal {
    static let shared = Senal()
    static let cambio = Notification.Name("alma.senal.cambio")

    /// ¿Hay camino a internet? (Lo que dice iOS; si hay camino pero no alcanza, lo dicen los cortes de la voz.)
    private(set) var hayRed = true
    /// Desde cuándo hay señal sin cortes (nil: ahora no hay).
    private(set) var buenaDesde: Date? = Date()
    /// Lo que se manda al volver la señal dice su resultado aquí (la voz de respaldo, si sigue en la llamada).
    var alMandar: ((String) -> Void)?

    private let monitor = NWPathMonitor()
    private var mandando = false
    private let clave = "respaldo_pendientes"

    private init() {
        monitor.pathUpdateHandler = { [weak self] p in
            let hay = p.status == .satisfied
            DispatchQueue.main.async {
                guard let self, hay != self.hayRed else { return }
                self.hayRed = hay; self.buenaDesde = hay ? Date() : nil
                NotificationCenter.default.post(name: Senal.cambio, object: nil)
                if hay { self.mandarPendientes() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "alma.senal"))
    }

    /// Se empieza a vigilar al abrir la app (la primera lectura llega en milisegundos).
    func empezar() { if hayRed { mandarPendientes() } }

    /// Un corte de la voz con internet: la señal no es tan buena; vuelve a contar desde ahora.
    func anotarCorte() { if hayRed { buenaDesde = Date() } }

    // MARK: - Lo guardado sin internet

    private var pendientes: [RespaldoReglas.Pendiente] {
        get { (UserDefaults.standard.data(forKey: clave)).flatMap { try? JSONDecoder().decode([RespaldoReglas.Pendiente].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: clave) }
    }

    /// Guarda un pedido dicho sin internet. false: ya no cabe.
    func guardar(_ texto: String) -> Bool {
        guard let l = RespaldoReglas.guardar(pendientes, texto: texto, ahora: Date()) else { return false }
        pendientes = l; return true
    }

    /// Manda uno por uno lo guardado (si sigue vigente). Lo que conteste Alma queda en el Chat con Alma (lo guarda el Hub).
    func mandarPendientes() {
        guard !mandando, hayRed else { return }
        let l = RespaldoReglas.vigentes(pendientes, ahora: Date())
        guard let primero = l.first else { pendientes = []; return }
        guard let url = Llave.leer("voz_url"), let token = Llave.leer("voz_token"), let sesion = Llave.leer("voz_sesion"), let u = URL(string: url) else { return }
        mandando = true
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type"); r.timeoutInterval = 30
        r.httpBody = try? JSONSerialization.data(withJSONObject: RespaldoReglas.pedido(token: token, sesion: sesion, texto: primero.texto))
        URLSession.shared.dataTask(with: r) { [weak self] data, _, _ in
            let j = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async {
                guard let self else { return }
                self.mandando = false
                guard j != nil else { return }   // no llegó: queda guardado para la próxima vez que vuelva la señal
                self.pendientes = Array(RespaldoReglas.vigentes(self.pendientes, ahora: Date()).filter { $0 != primero })
                if let h = RespaldoReglas.respuesta(j)?.hablar { self.alMandar?(h) }
                self.mandarPendientes()
            }
        }.resume()
    }
}
