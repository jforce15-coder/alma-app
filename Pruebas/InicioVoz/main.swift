// Pruebas del orden al empezar una llamada con ElevenLabs (Alma/InicioVoz.swift).
//   swiftc Alma/InicioVoz.swift Pruebas/InicioVoz/main.swift -o /tmp/inicio-voz && /tmp/inicio-voz
// Las corre el robot en cada PR (testflight.yml, «Probar el inicio de la llamada»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}

revisa(InicioVoz.decidir(tipo: InicioVoz.ficha, inicioEnviado: false) == .mandar, "la ficha (con quien_llama) sale primero")
revisa(InicioVoz.decidir(tipo: "user_message", inicioEnviado: false) == .esperar, "lo que dijiste con «Alma» espera a la ficha (conferencia, Modo Inicio)")
revisa(InicioVoz.decidir(tipo: "contextual_update", inicioEnviado: false) == .esperar, "la captura de la pantalla también espera")
revisa(InicioVoz.decidir(tipo: "user_audio_chunk", inicioEnviado: false) == .esperar, "el audio también espera")
revisa(InicioVoz.decidir(tipo: "pong", inicioEnviado: false) == .mandar, "el pong no espera (ElevenLabs no corta la conexión)")
revisa(InicioVoz.decidir(tipo: "user_message", inicioEnviado: true) == .mandar, "después de la ficha, todo sale")
revisa(InicioVoz.tipo(["type": "user_message", "text": "Alma, …"]) == "user_message" && InicioVoz.tipo(["user_audio_chunk": "AAA"]) == "user_audio_chunk",
       "el tipo de cada mensaje")

// La conferencia del 5-nov, en orden: ElevenLabs contesta (metadata) antes de la ventana del saludo.
var salio: [String] = [], espera: [[String: Any]] = [], enviado = false
func mandar(_ o: [String: Any]) {
    if InicioVoz.decidir(tipo: InicioVoz.tipo(o), inicioEnviado: enviado) == .esperar { espera.append(o); return }
    salio.append(InicioVoz.tipo(o))
}
mandar(["type": "user_message", "text": "Alma, a la interesada…"])       // llegó la metadata: el pedido
mandar(["type": InicioVoz.ficha, "dynamic_variables": ["quien_llama": "Juan"]])  // pasó la ventana del saludo
enviado = true
let p = espera; espera = []; p.forEach(mandar)
revisa(salio == [InicioVoz.ficha, "user_message"], "la ficha sale antes que el pedido: Alma sabe que es Juan")

if fallos > 0 { print("\(fallos) fallaron"); exit(1) }
print("Todo bien")
