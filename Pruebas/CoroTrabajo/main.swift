// Pruebas de la lógica pura del coro de espera (Alma/CoroTrabajoReglas.swift). Corren solas, sin iOS:
//   swiftc Alma/CoroTrabajoReglas.swift Pruebas/CoroTrabajo/main.swift -o /tmp/coro-trabajo && /tmp/coro-trabajo
// Las corre el robot en cada PR (testflight.yml, «Probar el coro de Alma trabajando»).
// Juan, 17-nov-2026: «el typing es mientras se procesa (lo corto); el eco es el sonido de espera (lo largo)».
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}
func cerca(_ a: Double, _ b: Double, _ tol: Double = 0.001) -> Bool { abs(a - b) <= tol }

let t0 = Date(timeIntervalSince1970: 1_800_000_000)
func en(_ s: Double) -> Date { t0.addingTimeInterval(s) }

// Lo corto suena a tecleo; pasados 2,5 s, coro de espera
do {
    var r = CoroReglas()
    revisa(r.empieza("a", nombre: "secretaria", ahora: t0), "una herramienta que espera respuesta cuenta")
    revisa(!r.debeSonar(en(1)), "a 1 s: solo tecleo (búsqueda corta)")
    revisa(!r.debeSonar(en(2.4)), "a 2,4 s: todavía tecleo")
    revisa(r.debeSonar(en(2.5)), "a 2,5 s: entra el coro de espera")
    revisa(r.termina("a"), "al terminar la única, queda en cero")
    revisa(!r.debeSonar(en(3)), "sin herramientas, no suena")
    var rapida = CoroReglas()
    rapida.empieza("b", nombre: "lookup_reservation", ahora: t0)
    rapida.termina("b")
    revisa(!rapida.debeSonar(en(3)), "una búsqueda de 2 s nunca llega al coro")
}

// Cambiar de agente es espera larga: de inmediato, y como mucho 12 s
do {
    var r = CoroReglas()
    revisa(r.empieza("c", nombre: "hablar_con_claudio", ahora: t0), "pasar a Claudio cuenta como espera")
    revisa(r.debeSonar(t0), "pasar a Claudio: el coro entra de inmediato")
    r.vencer(en(11)); revisa(r.debeSonar(en(11)), "a los 11 s sigue")
    r.vencer(en(12.5)); revisa(r.cuantas == 0, "si la conversación nueva no llegó, a los 12 s se olvida")
}

// La cuenta: para al terminar la última
do {
    var r = CoroReglas()
    r.empieza("a", nombre: "secretaria", ahora: t0)
    r.empieza("b", nombre: "property_info", ahora: en(1))
    revisa(r.cuantas == 2, "dos herramientas a la vez cuentan dos")
    revisa(!r.empieza("a", nombre: "secretaria", ahora: en(1.5)), "la misma herramienta (request y client_tool_call) no cuenta dos veces")
    revisa(!r.termina("a"), "termina la primera: todavía queda una")
    revisa(!r.debeSonar(en(3)), "la que sigue espera su propio umbral (empezó al segundo 1)")
    revisa(r.debeSonar(en(3.5)), "y suena a los 2,5 s de ella")
    revisa(r.termina("b"), "termina la última: queda en cero")
    revisa(!r.termina("b") && !r.termina("x"), "respuestas repetidas o ajenas no hacen nada")
}

// Las de fondo y las que no esperan respuesta no cuentan; tope de 75 s; cortar
do {
    var r = CoroReglas()
    for n in ["enviar_confirmado", "claudio_pedido", "nivel_weebo", "mostrar_gif", "mostrar_en_chat", "pasar_a_maricarmen", ""] {
        revisa(!r.empieza("id-" + n, nombre: n, ahora: t0), "«" + n + "» nunca suena (de fondo o sin espera)")
    }
    revisa(!r.empieza("", nombre: "secretaria", ahora: t0), "sin tool_call_id no cuenta")
    r.empieza("a", nombre: "anillo_medir_ahora", ahora: t0)
    revisa(r.debeSonar(en(30)), "a los 30 s sigue sonando")
    r.vencer(en(80))
    revisa(r.cuantas == 0 && !r.debeSonar(en(80)), "si la respuesta nunca llega, se olvida (75 s)")
    r.empieza("b", nombre: "secretaria", ahora: t0)
    r.empieza("c", nombre: "hablar_con_claudio", ahora: t0)
    r.corta()
    revisa(r.cuantas == 0 && !r.debeSonar(en(5)), "interrupción, conversación nueva o colgar: se corta todo")
}

// El tecleo se baja solo mientras suena la espera y Alma no habla
do {
    revisa(CoroReglas.volumenTecleo(coroSuena: false, almaHabla: false, normal: 1) == 1, "sin coro: tecleo normal")
    revisa(CoroReglas.volumenTecleo(coroSuena: true, almaHabla: false, normal: 1) == CoroReglas.tecleo, "con coro: tecleo bajo (0,12)")
    revisa(CoroReglas.volumenTecleo(coroSuena: true, almaHabla: true, normal: 1) == 1, "Alma hablando se oye completa")
}

// Ducking: Alma −10 dB, Juan −6 dB, Alma manda
do {
    revisa(CoroReglas.objetivoDb(almaHabla: false, juanHabla: false) == 0, "nadie habla: volumen completo")
    revisa(CoroReglas.objetivoDb(almaHabla: true, juanHabla: false) == -10, "Alma habla: −10 dB")
    revisa(CoroReglas.objetivoDb(almaHabla: false, juanHabla: true) == -6, "Juan habla: −6 dB")
    revisa(CoroReglas.objetivoDb(almaHabla: true, juanHabla: true) == -10, "los dos: manda Alma (−10 dB)")
    revisa(cerca(Double(CoroReglas.lineal(-10)), 0.3162), "−10 dB es 0,316 lineal")
    revisa(cerca(Double(CoroReglas.lineal(-6)), 0.5012), "−6 dB es 0,501 lineal")
}

// Rampas: entrar 0,4 · salir 0,5 · bajar 150 ms · subir 400 ms
do {
    revisa(CoroReglas.duracion(desde: 0, hacia: 1) == 0.4, "entrar en 0,4 s")
    revisa(CoroReglas.duracion(desde: 1, hacia: 0) == 0.5, "salir en 0,5 s")
    revisa(CoroReglas.duracion(desde: 1, hacia: CoroReglas.lineal(-10)) == 0.15, "bajar en 150 ms")
    revisa(CoroReglas.duracion(desde: CoroReglas.lineal(-10), hacia: 1) == 0.4, "volver en 400 ms")
    let objetivo = CoroReglas.lineal(-10)
    let v = (1 - objetivo) / Float(CoroReglas.duracion(desde: 1, hacia: objetivo))
    var nivel: Float = 1, t = 0.0
    while nivel > objetivo { nivel = CoroReglas.paso(nivel: nivel, objetivo: objetivo, velocidad: v, dt: 0.025); t += 0.025 }
    revisa(cerca(t, 0.15, 0.026) && nivel == objetivo, "la bajada a −10 dB tarda ~150 ms y no se pasa")
    let vs = Float(1) / Float(CoroReglas.duracion(desde: 1, hacia: 0))
    nivel = 1; t = 0
    while nivel > 0 { nivel = CoroReglas.paso(nivel: nivel, objetivo: 0, velocidad: vs, dt: 0.025); t += 0.025 }
    revisa(cerca(t, 0.5, 0.026), "la salida tarda ~0,5 s")
}

print(fallos == 0 ? "Todo bien" : "\(fallos) fallos")
exit(fallos == 0 ? 0 : 1)
