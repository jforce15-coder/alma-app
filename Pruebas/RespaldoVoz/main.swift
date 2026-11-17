// Pruebas de la voz de respaldo de Alma (Alma/RespaldoVoz.swift; Hub #657).
//   swiftc Alma/RespaldoVoz.swift Pruebas/RespaldoVoz/main.swift -o /tmp/respaldo-voz && /tmp/respaldo-voz
// Las corre el robot en cada PR (testflight.yml, «Probar la voz de respaldo»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}
typealias R = RespaldoVoz
let t0 = Date(timeIntervalSince1970: 10_000)

// Cuándo entra
revisa(R.usar(hayRed: false, cortes: [t0], ahora: t0, calle: false, conferencia: false, sinCreditos: false), "sin internet, la llamada normal sigue con la voz de respaldo")
revisa(!R.usar(hayRed: true, cortes: [t0], ahora: t0, calle: false, conferencia: false, sinCreditos: false), "con internet y un solo corte, se reabre ElevenLabs como siempre")
revisa(R.usar(hayRed: true, cortes: [t0.addingTimeInterval(-40), t0], ahora: t0, calle: false, conferencia: false, sinCreditos: false), "dos cortes en poco tiempo: conexión inestable, voz de respaldo")
revisa(!R.usar(hayRed: true, cortes: [t0.addingTimeInterval(-200), t0], ahora: t0, calle: false, conferencia: false, sinCreditos: false), "un corte viejo ya no cuenta")
revisa(!R.usar(hayRed: false, cortes: [t0], ahora: t0, calle: true, conferencia: false, sinCreditos: false), "en el Modo calle no: ahí se vuelve a esperar «Alma»")
revisa(!R.usar(hayRed: false, cortes: [t0], ahora: t0, calle: false, conferencia: true, sinCreditos: false), "en conferencia tampoco")
revisa(!R.usar(hayRed: false, cortes: [t0], ahora: t0, calle: false, conferencia: false, sinCreditos: true), "sin créditos no es la conexión: se dice el error")

// Cuándo sale
revisa(R.estableTras(vueltas: 0) == 6 && R.estableTras(vueltas: 1) == 12 && R.estableTras(vueltas: 5) == 60, "cada vez que vuelve y se cae, espera más para volver (6 s, 12 s… hasta 60 s)")
revisa(!R.puedeVolver(hayRed: true, redDesde: t0, ahora: t0.addingTimeInterval(3), vueltas: 0, ocupada: false, pendientes: 0), "recién volvió el internet: todavía no")
revisa(R.puedeVolver(hayRed: true, redDesde: t0, ahora: t0.addingTimeInterval(6.5), vueltas: 0, ocupada: false, pendientes: 0), "estable unos segundos: vuelve a su voz de siempre")
revisa(!R.puedeVolver(hayRed: false, redDesde: t0, ahora: t0.addingTimeInterval(60), vueltas: 0, ocupada: false, pendientes: 0), "sin internet no vuelve")
revisa(!R.puedeVolver(hayRed: true, redDesde: t0, ahora: t0.addingTimeInterval(60), vueltas: 0, ocupada: true, pendientes: 0), "si Alma está pensando o hablando, espera")
revisa(!R.puedeVolver(hayRed: true, redDesde: t0, ahora: t0.addingTimeInterval(60), vueltas: 0, ocupada: false, pendientes: 1), "si hay algo guardado, primero lo manda")

// Lo que se guarda sin internet
var cola: [String] = []
var g = R.guardar(cola, "  anota que mañana llega el plomero  "); cola = g.cola
revisa(g.cupo && cola == ["anota que mañana llega el plomero"], "lo dicho sin internet se guarda (limpio)")
revisa(R.trasGuardar(cuantas: 1, cupo: true) == R.guardado && R.trasGuardar(cuantas: 2, cupo: true) == "Guardado.", "la primera vez explica; después, corto")
revisa(R.guardar(cola, "   ").cola.count == 1, "lo vacío no se guarda")
for i in 0..<10 { g = R.guardar(cola, "pedido \(i)"); cola = g.cola }
revisa(cola.count == R.maxCola && !g.cupo && R.trasGuardar(cuantas: cola.count, cupo: false) == R.lleno, "hasta cinco cosas; después lo dice")
revisa(R.juntar(["uno"]) == "uno", "una sola va tal cual")
revisa(R.juntar(["uno", "dos"]).hasPrefix("Te lo dije mientras no había internet") && R.juntar(["uno", "dos"]).contains("uno · dos"), "varias van juntas en un pedido")

// El Hub
let p = R.pedido(token: "t", sesion: "s", texto: "  ¿cuántas llegadas hay hoy?  ")
revisa(p["action"] as? String == "calle" && p["sin_audio"] as? Bool == true && p["texto"] as? String == "¿cuántas llegadas hay hoy?" && p["session"] as? String == "s", "se pide con «calle», sin audio y con la sesión")
revisa(R.hablar(["hablar": " Hoy llegan tres. "]) == "Hoy llegan tres." && R.hablar(nil) == R.noLlego, "dice lo que contestó el Hub; sin respuesta, pide repetir")

// Lo que dice
revisa(R.frase(hayRed: false) == R.entra && R.frase(hayRed: true) == R.inestable, "dice por qué cambió de voz")
revisa(R.voz["genero"] as? String == "mujer", "la voz del iPhone es de mujer (es Alma)")

print(fallos == 0 ? "Todo bien" : "\(fallos) fallos")
exit(fallos == 0 ? 0 : 1)
