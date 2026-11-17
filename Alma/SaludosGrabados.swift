import Foundation

/// Saludos grabados (Hub #724, SaludosGrabadosReglas.swift): los baja del Hub una vez, los guarda en el teléfono
/// (Application Support/SaludosGrabados/<id>.mp3) y dice cuál suena. VozNativa los toca con su reproductor de señales.
final class SaludosGrabados {
    static let shared = SaludosGrabados()
    private typealias R = SaludosGrabadosReglas
    private let d = UserDefaults.standard
    private var pidiendo = false
    private var ultimoPedido: Date?

    private lazy var carpeta: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let c = base.appendingPathComponent("SaludosGrabados", isDirectory: true)
        try? FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)
        return c
    }()
    private var version: String { d.string(forKey: "sg_version") ?? "" }
    private var completo: Bool { d.bool(forKey: "sg_completo") }
    /// Los que están guardados en el teléfono (solo los que de verdad están en disco).
    private var guardados: [String] {
        ((d.array(forKey: "sg_ids") as? [String]) ?? []).filter { FileManager.default.fileExists(atPath: archivo($0).path) }
    }
    private func archivo(_ id: String) -> URL { carpeta.appendingPathComponent(id + ".mp3") }

    /// Un saludo para esta llamada (nunca el de la anterior), o nil si todavía no hay ninguno guardado.
    func elegirSaludo() -> URL? {
        guard let id = R.elegir(guardados, ultimo: d.string(forKey: "sg_ultimo")) else { return nil }
        d.set(id, forKey: "sg_ultimo")
        return archivo(id)
    }
    /// El Aviso de volver a llamar, si ya está guardado.
    var aviso: URL? { guardados.contains(R.aviso) ? archivo(R.aviso) : nil }

    /// Pide al Hub los que falten (al abrir la app y con cada ficha de voz, que trae la versión en `saludos_grabados`).
    func actualizar(versionHub: String? = nil, vuelta: Int = 0) {
        guard !pidiendo, vuelta < R.vueltas else { return }
        if vuelta == 0, !R.pedir(version: versionHub, local: version, completo: completo, ultimo: ultimoPedido, ahora: Date()) { return }
        guard let url = Llave.leer("voz_url"), let token = Llave.leer("voz_token"), let sesion = Llave.leer("voz_sesion"), let u = URL(string: url) else { return }
        pidiendo = true; ultimoPedido = Date()
        // Si la versión cambió, se piden todos de nuevo (los de antes se reemplazan al llegar).
        let tiene = versionHub.map { $0.isEmpty || $0 == version } ?? true ? guardados : []
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        r.timeoutInterval = 120   // la primera vez el Hub graba hasta 12 mientras contesta
        r.httpBody = try? JSONSerialization.data(withJSONObject: R.pedido(token: token, sesion: sesion, version: version, tiene: tiene))
        URLSession.shared.dataTask(with: r) { [weak self] data, _, _ in
            guard let self else { return }
            let j = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async {
                self.pidiendo = false
                guard let res = R.respuesta(j) else { return }
                var ids = res.version == self.version ? self.guardados : []
                for (id, b64) in res.clips {
                    guard let datos = Data(base64Encoded: b64) else { continue }
                    if (try? datos.write(to: self.archivo(id), options: .atomic)) != nil, !ids.contains(id) { ids.append(id) }
                }
                if res.version != self.version {   // versión nueva: lo que no vino con ella ya no vale
                    for id in self.guardados where !ids.contains(id) { try? FileManager.default.removeItem(at: self.archivo(id)) }
                }
                self.d.set(ids, forKey: "sg_ids"); self.d.set(res.version, forKey: "sg_version"); self.d.set(res.completo, forKey: "sg_completo")
                // Faltan: otra vuelta enseguida (cada una graba hasta 12 en el Hub).
                if !res.completo && !res.clips.isEmpty { self.actualizar(versionHub: res.version, vuelta: vuelta + 1) }
            }
        }.resume()
    }
}
