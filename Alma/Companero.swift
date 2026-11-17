import UIKit

/// Modo compañero (Hub #607 T-C1): manda al Hub (acción vivoPublicar) el estado y los subtítulos de la llamada que está en
/// este dispositivo, para que el otro los muestre sin audio. Las reglas de cuándo mandar: ColaVivo.swift.
final class Companero {
    static let shared = Companero()
    private var cola = ColaVivo()
    private var reloj: Timer?
    private var enviando = false
    private let dispositivo = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"

    func empezo(_ conv: String) { DispatchQueue.main.async { self.cola.empezo(conv); self.revisar() } }
    func estado(_ e: String) { DispatchQueue.main.async { self.cola.cambiar(e); self.revisar() } }
    func sub(alma: Bool, _ t: String) { DispatchQueue.main.async { self.cola.sub(alma: alma, t); self.revisar() } }

    private func revisar() {
        if reloj == nil { reloj = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.mandar() } }
        mandar()
    }
    private func mandar() {
        guard !enviando else { return }
        guard let b0 = cola.sacar(Date()) else { if cola.conv.isEmpty { reloj?.invalidate(); reloj = nil }; return }
        if cola.conv.isEmpty { Retransmision.shared.fin() }   // con «fin», la voz al compañero también termina
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
                if let m = j?["mirando"] as? Bool {
                    self.cola.mirando = m; AudioLlamada.shared.companeroMira(m)
                    Retransmision.shared.mirando(m && !self.cola.conv.isEmpty, clave: j?["clave"] as? String)   // la voz va directo al compañero (Hub #727)
                }
            }
        }.resume()
    }
}
