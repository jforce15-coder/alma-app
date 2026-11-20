// Pruebas de la lógica pura de la Guía de camino (Alma/GuiaCaminoReglas.swift). Corren solas, sin iOS:
//   swiftc Alma/GuiaCaminoReglas.swift Pruebas/GuiaCamino/main.swift -o /tmp/guia-camino && /tmp/guia-camino
// Las corre el robot en cada PR (testflight.yml, «Probar la Guía de camino»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}

// Una calle recta hacia el norte: un paso cada ~111 m (0,001° de latitud).
let p0 = GuiaPunto(lat: 14.000, lng: -90.5), p1 = GuiaPunto(lat: 14.001, lng: -90.5), p2 = GuiaPunto(lat: 14.002, lng: -90.5)
let fin = GuiaPunto(lat: 14.003, lng: -90.5)
let pasos = [GuiaPaso(texto: "Camina al norte.", punto: p0), GuiaPaso(texto: "Sigue recto.", punto: p1), GuiaPaso(texto: "Gira a la derecha.", punto: p2)]
func en(_ lat: Double, _ lng: Double = -90.5) -> GuiaPunto { GuiaPunto(lat: lat, lng: lng) }

do {
    let d = GuiaCaminoReglas.distancia(p0, p1)
    revisa(abs(d - 111) < 2, "0,001° de latitud son unos 111 m (\(Int(d)))")
    revisa(GuiaCaminoReglas.aLaLinea(en(14.0005, -90.4995), [p0, fin]) < 60, "a unos 54 m de la línea")
    let l = GuiaCaminoReglas.decodificar("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
    revisa(l.count == 3 && abs(l[0].lat - 38.5) < 1e-6 && abs(l[0].lng + 120.2) < 1e-6 && abs(l[2].lat - 43.252) < 1e-6, "decodifica la línea de Google (ejemplo oficial)")
    revisa(GuiaCaminoReglas.textoDistancia(124) == "120 m" && GuiaCaminoReglas.textoDistancia(1430) == "1,4 km", "la distancia en la pantalla")
}

do {
    var r = GuiaCaminoReglas(pasos: pasos, fin: fin, modo: "caminando", linea: [])
    revisa(r.ubicacion(en(14.0003), precision: 5) == nil && r.siguiente == 1, "a medio camino no dice nada")
    var r2 = GuiaCaminoReglas(pasos: pasos, fin: fin, modo: "caminando", linea: [])
    revisa(r2.ubicacion(en(14.00095), precision: 5) == .decir(1, "Sigue recto."), "al llegar al punto dice ese paso, justo a tiempo")
    revisa(r2.ubicacion(en(14.00098), precision: 5) == nil, "no lo repite")
    revisa(r2.ubicacion(en(14.0021), precision: 5) == .decir(2, "Gira a la derecha."), "el siguiente en su punto")
    revisa(r2.ubicacion(en(14.00295), precision: 5) == .llegaste, "al final: llegaste")
    revisa(r2.ubicacion(en(14.003), precision: 5) == nil, "llegaste se dice una vez")
}

do {
    var r = GuiaCaminoReglas(pasos: pasos, fin: fin, modo: "caminando", linea: [])
    revisa(r.ubicacion(en(14.002), precision: 5) == .decir(2, "Gira a la derecha."), "si se saltó un punto, dice el último que alcanzó")
    revisa(r.ubicacion(en(14.001), precision: 200) == nil, "un GPS muy malo no cuenta")
}

do {
    var r = GuiaCaminoReglas(pasos: pasos, fin: fin, modo: "caminando", linea: [])
    let fuera = en(14.0005, -90.502)   // ~215 m al oeste
    revisa(r.ubicacion(fuera, precision: 5) == nil && r.ubicacion(fuera, precision: 5) == nil, "dos veces lejos: espera")
    revisa(r.ubicacion(fuera, precision: 5) == .recalcular, "la tercera: otra ruta")
    var c2 = GuiaCaminoReglas(pasos: pasos, fin: GuiaPunto(lat: 14.01, lng: -90.5), modo: "carro", linea: [])
    revisa(c2.ubicacion(en(14.0000), precision: 5) == .decir(1, "Sigue recto."), "en carro el paso sale a ~110 m (umbral 150)")
    let bus = [GuiaPaso(texto: "Toma el bus.", punto: p0), GuiaPaso(texto: "Prepárate para bajarte.", punto: GuiaPunto(lat: 14.01, lng: -90.5), antes: 350)]
    var b = GuiaCaminoReglas(pasos: bus, fin: GuiaPunto(lat: 14.011, lng: -90.5), modo: "bus", linea: [])
    revisa(b.ubicacion(en(14.0072), precision: 5) == .decir(1, "Prepárate para bajarte."), "bajarse del bus se avisa unos 300 m antes")
}

// La pantalla estilo carro (Juan, 20-nov-2026): sin «En media cuadra» (la distancia va en grande), la flecha y lo que falta.
do {
    revisa(GuiaCaminoReglas.textoPantalla("En media cuadra, en la tienda Polo, cruza a la izquierda.") == "En la tienda Polo, cruza a la izquierda.", "la pantalla quita «en media cuadra»")
    revisa(GuiaCaminoReglas.textoPantalla("En una cuadra, gira a la derecha.") == "Gira a la derecha." && GuiaCaminoReglas.textoPantalla("Sigue recto.") == "Sigue recto.", "y «en una cuadra»; lo demás igual")
    revisa(GuiaCaminoReglas.simbolo("izquierda") == "arrow.turn.up.left" && GuiaCaminoReglas.simbolo("") == "arrow.up", "la flecha de cada giro")
    let l = [p0, p1, p2, fin]
    let r = GuiaCaminoReglas.restante(en(14.0015), l)
    revisa(abs(r - 167) < 3, "faltan unos 167 m por el camino (\(Int(r)))")
    revisa(GuiaCaminoReglas.restante(en(14.003), l) < 1, "al final no falta nada")
    let gp = [GuiaPaso(texto: "Camina.", punto: p0, giro: "recto"), GuiaPaso(texto: "En media cuadra, cruza a la izquierda.", punto: p1, antes: 50, giro: "izquierda"), GuiaPaso(texto: "Cruza a la derecha.", punto: p2, giro: "derecha")]
    var g = GuiaCaminoReglas(pasos: gp, fin: fin, modo: "caminando", linea: [])
    revisa(g.proximoGiro == "izquierda" && g.luegoGiro == "derecha", "el próximo giro y el de luego")
    revisa(g.ubicacion(en(14.0006), precision: 5) == .decir(1, "En media cuadra, cruza a la izquierda."), "con anticipación del Hub: se dice a ~50 m del cruce")
    revisa(g.proximoGiro == "derecha" && g.luegoGiro == "llegar", "después: el siguiente y luego llegar")
}

print(fallos == 0 ? "Todo bien." : "\(fallos) fallo(s).")
exit(fallos == 0 ? 0 : 1)
