// Pruebas de la lógica pura de la tarjeta de la llamada (Alma/TarjetaLlamada.swift). Corren solas, sin iOS:
//   swiftc Alma/TarjetaLlamada.swift Pruebas/TarjetaLlamada/main.swift -o /tmp/tarjeta && /tmp/tarjeta
// Las corre el robot en cada PR (testflight.yml, «Probar la tarjeta de la llamada»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}

func tarjeta(_ clave: String, id: String) -> TarjetaVoz {
    TarjetaVoz(["id": id, "clave": clave, "tipo": "reserva", "titulo": "Mariana López", "etiqueta": "Reserva · HM4K2Q9XAB",
                "fechas": [["t": "Llega", "v": "vie 6 nov", "d": "15:00"]], "datos": ["Registro completo"],
                "semana": [["letra": "M", "n": 4, "e": "res", "hoy": true]], "conv": "HM4K2Q9XAB"])!
}

// MARK: - Lo que manda el Hub

do {
    let t = tarjeta("reserva:HM4K2Q9XAB", id: "tv1")
    revisa(t.titulo == "Mariana López" && t.fechas.first?.v == "vie 6 nov" && t.semana.first?.n == 4 && t.semana.first?.hoy == true && t.conv == "HM4K2Q9XAB",
           "la tarjeta se lee del Hub (título, fechas, semana y la conversación)")
    revisa(TarjetaVoz(["clave": "x", "tipo": "lista"]) == nil && TarjetaVoz(["tipo": "reserva"]) == nil, "un tipo que la app no pinta, o sin clave, no es tarjeta")
    // La consulta de Airbnb (Hub #470): se lee como una reserva, con su borrador y «Abrir conversación».
    let c = TarjetaVoz(["id": "tv9", "clave": "consulta:HAX1:b120", "tipo": "consulta", "titulo": "Alison Prueba", "sub": "Likin · 28 noches",
                        "etiqueta": "Consulta · Airbnb", "chip": "Borrador", "tono": "aviso",
                        "fechas": [["t": "Llega", "v": "lun 1 dic", "d": ""], ["t": "Sale", "v": "lun 29 dic", "d": "28 noches"]],
                        "mensajes": [["de": "huesped", "quien": "Alison", "texto": "¿Tienen tarifa por mes?", "hora": "10:12"],
                                     ["de": "equipo", "quien": "Borrador · sale con tu sí", "texto": "Hola Alison…", "hora": ""]],
                        "datos": ["Precio US$ 1450"], "conv": "HAX1"])
    revisa(c != nil && c?.tipo == "consulta" && c?.fechas.count == 2 && c?.mensajes.last?.quien.hasPrefix("Borrador") == true && c?.datos.first == "Precio US$ 1450" && c?.conv == "HAX1",
           "la consulta se lee: fechas, su mensaje, el borrador, el precio y la conversación")
    revisa(TarjetaVoz.nombre("consulta") == "Consulta" && TarjetaVoz.nombre("reserva") == "Reserva" && TarjetaVoz.nombre("apartamento") == "Apartamento", "el nombre de cada tipo")
}

// MARK: - Por estado (Hub #508, Juan 13-nov-2026): se queda, se reemplaza y se va al colgar

do {
    var r = ReglasTarjeta()
    revisa(r.recibir(tarjeta("reserva:A", id: "1"), pantalla: true) == .mostrar && r.vista == .abierta, "la primera se muestra abierta")
    revisa(r.recibir(tarjeta("reserva:A", id: "1"), pantalla: true) == .igual && r.vista == .abierta, "la misma (mismo id) no cambia nada")
    revisa(r.recibir(tarjeta("conversacion:B", id: "2"), pantalla: true) == .mostrar && r.actual?.clave == "conversacion:B" && r.vista == .abierta, "una a la vez: otra cosa la reemplaza")
    revisa(r.recibir(tarjeta("reserva:A", id: "3"), pantalla: true) == .mostrar && r.actual?.clave == "reserva:A", "volver a algo que ya se vio en la llamada lo muestra otra vez")
    r.terminar()
    revisa(r.vista == .nada && r.actual == nil, "al colgar (o al volver la conferencia a esperar) no queda nada")
    revisa(r.recibir(tarjeta("reserva:A", id: "4"), pantalla: true) == .mostrar, "en otra llamada sale de nuevo")
}

do {
    var r = ReglasTarjeta()
    _ = r.recibir(tarjeta("reserva:A", id: "1"), pantalla: true)
    revisa(r.vista == .abierta, "no hay reloj: sigue abierta mientras dure la llamada (ya no se encoge a los 20 s)")
    r.detalle()
    revisa(r.vista == .detalle, "tocar la tarjeta muestra más")
    r.detalle()
    revisa(r.vista == .abierta, "otro toque, menos")
    r.plegar()
    revisa(r.vista == .pestana && r.actual != nil, "el asa (o tocar a Alma en la esquina) la guarda en la pestañita, no se va")
    r.detalle()
    revisa(r.vista == .pestana, "en la pestañita, «ver más» no hace nada: primero se abre")
    r.abrir()
    revisa(r.vista == .abierta, "tocar la pestañita la abre otra vez")
    r.plegar()
    revisa(r.recibir(tarjeta("reserva:A", id: "1"), pantalla: true) == .mostrar && r.vista == .abierta, "en la pestañita, si Alma vuelve a hablar de lo mismo, se abre")
    r.plegar()
    revisa(r.recibir(tarjeta("apartamento:C", id: "5"), pantalla: true) == .mostrar && r.vista == .abierta && r.actual?.clave == "apartamento:C", "en la pestañita, una tarjeta nueva se abre")
}

// MARK: - Pantalla: bloqueada o Modo calle, nada; conferencia con la pantalla encendida, sí

do {
    revisa(!ReglasTarjeta.pantallaVisible(appActiva: false, calle: false), "con el teléfono bloqueado no hay pantalla")
    revisa(!ReglasTarjeta.pantallaVisible(appActiva: true, calle: true), "en el Modo calle no hay pantalla")
    revisa(ReglasTarjeta.pantallaVisible(appActiva: true, calle: false), "con la app a la vista, sí (también en el modo conferencia)")
    var r = ReglasTarjeta()
    revisa(r.recibir(tarjeta("reserva:A", id: "1"), pantalla: false) == .soloChat && r.vista == .nada && r.actual == nil, "bloqueado: no se muestra, queda para el chat")
    revisa(r.recibir(tarjeta("reserva:A", id: "2"), pantalla: true) == .mostrar, "lo que no se vio bloqueado sí sale al volver a la pantalla")
    let e = TarjetaVoz(["id": "tv7", "clave": "edificio:z10brunelo", "tipo": "edificio", "titulo": "Edificio Brunelo"])
    revisa(e != nil && TarjetaVoz.nombre("edificio") == "Edificio", "el edificio (Hub #508 T2) es tarjeta")
}

print(fallos == 0 ? "Todo bien." : "\(fallos) fallaron.")
exit(fallos == 0 ? 0 : 1)
