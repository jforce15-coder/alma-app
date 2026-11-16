// Pruebas de la lógica pura del GIF de la broma (Alma/GifBroma.swift). Corren solas, sin iOS:
//   swiftc Alma/GifBroma.swift Pruebas/GifBroma/main.swift -o /tmp/gif-broma && /tmp/gif-broma
// Las corre el robot en cada PR (testflight.yml, «Probar el GIF de la broma»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}

let t0 = Date(timeIntervalSince1970: 1_800_000_000)

do {
    revisa(ReglasGif.idea("slow clap!!") == "slow clap", "la idea se limpia (sin signos)")
    revisa(ReglasGif.idea("I'll be back") == "I'll be back", "los apóstrofos se quedan")
    revisa(ReglasGif.idea("<>") == nil && ReglasGif.idea(nil) == nil && ReglasGif.idea("x") == nil, "sin idea, no hay GIF")
    revisa(ReglasGif.idea(String(repeating: "a", count: 90))?.count == 40, "la idea se corta a 40 letras")
}

do {
    var r = ReglasGif()
    revisa(r.pedir("clap", principal: false, pantalla: true, conAlma: true, ahora: t0) == nil, "con alguien que no es el principal, no")
    revisa(r.pedir("clap", principal: true, pantalla: false, conAlma: true, ahora: t0) == nil, "con el teléfono bloqueado o en el Modo calle, no")
    revisa(r.pedir("clap", principal: true, pantalla: true, conAlma: false, ahora: t0) == nil, "con Claudio, no")
    revisa(r.cuantos == 0, "lo que no se mostró no cuenta")
    revisa(r.pedir("mind blown", principal: true, pantalla: true, conAlma: true, ahora: t0) == "mind blown", "con Juan, la pantalla a la vista y Alma: se muestra")
    revisa(r.pedir("clap", principal: true, pantalla: true, conAlma: true, ahora: t0.addingTimeInterval(30)) == nil, "otro a los 30 s: no (uno cada 60 s)")
    revisa(r.pedir("clap", principal: true, pantalla: true, conAlma: true, ahora: t0.addingTimeInterval(61)) == "clap", "a los 61 s: sí")
    _ = r.pedir("a b", principal: true, pantalla: true, conAlma: true, ahora: t0.addingTimeInterval(130))
    _ = r.pedir("c d", principal: true, pantalla: true, conAlma: true, ahora: t0.addingTimeInterval(200))
    revisa(r.cuantos == 4 && r.pedir("e f", principal: true, pantalla: true, conAlma: true, ahora: t0.addingTimeInterval(300)) == nil, "como mucho 4 por llamada")
    r.reiniciar()
    revisa(r.pedir("e f", principal: true, pantalla: true, conAlma: true, ahora: t0.addingTimeInterval(301)) == "e f", "llamada nueva: se empieza de cero")
}

print(fallos == 0 ? "Todo bien." : "\(fallos) fallo(s).")
exit(fallos == 0 ? 0 : 1)
