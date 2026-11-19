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
revisa(UnaLlamada.motivo(companero: false, porVoz: true, otra: "", visto: nil, ahora: t0) == nil, "sin Modo compañero y sin saber del iPhone, todo como antes")
revisa(UnaLlamada.motivo(companero: true, porVoz: true, otra: "", visto: nil, ahora: t0) != nil, "con Modo compañero, por voz nunca (aunque no se sepa de otra llamada)")
revisa(UnaLlamada.motivo(companero: true, porVoz: false, otra: "", visto: t0, ahora: t0) == nil, "a mano y sin llamada en el otro, sí")
revisa(UnaLlamada.motivo(companero: true, porVoz: false, otra: "iPhone", visto: t0, ahora: t0.addingTimeInterval(5))?.contains("iPhone") == true, "a mano con la llamada en el iPhone, no")
revisa(UnaLlamada.motivo(companero: true, porVoz: false, otra: "iPhone", visto: t0, ahora: t0.addingTimeInterval(31)) == nil, "lo que dijo la página vence a los 30 s")
revisa(UnaLlamada.motivo(companero: true, porVoz: false, otra: "iPhone", visto: nil, ahora: t0) == nil, "sin noticia de la página, a mano sí")

// En el iPad (Juan, 19-nov-2026): con el Modo compañero encendido no se abren llamadas ni llegan notificaciones
revisa(UnaLlamada.motivo(companero: true, ipad: true, porVoz: false, otra: "", visto: nil, ahora: t0) == UnaLlamada.enIPad, "iPad compañero: a mano tampoco, aunque no haya llamada en el otro")
revisa(UnaLlamada.motivo(companero: true, ipad: true, porVoz: true, otra: "", visto: nil, ahora: t0) == UnaLlamada.enIPad, "iPad compañero: por voz tampoco")
revisa(UnaLlamada.motivo(companero: false, ipad: true, porVoz: false, otra: "", visto: t0, ahora: t0) == nil, "iPad sin Modo compañero: llama como siempre (si el iPhone no está en una llamada)")
revisa(UnaLlamada.motivo(companero: true, ipad: false, porVoz: false, otra: "", visto: nil, ahora: t0) == nil, "teléfono con el modo encendido: a mano sí, como antes")
revisa(UnaLlamada.callaAvisos(companero: true, ipad: true), "iPad compañero: sin notificaciones")
revisa(!UnaLlamada.callaAvisos(companero: true, ipad: false) && !UnaLlamada.callaAvisos(companero: false, ipad: true), "el teléfono, o el iPad sin el modo: notificaciones como siempre")
// Una sola voz (Juan, 19-nov-2026): el del teléfono manda
revisa(UnaLlamada.motivo(companero: true, telefono: true, porVoz: true, otra: "", visto: nil, ahora: t0) == nil, "el iPhone con Modo compañero sí abre por voz")
revisa(UnaLlamada.motivo(companero: true, telefono: true, porVoz: false, otra: "iPad", visto: t0, ahora: t0) == nil, "el iPhone abre aunque la llamada esté en el iPad (el iPad cede)")
var l = ColaVivo(); l.empezo("conv-9"); _ = l.sacar(t0)
revisa(l.sacar(t0.addingTimeInterval(3)) == nil, "sin nada nuevo, no se manda enseguida")
revisa(l.sacar(t0.addingTimeInterval(ColaVivo.latido)) != nil, "pero cada pocos segundos se avisa que la llamada sigue (para saber si hay que ceder)")
l.cambiar("fin"); _ = l.sacar(t0.addingTimeInterval(7))
revisa(l.sacar(t0.addingTimeInterval(20)) == nil, "después de terminar, ya no hay latido")
// Una voz a la vez (Juan, 19-nov-2026): el iPhone manda; el iPad no abre por voz mientras el iPhone está activo
revisa(UnaLlamada.motivo(companero: true, telefono: true, porVoz: true, otra: "iPad", visto: t0, ahora: t0, telActivo: true) == nil, "el iPhone nunca se bloquea (ni con Modo compañero encendido)")
revisa(UnaLlamada.motivo(companero: false, porVoz: true, otra: "", visto: t0, ahora: t0, telActivo: true)?.contains("iPhone") == true, "iPad sin compañero: con el iPhone activo, por voz no")
revisa(UnaLlamada.motivo(companero: false, porVoz: false, otra: "", visto: t0, ahora: t0, telActivo: true) == nil, "iPad: con el iPhone activo pero sin llamada, a mano sí")
revisa(UnaLlamada.motivo(companero: false, porVoz: true, otra: "iPhone", visto: t0, ahora: t0) != nil, "iPad sin compañero: con la llamada en el iPhone, por voz no")
revisa(UnaLlamada.motivo(companero: false, porVoz: false, otra: "iPhone", visto: t0, ahora: t0.addingTimeInterval(5))?.contains("iPhone") == true, "iPad sin compañero: con la llamada en el iPhone, a mano tampoco")
revisa(UnaLlamada.motivo(companero: false, porVoz: true, otra: "", visto: t0, ahora: t0.addingTimeInterval(31), telActivo: true) == nil, "lo que dijo la página del iPhone activo también vence a los 30 s")

print(fallos == 0 ? "Todo bien." : "\(fallos) fallaron.")
exit(fallos == 0 ? 0 : 1)
