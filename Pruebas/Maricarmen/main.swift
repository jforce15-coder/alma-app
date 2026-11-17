// Pruebas de Maricarmen, el alter ego de Alma (Alma/MaricarmenReglas.swift; Hub #666).
//   swiftc Alma/MaricarmenReglas.swift Alma/RespaldoReglas.swift Pruebas/Maricarmen/main.swift -o /tmp/maricarmen && /tmp/maricarmen
// Las corre el robot en cada PR (testflight.yml, «Probar Maricarmen»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}
typealias M = MaricarmenReglas

// Entrar
revisa(M.pideIr("Pásame con Maricarmen"), "«Pásame con Maricarmen» pasa con ella")
revisa(M.pideIr("Alma, ¿me pasas con Mari Carmen, por favor?"), "«Mari Carmen» separado también")
revisa(M.pideIr("quiero hablar con Maricarmen"), "«quiero hablar con Maricarmen»")
revisa(M.pideIr("Ponme a Maricarmen"), "«ponme a Maricarmen»")
revisa(M.pideIr("Maricarmen, ven"), "«Maricarmen, ven»")
revisa(!M.pideIr("no me pases con Maricarmen"), "«no me pases con Maricarmen» no")
revisa(!M.pideIr("¿Quién es Maricarmen?"), "una pregunta sobre ella no la llama")
revisa(!M.pideIr("Pásame con Claudio"), "con Claudio no es Maricarmen")
revisa(!M.pideIr("pasar el recado a Maricarmen"), "un recado para una persona llamada Maricarmen no la llama")
revisa(!M.pideIr("llama a Maricarmen"), "llamar a una persona llamada Maricarmen no la llama")
revisa(!M.pideIr(""), "vacío, no")

// Volver
revisa(M.pideVolver("Pásame con Alma"), "«Pásame con Alma» vuelve")
revisa(M.pideVolver("vuelve, Alma"), "«vuelve, Alma» vuelve")
revisa(M.pideVolver("Quiero hablar con Alma otra vez"), "«quiero hablar con Alma otra vez» vuelve")
revisa(M.pideVolver("regrésame con Alma"), "«regrésame con Alma» vuelve")
revisa(!M.pideVolver("no quiero volver con Alma"), "«no quiero volver con Alma» no")
revisa(!M.pideVolver("¿Qué opina Alma de esto?"), "nombrar a Alma no es volver")
revisa(!M.pideVolver("Pásame con Maricarmen"), "pedir a Maricarmen no es volver")

// Lo que manda al Hub: la acción calle sin audio y con alter
let p = RespaldoReglas.pedido(token: "t", sesion: "s", texto: " hola ", alter: M.alter)
revisa(p["action"] as? String == "calle" && p["sin_audio"] as? Bool == true, "va por la acción calle sin audio")
revisa(p["alter"] as? String == "maricarmen" && p["texto"] as? String == "hola", "con alter maricarmen y el texto limpio")
revisa(RespaldoReglas.pedido(token: "t", sesion: "s", texto: "hola")["alter"] == nil, "la voz de respaldo no manda alter")

// Su voz
revisa(M.idiomas.first == "es-ES", "primero una voz de España (el acento del nivel 3)")

if fallos > 0 { print("\(fallos) prueba(s) fallaron"); exit(1) }
print("Todas las pruebas de Maricarmen pasaron.")
