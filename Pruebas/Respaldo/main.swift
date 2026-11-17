// Pruebas de la voz de respaldo de Alma (Alma/RespaldoReglas.swift; Hub #657).
//   swiftc Alma/RespaldoReglas.swift Pruebas/Respaldo/main.swift -o /tmp/respaldo && /tmp/respaldo
// Las corre el robot en cada PR (testflight.yml, «Probar la voz de respaldo»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}
typealias R = RespaldoReglas
let t0 = Date(timeIntervalSince1970: 10_000)

// Cuándo entra
revisa(R.trasCorte(hayRed: false, conectada: 60, cortes: [], ahora: t0), "sin internet, un corte pasa a la voz de respaldo")
revisa(R.trasCorte(hayRed: true, conectada: nil, cortes: [], ahora: t0), "si ElevenLabs nunca conectó, también")
revisa(!R.trasCorte(hayRed: true, conectada: 60, cortes: [], ahora: t0), "un solo corte con internet se vuelve a abrir como siempre")
revisa(R.trasCorte(hayRed: true, conectada: 60, cortes: [t0.addingTimeInterval(-100)], ahora: t0), "el segundo corte en 3 min ya es señal mala: respaldo")
revisa(!R.trasCorte(hayRed: true, conectada: 60, cortes: [t0.addingTimeInterval(-200)], ahora: t0), "un corte de hace más de 3 min ya no cuenta")
let c = R.sumarCorte([t0.addingTimeInterval(-500), t0.addingTimeInterval(-10)], ahora: t0)
revisa(c.count == 2 && c.last == t0, "los cortes viejos se olvidan y el de ahora se suma")
revisa(R.esDeRed(NSURLErrorNotConnectedToInternet) && R.esDeRed(NSURLErrorTimedOut) && R.esDeRed(NSURLErrorNetworkConnectionLost), "sin internet, red caída o red lenta son de la red")
revisa(!R.esDeRed(NSURLErrorBadServerResponse) && !R.esDeRed(NSURLErrorCancelled), "un error del Hub o una cancelación no son de la red")

// Cuándo sale
revisa(!R.volver(hayRed: true, buenaDesde: t0.addingTimeInterval(-10), quieto: true, ultimoIntento: nil, ahora: t0), "con 10 s de señal todavía no vuelve")
revisa(R.volver(hayRed: true, buenaDesde: t0.addingTimeInterval(-21), quieto: true, ultimoIntento: nil, ahora: t0), "con 20 s de señal estable y en silencio, vuelve a su voz")
revisa(!R.volver(hayRed: true, buenaDesde: t0.addingTimeInterval(-60), quieto: false, ultimoIntento: nil, ahora: t0), "mientras habla, piensa o Juan habla, no cambia")
revisa(!R.volver(hayRed: false, buenaDesde: nil, quieto: true, ultimoIntento: nil, ahora: t0), "sin internet no vuelve")
revisa(!R.volver(hayRed: true, buenaDesde: t0.addingTimeInterval(-60), quieto: true, ultimoIntento: t0.addingTimeInterval(-60), ahora: t0), "si el último intento fue hace 1 min, espera")
revisa(R.volver(hayRed: true, buenaDesde: t0.addingTimeInterval(-60), quieto: true, ultimoIntento: t0.addingTimeInterval(-130), ahora: t0), "a los 2 min lo intenta otra vez")

// Lo que se manda al Hub
let p = R.pedido(token: "t", sesion: "s", texto: "  ¿quién llega hoy?  ")
revisa(p["action"] as? String == "calle" && p["sin_audio"] as? Bool == true && p["session"] as? String == "s" && p["texto"] as? String == "¿quién llega hoy?", "va por la acción calle, sin audio y con la sesión")
revisa(R.respuesta(nil) == nil, "sin respuesta del Hub no hay frase (la dice la app)")
revisa(R.respuesta(["ok": true, "hablar": "Llegan dos."]) == R.Respuesta(hablar: "Llegan dos.", claudio: false), "la frase del Hub se dice tal cual")
revisa(R.respuesta(["ok": false, "hablar": " "])?.hablar == R.fraseSinRespuesta, "sin frase, pide repetir (nunca en silencio)")
revisa(R.respuesta(["ok": true, "hablar": "Te paso.", "claudio": true])?.claudio == true, "«quiero hablar con Claudio» lo pasa con Claudio")

// Lo guardado sin internet
var l: [R.Pendiente] = []
for i in 0..<R.maxPendientes { l = R.guardar(l, texto: "pedido \(i)", ahora: t0) ?? [] }
revisa(l.count == R.maxPendientes, "se guardan hasta 5 pedidos")
revisa(R.guardar(l, texto: "uno más", ahora: t0) == nil, "el sexto ya no cabe (Alma lo dice)")
revisa(R.guardar(l, texto: "uno más", ahora: t0.addingTimeInterval(31 * 60))?.count == 1, "los de hace más de 30 min ya no se mandan y dejan lugar")
revisa(R.guardar([], texto: "   ", ahora: t0)?.isEmpty == true, "lo vacío no se guarda")
revisa(R.vigentes([.init(texto: "a", cuando: t0.addingTimeInterval(-60)), .init(texto: "b", cuando: t0.addingTimeInterval(-3600))], ahora: t0).map { $0.texto } == ["a"], "solo se mandan los vigentes")

print(fallos == 0 ? "Todo bien." : "\(fallos) fallos.")
exit(fallos == 0 ? 0 : 1)
