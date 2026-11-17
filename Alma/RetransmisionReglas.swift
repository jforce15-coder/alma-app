import CryptoKit
import Foundation

// Modo compañero · retransmisión del sonido (Hub #727; Juan, 17-nov-2026: «el audio que se reproduce en el teléfono es lo
// mismo que se debería reproducir en el iPad»). Lo puro (sin red ni audio), para probarlo solo (Pruebas/Retransmision).
// El teléfono de la llamada le manda al iPad la misma voz que suena en él, directo por la red local (Retransmision.swift).
// Para que solo la reciban los dispositivos del mismo administrador, el Hub les da la misma «par» (vivoPar_ en vivo.js):
//   · El iPad se anuncia con `anuncio(par)` (una huella, no la par).
//   · El teléfono lo invita con un número al azar y `invitacion(par, nonce)`: el iPad solo acepta si cuadra.
//   · Ya conectados, el iPad contesta `prueba(par, nonce)`: el teléfono solo le manda sonido si cuadra. Quien copie el
//     anuncio no sabe la par, así que no puede contestar.
enum RetransmisionReglas {
    static let servicio = "alma-comp"   // Info.plist: NSBonjourServices _alma-comp._tcp y _alma-comp._udp

    static func huella(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func anuncio(_ par: String) -> String { String(huella("anuncio|" + par).prefix(24)) }
    static func invitacion(_ par: String, _ nonce: String) -> String { huella("invita|" + par + "|" + nonce) }
    static func prueba(_ par: String, _ nonce: String) -> String { huella("ipad|" + par + "|" + nonce) }
    static func parValida(_ par: String?) -> Bool { (par?.count ?? 0) >= 16 }

    /// Lo que viaja: 1 byte de tipo y lo demás. Sonido: 2 bytes con los kHz·10 (p. ej. 160 = 16 kHz) y el PCM de 16 bits.
    enum Paquete: Equatable {
        case audio(hz: Int, pcm: Data)
        case corte            // Alma dejó de hablar de golpe (la interrumpieron): el iPad tira lo que le falta por sonar
        case fin              // terminó la llamada
        case prueba(String)   // la respuesta del iPad
    }
    static func empaquetar(_ p: Paquete) -> Data {
        switch p {
        case .audio(let hz, let pcm):
            let k = UInt16(clamping: hz / 100)
            var d = Data([1, UInt8(k >> 8), UInt8(k & 0xff)]); d.append(pcm); return d
        case .corte: return Data([2])
        case .fin: return Data([3])
        case .prueba(let s): var d = Data([4]); d.append(Data(s.utf8)); return d
        }
    }
    static func desempaquetar(_ d: Data) -> Paquete? {
        guard let t = d.first else { return nil }
        let resto = d.dropFirst()
        switch t {
        case 1:
            guard resto.count >= 2 else { return nil }
            let a = resto[resto.startIndex], b = resto[resto.startIndex + 1]
            let hz = (Int(a) << 8 | Int(b)) * 100, pcm = Data(resto.dropFirst(2))
            guard hz >= 8000, hz <= 48000, pcm.count % 2 == 0 else { return nil }
            return .audio(hz: hz, pcm: pcm)
        case 2: return .corte
        case 3: return .fin
        case 4: return String(data: Data(resto), encoding: .utf8).map { Paquete.prueba($0) }
        default: return nil
        }
    }
    /// La invitación viaja como «nonce.firma».
    static func contexto(_ par: String, _ nonce: String) -> Data { Data((nonce + "." + invitacion(par, nonce)).utf8) }
    /// El iPad revisa la invitación: devuelve el nonce si es de su par.
    static func revisar(_ ctx: Data?, par: String) -> String? {
        guard parValida(par), let ctx, let s = String(data: ctx, encoding: .utf8) else { return nil }
        let p = s.split(separator: ".", maxSplits: 1).map(String.init)
        guard p.count == 2, p[0].count >= 8, p[1] == invitacion(par, p[0]) else { return nil }
        return p[0]
    }
}
