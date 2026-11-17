// Pruebas de la lógica pura del coro «Alma está trabajando» (Alma/CoroTrabajoReglas.swift). Corren solas, sin iOS:
//   swiftc Alma/CoroTrabajoReglas.swift Pruebas/CoroTrabajo/main.swift -o /tmp/coro-trabajo && /tmp/coro-trabajo
// Las corre el robot en cada PR (testflight.yml, «Probar el coro de Alma trabajando»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}
func cerca(_ a: Double, _ b: Double, _ tol: Double = 0.001) -> Bool { abs(a - b) <= tol }

let t0 = Date(timeIntervalSince1970: 1_800_000_000)
func en(_ s: Double) -> Date { t0.addingTimeInterval(s) }

// Umbral: las herramientas rápidas no suenan
do {
    var r = CoroReglas()
    revisa(r.empieza("a", nombre: "secretaria", ahora: t0), "una herramienta que espera respuesta cuenta")
    revisa(!r.debeSonar(en(0.3)), "a los 0,3 s todavía no suena")
    revisa(r.debeSonar(en(0.6)), "a los 0,6 s ya suena")
    revisa(r.termina("a"), "al terminar la única, queda en cero")
    revisa(!r.debeSonar(en(0.7)), "sin herramientas, no suena")
    var rapida = CoroReglas()
    rapida.empieza("b", nombre: "lookup_reservation", ahora: t0)
    rapida.termina("b")
    revisa(!rapida.debeSonar(en(0.6)), "una herramienta de 0,4 s nunca llega a sonar")
}

// La cuenta: para al terminar la última
do {
    var r = CoroReglas()
    r.empieza("a", nombre: "secretaria", ahora: t0)
    r.empieza("b", nombre: "property_info", ahora: en(0.2))
    revisa(r.cuantas == 2, "dos herramientas a la vez cuentan dos")
    revisa(!r.empieza("a", nombre: "secretaria", ahora: en(0.3)), "la misma herramienta (request y client_tool_call) no cuenta dos veces")
    revisa(!r.termina("a"), "termina la primera: todavía queda una")
    revisa(r.debeSonar(en(1)), "con una corriendo sigue sonando")
    revisa(r.termina("b"), "termina la última: queda en cero")
    revisa(!r.termina("b"), "una respuesta repetida no hace nada")
    revisa(!r.termina("x"), "una respuesta de algo que no contaba no hace nada")
}

// El umbral cuenta desde la herramienta que sigue viva
do {
    var r = CoroReglas()
    r.empieza("a", nombre: "secretaria", ahora: t0)
    r.termina("a")
    r.empieza("b", nombre: "secretaria", ahora: en(1))
    revisa(!r.debeSonar(en(1.3)), "una nueva herramienta espera su propio umbral")
    revisa(r.debeSonar(en(1.6)), "y suena a los 0,6 s de ella")
}

// Las que no esperan respuesta no cuentan; tope de 75 s; cortar
do {
    var r = CoroReglas()
    for n in ["nivel_weebo", "mostrar_gif", "hablar_con_claudio", "volver_con_alma", "mostrar_en_chat"] {
        revisa(!r.empieza("id-" + n, nombre: n, ahora: t0), n + " no cuenta (no espera respuesta o contesta al instante)")
    }
    revisa(!r.empieza("", nombre: "secretaria", ahora: t0), "sin tool_call_id no cuenta")
    r.empieza("a", nombre: "anillo_medir_ahora", ahora: t0)
    revisa(r.debeSonar(en(30)), "a los 30 s sigue sonando")
    r.vencer(en(76))
    revisa(r.cuantas == 0 && !r.debeSonar(en(76)), "si la respuesta nunca llega, a los 75 s se olvida")
    r.empieza("b", nombre: "secretaria", ahora: t0)
    r.empieza("c", nombre: "secretaria", ahora: t0)
    r.corta()
    revisa(r.cuantas == 0 && !r.debeSonar(en(5)), "interrupción o colgar: se corta todo")
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
    revisa(CoroReglas.duracion(desde: 0, hacia: CoroReglas.lineal(-10)) == 0.4, "entrar mientras Alma habla: también 0,4 s")
    revisa(CoroReglas.duracion(desde: 1, hacia: 0) == 0.5, "salir en 0,5 s")
    revisa(CoroReglas.duracion(desde: 1, hacia: CoroReglas.lineal(-10)) == 0.15, "bajar en 150 ms")
    revisa(CoroReglas.duracion(desde: CoroReglas.lineal(-10), hacia: 1) == 0.4, "volver en 400 ms")
    // simular la bajada a −10 dB con pasos de 25 ms: llega en ~150 ms
    let objetivo = CoroReglas.lineal(-10)
    let v = (1 - objetivo) / Float(CoroReglas.duracion(desde: 1, hacia: objetivo))
    var nivel: Float = 1, t = 0.0
    while nivel > objetivo { nivel = CoroReglas.paso(nivel: nivel, objetivo: objetivo, velocidad: v, dt: 0.025); t += 0.025 }
    revisa(cerca(t, 0.15, 0.026), "la bajada a −10 dB tarda ~150 ms")
    revisa(nivel == objetivo, "y se queda justo en −10 dB (no se pasa)")
    // la salida desde volumen completo tarda ~0,5 s
    let vs = Float(1) / Float(CoroReglas.duracion(desde: 1, hacia: 0))
    nivel = 1; t = 0
    while nivel > 0 { nivel = CoroReglas.paso(nivel: nivel, objetivo: 0, velocidad: vs, dt: 0.025); t += 0.025 }
    revisa(cerca(t, 0.5, 0.026), "la salida tarda ~0,5 s")
}

print(fallos == 0 ? "Todo bien" : "\(fallos) fallos")
exit(fallos == 0 ? 0 : 1)
