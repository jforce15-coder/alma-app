// Pruebas de la lógica pura de las tarjetas de clubes (Alma/TarjetasClubReglas.swift). Corren solas, sin iOS:
//   swiftc Alma/TarjetasClubReglas.swift Pruebas/TarjetasClub/main.swift -o /tmp/tarjetas-club && /tmp/tarjetas-club
// Las corre el robot en cada PR (testflight.yml, «Probar las tarjetas de clubes»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}
func franjas(_ b: [Bool]?) -> String { (b ?? []).map { $0 ? "1" : "0" }.joined() }

do {   // EAN
    revisa(ReglasTarjetas.digitoControl("400638133393") == 1, "dígito de control de un EAN-13 conocido")
    revisa(ReglasTarjetas.eanValido("4006381333931") && !ReglasTarjetas.eanValido("4006381333932"), "EAN-13 válido e inválido")
    revisa(ReglasTarjetas.eanValido("96385074"), "EAN-8 válido")
    let b = ReglasTarjetas.barrasEAN13("4006381333931")
    revisa(b?.count == 95, "un EAN-13 tiene 95 franjas")
    // 4 → paridad LGLLGG; primer dígito del lado izquierdo (0) en L = 0001101
    revisa(franjas(b).hasPrefix("101" + "0001101"), "empieza con la guarda y el 0 en L")
    revisa(franjas(b).hasSuffix("101") && franjas(b).dropFirst(45).prefix(5) == "01010", "guardas del centro y del final")
    revisa(ReglasTarjetas.barrasEAN13("4006381333932") == nil, "un EAN-13 con el control mal no se dibuja")
    revisa(ReglasTarjetas.barrasEAN8("96385074")?.count == 67, "un EAN-8 tiene 67 franjas")
}

do {   // Code 39
    revisa(ReglasTarjetas.tablaCode39.values.allSatisfy { $0.count == 9 && $0.filter { $0 == "1" }.count == 3 }, "cada carácter de Code 39 tiene 9 elementos y 3 anchos")
    let b = ReglasTarjetas.barrasCode39("A1")
    // cada carácter: 6 angostos + 3 anchos (x3) = 15 módulos; 4 caracteres (*A1*) + 3 separadores
    revisa(b?.count == 4 * 15 + 3, "Code 39 de «A1» mide lo que debe")
    revisa(b?.first == true && b?.last == true, "empieza y termina en barra")
    revisa(ReglasTarjetas.barrasCode39("a1") == b, "las minúsculas se dibujan en mayúscula")
    revisa(ReglasTarjetas.barrasCode39("Ñ") == nil && ReglasTarjetas.barrasCode39("A*B") == nil, "lo que no cabe en Code 39 no se dibuja")
}

do {   // formato sugerido y contenido
    revisa(ReglasTarjetas.formatoSugerido("4006381333931") == .ean13, "13 dígitos con control bien: EAN-13")
    revisa(ReglasTarjetas.formatoSugerido("4006 3813 3393 1") == .ean13, "con espacios, igual")
    revisa(ReglasTarjetas.formatoSugerido("036000291452") == .ean13 && ReglasTarjetas.contenido("036000291452", .ean13) == "0036000291452", "UPC-A pasa a EAN-13 con un 0")
    revisa(ReglasTarjetas.formatoSugerido("96385074") == .ean8, "8 dígitos con control bien: EAN-8")
    revisa(ReglasTarjetas.formatoSugerido("4006381333932") == .code128, "13 dígitos con control mal: Code 128")
    revisa(ReglasTarjetas.formatoSugerido("CLUB-12345") == .code128, "con letras: Code 128")
    revisa(ReglasTarjetas.sePuede("4006381333931", .ean13) && !ReglasTarjetas.sePuede("123", .ean13), "se avisa al guardar si el número no cabe en el formato")
    revisa(ReglasTarjetas.sePuede("12345", .numero) && !ReglasTarjetas.sePuede(" ", .code128), "solo el número siempre; vacío nunca")
}

let torre = TarjetaClub(id: "1", nombre: "La Torre", numero: "4006381333931", formato: .ean13)
let price = TarjetaClub(id: "2", nombre: "PriceSmart", numero: "123456", formato: .code128)
let paiz = TarjetaClub(id: "3", nombre: "Club Paiz", numero: "96385074", formato: .ean8)
let pacifiko = TarjetaClub(id: "4", nombre: "Farmacia Galeno", numero: "A1", formato: .code39)
let todas = [torre, price, paiz, pacifiko]

do {   // encontrar la que pidió
    revisa(ReglasTarjetas.buscar("la torre", en: todas) == .una(torre), "por su nombre")
    revisa(ReglasTarjetas.buscar("mi tarjeta del club de La Torre", en: todas) == .una(torre), "con palabras de relleno")
    revisa(ReglasTarjetas.buscar("Price Smart", en: todas) == .una(price), "con otro espacio")
    revisa(ReglasTarjetas.buscar("paíz", en: todas) == .una(paiz), "sin importar tildes ni «club»")
    revisa(ReglasTarjetas.buscar("galeno", en: todas) == .una(pacifiko), "por una palabra del nombre")
    revisa(ReglasTarjetas.buscar("walmart", en: todas) == .ninguna, "la que no está")
    revisa(ReglasTarjetas.buscar("tarjeta", en: [torre]) == .una(torre), "sin nombre y una sola guardada: esa")
    revisa(ReglasTarjetas.buscar("", en: [torre, price]) == .varias([torre, price]), "sin nombre y varias: pregunta")
    let otra = TarjetaClub(id: "5", nombre: "La Torre Express", numero: "1", formato: .numero)
    let plus = TarjetaClub(id: "6", nombre: "Torre Plus", numero: "2", formato: .numero)
    revisa(ReglasTarjetas.buscar("torre", en: [otra, plus]) == .varias([otra, plus]), "dos que encajan: pregunta cuál")
    revisa(ReglasTarjetas.buscar("la torre", en: [torre, otra]) == .una(torre), "el nombre igual gana")
}

do {   // lo que se le contesta a Alma
    let r = ReglasTarjetas.respuesta(pedido: "la torre", tarjetas: todas, pantalla: true)
    revisa(r.mostrar == torre && !r.pendiente && !r.error, "encontrada y con pantalla: se muestra")
    revisa(!r.texto.contains(torre.numero), "a Alma no se le da el número (no lo lee en voz alta)")
    let b = ReglasTarjetas.respuesta(pedido: "la torre", tarjetas: todas, pantalla: false)
    revisa(b.mostrar == torre && b.pendiente, "con el teléfono bloqueado: queda para cuando abra la app")
    let n = ReglasTarjetas.respuesta(pedido: "walmart", tarjetas: todas, pantalla: true)
    revisa(n.mostrar == nil && n.error && n.texto.contains("PriceSmart"), "no está: Alma dice cuáles tiene")
    let v = ReglasTarjetas.respuesta(pedido: "x", tarjetas: [], pantalla: true)
    revisa(v.mostrar == nil && v.texto.contains("Ajustes"), "sin tarjetas: le dice dónde agregarlas")
    revisa(ReglasTarjetas.lista([torre, price, paiz]) == "La Torre, PriceSmart y Club Paiz", "la lista se dice natural")
}

do {   // se guardan y vuelven igual
    let d = try! JSONEncoder().encode(todas)
    revisa((try? JSONDecoder().decode([TarjetaClub].self, from: d)) == todas, "se guardan y se leen igual")
}

do {   // boletos (ajuste del 17-nov-2026): avión, tren, concierto y evento, con fecha y detalle
    let hoy = "2026-11-17"
    var madrid = TarjetaClub(id: "b1", nombre: "Vuelo a Madrid", numero: "M1OVALLE/JUAN EABC123", formato: .pdf417)
    madrid.tipo = .avion; madrid.fecha = "2026-11-20"; madrid.detalle = "Asiento 14C"
    var regreso = TarjetaClub(id: "b2", nombre: "Regreso de Madrid", numero: "M1OVALLE/JUAN EXYZ987", formato: .aztec)
    regreso.tipo = .avion; regreso.fecha = "2026-11-28"
    var coldplay = TarjetaClub(id: "b3", nombre: "Coldplay", numero: "TK-88412", formato: .qr)
    coldplay.tipo = .concierto; coldplay.fecha = "2026-12-05"
    var tren = TarjetaClub(id: "b4", nombre: "AVE a Sevilla", numero: "7781", formato: .qr)
    tren.tipo = .tren; tren.fecha = "2026-11-16"   // ayer: todavía sirve hoy
    var partido = TarjetaClub(id: "b5", nombre: "Partido Municipal", numero: "X1", formato: .qr)
    partido.tipo = .evento; partido.fecha = "2026-10-02"   // ya pasó
    let todo = [torre, price, madrid, regreso, coldplay, tren, partido]

    revisa(ReglasTarjetas.buscar("vuelo a madrid", en: todo, hoy: hoy) == .una(madrid), "un boleto por su nombre")
    revisa(ReglasTarjetas.buscar("mi boleto de avión", en: todo, hoy: hoy) == .una(madrid), "por el tipo: el vuelo más próximo")
    revisa(ReglasTarjetas.buscar("la entrada del concierto", en: todo, hoy: hoy) == .una(coldplay), "«la entrada del concierto»")
    revisa(ReglasTarjetas.buscar("el boleto del tren", en: todo, hoy: hoy) == .una(tren), "el de ayer todavía se ofrece hoy")
    revisa(ReglasTarjetas.buscar("boleto del partido", en: todo, hoy: hoy) == .una(partido), "uno que ya pasó solo sale si lo nombra")
    revisa(ReglasTarjetas.buscar("el boleto del evento", en: todo, hoy: hoy) == .ninguna, "por el tipo no se ofrece uno que ya pasó")
    revisa(ReglasTarjetas.buscar("la torre", en: todo, hoy: hoy) == .una(torre), "las tarjetas de club siguen igual")
    revisa(ReglasTarjetas.paso(partido, hoy: hoy) && !ReglasTarjetas.paso(tren, hoy: hoy) && !ReglasTarjetas.paso(torre, hoy: hoy), "cuándo pasa un boleto")
    revisa(ReglasTarjetas.tipoPedido("mi pase de abordar") == .avion && ReglasTarjetas.tipoPedido("la de La Torre") == nil, "el tipo que pidió")
    revisa(ReglasTarjetas.fechaCorta("2026-11-20", hoy: hoy) == "20 nov" && ReglasTarjetas.fechaCorta("2027-01-03", hoy: hoy) == "3 ene 2027", "la fecha corta")
    let r = ReglasTarjetas.respuesta(pedido: "mi boleto de avión", tarjetas: todo, pantalla: true, hoy: hoy)
    revisa(r.mostrar == madrid && r.texto.contains("el boleto de Vuelo a Madrid") && !r.texto.contains(madrid.numero), "Alma dice «el boleto de…» y nunca el número")
    let n = ReglasTarjetas.respuesta(pedido: "walmart", tarjetas: todo, pantalla: true, hoy: hoy)
    revisa(!n.texto.contains("Partido Municipal"), "lo que ya pasó no se ofrece en la lista")
    // las guardadas antes de los boletos (sin tipo, fecha ni detalle) se leen igual, como tarjeta de club
    let vieja = #"[{"id":"1","nombre":"La Torre","numero":"4006381333931","formato":"ean13","titular":""}]"#
    let l = try? JSONDecoder().decode([TarjetaClub].self, from: Data(vieja.utf8))
    revisa(l?.first == torre && l?.first?.tipo == .club, "las tarjetas guardadas antes se leen igual")
    let d = try! JSONEncoder().encode(todo)
    revisa((try? JSONDecoder().decode([TarjetaClub].self, from: d)) == todo, "los boletos se guardan y se leen igual")
}

print(fallos == 0 ? "\nTodo bien." : "\n\(fallos) fallaron.")
exit(fallos == 0 ? 0 : 1)
