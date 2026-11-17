import Foundation

// Prueba del modo compañero (Hub #607 T-C1): cuándo se manda el estado y los subtítulos de la llamada (ColaVivo.swift).
var fallos = 0
func revisa(_ c: Bool, _ m: String) { print((c ? "✓ " : "✗ ") + m); if !c { fallos += 1 } }

var c = ColaVivo()
let t0 = Date()
revisa(c.sacar(t0) == nil, "sin llamada no se manda nada")
c.sub(alma: true, "hola"); revisa(c.subs.isEmpty, "un subtítulo sin llamada no se guarda")
c.empezo("conv-1")
let b1 = c.sacar(t0)
revisa((b1?["estado"] as? String) == "conectando" && (b1?["conv_id"] as? String) == "conv-1", "al empezar, el estado sale enseguida")
c.cambiar("hablando"); c.sub(alma: false, "¿Quién llega hoy?")
let b2 = c.sacar(t0.addingTimeInterval(0.2))
revisa((b2?["estado"] as? String) == "hablando" && (b2?["subs"] as? [[String: String]])?.first?["de"] == "yo", "un cambio de estado sale ya, con lo que haya")
c.sub(alma: true, "Hoy   llegan\n dos.")
revisa(c.sacar(t0.addingTimeInterval(0.5)) == nil, "los subtítulos se juntan (no uno por uno)")
let b3 = c.sacar(t0.addingTimeInterval(1.5))
revisa((b3?["subs"] as? [[String: String]])?.first?["t"] == "Hoy llegan dos." && b3?["estado"] == nil, "y salen juntos al ratito, sin espacios de más")
c.mirando = false; c.sub(alma: true, "otra")
revisa(c.sacar(t0.addingTimeInterval(4)) == nil && c.sacar(t0.addingTimeInterval(14)) != nil, "si nadie mira, cada 12 s")
for i in 0..<20 { c.sub(alma: true, "frase \(i)") }
revisa(c.subs.count == ColaVivo.maxSubs && c.subs.last?.t == "frase 19", "se quedan los últimos 8")
c.cambiar("fin")
let b4 = c.sacar(t0.addingTimeInterval(15))
revisa((b4?["estado"] as? String) == "fin" && c.conv.isEmpty && c.sacar(t0.addingTimeInterval(30)) == nil, "al terminar se manda «fin» y no queda nada")
c.empezo("conv-2")
revisa(c.subs.isEmpty && c.mirando && c.conv == "conv-2", "una llamada nueva empieza vacía")

// Una sola llamada (Juan, 17-nov-2026): el compañero no abre otra
revisa(UnaLlamada.motivo(companero: false, porVoz: true, otra: "iPhone", visto: t0, ahora: t0) == nil, "sin Modo compañero, todo como antes")
revisa(UnaLlamada.motivo(companero: true, porVoz: true, otra: "", visto: nil, ahora: t0) != nil, "con Modo compañero, por voz nunca (aunque no se sepa de otra llamada)")
revisa(UnaLlamada.motivo(companero: true, porVoz: false, otra: "", visto: t0, ahora: t0) == nil, "a mano y sin llamada en el otro, sí")
revisa(UnaLlamada.motivo(companero: true, porVoz: false, otra: "iPhone", visto: t0, ahora: t0.addingTimeInterval(5))?.contains("iPhone") == true, "a mano con la llamada en el iPhone, no")
revisa(UnaLlamada.motivo(companero: true, porVoz: false, otra: "iPhone", visto: t0, ahora: t0.addingTimeInterval(31)) == nil, "lo que dijo la página vence a los 30 s")
revisa(UnaLlamada.motivo(companero: true, porVoz: false, otra: "iPhone", visto: nil, ahora: t0) == nil, "sin noticia de la página, a mano sí")

print(fallos == 0 ? "Todo bien." : "\(fallos) fallaron.")
exit(fallos == 0 ? 0 : 1)
