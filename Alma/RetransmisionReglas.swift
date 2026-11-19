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
    // Lo que se ve, al momento (Juan, 19-nov-2026: «no sincroniza la actividad de voz en pantalla en tiempo real»): el iPad
    // lo pinta en cuanto llega, sin esperar la vuelta por el Hub.
    case texto(alma: Bool, t: String) // un subtítulo: lo que dijo Alma (o Claudio) o lo que dijiste tú
    case estado(String)               // conectando · hablando · …
    static let largoTexto = 280, largoEstado = 20

    func datos() -> Data {
        switch self {
        case .corte: return Data([2])
        case .fin: return Data([3])
        case let .texto(alma, t): var d = Data([4, alma ? 1 : 0]); d.append(Data(String(t.prefix(PaqueteVivo.largoTexto)).utf8)); return d
        case let .estado(e): var d = Data([5]); d.append(Data(String(e.prefix(PaqueteVivo.largoEstado)).utf8)); return d
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
        case 4:
            guard b.count > 2, b[1] <= 1, let t = String(bytes: b[2...], encoding: .utf8) else { return nil }
            let limpio = t.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !limpio.isEmpty, limpio.count <= PaqueteVivo.largoTexto else { return nil }
            return .texto(alma: b[1] == 1, t: limpio)
        case 5:
            guard b.count > 1, let e = String(bytes: b[1...], encoding: .utf8), !e.isEmpty, e.count <= PaqueteVivo.largoEstado,
                  e.unicodeScalars.allSatisfy({ CharacterSet.lowercaseLetters.contains($0) }) else { return nil }
            return .estado(e)
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

/// Qué tan fuerte suena un trozo de la voz (0 a 1), para que la pantalla del iPad se mueva con ella (la roca y el punto
/// de «En vivo»). PCM de 16 bits, como llega.
enum NivelVivo {
    static func de(_ pcm16: Data) -> Double {
        let n = pcm16.count / 2
        guard n > 0 else { return 0 }
        var suma = 0.0
        pcm16.withUnsafeBytes { (r: UnsafeRawBufferPointer) in
            let s = r.bindMemory(to: Int16.self)
            for i in 0..<n { let x = Double(Int16(littleEndian: s[i])) / 32768; suma += x * x }
        }
        return min(1, (suma / Double(n)).squareRoot() * 4)
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
