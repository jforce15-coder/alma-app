import Foundation

// Prueba de la retransmisión del modo compañero (Hub #727): las tramas de la voz y la regla de una sola llamada (TramaVivo.swift).
var fallos = 0
func revisa(_ c: Bool, _ m: String) { print((c ? "✓ " : "✗ ") + m); if !c { fallos += 1 } }

let voz = Data((0..<3200).map { UInt8($0 % 251) })
var buf = TramaVivo.formato(24000) + TramaVivo.armar(.audio, voz) + TramaVivo.armar(.corte)
let todo = buf
var r = TramaVivo.sacar(&buf)
revisa(r?.count == 3 && buf.isEmpty, "tres tramas seguidas salen las tres")
revisa(r.flatMap { TramaVivo.hz($0[0].1) } == 24000, "el formato dice los Hz")
revisa(r?[1].0 == .audio && r?[1].1 == voz, "la voz llega igual, byte por byte")
revisa(r?[2].0 == .corte && r?[2].1.isEmpty == true, "el corte va sin datos")
// La red parte las tramas donde quiere: llegan a pedazos
var b2 = Data(); var salidas: [TramaVivo.Tipo] = []
for i in stride(from: 0, to: todo.count, by: 700) { b2.append(todo[i..<min(i + 700, todo.count)]); salidas += (TramaVivo.sacar(&b2) ?? []).map { $0.0 } }
revisa(salidas == [.formato, .audio, .corte] && b2.isEmpty, "a pedazos, igual salen completas y en orden")
var mala = Data([9, 0, 0, 0, 0]); revisa(TramaVivo.sacar(&mala) == nil, "un tipo desconocido corta la conexión")
var grande = Data([2, 0x7f, 0xff, 0xff, 0xff]); revisa(TramaVivo.sacar(&grande) == nil, "un largo absurdo corta la conexión")
revisa(TramaVivo.hz(Data("999999".utf8)) == nil && TramaVivo.hz(Data("16000".utf8)) == 16000, "solo Hz de voz razonables")
let t0 = Date()
revisa(!TramaVivo.otraLlamada(vista: nil, ahora: t0), "sin llamada en el otro, aquí se puede llamar")
revisa(TramaVivo.otraLlamada(vista: t0, ahora: t0.addingTimeInterval(2)), "con la llamada del otro vista hace 2 s, aquí no se abre otra")
revisa(!TramaVivo.otraLlamada(vista: t0, ahora: t0.addingTimeInterval(7)), "si la página dejó de verla, ya se puede")
print(fallos == 0 ? "Todo bien." : "\(fallos) fallaron.")
exit(fallos == 0 ? 0 : 1)
