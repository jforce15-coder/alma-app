import Foundation

// Retransmisión del modo compañero (Hub #727; Juan, 17-nov-2026: «el audio que se reproduce en el teléfono es lo mismo que
// se debería reproducir en el iPad… importante que en modo Companion sólo haya una llamada»). La lógica pura (sin red ni
// iOS), para probarla sola (Pruebas/Retransmision). La red y el audio: Retransmision.swift.
//   · Cada trozo viaja como [tipo, 1 byte][largo, 4 bytes][datos]: el formato de la voz (Hz), la voz (PCM de 16 bits, tal
//     cual llega de ElevenLabs), «corte» (Alma se calló porque le hablaste: lo que faltaba no suena) y «fin».
//   · Una sola llamada: el compañero no abre otra mientras la del otro dispositivo siga (la página lo confirma en cada
//     vistazo, cada ~1,5 s; si deja de decirlo por `vence` segundos, ya no cuenta).
enum TramaVivo {
    enum Tipo: UInt8 { case formato = 1, audio = 2, corte = 3, fin = 4 }
    static let maximo = 1 << 20

    static func armar(_ t: Tipo, _ datos: Data = Data()) -> Data {
        var d = Data([t.rawValue]); var n = UInt32(datos.count).bigEndian
        d.append(Data(bytes: &n, count: 4)); d.append(datos); return d
    }
    static func formato(_ hz: Double) -> Data { armar(.formato, Data(String(Int(hz.rounded())).utf8)) }
    static func hz(_ d: Data) -> Double? { String(data: d, encoding: .utf8).flatMap(Double.init).flatMap { $0 >= 8000 && $0 <= 48000 ? $0 : nil } }

    /// Saca del búfer las tramas completas y deja lo que falta por llegar. nil: algo no cuadra (se corta la conexión).
    static func sacar(_ buf: inout Data) -> [(Tipo, Data)]? {
        var r: [(Tipo, Data)] = []
        while buf.count >= 5 {
            let b = [UInt8](buf.prefix(5))
            guard let t = Tipo(rawValue: b[0]) else { return nil }
            let n = Int(b[1]) << 24 | Int(b[2]) << 16 | Int(b[3]) << 8 | Int(b[4])
            guard n <= maximo else { return nil }
            guard buf.count >= 5 + n else { break }
            r.append((t, Data(buf.dropFirst(5).prefix(n))))
            buf = Data(buf.dropFirst(5 + n))
        }
        return r
    }

    static let vence: TimeInterval = 6
    /// ¿La llamada del otro dispositivo sigue? (para no abrir otra aquí)
    static func otraLlamada(vista: Date?, ahora: Date) -> Bool { vista.map { ahora.timeIntervalSince($0) < vence } ?? false }
}
