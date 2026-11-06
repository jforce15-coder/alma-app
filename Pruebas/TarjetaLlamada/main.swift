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
let t0 = Date(timeIntervalSince1970: 1_000_000)

// MARK: - Lo que manda el Hub

do {
    let t = tarjeta("reserva:HM4K2Q9XAB", id: "tv1")
    revisa(t.titulo == "Mariana López" && t.fechas.first?.v == "vie 6 nov" && t.semana.first?.n == 4 && t.semana.first?.hoy == true && t.conv == "HM4K2Q9XAB",
           "la tarjeta se lee del Hub (título, fechas, semana y la conversación)")
    revisa(TarjetaVoz(["clave": "x", "tipo": "lista"]) == nil && TarjetaVoz(["tipo": "reserva"]) == nil, "un tipo que no es v1, o sin clave, no es tarjeta")
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

// MARK: - Una a la vez, sin repetir

do {
    var r = ReglasTarjeta()
    revisa(r.recibir(tarjeta("reserva:A", id: "1"), pantalla: true, ahora: t0) == .mostrar && r.vista == .abierta, "la primera se muestra abierta")
    revisa(r.recibir(tarjeta("conversacion:B", id: "2"), pantalla: true, ahora: t0) == .mostrar && r.actual?.clave == "conversacion:B", "una a la vez: la nueva reemplaza a la anterior")
    revisa(r.recibir(tarjeta("reserva:A", id: "3"), pantalla: true, ahora: t0) == .repetida && r.actual?.clave == "conversacion:B", "la misma cosa no vuelve a salir en la llamada")
    r.terminar()
    revisa(r.vista == .nada && r.actual == nil && r.recibir(tarjeta("reserva:A", id: "4"), pantalla: true, ahora: t0) == .mostrar, "al colgar se olvida: en otra llamada sí sale")
}

// MARK: - Se encoge a los 20 s o al cambiar de tema

do {
    var r = ReglasTarjeta()
    _ = r.recibir(tarjeta("reserva:A", id: "1"), pantalla: true, ahora: t0)
    revisa(!r.tic(ahora: t0.addingTimeInterval(19)) && r.vista == .abierta, "a los 19 s sigue abierta")
    revisa(r.tic(ahora: t0.addingTimeInterval(20)) && r.vista == .pestana, "a los 20 s sin tocarla se encoge a la pestañita")
    r.abrir(ahora: t0.addingTimeInterval(30))
    revisa(r.vista == .abierta, "tocar la pestañita la abre otra vez")
    r.toque(ahora: t0.addingTimeInterval(45))
    revisa(!r.tic(ahora: t0.addingTimeInterval(60)) && r.vista == .abierta, "tocarla vuelve a contar los 20 s")
    revisa(r.tic(ahora: t0.addingTimeInterval(65)), "… y a los 20 s del último toque se encoge")
    r.abrir(ahora: t0.addingTimeInterval(70)); r.detalle(ahora: t0.addingTimeInterval(71))
    revisa(r.vista == .detalle, "tocar la tarjeta muestra más")
    r.detalle(ahora: t0.addingTimeInterval(72))
    revisa(r.vista == .abierta, "otro toque, menos")
    r.cambioDeTema()
    revisa(r.vista == .pestana && r.actual != nil, "al cambiar de tema se encoge (no se va)")
    r.cambioDeTema()
    revisa(r.vista == .pestana, "la pestañita no cambia con otro tema")
    r.plegar(); r.detalle(ahora: t0)
    revisa(r.vista == .pestana, "en la pestañita, «ver más» no hace nada: primero se abre")
}

// MARK: - Teléfono bloqueado: nada en la llamada, queda en el chat

do {
    revisa(!ReglasTarjeta.pantallaVisible(appActiva: false, calle: false, conferencia: false), "con el teléfono bloqueado no hay pantalla")
    revisa(!ReglasTarjeta.pantallaVisible(appActiva: true, calle: true, conferencia: false), "en el Modo calle no hay pantalla")
    revisa(!ReglasTarjeta.pantallaVisible(appActiva: true, calle: false, conferencia: true), "en el modo conferencia no hay pantalla")
    revisa(ReglasTarjeta.pantallaVisible(appActiva: true, calle: false, conferencia: false), "con la app a la vista, sí")
    var r = ReglasTarjeta()
    revisa(r.recibir(tarjeta("reserva:A", id: "1"), pantalla: false, ahora: t0) == .soloChat && r.vista == .nada && r.actual == nil, "bloqueado: no se muestra, queda para el chat")
    revisa(r.recibir(tarjeta("reserva:A", id: "2"), pantalla: true, ahora: t0) == .mostrar, "lo que no se vio bloqueado sí sale al volver a la pantalla")
}

print(fallos == 0 ? "Todo bien." : "\(fallos) fallaron.")
exit(fallos == 0 ? 0 : 1)
