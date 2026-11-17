import Foundation

/// Wearables (Juan, 17-nov-2026: «una sección solo para dispositivos: ahí va a estar todo lo del anillo, de lentes o
/// auriculares o lo que sea; ahí se va a ver y ahí se va a configurar. Le vamos a llamar Wearables»). Lógica pura, sin iOS:
/// se prueba sola en Pruebas/Wearables.
///   · Cada wearable con lo que se sabe de verdad: conectado o no, y la batería solo si el dispositivo la da (el anillo sí;
///     lentes y audífonos Bluetooth clásicos no, iOS no la comparte con las apps). Nada se inventa.
///   · «Agregar»: los audífonos o bocinas Bluetooth que el iPhone ve ahora (salida o micrófono) y que no son los lentes ni
///     uno ya agregado. Se guardan por nombre solo en este iPhone.
///   · Lo que va a Ajustes (alma/inicio.html): una tarjeta por wearable con su batería y su estado (resumenWeb).
enum WearablesReglas {
    enum Tipo: String { case anillo, lentes, audio }

    struct Wearable: Equatable {
        var id: String
        var tipo: Tipo
        var nombre: String
        var corto: String
        var conectado: Bool
        var bateria: Int?
        var cargando = false
        var estado: String
    }

    /// Los tipos de puerto de audio que son Bluetooth (AVAudioSession.Port, en texto para que esto no dependa de iOS).
    static let puertosBluetooth: Set<String> = ["BluetoothA2DPOutput", "BluetoothHFP", "BluetoothLE"]
    static func esBluetooth(_ puerto: String) -> Bool { puertosBluetooth.contains(puerto) }

    /// El id de unos audífonos agregados: «audio-» y su nombre en minúsculas, sin acentos ni signos.
    static func idAudio(_ nombre: String) -> String {
        let base = nombre.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es")).lowercased()
        let limpio = base.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let s = String(limpio).split(separator: "-").joined(separator: "-")
        return "audio-" + (s.isEmpty ? "bt" : s)
    }

    /// Lo que se puede agregar: los Bluetooth que se ven ahora, sin repetir, sin los lentes y sin los ya agregados.
    static func paraAgregar(vistos: [String], guardados: [String], sonLentes: (String) -> Bool) -> [String] {
        var ya = Set(guardados.map(idAudio)), out: [String] = []
        for n in vistos {
            let t = n.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !sonLentes(t), !ya.contains(idAudio(t)) else { continue }
            ya.insert(idAudio(t)); out.append(t)
        }
        return out
    }

    /// Agregar uno a la lista guardada (sin repetir) y quitarlo por su id.
    static func agregar(_ nombre: String, a lista: [String]) -> [String] {
        let t = nombre.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !lista.map(idAudio).contains(idAudio(t)) else { return lista }
        return lista + [t]
    }
    static func quitar(id: String, de lista: [String]) -> [String] { lista.filter { idAudio($0) != id } }

    /// El estado de unos audífonos: si son la salida de ahora, si solo están conectados, o no.
    static func estadoAudio(salida: Bool, conectado: Bool) -> String {
        salida ? "El audio sale por aquí" : conectado ? "Conectados" : "Sin conectar"
    }

    /// La batería en texto: «82 %», «82 % · cargando» o lo que diga cuando no hay dato.
    static func bateria(_ b: Int?, cargando: Bool = false, sin: String = "Batería no disponible") -> String {
        guard let b else { return sin }
        return "\(max(0, min(100, b))) %" + (cargando ? " · cargando" : "")
    }

    /// Batería baja: el anillo se pinta en rojo de 20 % para abajo.
    static func bajo(_ b: Int?) -> Bool { (b ?? 100) <= 20 }

    /// Lo que va a Ajustes (alma/inicio.html, AlmaAjustes.wear): una tarjeta por wearable.
    static func resumenWeb(_ ws: [Wearable]) -> [[String: Any]] {
        ws.map { w in
            var r: [String: Any] = ["id": w.id, "tipo": w.tipo.rawValue, "nombre": w.nombre, "corto": w.corto, "conectado": w.conectado,
                                    "cargando": w.cargando, "estado": w.estado]
            if let b = w.bateria { r["bateria"] = max(0, min(100, b)) }
            return r
        }
    }
}
