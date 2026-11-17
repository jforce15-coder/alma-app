// Pruebas de Claudio local (Alma/ClaudioLocalReglas.swift; Hub #629).
//   swiftc Alma/AgenteVoz.swift Alma/ClaudioLocalReglas.swift Pruebas/ClaudioLocal/main.swift -o /tmp/claudio-local && /tmp/claudio-local
// Las corre el robot en cada PR (testflight.yml, «Probar Claudio local»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}
typealias R = ClaudioLocalReglas

// Cuándo terminó de hablar Juan
let t0 = Date(timeIntervalSince1970: 1_000)
revisa(!R.termino(texto: "", ultimoCambio: t0, empezo: t0, ahora: t0.addingTimeInterval(30)), "sin nada dicho no hay frase (aunque pase el tiempo)")
revisa(!R.termino(texto: "cambia el botón de pagos", ultimoCambio: t0, empezo: t0, ahora: t0.addingTimeInterval(0.8)), "una pausa cortita no corta a Juan")
revisa(R.termino(texto: "cambia el botón de pagos", ultimoCambio: t0, empezo: t0, ahora: t0.addingTimeInterval(1.2)), "a la pausa (1,1 s) la frase va")
revisa(!R.termino(texto: "cambia el botón de pagos y", ultimoCambio: t0, empezo: t0, ahora: t0.addingTimeInterval(1.5)), "si la frase queda colgando («… y») espera más")
revisa(R.termino(texto: "cambia el botón de pagos y", ultimoCambio: t0, empezo: t0, ahora: t0.addingTimeInterval(2.1)), "… pero no para siempre (2 s)")
revisa(R.termino(texto: "y esto y lo otro y", ultimoCambio: t0.addingTimeInterval(25), empezo: t0, ahora: t0.addingTimeInterval(25.1)), "con el tope (25 s hablando) la frase va igual")

// Lo que se manda al Hub
var h: [R.Turno] = []
for i in 0..<20 { h = R.sumar(h, .init(deClaudio: i % 2 == 1, texto: "frase \(i)")) }
revisa(h.count == R.maxTurnos && h.last?.texto == "frase 19", "la conversación que va al Hub es corta (las últimas 14)")
revisa(R.sumar(h, .init(deClaudio: false, texto: "   ")).count == h.count, "lo vacío no se suma")
revisa(R.sumar([], .init(deClaudio: false, texto: String(repeating: "a", count: 2000))).first?.texto.count == R.maxLetras, "cada frase va corta (600 letras)")
let p = R.pedido(token: "t", sesion: "s", conv: "conv_local_ab12", texto: "  hola  ", historial: [.init(deClaudio: true, texto: "Hola, Juan")])
let hist = p["historial"] as? [[String: String]] ?? []
revisa(p["action"] as? String == "claudioLocal" && p["session"] as? String == "s" && p["conv_id"] as? String == "conv_local_ab12" && p["texto"] as? String == "hola", "se pide con claudioLocal, la sesión y la conversación local")
revisa(hist.count == 1 && hist[0]["de"] == "claudio" && hist[0]["texto"] == "Hola, Juan", "lo dicho va con quién lo dijo")

// La respuesta del Hub
let r1 = R.respuesta(["ok": true, "hablar": "Listo, te paso con Alma.", "volver": true, "herramientas": ["claudio_pedido", "otra"]])
revisa(r1.hablar == "Listo, te paso con Alma." && r1.volver && r1.herramientas == ["claudio_pedido"], "dice la frase, vuelve con Alma y avisa las herramientas de Claudio (para su panel)")
revisa(R.respuesta(nil).hablar == R.repite && !R.respuesta(nil).volver, "sin respuesta del Hub: una frase, nunca en silencio")
revisa(R.respuesta(["ok": true, "hablar": "  "]).hablar == R.repite, "con la frase vacía, también")

// La misma voz de ElevenLabs (Hub #636)
let pcm = Data((0..<40001).map { UInt8($0 % 256) })   // 1,25 s a 16 kHz y un byte suelto
let ra = R.respuesta(["ok": true, "hablar": "Ya quedó.", "audio": pcm.base64EncodedString(), "hz": 16000])
revisa(ra.audio?.count == 40000, "la frase llega con su voz de ElevenLabs (sin el byte suelto)")
revisa(R.respuesta(["ok": true, "hablar": "Ya quedó.", "audio": pcm.base64EncodedString(), "hz": 22050]).audio == nil, "otro formato: con la voz del iPhone")
revisa(R.respuesta(["ok": true, "hablar": "Ya quedó.", "audio": "%%%", "hz": 16000]).audio == nil && R.respuesta(["ok": true, "hablar": "Ya quedó."]).audio == nil, "audio roto o sin audio: con la voz del iPhone")
revisa(R.respuesta(["ok": true, "hablar": " ", "audio": pcm.base64EncodedString(), "hz": 16000]).audio == nil, "sin frase, «¿me lo repites?» no lleva un audio que no es suyo")
let tz = R.trozos(ra.audio!)
revisa(tz.count == 5 && tz.allSatisfy { $0.count == 8000 } && tz.reduce(into: Data(), { $0.append($1) }) == ra.audio!, "suena en trozos de un cuarto de segundo, completo y en orden")
revisa(abs(R.duracion(ra.audio!) - 1.25) < 0.001, "y sabe cuánto suena (para volver a escuchar al terminar)")
revisa(R.audio(["audio": pcm.base64EncodedString(), "hz": 16000, "genero": "hombre"])?.count == 40000, "el saludo (voz_local.audio) también con su voz")

// Lo que dice la voz del iPhone
let d = R.paraDecir("[warm] **Listo**, quedó pedido. https://github.com/x\n- uno")
revisa(d == "Listo, quedó pedido. uno", "sin etiquetas de emoción, markdown, enlaces ni viñetas: «\(d)»")

// Los ajustes de la voz (del Hub)
let a0 = R.Ajustes(nil)
revisa(a0.hombre && a0.idiomas.first == "es-MX" && a0.tono < 1 && a0.velocidad == 0.5, "de fábrica: hombre, México primero, un poco más grave")
let a1 = R.Ajustes(["velocidad": 3, "tono": 0.85, "idiomas": ["es-ES", "en-US"], "genero": "mujer"])
revisa(a1.velocidad == 0.65 && a1.tono == 0.85 && a1.idiomas == ["es-ES"] && !a1.hombre, "los del Hub, con límites y solo español")

// La voz que más se parece a Claudio
let voces = [R.Voz(id: "paulina", idioma: "es-MX", hombre: false, calidad: 0, rara: false),
             R.Voz(id: "juan-normal", idioma: "es-MX", hombre: true, calidad: 2, rara: false),
             R.Voz(id: "juan-mejorada", idioma: "es-MX", hombre: true, calidad: 1, rara: false),
             R.Voz(id: "jorge-premium", idioma: "es-ES", hombre: true, calidad: 0, rara: false),
             R.Voz(id: "robot", idioma: "es-MX", hombre: true, calidad: 0, rara: true),
             R.Voz(id: "fred", idioma: "en-US", hombre: true, calidad: 0, rara: false)]
revisa(R.elegir(voces, a0)?.id == "juan-mejorada", "de hombre, de México y la mejor calidad (nunca una de novedad)")
revisa(R.elegir(voces.filter { $0.id != "juan-normal" && $0.id != "juan-mejorada" }, a0)?.id == "jorge-premium", "sin una de hombre de México, la de España")
revisa(R.elegir([voces[0]], a0)?.id == "paulina", "sin ninguna de hombre en español, la mejor en español (mejor una voz que ninguna)")
revisa(R.elegir([voces[5]], a0) == nil, "en inglés, ninguna")

if fallos > 0 { print("\(fallos) fallaron"); exit(1) }
print("Todo bien: Claudio local.")
