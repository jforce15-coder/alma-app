import Foundation
import Network

/// La conexión a internet del teléfono (Hub #657, voz de respaldo de Alma; reglas en RespaldoVoz.swift). La vigila siempre
/// desde que se abre la app: hay red o no, y desde cuándo. VozNativa la mira para pasar a la voz de respaldo y para volver.
final class Conexion {
    static let shared = Conexion()

    /// ¿Hay internet? (Wifi o datos, según iOS.) Empieza en sí: hasta que iOS diga otra cosa, no se cambia nada.
    private(set) var hayRed = true
    /// Desde cuándo está como está (con red o sin red).
    private(set) var desde = Date()
    /// Por dónde: «wifi», «datos», «cable» u «otra» (para el registro de la llamada).
    private(set) var via = ""

    private let monitor = NWPathMonitor()
    private var oyentes: [(Bool) -> Void] = []

    private init() {
        monitor.pathUpdateHandler = { [weak self] p in
            let hay = p.status == .satisfied
            let via = p.usesInterfaceType(.wifi) ? "wifi" : p.usesInterfaceType(.cellular) ? "datos" : p.usesInterfaceType(.wiredEthernet) ? "cable" : hay ? "otra" : ""
            DispatchQueue.main.async {
                guard let self else { return }
                self.via = via
                guard hay != self.hayRed else { return }
                self.hayRed = hay; self.desde = Date()
                self.oyentes.forEach { $0(hay) }
            }
        }
        monitor.start(queue: DispatchQueue(label: "alma.senal"))
    }

    /// Avisa en el hilo principal cada vez que el internet se va o vuelve.
    func escuchar(_ f: @escaping (Bool) -> Void) { oyentes.append(f) }
}
