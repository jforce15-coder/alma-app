// Pruebas de la lógica pura del anillo que vuelve y de los pasos que van al Hub (Alma/AnilloVuelve.swift).
//   swiftc Alma/AnilloVuelve.swift Pruebas/AnilloVuelve/main.swift -o /tmp/anillo-vuelve && /tmp/anillo-vuelve
// Las corre el robot en cada PR (testflight.yml, «Probar el anillo que vuelve»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}
typealias V = AnilloVuelve

// MARK: - ¿Vuelve a quedar lista?

revisa(V.decidir(.interrupcionTermino, modoAnillo: true, enLlamada: false, microfono: false, silencio: false) == .quedarLista, "terminó la interrupción (Spotify, una llamada): vuelve a quedar lista")
revisa(V.decidir(.interrupcionTermino, modoAnillo: false, enLlamada: false, microfono: false, silencio: false) == .nada, "sin el modo anillo, nada")
revisa(V.decidir(.interrupcionTermino, modoAnillo: true, enLlamada: true, microfono: true, silencio: true) == .nada, "en una llamada de Alma, la maneja la llamada")
revisa(V.decidir(.interrupcionSinFin, modoAnillo: true, enLlamada: false, microfono: false, silencio: false) == .quedarLista, "iOS no avisó que terminó (30 s): se intenta igual")
revisa(V.decidir(.interrupcionSinFin, modoAnillo: true, enLlamada: false, microfono: false, silencio: false, telefono: true) == .esperar, "en una llamada de teléfono se espera: nada a media llamada")
revisa(V.decidir(.interrupcionSinFin, modoAnillo: true, enLlamada: false, microfono: false, silencio: false, otraSuena: true) == .esperar, "Spotify sigue sonando a los 30 s: el anillo espera, no pausa la música")
revisa(V.decidir(.interrupcionTermino, modoAnillo: true, enLlamada: false, microfono: false, silencio: false, otraSuena: false) == .quedarLista, "la música paró: el anillo vuelve")
revisa(V.decidir(.ruta(motivo: 2), modoAnillo: true, enLlamada: false, microfono: false, silencio: true, otraSuena: true) == .nada, "cambia la salida con música sonando: no se le quita el audio")
revisa(!V.alAbrir(modoAnillo: true, otraSuena: true), "abrir Alma con música sonando no la pausa")
revisa(V.alAbrir(modoAnillo: true, otraSuena: false), "abrir Alma sin música: el anillo queda listo como siempre")
revisa(V.alQuedarLista(otraSuena: false, microfonoOcupado: false) == .tomar, "sin música: el anillo toma el audio como siempre")
revisa(V.alQuedarLista(otraSuena: true, microfonoOcupado: false) == .dejarSonar, "colgar o abrir con Spotify sonando: Alma suelta su audio y la música sigue")
revisa(V.alQuedarLista(otraSuena: true, microfonoOcupado: true) == .esperar, "música sonando y la conferencia con el micrófono: solo se espera, no se toca")
revisa(V.alQuedarLista(otraSuena: false, microfonoOcupado: true) == .tomar, "sin música, aunque otro modo escuche: como siempre")
revisa(V.decidir(.ruta(motivo: 2), modoAnillo: true, enLlamada: false, microfono: false, silencio: true) == .quedarLista, "se fueron los audífonos y se apagó el micrófono: vuelve")
revisa(V.decidir(.ruta(motivo: 1), modoAnillo: true, enLlamada: false, microfono: true, silencio: false) == .quedarLista, "audífonos nuevos y el audio en silencio se detuvo: vuelve")
revisa(V.decidir(.ruta(motivo: 2), modoAnillo: true, enLlamada: false, microfono: true, silencio: true) == .nada, "cambió la salida pero todo sigue: nada")
revisa(V.decidir(.ruta(motivo: 5), modoAnillo: true, enLlamada: false, microfono: false, silencio: false) == .nada, "un motivo que no rompe nada (5): nada")

// MARK: - ¿Abre Alma?

revisa(V.avisar(activo: false, silencio: false, microfono: false, appActiva: false, yaAvisado: false), "no pudo tomar el audio con la app cerrada: se avisa")
revisa(V.avisar(activo: true, silencio: true, microfono: false, appActiva: false, yaAvisado: false), "el micrófono no volvió con el teléfono bloqueado: se avisa")
revisa(!V.avisar(activo: true, silencio: true, microfono: true, appActiva: false, yaAvisado: false), "volvió todo: no se avisa")
revisa(!V.avisar(activo: false, silencio: false, microfono: false, appActiva: true, yaAvisado: false), "con la app a la vista no hace falta avisar")
revisa(!V.avisar(activo: false, silencio: false, microfono: false, appActiva: false, yaAvisado: true), "una sola vez hasta que vuelva a funcionar")
revisa(V.texto == "Abre Alma para que el anillo vuelva a funcionar.", "el texto que pidió Juan")

// MARK: - El audio para escuchar con el anillo (Hub #793: Spotify se pausaba al abrir la app)

revisa(V.sesionEscucha(enLlamada: false, anilloListo: true, otraSuena: true) == .mezclar, "anillo con Spotify sonando: se mezcla, Spotify no se pausa")
revisa(V.sesionEscucha(enLlamada: false, anilloListo: true, otraSuena: false) == .anillo, "anillo sin música: el audio del anillo, como antes")
revisa(V.sesionEscucha(enLlamada: false, anilloListo: false, otraSuena: true) == .mezclar, "sin anillo: se mezcla")
revisa(V.sesionEscucha(enLlamada: true, anilloListo: true, otraSuena: true) == .llamada, "en plena llamada no se cambian las opciones (la música baja, no se pausa)")
revisa(V.sesionEscucha(enLlamada: true, anilloListo: false, otraSuena: false) == .llamada, "en llamada sin anillo, igual")

// MARK: - Los pasos que van al Hub

let pasos = ["10:00:01 Micrófono listo para el anillo", "10:00:05 El anillo encendió el modo conferencia", "10:01:00 Aviso: Flor pagó el depósito de 1104"]
revisa(PasosAnillo.nuevos(pasos, ultimoEnviado: nil) == pasos, "la primera vez van todos")
revisa(PasosAnillo.nuevos(pasos, ultimoEnviado: pasos[1]) == [pasos[2]], "después, solo lo nuevo")
revisa(PasosAnillo.nuevos(pasos, ultimoEnviado: pasos[2]).isEmpty, "sin nada nuevo, nada")
revisa(PasosAnillo.nuevos(pasos, ultimoEnviado: "09:00:00 otra llamada") == pasos, "si la lista se reinició (otra llamada), van todos")
let l = PasosAnillo.limpiar(pasos + ["10:02:00 Alma lo puso en el chat: Itinerario de Lucky",
                                     "10:03:00 Ya hablabas al conectar (0.4 s): Alma no saluda y te escucha",
                                     "10:04:00 Error: No pude pedir tu ficha: juan@spacioam.com «algo»",
                                     "10:05:00 Error: ElevenLabs cerró la voz (1006) https://api.elevenlabs.io/x"])
revisa(l[2] == "10:01:00 Aviso: …", "el texto de un aviso no sale del teléfono")
revisa(l[3] == "10:02:00 Alma lo puso en el chat: …", "lo que Alma puso en el chat, tampoco")
revisa(l[4].hasPrefix("10:03:00 Ya hablabas al conectar (0.4 s)"), "lo técnico queda igual")
revisa(!l[5].contains("@") && l[5].contains("(correo)") && l[5].contains("«…»"), "sin correos ni lo que va entre «»")
revisa(!l[6].contains("http") && l[6].contains("(1006)"), "sin enlaces; el código del error se queda")
revisa(PasosAnillo.limpiar([String](repeating: "x", count: 40)).count == PasosAnillo.maximo, "como mucho 30 por vez")
let muchos = (0..<70).map { "10:00:\($0) paso \($0)" }
revisa(PasosAnillo.nuevos(muchos, ultimoEnviado: nil) == Array(muchos.prefix(30)), "una llamada larga va por tandas, empezando por lo más viejo (ahí está el porqué de un corte)")
revisa(PasosAnillo.nuevos(muchos, ultimoEnviado: muchos[29]) == Array(muchos[30..<60]) && PasosAnillo.nuevos(muchos, ultimoEnviado: muchos[59]) == Array(muchos[60...]), "la siguiente vuelta sigue donde quedó, sin perder ninguno")
revisa(PasosAnillo.limpiar([String(repeating: "a", count: 400)])[0].count == PasosAnillo.largo, "cada paso, corto")

// Guardia 20-nov-2026: bucle «No pude volver a abrir el micrófono (2003329396)» cada 3 s con otra app dueña del audio.
let fallo0 = Date()
revisa(!V.revivirAlReacomodar(enLlamada: false, ultimoFallo: fallo0.addingTimeInterval(-3), ahora: fallo0), "sin llamada, 3 s después de un fallo no se vuelve a intentar")
revisa(V.revivirAlReacomodar(enLlamada: false, ultimoFallo: fallo0.addingTimeInterval(-31), ahora: fallo0), "pasados 30 s, sí")
revisa(V.revivirAlReacomodar(enLlamada: false, ultimoFallo: .distantPast, ahora: fallo0), "sin fallos antes, sí")
revisa(V.revivirAlReacomodar(enLlamada: true, ultimoFallo: fallo0, ahora: fallo0), "en una llamada siempre se intenta")

if fallos > 0 { print("\(fallos) fallaron"); exit(1) }
print("Todo bien")
