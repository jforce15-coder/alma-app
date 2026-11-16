// Pruebas de Hablar con Claudio (Alma/AgenteVoz.swift; Hub #550).
//   swiftc Alma/AgenteVoz.swift Pruebas/AgenteVoz/main.swift -o /tmp/agente-voz && /tmp/agente-voz
// Las corre el robot en cada PR (testflight.yml, «Probar Hablar con Claudio»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}

// Quién cambia a quién
revisa(AgenteVoz.cambio(herramienta: "hablar_con_claudio", actual: .alma) == .claudio, "Alma pasa con Claudio")
revisa(AgenteVoz.cambio(herramienta: "volver_con_alma", actual: .claudio) == .alma, "Claudio vuelve con Alma")
revisa(AgenteVoz.cambio(herramienta: "hablar_con_claudio", actual: .claudio) == nil, "con Claudio, «hablar con Claudio» no abre otro")
revisa(AgenteVoz.cambio(herramienta: "volver_con_alma", actual: .alma) == nil, "con Alma, «volver con Alma» no hace nada")
revisa(AgenteVoz.cambio(herramienta: "mostrar_en_chat", actual: .alma) == nil && !AgenteVoz.esCambio("mostrar_en_chat"), "las demás herramientas no cambian de agente")
revisa(AgenteVoz.esCambio("hablar_con_claudio") && AgenteVoz.esCambio("volver_con_alma"), "las dos de cambio se reconocen (y no se contestan)")

// Lo que se pide al Hub
let pc = AgenteVoz.pedido(.claudio, token: "t", sesion: "s", motivo: "  cambiar el botón  ")
revisa(pc["action"] as? String == "vozClaudio" && pc["session"] as? String == "s" && pc["motivo"] as? String == "cambiar el botón", "Claudio se pide con vozClaudio, la sesión y lo que Juan le dijo a Alma")
revisa((AgenteVoz.pedido(.claudio, token: "t", sesion: "s", motivo: String(repeating: "a", count: 900))["motivo"] as? String)?.count == 300, "el motivo va corto (300 letras)")
let pa = AgenteVoz.pedido(.alma, token: "t", sesion: "s")
revisa(pa["action"] as? String == "vozWeb" && pa["app"] as? String == "alma" && pa["claudio"] as? Bool == true && pa["motivo"] == nil, "Alma se pide con vozWeb, como la app de Alma que sabe cambiar a Claudio")

// Cuándo se corta la conversación de antes: después de su frase
let t0 = Date(timeIntervalSince1970: 1_000)
revisa(!AgenteVoz.listo(finVoz: t0.addingTimeInterval(2), pedido: t0, ahora: t0.addingTimeInterval(1)), "mientras Alma todavía dice «te paso con Claudio», no se corta")
revisa(!AgenteVoz.listo(finVoz: t0.addingTimeInterval(1), pedido: t0, ahora: t0.addingTimeInterval(1.2)), "un respiro después de la frase")
revisa(AgenteVoz.listo(finVoz: t0.addingTimeInterval(1), pedido: t0, ahora: t0.addingTimeInterval(1.4)), "terminó la frase: se cambia")
revisa(AgenteVoz.listo(finVoz: t0.addingTimeInterval(60), pedido: t0, ahora: t0.addingTimeInterval(6)), "si el audio no avisa, a los 6 s se cambia igual")

// Lo que se dice y se ve
revisa(AgenteVoz.primerMensaje(.claudio, ficha: "Hola, Juan, aquí Claudio. ¿Qué hacemos?") == "Hola, Juan, aquí Claudio. ¿Qué hacemos?", "Claudio saluda con lo que trae su ficha")
revisa(AgenteVoz.primerMensaje(.claudio, ficha: "").contains("Claudio"), "sin ficha, Claudio igual se presenta")
revisa(AgenteVoz.primerMensaje(.alma, ficha: "¡Hola, Juan!") == AgenteVoz.vuelta, "al volver, Alma no saluda de nuevo: «Aquí estoy de nuevo»")
revisa(AgenteVoz.claudio.estadoTexto(habla: true) == "Claudio te responde" && AgenteVoz.alma.estadoTexto(habla: true) == "Alma te responde", "la pantalla dice quién responde")
if let h = AgenteVoz.claudio.halo { revisa(h.r > 0.9 && h.g > 0.4 && h.g < 0.6 && h.b < 0.2, "el halo de Claudio es naranja") } else { revisa(false, "el halo de Claudio es naranja") }
revisa(AgenteVoz.alma.halo == nil, "Alma conserva su halo de siempre")

if fallos > 0 { print("\(fallos) fallaron"); exit(1) }
print("Todo bien")
