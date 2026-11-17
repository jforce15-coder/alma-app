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
revisa(pa["maricarmen"] as? Bool == true && pc["maricarmen"] == nil, "Alma se pide con «maricarmen»: la app sabe pasar a Maricarmen en la llamada (Hub #707); Claudio no")

// Cuándo se corta la conversación de antes: después de su frase
let t0 = Date(timeIntervalSince1970: 1_000)
revisa(!AgenteVoz.listo(finVoz: t0.addingTimeInterval(1), pedido: t0, ahora: t0.addingTimeInterval(0.8)), "mientras Alma todavía dice «Te lo paso.», no se corta")
revisa(!AgenteVoz.listo(finVoz: t0.addingTimeInterval(1), pedido: t0, ahora: t0.addingTimeInterval(1.05)), "un respiro cortito después de la frase")
revisa(AgenteVoz.listo(finVoz: t0.addingTimeInterval(1), pedido: t0, ahora: t0.addingTimeInterval(1.15)), "terminó la frase: se cambia casi de inmediato (Juan: «que sea más rápido»)")
revisa(AgenteVoz.listo(finVoz: t0.addingTimeInterval(60), pedido: t0, ahora: t0.addingTimeInterval(3)), "si el audio no avisa, a los 3 s se cambia igual")
revisa(AgenteVoz.respiro <= 0.15 && AgenteVoz.tope <= 3, "sin respiro largo: el pase no espera")

// Lo que se dice y se ve
revisa(AgenteVoz.primerMensaje(.claudio, ficha: "Hola, Juan, aquí Claudio. ¿Qué hacemos?") == "Hola, Juan, aquí Claudio. ¿Qué hacemos?", "Claudio saluda con lo que trae su ficha")
revisa(AgenteVoz.primerMensaje(.claudio, ficha: "") == AgenteVoz.saludoClaudio && AgenteVoz.saludoClaudio.contains("Alma me dijo que me necesitabas"), "sin ficha, Claudio saluda como alguien a quien fueron a llamar")
revisa(AgenteVoz.primerMensaje(.alma, ficha: "¡Hola, Juan!") == AgenteVoz.vuelta, "al volver con un Hub de antes, Alma no saluda de nuevo: «Aquí estoy de nuevo»")
revisa(AgenteVoz.primerMensaje(.alma, ficha: "¡Hola, Juan!", cierre: "Listo, quedó pedido lo de cambiar el botón. Si necesitas algo más, aquí estoy.") == "Listo, quedó pedido lo de cambiar el botón. Si necesitas algo más, aquí estoy.", "al volver, Alma cierra con la frase del Hub (lo que hizo Claudio)")

// Alma cierra y cuelga (Juan, 16-nov-2026: «Claudio aparece y se va; cuando se va vuelve Alma y cierra esa interacción»)
let v0 = Date(timeIntervalSince1970: 5_000)
let pv = AgenteVoz.pedido(.alma, token: "t", sesion: "s", deClaudio: "conv_c1")
revisa(pv["vuelta_claudio"] as? String == "conv_c1" && AgenteVoz.pedido(.alma, token: "t", sesion: "s")["vuelta_claudio"] == nil, "al volver, se manda la conversación de Claudio para que el Hub sepa qué hizo")
revisa(!AgenteVoz.cuelgaTrasVuelta(desde: v0, finVoz: v0.addingTimeInterval(3), juanHablo: nil, ahora: v0.addingTimeInterval(2)), "mientras Alma dice el cierre, no cuelga")
revisa(!AgenteVoz.cuelgaTrasVuelta(desde: v0, finVoz: v0.addingTimeInterval(3), juanHablo: nil, ahora: v0.addingTimeInterval(5)), "un momento después del cierre, todavía no (Juan puede pedir algo más)")
revisa(AgenteVoz.cuelgaTrasVuelta(desde: v0, finVoz: v0.addingTimeInterval(3), juanHablo: nil, ahora: v0.addingTimeInterval(7.1)), "cerró y Juan no dijo nada: cuelga")
revisa(!AgenteVoz.cuelgaTrasVuelta(desde: v0, finVoz: v0.addingTimeInterval(3), juanHablo: v0.addingTimeInterval(5), ahora: v0.addingTimeInterval(30)), "Juan siguió hablando: no cuelga")
revisa(AgenteVoz.cuelgaTrasVuelta(desde: v0, finVoz: v0.addingTimeInterval(3), juanHablo: v0.addingTimeInterval(-10), ahora: v0.addingTimeInterval(7.1)), "lo que Juan dijo antes de volver (con Claudio) no cuenta")
revisa(!AgenteVoz.cuelgaTrasVuelta(desde: v0, finVoz: v0.addingTimeInterval(-1), juanHablo: nil, ahora: v0.addingTimeInterval(10)) && AgenteVoz.cuelgaTrasVuelta(desde: v0, finVoz: v0.addingTimeInterval(-1), juanHablo: nil, ahora: v0.addingTimeInterval(20)), "si el audio del cierre nunca llega, cuelga a los 20 s")
revisa(AgenteVoz.claudio.estadoTexto(habla: true) == "Claudio te responde" && AgenteVoz.alma.estadoTexto(habla: true) == "Alma te responde", "la pantalla dice quién responde")
if let h = AgenteVoz.claudio.halo { revisa(h.r > 0.9 && h.g > 0.4 && h.g < 0.6 && h.b < 0.2, "el halo de Claudio es naranja") } else { revisa(false, "el halo de Claudio es naranja") }
revisa(AgenteVoz.alma.halo == nil, "Alma conserva su halo de siempre")


// Desde el Modo calle (16-nov-2026): «quiero hablar con Claudio» abre directo la llamada con Claudio
for t in ["quiero hablar con Claudio", "Quiero hablar con el equipo de desarrollo", "pásame con Claudio", "Alma, pásame a Claudio",
          "comunícame con los de desarrollo", "¿Me pones con Claudio?", "quiero hablar un momento con Claudio sobre el botón de pagos", "Ponme con Claudio"] {
    revisa(AgenteVoz.pideClaudio(t), "«\(t)» pide hablar con Claudio")
}
for t in ["dile a Claudio que cambie el botón", "no quiero hablar con Claudio", "¿Claudio ya terminó lo del botón?", "habla con Flor sobre la limpieza",
          "pide a desarrollo que arregle el botón", ""] {
    revisa(!AgenteVoz.pideClaudio(t), "«\(t)» no abre a Claudio (va como pedido)")
}
revisa(AgenteVoz.normal("¿Me PASAS con Claudio?") == "me pasas con claudio", "sin acentos, signos ni mayúsculas (la misma regla que el Hub)")
revisa(AgenteVoz.motivoDe("quiero hablar con Claudio") == "", "sin nada más: Claudio saluda con «¿Qué hacemos?»")
revisa(AgenteVoz.motivoDe("Alma, quiero hablar con Claudio por favor") == "", "«Alma» y «por favor» no son un motivo")
revisa(AgenteVoz.motivoDe("quiero hablar con Claudio sobre el botón de pagos") == "quiero hablar con Claudio sobre el botón de pagos", "con un tema: Claudio empieza por ahí")
revisa(AgenteVoz.enCalle(["ok": true, "signed_url": "wss://x", "agent_id": "a"]) == .abrir, "con su conversación: se abre la llamada con Claudio")
revisa(AgenteVoz.enCalle(["ok": false, "error": "Claudio es solo para el administrador principal.", "codigo": "no_principal"]) == .comoPedido, "otra persona: Claudio no existe, va como pedido")
revisa(AgenteVoz.enCalle(["ok": false, "error": "accion"]) == .comoPedido, "un Hub sin vozClaudio: va como pedido")
revisa(AgenteVoz.enCalle(["ok": false, "error": "Claudio todavía no está listo (el Hub lo crea en la próxima vuelta).", "codigo": "sin_agente"]) == .decir(AgenteVoz.sinClaudio), "sin el agente de Claudio: una frase corta")
revisa(AgenteVoz.enCalle(["ok": false, "error": "Claudio todavía no está listo (el Hub lo crea en la próxima vuelta)."]) == .decir(AgenteVoz.sinClaudio), "lo mismo con un Hub sin «codigo»")
revisa(AgenteVoz.enCalle(nil) == .decir(AgenteVoz.noPase) && AgenteVoz.enCalle(["ok": false, "error": "ElevenLabs 401", "codigo": "sin_url"]) == .decir(AgenteVoz.noPase), "el Hub no contestó o ElevenLabs falló: una frase, sin quedarse colgado")
revisa(AgenteVoz.sinClaudio.split(separator: " ").count <= 12 && AgenteVoz.noPase.split(separator: " ").count <= 12, "las frases son cortas y simples")

// El socket de antes de cambiar de agente no corta la conversación nueva (16-nov-2026: así se caía el paso a Claudio)
final class SocketDoble {}
let viejoS = SocketDoble(), nuevoS = SocketDoble()
revisa(AgenteVoz.esSocketActual(nuevoS, nuevoS), "el socket de ahora sí cuenta")
revisa(!AgenteVoz.esSocketActual(viejoS, nuevoS), "el error del socket viejo no es de la conversación nueva")
revisa(!AgenteVoz.esSocketActual(viejoS, nil) && !AgenteVoz.esSocketActual(nil, nuevoS), "sin socket (ya se colgó) no cuenta ninguno")

if fallos > 0 { print("\(fallos) fallaron"); exit(1) }
print("Todo bien")
