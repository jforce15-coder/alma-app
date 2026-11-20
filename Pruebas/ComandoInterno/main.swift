// Pruebas de los comandos internos en voz alta (Alma/ComandoInterno.swift; Juan, 20-nov-2026: «no estés diciendo skip turn»).
//   swiftc Alma/ComandoInterno.swift Pruebas/ComandoInterno/main.swift -o /tmp/comando-interno && /tmp/comando-interno
// Las corre el robot en cada PR (testflight.yml, «Probar los comandos internos»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}
typealias C = ComandoInterno

// MARK: - Se calla: solo el comando, o el comando con poquito alrededor
for f in ["skip_turn", "skip turn", "Skip turn.", "skip", "[softly] skip_turn", "end_call", "End call.", "nivel_weebo",
          "nivel weebo dos", "Nivel weebo 3.", "mostrar_gif(\"slow clap\")", "mostrar gif", "Claro. skip_turn", "Ok, skip turn.",
          "Te escucho. skip_turn", "skip_turn skip_turn", "hablar_con_claudio()"] {
    revisa(C.callar(f), "se calla: «\(f)»")
}

// MARK: - Suena: respuestas de verdad
for f in ["Claro, Juan, lo reviso ahora.", "Tu Modo Weebo está encendido.", "El nivel tres es el más alto.",
          "Listo, ya quedó la reserva del 1104 para el viernes. skip_turn",
          "Te mando el correo a recepcion_brunelo@ejemplo.com", "Te dejo la llamada.", "Sí.", "", "¿Algo más?",
          "Saltamos ese paso y sigo con el siguiente."] {
    revisa(!C.callar(f), "suena: «\(f)»")
}

// MARK: - Qué queda sin el comando
revisa(C.quitar("Claro. skip_turn").palabras == ["claro"], "«Claro. skip_turn» → queda «claro»")
revisa(C.quitar("nivel weebo dos, ¿qué tal?").palabras == ["que", "tal"], "«nivel weebo dos» se quita con su número")
revisa(!C.quitar("escribe a ana_lopez@correo.com").habia, "un correo con guion bajo no es un comando")
revisa(C.quitar("Hola").habia == false, "sin comandos: nada que quitar")

print(fallos == 0 ? "\nTodo bien." : "\n\(fallos) fallaron.")
exit(fallos == 0 ? 0 : 1)
