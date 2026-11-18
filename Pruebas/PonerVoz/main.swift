// Pruebas de poner una voz en la llamada (Alma/PonerVozReglas.swift; Hub #779, Juan, 18-nov-2026).
//   swiftc Alma/FonemasES.swift Alma/VozKokoroReglas.swift Alma/PonerVozReglas.swift Pruebas/PonerVoz/main.swift -o /tmp/poner-voz && /tmp/poner-voz
// Las corre el robot en cada PR (testflight.yml, «Probar poner una voz en la llamada»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}
typealias P = PonerVozReglas
let voces = VozKokoroReglas.incluidas + [VozKokoroReglas.Voz(id: "claudio_propio", nombre: "Claudio propio", url: "https://x/y.bin", sha256: nil, acento: .latino, mujer: false)]
let pj = ["claudio": "em_alex", "maricarmen": "ef_dora"]
func ids(_ p: P.Pedido) -> [String] { if case .voces(let m) = p { return m.map { $0.id } }; return [] }

revisa(P.pedido(voz: "", enlace: "", voces: voces, personajes: pj) == .lista, "sin voz: la lista")
revisa(P.pedido(voz: "¿Cuáles hay?", enlace: "", voces: voces, personajes: pj) == .lista, "«cuáles hay»: la lista")
revisa(ids(P.pedido(voz: "Dora", enlace: "", voces: voces, personajes: pj)) == ["ef_dora"], "por nombre")
revisa(ids(P.pedido(voz: "la de Santa", enlace: "", voces: voces, personajes: pj)) == ["em_santa"], "con palabras de más")
revisa(ids(P.pedido(voz: "ÁLEX y dora", enlace: "", voces: voces, personajes: pj)) == ["em_alex", "ef_dora"], "dos, sin acentos ni mayúsculas")
revisa(ids(P.pedido(voz: "todas", enlace: "", voces: voces, personajes: pj)) == ["em_alex", "ef_dora", "em_santa", "claudio_propio", "claudio_gratis", "maricarmen_gratis", "iphone"], "todas, con las gratis y la del iPhone al final")
revisa(ids(P.pedido(voz: "la de Maricarmen", enlace: "", voces: voces, personajes: ["maricarmen": "maricarmen_gratis"])) == ["maricarmen_gratis"], "la de Maricarmen con la voz gratis")
revisa(ids(P.pedido(voz: "la gratis", enlace: "", voces: voces, personajes: pj)) == ["claudio_gratis", "maricarmen_gratis"], "«la gratis»: las dos")
revisa(P.frase(P.gratis[0], pedida: "").contains("Claudio gratis"), "la gratis se presenta con su nombre")
revisa(ids(P.pedido(voz: "la de Maricarmen", enlace: "", voces: voces, personajes: pj)) == ["ef_dora"], "la de Maricarmen: la que tiene elegida")
revisa(ids(P.pedido(voz: "la tuya", enlace: "", voces: voces, personajes: ["claudio": "iphone"])) == ["iphone"], "la tuya con la voz del iPhone")
revisa(ids(P.pedido(voz: "la voz del iPhone", enlace: "", voces: voces, personajes: pj)) == ["iphone"], "la del iPhone")
revisa(ids(P.pedido(voz: "Claudio propio", enlace: "", voces: voces, personajes: pj)).contains("claudio_propio"), "una propia por su nombre")
if case .nada(let t) = P.pedido(voz: "Rigoberto", enlace: "", voces: voces, personajes: pj) { revisa(t.contains("Dora"), "una que no existe: dice cuáles hay") } else { revisa(false, "una que no existe: nada") }
revisa(P.pedido(voz: "", enlace: "https://ejemplo.com/a.mp3", voces: voces, personajes: pj) == .enlace(URL(string: "https://ejemplo.com/a.mp3")!), "un enlace https")
if case .nada = P.pedido(voz: "Dora", enlace: "http://ejemplo.com/a.mp3", voces: voces, personajes: pj) { revisa(true, "un enlace sin https no suena") } else { revisa(false, "un enlace sin https no suena") }
let muchas = (0..<10).map { VozKokoroReglas.Voz(id: "v\($0)", nombre: "V\($0)", url: "https://x", sha256: nil, acento: .latino, mujer: false) }
revisa(ids(P.pedido(voz: "todas", enlace: "", voces: muchas, personajes: pj)).count == P.maxVoces, "todas: con tope")

let dora = P.Muestra(id: "ef_dora", nombre: "Dora", kokoro: true)
revisa(P.frase(dora, pedida: "").contains("Dora"), "la frase dice su nombre")
revisa(P.frase(P.iphone, pedida: "").contains("iPhone"), "la del iPhone se presenta como tal")
revisa(P.frase(dora, pedida: "  Buenos días, Brunelo. ") == "Buenos días, Brunelo.", "la frase que pidió Juan")
revisa(P.frase(dora, pedida: String(repeating: "a", count: 500)).count == P.maxFrase, "la frase pedida, con tope")
revisa(P.silencio(hz: 16000, segundos: 0.5).count == 16000, "el respiro: medio segundo a 16 kHz")

let r1 = P.resultado(sonaron: ["Alex", "Dora"], faltan: [], sinModelo: false)
revisa(!r1.error && r1.texto.contains("Alex, Dora") && r1.texto.contains("no la describas"), "sonaron: Claudio pregunta qué le pareció")
let r2 = P.resultado(sonaron: [], faltan: ["Dora"], sinModelo: true)
revisa(r2.error && r2.texto.contains("Kokoro"), "sin Kokoro: error y cómo bajarlo")
let r3 = P.resultado(sonaron: ["Alex"], faltan: ["Santa"], sinModelo: false)
revisa(!r3.error && r3.texto.contains("Santa"), "una faltó: lo dice")
revisa(P.lista(VozKokoroReglas.incluidas, personajes: pj).contains("Alex, Dora, Santa, Claudio gratis, Maricarmen gratis y la voz del iPhone"), "la lista con sus nombres")
revisa(P.listaParaJuan(VozKokoroReglas.incluidas) == "Tengo Alex, Dora, Santa, Claudio gratis, Maricarmen gratis y la voz del iPhone. ¿Cuál quieres oír, o todas?", "la lista para Juan, en simple")
revisa(P.enlaceListo(segundos: 90).contains("minuto y medio"), "un audio largo se corta y se dice")

print(fallos == 0 ? "\nTodo bien." : "\n\(fallos) fallos.")
exit(fallos == 0 ? 0 : 1)
