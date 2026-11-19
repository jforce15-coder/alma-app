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
    for n in ["enviar_confirmado", "claudio_pedido", "poner_voz", "nivel_weebo", "mostrar_gif", "mostrar_en_chat", "pasar_a_maricarmen", ""] {
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

// Rampas suaves (Juan, 19-nov-2026: «fade in y fade out, ease in y ease out, que no entre ni se corte de golpe»):
// entrar 1,2 · salir 1,2 · cortar 0,35 · bajar 250 ms · subir 600 ms, todas con curva coseno
do {
    revisa(CoroReglas.duracion(desde: 0, hacia: 1) == 1.2, "entrar en 1,2 s")
    revisa(CoroReglas.duracion(desde: 1, hacia: 0) == 1.2, "salir en 1,2 s")
    revisa(CoroReglas.corte == 0.35, "interrupción o colgar: sale en 0,35 s, no en seco")
    revisa(CoroReglas.duracion(desde: 1, hacia: CoroReglas.lineal(-10)) == 0.25, "bajar en 250 ms")
    revisa(CoroReglas.duracion(desde: CoroReglas.lineal(-10), hacia: 1) == 0.6, "volver en 600 ms")
    revisa(CoroReglas.curva(0) == 0 && cerca(CoroReglas.curva(1), 1) && cerca(CoroReglas.curva(0.5), 0.5), "la curva va de 0 a 1 y pasa por la mitad")
    revisa(CoroReglas.curva(-1) == 0 && cerca(CoroReglas.curva(2), 1), "fuera de la rampa se queda en los bordes")
    // ease-in y ease-out: el primer y el último 10 % cambian mucho menos que el 10 % del medio (lineal sería igual)
    let inicio = CoroReglas.curva(0.1) - CoroReglas.curva(0), medio = CoroReglas.curva(0.55) - CoroReglas.curva(0.45), fin = CoroReglas.curva(1) - CoroReglas.curva(0.9)
    revisa(inicio < medio / 5 && fin < medio / 5, "arranca y termina despacio (sin escalón al entrar ni al cortarse)")
    // Paso a paso, como el reloj de 25 ms: nunca sube de golpe y llega justo
    var nivel: Float = 0, mayor: Float = 0, t = 0.0
    while t < CoroReglas.entrada + 0.05 {
        t += 0.025
        let n = CoroReglas.nivel(desde: 0, hacia: 1, duracion: CoroReglas.entrada, transcurrido: t)
        mayor = max(mayor, n - nivel); nivel = n
    }
    revisa(nivel == 1, "la entrada llega al volumen completo")
    revisa(mayor < 0.04, "en la entrada ningún paso de 25 ms sube más de 4 %")
    let primero = CoroReglas.nivel(desde: 0, hacia: 1, duracion: CoroReglas.entrada, transcurrido: 0.025)
    revisa(primero < 0.002, "el primer paso casi no se oye (fade in, no golpe)")
    let ultimo = CoroReglas.nivel(desde: 1, hacia: 0, duracion: CoroReglas.salida, transcurrido: CoroReglas.salida - 0.025)
    revisa(ultimo < 0.002, "el último paso antes de callar casi no se oye (fade out, no corte)")
    revisa(CoroReglas.nivel(desde: 1, hacia: 0, duracion: CoroReglas.corte, transcurrido: CoroReglas.corte) == 0, "el corte termina en silencio")
    revisa(CoroReglas.nivel(desde: 0.4, hacia: 1, duracion: 0, transcurrido: 0) == 1, "sin duración va directo")
}

print(fallos == 0 ? "Todo bien" : "\(fallos) fallos")
exit(fallos == 0 ? 0 : 1)
