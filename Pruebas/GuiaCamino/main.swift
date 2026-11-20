// Pruebas de la lógica pura de la Guía de camino (Alma/GuiaCaminoReglas.swift). Corren solas, sin iOS:
//   swiftc Alma/GuiaCaminoReglas.swift Alma/GuiaPantallaReglas.swift Pruebas/GuiaCamino/main.swift -o /tmp/guia-camino && /tmp/guia-camino
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

// La pantalla de dos paneles (Juan, 20-nov-2026: «A teléfono, A iPad y B teléfono girado»; luz de rumbo más ancha).
do {
    typealias P = GuiaPantalla
    revisa(P.distribucion(ancho: 390, alto: 844) == .dividido, "teléfono en vertical: A (dividido)")
    revisa(P.distribucion(ancho: 820, alto: 1180) == .dividido, "iPad en vertical: A")
    revisa(P.distribucion(ancho: 844, alto: 390) == .ladoALado, "teléfono girado: B (lado a lado)")
    revisa(P.distribucion(ancho: 1180, alto: 820) == .ladoALado, "iPad acostado: B")
    revisa(P.distribucion(ancho: 500, alto: 320) == .dividido, "una ventana angosta acostada se queda en A")

    revisa(P.apertura >= 80, "la luz de rumbo abre \(Int(P.apertura))° (Juan la pidió más ancha; ≥ 80°)")
    revisa(P.rumbo(verdadero: 12, magnetico: 15) == 12, "usa el rumbo verdadero si lo hay")
    revisa(P.rumbo(verdadero: -1, magnetico: 15) == 15 && P.rumbo(verdadero: -1, magnetico: -1) == nil, "si no, el magnético; sin ninguno, nada")
    revisa(P.diferencia(de: 359, a: 1) == 2 && P.diferencia(de: 1, a: 359) == -2, "de 359° a 1° son 2° (el camino corto)")
    let s = P.suavizar(359, hacia: 1, k: 0.5)
    revisa(abs(s - 360) < 1e-9, "suavizado de 359° hacia 1°: pasa por 360°, no da la vuelta (\(s))")
    var a = 350.0
    for _ in 0..<60 { a = P.suavizar(a, hacia: 10, k: 0.2) }
    revisa(abs(P.normal(a) - 10) < 0.01 && a > 359, "llega a 10° avanzando por el norte (\(a))")
    revisa(P.suavizar(.nan, hacia: 370, k: 0.2) == 10, "sin rumbo anterior, toma el nuevo")
    revisa(P.luzEnPantalla(rumbo: 10, mapa: 350) == 20, "con el mapa girado, la luz se corrige")

    let t = P.tarjeta(faltan: "80 m", proximo: "En la farmacia, gira a la derecha.", luego: "En la iglesia, cruza a la izquierda.", llego: false)
    revisa(t == P.Tarjeta(titulo: "En 80 m", frase: "gira a la derecha en la farmacia", luego: "Luego, a la izquierda en la iglesia"), "la tarjeta del giro con su punto de referencia: \(t)")
    revisa(P.frase("En media cuadra, en la tienda Polo, cruza a la izquierda hacia 6a Calle.") == "cruza a la izquierda en la tienda Polo hacia 6a Calle", "la referencia va pegada al giro, la calle al final")
    revisa(P.frase("Sigue recto hasta la farmacia; ahí cruzas a la izquierda. Yo te aviso.") == "sigue recto hasta la farmacia; ahí cruzas a la izquierda", "el aviso sin «Yo te aviso»")
    revisa(P.frase("Gira a la derecha en 5a Av.") == "gira a la derecha en 5a Av", "sin referencia, como viene")
    revisa(P.tarjeta(faltan: "", proximo: "Toma el bus 101 hacia Centro.", luego: "", llego: false) == P.Tarjeta(titulo: "Ahora", frase: "toma el bus 101 hacia Centro", luego: ""), "sin distancia: «Ahora»; sin luego, nada")
    revisa(P.tarjeta(faltan: "", proximo: "Llegaste a Plaza Berlín", luego: "x", llego: true).titulo == "Llegaste", "al llegar: «Llegaste»")

    revisa(P.velocidad(4.8 / 3.6) == "4,8" && P.velocidad(38 / 3.6) == "38" && P.velocidad(-1) == "0", "la velocidad en km/h")
    revisa(P.ritmo(1000.0 / 750) == "12:30" && P.ritmo(0.1) == nil, "a pie, el ritmo por km")
    revisa(P.medioVisto(hub: "bus", elegido: "metro") == "metro" && P.medioVisto(hub: "bus", elegido: "") == "bus" && P.medioVisto(hub: "x", elegido: "") == "caminando", "el medio del selector (metro va como transporte público)")
}

print(fallos == 0 ? "Todo bien." : "\(fallos) fallo(s).")
exit(fallos == 0 ? 0 : 1)
