// Pruebas de la conversación continua (Alma/LlamadaContinua.swift; Juan, 16-nov-2026: «se corta en automático»).
//   swiftc Alma/LlamadaContinua.swift Alma/SuenoCalle.swift Pruebas/LlamadaContinua/main.swift -o /tmp/llamada-continua && /tmp/llamada-continua
// Las corre el robot en cada PR (testflight.yml, «Probar la conversación continua»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}
typealias C = LlamadaContinua

// MARK: - Lo que la ficha le dice a Alma: no se despide y NO cuelga

revisa(C.regla.hasPrefix("CONVERSACIÓN CONTINUA:"), "la ficha lo nombra como el Hub: «CONVERSACIÓN CONTINUA»")
revisa(C.regla.contains("NUNCA uses end_call"), "Alma nunca cuelga en el Modo calle ni en conferencia")
revisa(!C.regla.contains("cuelga con end_call") && !C.regla.lowercased().contains("y cuelga"), "nada le pide colgar (así se cortaba: «cuelga con end_call en ese mismo turno»)")
revisa(C.regla.contains("sin volver a decir «Alma»"), "Juan sigue sin volver a decir «Alma»")
revisa(C.regla.contains("skip_turn"), "lo que no es para ella (o el silencio): skip_turn, sin contestar")
revisa(C.regla.contains("«Entendido, lo hago y te aviso cuando esté listo» y sigue escuchando"), "segundo plano: la frase corta y sigue en la llamada")
revisa(!C.regla.contains("te despid") || C.regla.contains("no te despidas"), "sin despedidas")

// MARK: - Cuándo cierra sola la app

let calle = C.Tiempos(silencio: 6, tope: 45), conf = C.Tiempos(silencio: C.silencioConferencia, tope: C.topeConferencia, ruido: C.ruidoConferencia, pausa: C.pausaConferencia)
revisa(C.tiempos(calle: false, conferencia: false, porAviso: false, juanHablo: false, deCalle: calle, deConferencia: conf) == nil, "una llamada normal (la roca, el anillo) no la cierra el silencio")
revisa(C.tiempos(calle: false, conferencia: true, porAviso: false, juanHablo: false, deCalle: calle, deConferencia: conf) == conf, "conferencia: 45 s de silencio de verdad o 60 s sin que Alma hable (en una pausa de 8 s)")
revisa(conf.silencio == 45 && conf.tope == 60 && conf.ruido == 180 && conf.pausa == 8, "de fábrica en conferencia: 45 s, 60 s, ruido a los 3 min, pausa de 8 s")
revisa(C.tiempos(calle: false, conferencia: true, porAviso: false, juanHablo: true, claudio: true, deCalle: calle, deConferencia: conf) == nil, "con Claudio nunca se cierra por silencio (23:43: lo cortaba explicándole un pedido)")
revisa(C.tiempos(calle: true, conferencia: false, porAviso: false, juanHablo: true, claudio: true, deCalle: calle, deConferencia: conf) == nil, "con Claudio desde el Modo calle tampoco")
revisa(C.tiempos(calle: true, conferencia: false, porAviso: false, juanHablo: true, deCalle: calle, deConferencia: conf) == calle, "Modo calle: los segundos del sueño de siempre")
revisa(C.tiempos(calle: false, conferencia: true, porAviso: true, juanHablo: false, deCalle: calle, deConferencia: conf) == calle, "Alma abre en conferencia y nadie contesta: cierra rápido")
revisa(C.tiempos(calle: false, conferencia: true, porAviso: true, juanHablo: true, deCalle: calle, deConferencia: conf) == conf, "Alma abre en conferencia y Juan contesta: ya es una conversación continua")
revisa(C.segundos(nil, fabrica: 30, desde: 10, hasta: 120) == 30, "un Hub de antes (sin el dato): el de fábrica")
revisa(C.segundos(40, fabrica: 30, desde: 10, hasta: 120) == 40, "el Hub lo ajusta sin otra versión de la app")
revisa(C.segundos(2, fabrica: 30, desde: 10, hasta: 120) == 10 && C.segundos(9999, fabrica: 30, desde: 10, hasta: 120) == 120, "siempre entre sus límites")
revisa(C.segundos(30, fabrica: C.silencioConferencia, desde: C.silencioConferenciaMinimo, hasta: 120) == 45, "el Hub manda 30 en conferencia: la app usa 45 como mínimo")
revisa(C.segundos(0, fabrica: 45, desde: 20, hasta: 300) == 45, "un cero no apaga el cierre: cada minuto abierto gasta créditos")

// Con las reglas del sueño (SuenoCalle.decidir) y los segundos de conferencia.
let t0 = Date(timeIntervalSince1970: 1_000_000)
func momentos(alma: TimeInterval, juan: TimeInterval? = nil, sonido: TimeInterval? = nil, herramienta: TimeInterval? = nil) -> SuenoCalle.Momentos {
    SuenoCalle.Momentos(conectada: t0, finVozAlma: t0.addingTimeInterval(alma), vozJuan: juan.map { t0.addingTimeInterval($0) } ?? .distantPast,
                        sonido: sonido.map { t0.addingTimeInterval($0) } ?? .distantPast, herramientaDesde: herramienta.map { t0.addingTimeInterval($0) }, finHerramienta: .distantPast)
}
func decide(_ m: SuenoCalle.Momentos, a s: TimeInterval) -> SuenoCalle.Motivo? {
    SuenoCalle.decidir(m, ahora: t0.addingTimeInterval(s), silencio: conf.silencio, tope: conf.tope, ruido: conf.ruido, pausa: conf.pausa)
}
revisa(decide(momentos(alma: 5), a: 6) == nil, "Alma acaba de responder: la llamada sigue (antes colgaba en ese mismo turno)")
revisa(decide(momentos(alma: 5), a: 40) == nil, "35 s pensando: sigue ahí")
revisa(decide(momentos(alma: 5, juan: 20), a: 40) == nil, "Juan siguió hablando sin decir «Alma»: sigue")
revisa(decide(momentos(alma: 5), a: 51) == .silencio, "46 s sin que nadie suene: cierra sola")
// Lo que vivió Juan (16-nov-2026, 23:43): 50 s explicando un pedido, sin que llegara su texto, y la app cerró «por silencio».
var juanHablando: [SuenoCalle.Motivo?] = []
for s in stride(from: 6.0, through: 56.0, by: 0.5) { juanHablando.append(decide(momentos(alma: 5, sonido: s - 0.3), a: s)) }
revisa(juanHablando.allSatisfy { $0 == nil }, "50 s de Juan hablando sin que llegue nada escrito: no se cierra")
revisa(decide(momentos(alma: 5, sonido: 70), a: 75) == nil, "una pausa de 5 s pensando a media idea (a los 70 s): no se cierra, ni por el tope")
revisa(decide(momentos(alma: 5, juan: 50, sonido: 65), a: 66) == nil, "60 s sin que Alma hable pero alguien habla ahora: no se corta a media frase")
revisa(decide(momentos(alma: 5, juan: 64, sonido: 65), a: 74) == .tope, "60 s sin que Alma hable: cierra en una pausa de verdad (8 s)")
revisa(decide(momentos(alma: 5, juan: 40, sonido: 59), a: 59.5) == nil, "Juan habla una frase larga (lo escrito aún no llega): sigue abierta")
revisa(decide(momentos(alma: 5, juan: 20, sonido: 60), a: 61) == nil, "41 s de voz sin nada escrito: todavía es alguien hablando (antes cerraba)")
revisa(decide(momentos(alma: 5, sonido: 199.5), a: 200) == .tope, "3 min de sonido sin una palabra escrita: es ruido de fondo, cierra")
revisa(decide(momentos(alma: 5, juan: 45, sonido: 69.5), a: 70) == nil, "Juan sigue hablando pasado el tope: no se corta")
revisa(decide(momentos(alma: 20, juan: 25), a: 71) == .silencio, "Juan dejó de hablar hace 46 s: cierra")
let callePrueba = { (m: SuenoCalle.Momentos, s: TimeInterval) in SuenoCalle.decidir(m, ahora: t0.addingTimeInterval(s), silencio: calle.silencio, tope: calle.tope, ruido: calle.ruido, pausa: calle.pausa) }
revisa(callePrueba(momentos(alma: 5, sonido: 23.5), 24) == nil, "Modo calle: Juan empezó una frase larga tras el silencio: no se corta (antes, a los 8 s de gracia)")
revisa(callePrueba(momentos(alma: 5), 12) == .silencio, "Modo calle: 6 s callado: cuelga como siempre")
revisa(callePrueba(momentos(alma: 5, sonido: 10), 17) == .silencio, "Modo calle: habló un momento y calló 7 s: cuelga")
revisa(callePrueba(momentos(alma: 5, juan: 49, sonido: 50), 51) == nil && callePrueba(momentos(alma: 5, juan: 49, sonido: 50), 52) == .tope, "Modo calle: el tope de 45 s espera a que Juan termine")
revisa(decide(momentos(alma: 5, juan: 50, sonido: 55), a: 56) == nil, "a los 50 s todavía no")
revisa(decide(momentos(alma: 5, herramienta: 10), a: 80) == nil, "mientras Alma trabaja (la secretaria tarda) no se cierra")

revisa(C.pasoCierre("silencio", calle: false, conferencia: true).contains("Conferencia") && C.pasoCierre("silencio", calle: false, conferencia: true).contains("(silencio)"), "el paso dice el modo y el porqué")
revisa(C.pasoCierre("tope", calle: true, conferencia: false).hasPrefix("Modo calle: cuelga (tope)"), "en el Modo calle, el paso de siempre")
revisa(!C.pasoCierre("silencio", calle: false, conferencia: true).lowercased().contains("error"), "cerrar por silencio no es un error")

// MARK: - Al nombrarla otra vez, sabe de qué iban

let ctx = C.contexto(["[10:01] Hay que revisar la factura"], charla: ["Juan: Alma, ¿cuánto debe Flor?", "Alma: Debe 300 quetzales."])
revisa(ctx.count == 3 && ctx[1] == "[con Alma] Juan: Alma, ¿cuánto debe Flor?" && ctx[2] == "[con Alma] Alma: Debe 300 quetzales.", "lo que se habló con Alma queda en lo último que se dijo")
revisa(C.contexto(ctx, charla: ["Alma: Debe 300 quetzales."]).count == 3, "sin repetir lo que ya estaba")
revisa(C.contexto((1...10).map { "l\($0)" }, charla: ["Juan: hola"]).count == 8, "solo lo último (8 líneas)")

// MARK: - Si la conexión se cae

revisa(C.trasCorte(claudio: false, calle: false, conferencia: false, conectada: 40, reabiertas: 0, sinCreditos: false) == .reabrir, "llamada normal que se cae: se vuelve a abrir sola")
revisa(C.trasCorte(claudio: false, calle: false, conferencia: false, conectada: 40, reabiertas: 2, sinCreditos: false) == .fallar, "dos veces como mucho; después se dice por qué")
revisa(C.trasCorte(claudio: false, calle: false, conferencia: false, conectada: 1, reabiertas: 0, sinCreditos: false) == .fallar, "si se cae al segundo de conectar, algo la rechaza: no se entra en un bucle")
revisa(C.trasCorte(claudio: false, calle: false, conferencia: false, conectada: nil, reabiertas: 0, sinCreditos: false) == .fallar, "Alma nunca contestó: se dice por qué")
revisa(C.trasCorte(claudio: false, calle: false, conferencia: false, conectada: 40, reabiertas: 0, sinCreditos: true) == .fallar, "sin créditos de voz: se dice claro, no se reintenta")
revisa(C.trasCorte(claudio: true, calle: false, conferencia: false, conectada: nil, reabiertas: 0, sinCreditos: false) == .volverConAlma, "Claudio no conectó: vuelve Alma (la llamada no se cuelga)")
revisa(C.trasCorte(claudio: true, calle: false, conferencia: false, conectada: 20, reabiertas: 0, sinCreditos: false) == .volverConAlma, "se cayó hablando con Claudio: vuelve Alma")
revisa(C.trasCorte(claudio: true, calle: true, conferencia: false, conectada: nil, reabiertas: 0, sinCreditos: false) == .volverConAlma, "también si a Claudio lo abrió el Modo calle")
revisa(C.trasCorte(claudio: true, calle: false, conferencia: false, conectada: nil, reabiertas: 2, sinCreditos: false) == .fallar, "sin dar vueltas entre Claudio y Alma")
revisa(C.trasCorte(claudio: false, calle: true, conferencia: false, conectada: 12, reabiertas: 0, sinCreditos: false) == .colgar, "Modo calle: se cierra sin error y vuelve a esperar «Alma»")
revisa(C.trasCorte(claudio: false, calle: false, conferencia: true, conectada: 12, reabiertas: 0, sinCreditos: false) == .colgar, "conferencia: se cierra sin error y vuelve a escuchar «Alma»")
revisa(C.trasCorte(claudio: false, calle: false, conferencia: true, conectada: nil, reabiertas: 0, sinCreditos: false) == .fallar, "conferencia y Alma nunca contestó: se dice por qué")

revisa(C.cierreAlEmpezar(claudio: true, conectada: 3, juanHablo: false), "Claudio «colgó» a los 3 s sin que Juan dijera nada: algo lo cerró al empezar; vuelve Alma")
revisa(!C.cierreAlEmpezar(claudio: true, conectada: 3, juanHablo: true) && !C.cierreAlEmpezar(claudio: true, conectada: 40, juanHablo: false), "si Juan ya le habló o llevaban rato, Claudio colgó de verdad")
revisa(!C.cierreAlEmpezar(claudio: false, conectada: 3, juanHablo: false), "con Alma no aplica: ella sí puede colgar pronto")
revisa(!C.cerroPorDuracion(conectada: 300) && C.cerroPorDuracion(conectada: 899), "un cierre a los 15 min no es que Alma colgó: es el tope de ElevenLabs")

revisa(C.vencio(intentoDelReloj: 3, intentoActual: 3, conectando: true), "12 s sin contestar en este intento: no contestó")
revisa(!C.vencio(intentoDelReloj: 2, intentoActual: 3, conectando: true), "el reloj de un intento anterior no corta la conexión de ahora")
revisa(!C.vencio(intentoDelReloj: 3, intentoActual: 3, conectando: false), "ya conectó: nada")

revisa(C.fraseSinClaudio(conectado: false).contains("No pude pasarte con Claudio") && C.fraseSinClaudio(conectado: true).contains("Se cortó"), "Alma lo dice en una frase")
let f = C.ficha("FICHA", frase: C.fraseTrasCorte, charla: ["Juan: mándale el código a Flor", "Alma: ¿El del D7?"], porClaudio: false)
revisa(f.hasPrefix("FICHA\n\nSE CORTÓ LA CONEXIÓN") && f.contains("No saludes") && f.hasSuffix("Alma: ¿El del D7?"), "la conversación reabierta lleva lo último que se dijo y no saluda otra vez")
revisa(C.ficha("FICHA", frase: C.fraseSinClaudio(conectado: false), charla: [], porClaudio: true).contains("NO SE PUDO SEGUIR CON CLAUDIO") , "si fue por Claudio, lo sabe")
revisa(!C.ficha("FICHA", frase: "x", charla: [], porClaudio: false).contains("LO ÚLTIMO QUE SE DIJO"), "sin nada dicho, no inventa contexto")

// MARK: - El saludo se oye entero

let s0 = Date(timeIntervalSince1970: 2_000_000)
revisa(C.protegeSaludo(primero: "Hola, cuéntame.") && !C.protegeSaludo(primero: "  "), "se protege el saludo; si Juan ya hablaba (primer mensaje vacío), no")
revisa(C.saludoSigue(desde: s0, ahora: s0.addingTimeInterval(1), sono: false, finVoz: .distantPast), "antes de que llegue la voz: protegido (lo del micrófono no la corta)")
revisa(C.saludoSigue(desde: s0, ahora: s0.addingTimeInterval(2), sono: true, finVoz: s0.addingTimeInterval(3)), "mientras suena el saludo: protegido")
revisa(!C.saludoSigue(desde: s0, ahora: s0.addingTimeInterval(3.5), sono: true, finVoz: s0.addingTimeInterval(3)), "terminó de sonar: Juan ya puede hablar")
revisa(!C.saludoSigue(desde: s0, ahora: s0.addingTimeInterval(8), sono: false, finVoz: .distantPast), "si la voz nunca llega, a los 8 s se suelta")

// MARK: - La voz de Alma se oye (16-nov-2026: «todo el audio previo estaba en mute»)

revisa(C.volumenVoz == 1, "la voz de Alma suena entera: el micrófono en pausa y el modo chat ya no la bajan a 0")
revisa(C.aParlante(salida: "Receiver"), "si la voz sale por el auricular de oreja, se pasa al parlante")
revisa(!C.aParlante(salida: "Speaker") && !C.aParlante(salida: "BluetoothA2DPOutput") && !C.aParlante(salida: "BluetoothHFP") && !C.aParlante(salida: "Headphones") && !C.aParlante(salida: "CarAudio"), "parlante, audífonos, Bluetooth y el carro no se tocan")
revisa(C.volumenBajo(0) && C.volumenBajo(0.05) && !C.volumenBajo(0.1) && !C.volumenBajo(0.6), "volumen del teléfono casi en cero: se avisa")

// MARK: - El registro de pasos

var lista: [String] = []
for i in 0..<70 { lista = C.guardar(lista, "10:00:\(i) paso \(i)") }
revisa(lista.count == C.pasosGuardados && lista.last == "10:00:69 paso 69" && lista.first == "10:00:10 paso 10", "se guardan los últimos 60 pasos, también los de la llamada anterior")

if fallos > 0 { print("\(fallos) fallaron"); exit(1) }
print("Todo bien")
