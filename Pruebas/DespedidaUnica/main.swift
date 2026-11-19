// Pruebas de la despedida única (Alma/DespedidaUnica.swift; Juan, 19-nov-2026).
//   swiftc Alma/DespedidaUnica.swift Pruebas/DespedidaUnica/main.swift -o /tmp/despedida-unica && /tmp/despedida-unica
// Las corre el robot en cada PR (testflight.yml, «Probar la despedida única»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}
let D = DespedidaUnica.self

// Qué es una despedida
revisa(D.esDespedida("Listo, queda así. Que descanses."), "«Listo, queda así. Que descanses.» es despedida")
revisa(D.esDespedida("Te dejo; si me necesitas, aquí estoy."), "«Te dejo; si me necesitas, aquí estoy» es despedida")
revisa(D.esDespedida("Perfecto, ya quedó programado. ¡Hasta luego, Juan!"), "«¡Hasta luego, Juan!» al final es despedida")
revisa(D.esDespedida("Me encargo. Cuídate."), "«Me encargo. Cuídate.» es despedida")
revisa(D.esDespedida("Que descanses"), "sin punto final también")
revisa(!D.esDespedida("¡Hola, Juan! Aquí estoy. ¿Qué hacemos?"), "el saludo no es despedida")
revisa(!D.esDespedida("Listo, le escribí a Gabriel. ¿Algo más?"), "una pregunta al final no es despedida")
revisa(!D.esDespedida("Que descanses. ¿Quieres que te recuerde lo de mañana?"), "si termina preguntando, no cuelga")
revisa(!D.esDespedida("La reserva de mañana entra a las tres y sale el domingo."), "una respuesta con datos no es despedida")
revisa(!D.esDespedida("Te dejo el resumen en pantalla con las tres reservas de la semana, los montos y las horas de entrada de cada huésped."),
       "una frase larga con «te dejo» no es despedida")
revisa(!D.esDespedida(""), "vacío no es despedida")

// Cuándo cuelga
let t0 = Date(timeIntervalSince1970: 1_000_000), lejos = Date.distantPast
func c(_ fin: Double, _ ahora: Double, juan: Double? = nil, voz: Date = lejos, trabajando: Bool = false) -> Bool {
    D.cuelga(desde: t0, finVoz: t0.addingTimeInterval(fin), juanHablo: juan.map { t0.addingTimeInterval($0) }, vozJuan: voz,
             trabajando: trabajando, ahora: t0.addingTimeInterval(ahora))
}
revisa(!c(3, 2), "mientras suena la despedida, no cuelga")
revisa(!c(3, 7), "a los 4 s del final todavía espera")
revisa(c(3, 8.1), "5 s de silencio después de la despedida: cuelga")
revisa(!c(3, 30, juan: 6), "Juan respondió después de la despedida: no cuelga (la llamada sigue)")
revisa(c(3, 8.1, juan: -10), "lo que Juan dijo antes de la despedida no cuenta")
revisa(!c(3, 8.1, voz: t0.addingTimeInterval(7.5)), "Juan está hablando (el micrófono lo oye): no cuelga encima")
revisa(!c(3, 10, voz: t0.addingTimeInterval(6)), "la cuenta de 5 s empieza de nuevo desde que Juan dejó de sonar")
revisa(c(3, 11.1, voz: t0.addingTimeInterval(6)), "y si no llega nada escrito, a los 5 s de su último sonido cuelga")
revisa(!c(3, 20, trabajando: true), "con una herramienta en curso no cuelga")
revisa(!c(-1, 10) && c(-1, 25.1), "si la voz nunca sonó, cuelga al tope")
revisa(c(3, 43.1, voz: t0.addingTimeInterval(43)), "ruido sin palabras 40 s después de la despedida: cuelga igual")

print(fallos == 0 ? "Todo bien" : "\(fallos) fallos")
exit(fallos == 0 ? 0 : 1)
