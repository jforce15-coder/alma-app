import CryptoKit
import Foundation

// Modo compañero con sonido (Hub #727; Juan, 17-nov-2026: «El audio que se reproduce en el teléfono es lo mismo que se
// debería reproducir en el iPad»). La lógica pura (sin red ni iOS), para probarla sola (Pruebas/Retransmision).
// El dispositivo de la llamada manda por la red de cerca (Wi-Fi o Bluetooth, sin pasar por internet) la misma voz que
// suena en él; el otro, con «Modo compañero» encendido, la reproduce. Lo que va por la red (Retransmision.swift):

/// Un paquete: 1 byte de tipo; el audio lleva además la frecuencia (4 bytes) y el sonido en PCM de 16 bits.
enum PaqueteVivo: Equatable {
    case audio(hz: Int, pcm: Data)   // un trozo de la voz, tal como sonó en el teléfono
    case corte                        // Juan interrumpió: lo que quedaba por sonar se tira (igual que en el teléfono)
    case fin                          // terminó la llamada

    func datos() -> Data {
        switch self {
        case .corte: return Data([2])
        case .fin: return Data([3])
        case let .audio(hz, pcm):
            var d = Data([1]); let h = UInt32(clamping: max(0, hz))
            d.append(contentsOf: [UInt8(h & 0xff), UInt8((h >> 8) & 0xff), UInt8((h >> 16) & 0xff), UInt8((h >> 24) & 0xff)])
            d.append(pcm); return d
        }
    }

    static func leer(_ d: Data) -> PaqueteVivo? {
        let b = [UInt8](d)
        guard let t = b.first else { return nil }
        switch t {
        case 2: return .corte
        case 3: return .fin
        case 1:
            guard b.count > 5 else { return nil }
            let hz = Int(b[1]) | Int(b[2]) << 8 | Int(b[3]) << 16 | Int(b[4]) << 24
            let pcm = Data(b[5...])
            guard (8000...48000).contains(hz), pcm.count % 2 == 0 else { return nil }
            return .audio(hz: hz, pcm: pcm)
        default: return nil
        }
    }
}

/// Cuándo busca, cuándo acepta y cuándo suena.
struct ReglasRetransmision {
    var companero = false     // «Modo compañero» encendido en este dispositivo (lo dice la página)
    var llamadaAqui = false   // la llamada está en este dispositivo: él es el que manda, no el que oye
    var aLaVista = true       // la app abierta (con la app cerrada no se busca)

    /// El compañero busca la llamada del otro solo encendido, sin llamada propia y con la app abierta.
    var busca: Bool { companero && !llamadaAqui && aLaVista }
    /// Y la voz que llega suena con el modo encendido y sin llamada propia (una vez conectado, sigue sonando bloqueado).
    var suena: Bool { companero && !llamadaAqui }

    /// Solo se juntan los dispositivos de la misma cuenta: los dos guardan la misma llave de la app (voz_token), y lo que
    /// se anuncia es una huella de ella (nunca la llave). Sin llave, nada.
    static func pareja(_ token: String?) -> String? {
        guard let t = token?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        let h = SHA256.hash(data: Data(("alma-vivo|" + t).utf8))
        return h.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// El teléfono acepta al compañero solo durante su llamada y con la misma huella.
    static func acepta(contexto: Data?, pareja: String?, llamadaAqui: Bool) -> Bool {
        guard llamadaAqui, let p = pareja, let c = contexto else { return false }
        return String(data: c, encoding: .utf8) == p
    }
}
