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

// MARK: - Panel de Claudio (Hub #550): la lista de trabajos o el del que se habla, por estado como el tablero

do {
    let a = TarjetaVoz(["id": "cpA", "clave": "claudio:lista", "tipo": "claudio", "vista": "lista", "titulo": "Trabajando en 3", "etiqueta": "Claudio · Desarrollo",
                        "datos": ["Botón de facturas · Revisiones", "Reporte de limpieza · Te pregunta algo"],
                        "trabajos": [["id": "mp:mpB", "nombre": "Reporte de limpieza", "etapa": "pregunta", "pasos": ["hecho", "espera", "pendiente", "pendiente"]]]])
    revisa(a != nil && a?.tipo == "claudio" && a?.datos.count == 2 && (a?.crudo["vista"] as? String) == "lista", "el Panel de Claudio se lee (y lo demás va tal cual a la página)")
    revisa(TarjetaVoz.nombre("claudio") == "Claudio", "su nombre en la pestañita: Claudio")
    let b = TarjetaVoz(["id": "cpB", "clave": "claudio:trabajo:mp:mpA", "tipo": "claudio", "vista": "trabajo", "titulo": "Botón de facturas"])!
    var r = ReglasTarjeta()
    revisa(r.recibir(a!, pantalla: true) == .mostrar && r.vista == .abierta, "A al entrar con Claudio")
    revisa(r.recibir(a!, pantalla: true) == .igual, "el mismo panel no cambia nada")
    revisa(r.recibir(b, pantalla: true) == .mostrar && r.actual?.clave == "claudio:trabajo:mp:mpA", "B (el trabajo del que se habla) reemplaza a A")
    revisa(r.recibir(a!, pantalla: false) == .soloChat && r.actual?.id == "cpB", "con el teléfono bloqueado no cambia lo que se ve")
    r.terminar()
    revisa(r.actual == nil && r.vista == .nada, "al volver con Alma o al colgar se quita")
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

// MARK: - Socio (Hub #508 Fase 2): su tablero mientras se habla de él

do {
    let s = TarjetaVoz(["id": "tvS", "clave": "socio:1x2y3z", "tipo": "socio", "titulo": "Carlos Prueba", "sub": "Edificio Prueba 633 · Torre Demo 301",
                        "etiqueta": "Socio", "chip": "Socio", "tono": "info", "iniciales": "CP", "datos": ["Ocupación octubre: 75.8%", "2 pedidos abiertos"],
                        "detalle": ["Retomar: La boda de su hija (dom 8 nov)"], "conv": "", "tel": "", "wa": "",
                        "cuadros": [["id": "foto", "tipo": "foto", "tam": "m", "prioridad": 1, "iniciales": "CP", "esfera": "proposito"]]])
    revisa(s != nil && s?.tipo == "socio" && s?.datos.count == 2 && s?.tel == "" && s?.wa == "" && (s?.crudo["cuadros"] as? [Any])?.count == 1,
           "el tablero del socio es tarjeta (sin teléfono ni WhatsApp) y sus cuadros van tal cual a la página")
    revisa(TarjetaVoz.nombre("socio") == "Socio" && TarjetaVoz.tipos.contains("socio"), "su nombre en la pestañita: Socio, y va en los tipos que la app avisa al Hub")
    var r = ReglasTarjeta()
    revisa(r.recibir(s!, pantalla: true) == .mostrar && r.actual?.clave == "socio:1x2y3z", "el socio se muestra y reemplaza a lo que había, como el tablero")
}

// MARK: - Tablero de datos (Hub #607): números, barras y línea de tiempo

do {
    let d = TarjetaVoz(["id": "tvD", "clave": "datos:ruta:abc", "tipo": "datos", "titulo": "Rutas · Hoy", "etiqueta": "Ruta del día", "datos": ["5 trabajos · 3 personas"],
                        "detalle": ["8:30 · Limpieza · Brunelo 1203"], "cuadros": [["id": "n", "tipo": "numero", "tam": "s", "k": "Trabajos", "v": "5"]]])
    revisa(d != nil && d?.tipo == "datos" && d?.datos.count == 1 && (d?.crudo["cuadros"] as? [Any])?.count == 1, "el tablero de datos es tarjeta y sus cuadros van tal cual a la página")
    revisa(TarjetaVoz.nombre("datos") == "Datos" && TarjetaVoz.tipos.contains("datos"), "su nombre: Datos, y va en los tipos que la app avisa al Hub")
}

// MARK: - Snapshot estilo Jarvis (Hub, snapshot.js; Juan 16-nov-2026): recepción, proyecto y lo importante arriba

do {
    let j: [String: Any] = ["id": "tvJ", "clave": "reserva:HMPRUEBA01", "tipo": "reserva", "titulo": "Lucía Prado",
        "destacado": ["texto": "Le encantó el apartamento, pero el agua caliente sigue fallando.", "tono": "aviso"],
        "cuadros": [["id": "foto", "tipo": "foto"],
                    ["id": "experiencia", "tipo": "termometro", "k": "Experiencia", "nivel": 55, "v": "Hay que cuidarla", "tono": "aviso", "riesgo": "Medio", "porque": "La falla sigue abierta."],
                    ["id": "animo", "tipo": "animo", "molesta": ["La ducha sin agua caliente", ""], "feliz": ["La vista", "La bienvenida", "El café", "Otra más"]],
                    ["id": "foco", "tipo": "foco", "problema": "La ducha sigue sin agua caliente."]]]
    let t = TarjetaVoz(j)!
    revisa(t.snapshot.destacado.hasPrefix("Le encantó") && t.snapshot.destacadoTono == "aviso", "el destacado del snapshot se lee")
    revisa(t.snapshot.experiencia == "Hay que cuidarla" && t.snapshot.nivel == 55 && t.snapshot.riesgo == "Medio" && t.snapshot.porque == "La falla sigue abierta.", "la experiencia, su nivel, el riesgo de mala reseña y su porqué")
    revisa(t.snapshot.molesta == ["La ducha sin agua caliente"] && t.snapshot.feliz.count == 3 && t.snapshot.problema.hasPrefix("La ducha"), "lo que le molesta y lo que lo tiene feliz (máximo 3, sin vacíos) y el problema")
    revisa(!t.snapshot.vacio && TarjetaVoz(["clave": "x", "tipo": "reserva"])!.snapshot.vacio, "sin snapshot (Hub de antes) no se pinta nada nuevo")
    let n = TarjetaVoz(["clave": "x", "tipo": "reserva", "cuadros": [["tipo": "termometro", "v": "Mala", "nivel": 400]]])!
    revisa(n.snapshot.nivel == 100, "un nivel fuera de rango se queda entre 0 y 100")
    let r = TarjetaVoz(["id": "tvR", "clave": "recepcion:brunelo", "tipo": "recepcion", "titulo": "Recepción Brunelo"])
    let p = TarjetaVoz(["id": "tvP", "clave": "proyecto:p42", "tipo": "proyecto", "titulo": "Torre Prueba 804"])
    revisa(r != nil && p != nil && TarjetaVoz.nombre("recepcion") == "Recepción" && TarjetaVoz.nombre("proyecto") == "Proyecto", "recepción y proyecto son tarjetas, con su nombre")
    revisa(TarjetaVoz.tipos.contains("recepcion") && TarjetaVoz.tipos.contains("proyecto"), "y van en los tipos que la app avisa al Hub")
}

print(fallos == 0 ? "Todo bien." : "\(fallos) fallaron.")
exit(fallos == 0 ? 0 : 1)
