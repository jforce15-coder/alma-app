// Pruebas de los Saludos grabados (Alma/SaludosGrabadosReglas.swift; Hub #724).
//   swiftc Alma/SaludosGrabadosReglas.swift Pruebas/SaludosGrabados/main.swift -o /tmp/saludos-grabados && /tmp/saludos-grabados
// Las corre el robot en cada PR (testflight.yml, «Probar los saludos grabados»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}
typealias S = SaludosGrabadosReglas
typealias L = SaludosGrabadosReglas.Llamada

// Cuándo suena
revisa(S.toca(L()), "una llamada normal con Alma saluda con uno grabado")
revisa(S.toca(L(conferencia: true)), "en conferencia, si solo dijeron «Alma», también")
revisa(!S.toca(L(conferencia: true, conPedido: true)), "si dijeron el pedido con «Alma», no saluda")
revisa(!S.toca(L(alma: false)), "Claudio no lleva saludo grabado")
revisa(!S.toca(L(reabierta: true)) && !S.toca(L(porAviso: true)) && !S.toca(L(pantalla: true)), "reabierta, por aviso o en pantalla tienen su frase")
revisa(!S.toca(L(juanHabla: true)), "si Juan ya habla, no se le saluda encima")
revisa(!S.toca(L(sinRed: true)), "con la voz de respaldo no suena")

// Cuál suena
let ids = ["aviso", "s01", "s02", "s03"]
revisa(S.elegir(ids, ultimo: nil, azar: { _ in 0 }) == "s01", "el aviso nunca sale como saludo")
revisa(S.elegir(ids, ultimo: "s01", azar: { _ in 0 }) == "s02", "nunca el mismo dos veces seguidas")
revisa(S.elegir(["aviso"], ultimo: nil) == nil, "sin saludos guardados, ninguno (Alma saluda como antes)")
revisa(S.elegir(["s07"], ultimo: "s07") == "s07", "con uno solo, ese")
var vistos = Set<String>(); for _ in 0..<200 { if let s = S.elegir(ids, ultimo: nil) { vistos.insert(s) } }
revisa(vistos == ["s01", "s02", "s03"], "al azar salen todos")
revisa(S.primerMensaje(retomar: nil) == "", "tras el saludo grabado, ElevenLabs no saluda otra vez")
revisa(S.primerMensaje(retomar: "Por cierto, ya quedó lo del pago.") == "Por cierto, ya quedó lo del pago.", "un tema por retomar sí se dice")

// Cuándo se piden
let t0 = Date(timeIntervalSince1970: 10_000)
revisa(S.pedir(version: nil, local: "", completo: false, ultimo: nil, ahora: t0), "la primera vez se piden")
revisa(!S.pedir(version: "abc", local: "abc", completo: true, ultimo: nil, ahora: t0), "con todos y la misma versión, no")
revisa(S.pedir(version: "abd", local: "abc", completo: true, ultimo: nil, ahora: t0), "si cambió la versión, otra vez")
revisa(S.pedir(version: "abc", local: "abc", completo: false, ultimo: t0.addingTimeInterval(-100), ahora: t0), "si faltan, se siguen pidiendo")
revisa(!S.pedir(version: "abd", local: "abc", completo: false, ultimo: t0.addingTimeInterval(-30), ahora: t0), "como mucho cada 90 s")

// Lo que va y viene del Hub
let p = S.pedido(token: "t", sesion: "s", version: "v1", tiene: ["s02", "aviso"])
revisa(p["action"] as? String == "vozSaludosGrabados" && p["session"] as? String == "s" && (p["tiene"] as? [String]) == ["aviso", "s02"], "manda la sesión y los que ya tiene")
let r = S.respuesta(["ok": true, "version": "v1", "completo": false, "clips": [["id": "s01", "mp3": "AAA"], ["id": "../x", "mp3": "BBB"], ["id": "s02", "mp3": ""]]])
revisa(r == S.Respuesta(version: "v1", completo: false, clips: ["s01": "AAA"]), "solo clips con id limpio y audio")
revisa(S.respuesta(["ok": false, "error": "usuario"]) == nil && S.respuesta(nil) == nil, "un error del Hub no cambia nada")

print(fallos == 0 ? "\nTodo bien." : "\n\(fallos) fallo(s).")
exit(fallos == 0 ? 0 : 1)
