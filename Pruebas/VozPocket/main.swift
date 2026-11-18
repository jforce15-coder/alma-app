// Pruebas de la voz gratis (Alma/VozPocketReglas.swift; Pocket TTS, Juan, 18-nov-2026).
//   swiftc Alma/FonemasES.swift Alma/VozKokoroReglas.swift Alma/VozPocketReglas.swift Pruebas/VozPocket/main.swift -o /tmp/voz-pocket
//   /tmp/voz-pocket <carpeta con tokenizer.model y bundle.json de Pocket>
// Las corre el robot en cada PR (testflight.yml, «Probar la voz gratis»): baja esos dos archivos chicos con su suma.
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}
typealias G = VozPocketReglas
let carpeta = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Modelos/Pocket")

// MARK: - El tokenizador: lo mismo que sentencepiece (los números salen de sentencepiece 0.2 con el tokenizer.model)

if let d = try? Data(contentsOf: carpeta.appendingPathComponent("tokenizer.model")), let tk = TokenizadorPocket(modelo: d) {
    revisa(tk.cuantas == 4000, "el tokenizador trae sus 4000 piezas")
    let casos: [(String, [Int64])] = [
        ("Hola Juan, ¿cómo vas?", [3393, 1470, 261, 302, 1142, 610, 296]),
        ("Ya revisé las limpiezas de mañana y todo está en orden.", [856, 2079, 463, 287, 1108, 1011, 265, 262, 260, 982, 269, 325, 314, 268, 1444, 264]),
        ("La huésped del 1104 llega el viernes a las 3:30 p. m.", [406, 1209, 1235, 661, 424, 293, 260, 344, 344, 320, 539, 570, 270, 2512, 281, 266, 287, 260, 490, 62, 490, 320, 304, 264, 260, 528, 264]),
        ("¡Qué maravilla! Ñandú, pingüino… «comillas».", [260, 198, 165, 629, 1602, 1430, 37, 260, 199, 149, 376, 424, 799, 261, 304, 873, 199, 192, 2295, 230, 132, 170, 260, 198, 175, 1304, 1764, 198, 191, 264]),
        ("Spacio AM 😀 100 %", [555, 1062, 355, 1169, 260, 244, 163, 156, 132, 260, 344, 320, 320, 260, 41]),
    ]
    for (t, esperado) in casos {
        let sale = tk.codificar(t)
        revisa(sale == esperado, "tokens de «\(t)»" + (sale == esperado ? "" : "\n    sale:   \(sale)\n    espera: \(esperado)"))
    }
    revisa(tk.codificar("") == [], "nada: sin tokens")
    let largo = "Hola Juan, ya revisé las limpiezas de mañana, hablé con Recepción Brunelo, confirmé la llegada del viernes, pedí las toallas nuevas y dejé listo el apartamento de la terraza para el fin de semana largo"
    let partes = G.trozos(largo) { tk.codificar(G.preparar($0).texto).count }
    revisa(partes.count >= 2 && partes.allSatisfy { tk.codificar(G.preparar($0).texto).count <= G.maxTokensPorTrozo }, "una frase larga, en trozos de hasta 50 tokens")
    revisa(partes.joined(separator: " ").split(separator: " ") == largo.split(separator: " "), "los trozos no pierden palabras")
} else { revisa(false, "se lee el tokenizer.model de \(carpeta.path)") }
revisa(TokenizadorPocket(modelo: Data([0x0a, 0x05, 0x01])) == nil, "un archivo roto no es un tokenizador")

// MARK: - bundle.json: los estados del modelo

if let d = try? Data(contentsOf: carpeta.appendingPathComponent("bundle.json")), let e = G.estados(d) {
    revisa(e.flujo.count == 18 && e.mimi.count == 56, "18 estados del modelo principal (6 capas) y 56 del decodificador")
    revisa(e.flujo[0].entrada == "state_0" && e.flujo[0].salida == "out_state_0" && e.flujo[0].forma == [2, 1, 1000, 16, 64] && e.flujo[0].relleno == "nan",
           "el primero: la caché de la capa 0, llena de NaN")
    revisa(e.flujo.contains { $0.tipo == "int64" } && e.mimi.contains { $0.tipo == "bool" }, "también hay int64 y bool")
} else { revisa(false, "se lee bundle.json de \(carpeta.path)") }
revisa(G.estados(Data("{\"sample_rate\": 16000}".utf8)) == nil, "otro modelo: no sirve")

// MARK: - El texto

revisa(G.preparar("  hola Juan\n").texto == "Hola Juan." && G.preparar("hola Juan").despues == 5, "mayúscula, punto y frase corta: 3 + 2 cuadros tras el fin")
revisa(G.preparar("¿Cómo vas con las limpiezas de hoy?") == ("¿Cómo vas con las limpiezas de hoy?", 3), "con signo final no se agrega punto; frase larga: 1 + 2")
revisa(G.preparar("   ").texto.isEmpty, "solo espacios: nada")
revisa(G.maxCuadros(tokens: 15) == 88 && G.maxCuadros(tokens: 0) == 25, "cuántos cuadros como mucho (como el modelo)")
revisa(G.trozos("  ") { $0.count } == [], "nada que decir: sin trozos")
revisa(!G.finValido(paso: 3, tokens: 15) && G.finValido(paso: 15, tokens: 15), "el aviso de fin no vale al empezar la frase")

// MARK: - Las voces que trae la app

for v in [G.claudio, G.maricarmen] {
    let u = URL(fileURLWithPath: "Alma/Recursos/Voces/\(v.id).bin")
    let e = (try? Data(contentsOf: u)).flatMap { G.embeddings($0) }
    revisa(e != nil && e!.count / G.condicion > 100 && e!.count / G.condicion < 400, "la voz \(v.nombre) viene en la app (\(e.map { $0.count / G.condicion } ?? 0) filas de 1024)")
}
revisa(G.voz(.claudio) == G.claudio && G.voz(.maricarmen).nombre == "Maricarmen (gratis)", "cada personaje con su voz gratis")
revisa(G.embeddings(Data(count: 1000)) == nil, "un archivo de otro tamaño no es una voz")
revisa(G.archivos.count == 6 && G.archivos.allSatisfy { $0.sha256.count == 64 && $0.url.hasPrefix("https://huggingface.co/KevinAHM/pocket-tts-onnx/resolve/\(G.revision)/") },
       "lo que se baja: versión fija y suma de cada archivo")
revisa(G.megas >= 120 && G.megas <= 130, "pesa unos 125 MB (\(G.megas))")
revisa(G.credito.contains("Kyutai") && G.credito.contains("KevinAHM") && G.credito.contains("CC-BY"), "el crédito de la licencia")

// MARK: - El ruido

var gen = SystemRandomNumberGenerator()
let r = G.ruido(20000, usando: &gen)
let media = r.reduce(0, +) / Float(r.count), varianza = r.map { ($0 - media) * ($0 - media) }.reduce(0, +) / Float(r.count)
revisa(r.count == 20000 && abs(media) < 0.03 && abs(varianza - G.temperatura) < 0.05, "el ruido: media 0 y varianza 0,7 (\(media), \(varianza))")
revisa(G.ruido(7, temperatura: 0, usando: &gen) == [Float](repeating: 0, count: 7), "sin temperatura: ceros")

print(fallos == 0 ? "\nTodo bien." : "\n\(fallos) fallos.")
exit(fallos == 0 ? 0 : 1)
