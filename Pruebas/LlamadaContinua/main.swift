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
revisa(C.regla.contains("una frase corta y nueva cada vez") && C.regla.contains("nunca la misma seguida) y sigue escuchando"), "segundo plano: una frase corta que no se repite y sigue en la llamada")
revisa(!C.regla.contains("«Entendido, lo hago y te aviso cuando esté listo»"), "sin una frase fija que suene igual en cada pedido (Juan, 16-nov-2026: «vale, lo hago»)")
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
// Lo que vivió Juan (17-nov-2026): en una reunión siguen hablando entre ellos y la llamada con Alma no se cerraba nunca.
let duro = C.topeConferencia + C.margenDuro
func decideDuro(_ m: SuenoCalle.Momentos, a s: TimeInterval) -> SuenoCalle.Motivo? {
    SuenoCalle.decidir(m, ahora: t0.addingTimeInterval(s), silencio: conf.silencio, tope: conf.tope, ruido: conf.ruido, pausa: conf.pausa, duro: duro)
}
revisa(duro == 90, "tope duro de fábrica en conferencia: 90 s sin que Alma hable")
var reunion: [SuenoCalle.Motivo?] = [], antes: [SuenoCalle.Motivo?] = []   // hablan sin parar, con pausas de 4 s cada 6 s (nunca 8 s), y sus palabras siguen llegando
for s in stride(from: 6.0, through: 300.0, by: 0.5) {
    let resto = s.truncatingRemainder(dividingBy: 6)
    let ultimoSonido = resto < 4 ? s - resto : s - 0.3
    reunion.append(decideDuro(momentos(alma: 5, juan: s - 1, sonido: ultimoSonido), a: s))
    antes.append(decide(momentos(alma: 5, juan: s - 1, sonido: ultimoSonido), a: s))
}
revisa(antes.allSatisfy { $0 == nil }, "antes: la reunión sigue y la llamada no se cerraba nunca")
revisa(reunion.contains(SuenoCalle.Motivo.tope), "ahora: con la reunión hablando, la llamada se cierra sola")
let cuando = 6.0 + Double(reunion.firstIndex(of: SuenoCalle.Motivo.tope) ?? 0) * 0.5
revisa(cuando >= 95 && cuando <= 110, "se cierra al pasar el tope duro (90 s tras la última palabra de Alma), en una pausa corta")
revisa(decideDuro(momentos(alma: 5, juan: 99, sonido: 99.5), a: 100) == nil, "pasado el tope duro, nunca a media frase (se espera una pausa de 3 s)")
revisa(decideDuro(momentos(alma: 5, juan: 99, sonido: 99), a: 102.5) == .tope, "pasado el tope duro, en una pausa de 3 s: cierra")
revisa(decideDuro(momentos(alma: 80, juan: 99, sonido: 99), a: 102.5) == nil, "Alma habló hace poco: el tope duro no corre")
revisa(decideDuro(momentos(alma: 5, sonido: 70), a: 75) == nil, "la pausa de 5 s pensando (a los 70 s) sigue sin cerrarla")
revisa(decideDuro(momentos(alma: 5, herramienta: 10), a: 95) == nil, "mientras Alma trabaja, el tope duro tampoco corta")
revisa(C.tiempos(calle: true, conferencia: false, porAviso: false, juanHablo: true, deCalle: calle, deConferencia: C.Tiempos(silencio: 45, tope: 60, duro: 90))?.duro == nil, "el Modo calle no cambia: sin tope duro")
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

// Guardia 19-nov-2026: se cortó (1006) justo cuando Alma decía «Déjame revisar…» y Juan tuvo que volver a llamar.
revisa(C.trasCorte(claudio: false, calle: false, conferencia: true, conectada: 29, reabiertas: 0, sinCreditos: false, buscando: true) == .reabrir, "conferencia y Alma buscaba algo: se reabre sola y lo busca otra vez")
revisa(C.trasCorte(claudio: false, calle: true, conferencia: false, conectada: 29, reabiertas: 0, sinCreditos: false, buscando: true) == .reabrir, "Modo calle y Alma buscaba algo: también se reabre")
revisa(C.trasCorte(claudio: false, calle: false, conferencia: false, conectada: 29, reabiertas: 0, sinCreditos: false, buscando: true) == .reabrir, "llamada normal buscando: se reabre como siempre")
revisa(C.trasCorte(claudio: false, calle: false, conferencia: true, conectada: 29, reabiertas: 2, sinCreditos: false, buscando: true) == .fallar, "buscando, pero ya se reabrió dos veces: sin bucle")
revisa(C.trasCorte(claudio: false, calle: false, conferencia: true, conectada: 1, reabiertas: 0, sinCreditos: false, buscando: true) == .fallar, "buscando y se cayó al segundo de conectar: algo la rechaza, no se reabre")
revisa(C.pedidoTrasCorteBuscando.contains("búscalo otra vez") && C.pedidoTrasCorteBuscando.contains("sin preguntarme"), "al reabrir buscando, Alma lo busca otra vez sin que Juan lo repita")
revisa(C.ficha("FICHA", frase: "", charla: [], porClaudio: false).contains("te llega como un turno de Juan") && !C.ficha("FICHA", frase: "", charla: [], porClaudio: false).contains("«»"), "sin frase fija, la ficha no dice «ya le dijiste «»»")
let ahora = Date()
let nc = C.notaCorte(herramienta: "secretaria", desde: ahora.addingTimeInterval(-12), ahora: ahora, salida: "Speaker", enFondo: true, telefono: true)
revisa(nc.contains("herramienta secretaria en curso hace 12 s") && nc.contains("salida Speaker") && nc.contains("segundo plano") && nc.contains("llamada de teléfono"), "el corte dice qué herramienta corría, la salida, si estaba en segundo plano y si había llamada")
let nc2 = C.notaCorte(herramienta: nil, desde: nil, ahora: ahora, salida: "", enFondo: false, telefono: false)
revisa(!nc2.contains("herramienta") && nc2.contains("salida ?") && nc2.contains("a la vista") && !nc2.contains("teléfono"), "sin herramienta ni llamada, no las inventa")
revisa(!C.anotaVozEnviada(10) && !C.anotaVozEnviada(9.2), "«Voz enviada» normal ya no llena el registro")
revisa(C.anotaVozEnviada(0) && C.anotaVozEnviada(4.5), "«Voz enviada» rara (el micrófono mandó poco) sí se anota")
let pc = C.pasoAppCerrada(ultimoPaso: "Alma usa secretaria", latido: "10:40:30 · 29 s conectada · herramienta secretaria en curso hace 3 s")
revisa(pc.hasPrefix("La app se cerró a media llamada") && pc.contains("última señal: 10:40:30") && pc.contains("último paso: Alma usa secretaria"), "si la app se cerró a media llamada, al abrir queda dónde iba")
revisa(C.pasoAppCerrada(ultimoPaso: nil, latido: nil) == "La app se cerró a media llamada (iOS la terminó o falló), sin que tocaras Terminar", "sin señal guardada, solo lo que pasó")

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

// Guardia 18-nov-2026: los pasos del anillo no sacan a los de la voz.
var mix: [String] = []
for i in 0..<5 { mix = C.guardar(mix, "16:16:0\(i) Turno de Juan: \(i + 3) palabras") }
for i in 0..<100 { mix = C.guardar(mix, "16:17:\(i) Hay música sonando: no la pauso; el anillo vuelve cuando pare") }
revisa(mix.filter { C.esPasoAnillo($0) }.count == C.anilloGuardados, "del anillo quedan solo los últimos \(C.anilloGuardados)")
revisa(mix.filter { $0.contains("Turno de Juan") }.count == 5 && mix.first == "16:16:00 Turno de Juan: 3 palabras", "los pasos de la voz siguen ahí aunque el anillo mande 100")
revisa(mix.last == "16:17:99 Hay música sonando: no la pauso; el anillo vuelve cuando pare", "el último paso del anillo se guarda")
revisa(C.esPasoAnillo("10:00 Toque repetido ignorado: la llamada acaba de empezar") && !C.esPasoAnillo("10:00 Alma conectada · te escucha") && !C.esPasoAnillo("10:00 ElevenLabs cerró la voz (1006)") && !C.esPasoAnillo("10:00 Abriendo el micrófono (la música baja, no se pausa)") && C.esPasoAnillo("10:00 La música de otra app paró (fin): vuelve cuando Alma termine"), "se reconoce qué paso es del anillo")
let tj = Date()
revisa(C.esperaSinRespuesta(juan: tj, voz: nil, ahora: tj.addingTimeInterval(48)) == 48, "Juan habló y la voz nunca contestó: 48 s esperando")
revisa(C.esperaSinRespuesta(juan: tj, voz: tj.addingTimeInterval(2), ahora: tj.addingTimeInterval(48)) == nil, "si la voz contestó después, no hay espera")
revisa(C.esperaSinRespuesta(juan: nil, voz: nil, ahora: tj) == nil, "si Juan no habló, no hay espera")
revisa(C.notaCierre(juan: tj, voz: nil, ahora: tj.addingTimeInterval(48), palabras: 90).contains("90 palabras") && C.notaCierre(juan: nil, voz: nil, ahora: tj, palabras: 0).isEmpty, "la nota del cierre dice las palabras y la espera, o nada")

// MARK: - Sin «¿sigues ahí?» en calle ni conferencia (Juan, 17-nov-2026)

for f in ["¿Sigues ahí?", "¿Juan, sigues ahí?", "¿Estás ahí?", "¿Me escuchas?", "¿Hola?", "¿Juan?", "¿Sigues conmigo, Juan?",
          "¿Todavía estás ahí?", "Hola, ¿sigues ahí? Aquí estoy cuando quieras.", "¿Se cortó?", "¿SIGUES AHI?"] {
    revisa(C.esPreguntaDeSilencio(f), "se calla: «\(f)»")
}
for f in ["Listo, ya agendé la limpieza del 1104 para mañana a las nueve.", "Hola, cuéntame.", "Entendido, te aviso.",
          "La reserva del 301 entra el viernes; el huésped dijo que sigue ahí hasta el domingo y pidió toallas extra para la noche.",
          "Juan, el pago ya entró.", ""] {
    revisa(!C.esPreguntaDeSilencio(f), "no se calla una respuesta de verdad: «\(f)»")
}

// MARK: - Se cortó con Juan esperando respuesta (Juan, 19-nov-2026: conferencia por Bluetooth, pidió algo y se cayó a los 11 s)
let tJ = Date(timeIntervalSince1970: 2_000_000)
revisa(C.trasCorte(claudio: false, calle: false, conferencia: true, conectada: 23, reabiertas: 0, sinCreditos: false, esperando: true) == .reabrir, "conferencia y Juan esperaba respuesta: se reabre sola y Alma lo atiende")
revisa(C.trasCorte(claudio: false, calle: true, conferencia: false, conectada: 23, reabiertas: 0, sinCreditos: false, esperando: true) == .reabrir, "Modo calle y Juan esperaba: también se reabre")
revisa(C.trasCorte(claudio: false, calle: false, conferencia: true, conectada: 23, reabiertas: 0, sinCreditos: false, esperando: false) == .colgar, "conferencia sin nada pendiente: se cierra como siempre")
revisa(C.trasCorte(claudio: false, calle: false, conferencia: true, conectada: 23, reabiertas: 2, sinCreditos: false, esperando: true) == .fallar, "esperando, pero ya se reabrió dos veces: sin bucle")
revisa(C.trasCorte(claudio: false, calle: false, conferencia: true, conectada: 1, reabiertas: 0, sinCreditos: false, esperando: true) == .fallar, "esperando y se cayó al segundo de conectar: no se reabre")
revisa(C.juanEspera(juan: tJ, voz: nil, palabras: 8, ahora: tJ.addingTimeInterval(11)), "Juan pidió algo hace 11 s y Alma no respondió: espera")
revisa(!C.juanEspera(juan: tJ, voz: tJ.addingTimeInterval(3), palabras: 8, ahora: tJ.addingTimeInterval(11)), "Alma ya le respondió: no espera")
revisa(!C.juanEspera(juan: tJ, voz: nil, palabras: 1, ahora: tJ.addingTimeInterval(5)), "una sola palabra (un «mm») no cuenta como pedido")
revisa(!C.juanEspera(juan: tJ, voz: nil, palabras: 8, ahora: tJ.addingTimeInterval(C.esperaMaxima + 1)), "lo dijo hace mucho: ya no es lo que acaba de pedir")
revisa(!C.juanEspera(juan: nil, voz: nil, palabras: 0, ahora: tJ), "Juan no habló: no espera")
revisa(C.pedidoTrasCorteEsperando.contains("sin preguntarme de nuevo") && C.pedidoTrasCorteEsperando.contains("no digas nada"), "al reabrir lo atiende sin que Juan repita; si no era para ella, calla")
revisa(C.notaRuta(cambio: tJ, motivo: 4, salida: "Speaker", ahora: tJ.addingTimeInterval(11)).contains("cambió de ruta hace 11 s (motivo 4 → Speaker)"), "el corte dice si el audio cambió de ruta en los 15 s antes")
revisa(C.notaRuta(cambio: tJ, motivo: 4, salida: "Speaker", ahora: tJ.addingTimeInterval(40)).isEmpty, "un cambio de ruta viejo no se anota")
revisa(C.notaRuta(cambio: nil, motivo: 0, salida: "", ahora: tJ).isEmpty, "sin cambio de ruta: nada")

// MARK: - Juan dictando en conferencia (guardia 20-nov-2026: colgó a Juan a media instrucción de 3 min, «tope» a los 180 s)
// conv_4601…: Alma terminó de hablar a los 88 s (lo último escrito, 00:19:13); Juan dictó sin parar y ElevenLabs no cerró su
// turno. A los 268 s (00:22:13, 180 s después) la app tomó su voz como ruido y colgó.
func dictado(sonido: TimeInterval, desde: TimeInterval = 86, juan: TimeInterval? = 87) -> SuenoCalle.Momentos {
    var m = momentos(alma: 88, juan: juan, sonido: sonido); m.sonidoDesde = t0.addingTimeInterval(desde); return m
}
func decideConf(_ m: SuenoCalle.Momentos, a s: TimeInterval, conDictado: Bool = true) -> SuenoCalle.Motivo? {
    SuenoCalle.decidir(m, ahora: t0.addingTimeInterval(s), silencio: conf.silencio, tope: conf.tope, ruido: conf.ruido, pausa: conf.pausa,
                       duro: duro, dictado: conDictado ? C.ruidoDictado : nil)
}
revisa(decideConf(dictado(sonido: 267.7), a: 268, conDictado: false) == .tope, "antes: a los 180 s sin nada escrito la voz de Juan era «ruido» y colgaba (00:22:13)")
var dicta: [SuenoCalle.Motivo?] = []
for s in stride(from: 89.0, through: 300.0, by: 0.5) { dicta.append(decideConf(dictado(sonido: s - 0.3), a: s)) }
revisa(dicta.allSatisfy { $0 == nil }, "ahora: Juan dicta sin parar de 00:19:13 a 00:22:13 y más: la llamada NO se cierra")
revisa(SuenoCalle.dictando(dictado(sonido: 267.7), ahora: t0.addingTimeInterval(268)), "lo reconoce como Juan dictando")
revisa(decideConf(dictado(sonido: 150), a: 154) == nil, "se detiene 4 s a pensar a media instrucción: el tope duro no lo corta")
revisa(decideConf(dictado(sonido: 150), a: 158) == .tope, "se calló 8 s pasado el tope: ya terminó, cierra como siempre")
revisa(decideConf(dictado(sonido: 88 + C.ruidoDictado + 0.7), a: 88 + C.ruidoDictado + 1) == .tope, "6 min de sonido sin nada escrito: cierra igual (créditos)")
revisa(C.ruidoDictado == 360, "el dictado cuenta como Juan hasta 6 min")
revisa(!SuenoCalle.dictando(dictado(sonido: 200, desde: 150), ahora: t0.addingTimeInterval(201)), "un sonido que empezó 1 min después de lo último escrito no es dictado (es ruido)")
revisa(!SuenoCalle.dictando(dictado(sonido: 200, juan: 180), ahora: t0.addingTimeInterval(201)), "si siguen llegando palabras mientras suena (una reunión) no es dictado")
revisa(!SuenoCalle.dictando(momentos(alma: 88, sonido: 200), ahora: t0.addingTimeInterval(201)), "sin saber desde cuándo suena: no es dictado")
var reunion2: [SuenoCalle.Motivo?] = []   // la reunión de antes, ahora sabiendo desde cuándo suena: el tope duro sigue cerrando
for s in stride(from: 6.0, through: 300.0, by: 0.5) {
    let resto = s.truncatingRemainder(dividingBy: 6)
    var m = momentos(alma: 5, juan: s - 1, sonido: resto < 4 ? s - resto : s - 0.3); m.sonidoDesde = t0.addingTimeInterval(6)
    reunion2.append(decideConf(m, a: s))
}
revisa(reunion2.contains(SuenoCalle.Motivo.tope), "una reunión (llegan sus palabras) se sigue cerrando con el tope duro")
revisa(SuenoCalle.decidir(dictado(sonido: 267.7), ahora: t0.addingTimeInterval(268), silencio: 6, tope: 45, ruido: SuenoCalle.soloRuido) == .tope, "el Modo calle no cambia (sin dictado)")
revisa(C.pasoCierre("tope", calle: false, conferencia: true, hablando: true).contains("(tope, cerró con Juan hablando)"), "si cierra con Juan sonando, el paso lo dice para la guardia")
revisa(C.pasoCierre("tope", calle: false, conferencia: true) == "Conferencia: la llamada se cierra sola (tope) y vuelve a escuchar «Alma»", "sin nadie hablando, el paso de siempre")

// Guardia 20-nov-2026: en la calle con la Guía de camino otra app tomó el audio (motivo 0) y la conferencia colgó en el acto (1006).
revisa(C.esperaTrasInterrupcion(continua: true, motivo: 0, telefono: false), "conferencia o calle y otra app toma el audio: espera a que vuelva, no cuelga en el acto")
revisa(C.esperaTrasInterrupcion(continua: true, motivo: nil, telefono: false), "sin motivo de iOS también espera")
revisa(!C.esperaTrasInterrupcion(continua: true, motivo: 0, telefono: true), "con una llamada de teléfono cuelga como antes")
revisa(!C.esperaTrasInterrupcion(continua: true, motivo: 1, telefono: false), "si iOS suspendió la app (motivo 1) no espera")
revisa(!C.esperaTrasInterrupcion(continua: false, motivo: 0, telefono: false), "una llamada normal sigue como antes")
revisa(C.esperaInterrupcion >= 5 && C.esperaInterrupcion <= 20, "la espera es de unos segundos (de fábrica 10)")
revisa(C.trasCorte(claudio: false, calle: false, conferencia: true, conectada: 400, reabiertas: 0, sinCreditos: false, interrumpida: true) == .reabrir, "conferencia: si la conexión se cayó durante la interrupción y el audio volvió, se reabre")
revisa(C.trasCorte(claudio: false, calle: true, conferencia: false, conectada: 400, reabiertas: 0, sinCreditos: false, interrumpida: true) == .reabrir, "Modo calle: igual")
revisa(C.trasCorte(claudio: false, calle: false, conferencia: true, conectada: 400, reabiertas: 2, sinCreditos: false, interrumpida: true) == .fallar, "tras la interrupción, como mucho dos veces")
revisa(C.trasCorte(claudio: false, calle: false, conferencia: true, conectada: 400, reabiertas: 0, sinCreditos: false) == .colgar, "sin interrupción ni pedido, la conferencia cuelga como antes")
revisa(C.pedidoTrasInterrupcion.contains("no digas nada y sigue escuchando"), "al reabrir tras la interrupción, si Juan estaba en pausa Alma se queda callada")

if fallos > 0 { print("\(fallos) fallaron"); exit(1) }
print("Todo bien")
