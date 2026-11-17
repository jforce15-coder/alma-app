// Pruebas de la voz local con Kokoro (Alma/VozKokoroReglas.swift y Alma/FonemasES.swift; Juan, 17-nov-2026).
//   swiftc Alma/FonemasES.swift Alma/VozKokoroReglas.swift Pruebas/VozKokoro/main.swift -o /tmp/voz-kokoro && /tmp/voz-kokoro
// Las corre el robot en cada PR (testflight.yml, «Probar la voz local con Kokoro»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}
func igual(_ a: String, _ b: String, _ que: String, linea: Int = #line) {
    revisa(a == b, que + (a == b ? "" : "\n    sale:   \(a)\n    espera: \(b)"), linea: linea)
}
typealias F = FonemasES
typealias K = VozKokoroReglas

// MARK: - Fonemas (lo que daría espeak-ng es-419 / es, como lo vio Kokoro al entrenar)

igual(F.frase("Hola Juan, ¿cómo estás?", acento: .latino), "ˈola xwˈan, kˈomo estˈas?", "saludo: h muda, j = x, acentos y signos")
igual(F.frase("Listo, ya subí el cambio y está en verde.", acento: .latino), "lˈisto, ʝˈa suβˈi el kˈambjo i estˈa em bˈeɾðe.",
      "b suave entre vocales, n → m ante b, «y» sola es i")
igual(F.frase("Mañana llueve en la ciudad de Guatemala.", acento: .latino), "maɲˈana ʝuˈeβe en la sjuðˈad ðe ɣwˌatemˈala.",
      "seseo, ll = ʝ, d final, acento secundario")
igual(F.frase("El perro corre rápido hacia el agua.", acento: .latino), "el pˈero kˈore rˈapiðo ˌasja el ˈaɣwa.", "rr, r inicial y «hacia» con acento secundario")
igual(F.frase("Tengo un beso, enviar, un pan, conmigo.", acento: .latino), "tˈɛŋɡo ˈum bˈeso, embjˈaɾ, ˈum pˈan, konmˈiɣo.",
      "ɛ ante n + consonante, n → ŋ ante g, b dura tras nasal y tras pausa")
igual(F.frase("Hay que revisar la hoja de cálculo.", acento: .latino), "ˈI ke rˌeβisˈaɾ la ˈoxa ðe kˈalkulo.", "«hay» = ˈI (como espeak con Kokoro)")
igual(F.frase("Excelente, la piscina del hotel.", acento: .latino), "ˌekselˈɛnte, la pisˈina ðel otˈel.", "xc y sc con seseo: una sola s")
igual(F.frase("Venga, cuéntame qué hacemos hoy.", acento: .espana), "bˈɛŋɡa, kwˈɛntame kˈe aθˈemos ˈY.", "España: θ; «hoy» = ˈY")
igual(F.frase("Guillermo y Rodrigo bajaron al garaje.", acento: .latino), "ɡijjˈeɾmo i roðɾˈiɣo βaxˈaɾon al ɣaɾˈaxe.", "ll entre vocales (latino) = jj, gu + i")
igual(F.frase("Guillermo y Rodrigo bajaron al garaje.", acento: .espana), "ɡiʎˈeɾmo i roðɾˈiɣo βaxˈaɾon al ɣaɾˈaxe.", "ll en España = ʎ")
igual(F.frase("El huésped pidió una toalla.", acento: .latino), "el wˈesped piðjˈo ˈuna toˈajja.", "hue = we")
igual(F.frase("Ahijado, prohibido, reunión, aire, auto.", acento: .latino), "ˌaixˈaðo, pɾˌoiβˈiðo, reʊnjˈon, ˈIɾe, ˈWto.",
      "la h separa vocales; eu, ai, au decrecientes")
igual(F.frase("Administrador del calendario, ampliar la prioridad.", acento: .latino),
      "ˌadminˌistɾaðˈoɾ ðel kˌalendˈaɾjo, ˌampliˈaɾ la pɾˌioɾiðˈad.", "d ante consonante dura; tras pl / pr la i suena entera")
igual(F.palabra("que", acento: .latino), "kˈe", "«qu» = k")
igual(F.palabra("pingüino", acento: .latino), "piŋɡuˈino".replacingOccurrences(of: "ŋ", with: "n"), "gü suena u (la n → ŋ va entre palabras)")
igual(F.frase("OK, el Hub está listo", acento: .latino), "okˈei, el xˈaβ estˈa lˈisto", "palabras en inglés: excepciones")
igual(F.frase("hola", acento: .latino, excepciones: ["hola": "ˈoʊla"]), "ˈoʊla", "las pronunciaciones del catálogo mandan")
revisa(F.frase("🙂 ¡¡!!", acento: .latino).allSatisfy { $0 == "!" || $0 == " " }, "un emoji no se dice")

// MARK: - Números, horas y siglas

igual(F.numero(1104), "mil ciento cuatro", "1104")
igual(F.numero(21_000), "veintiún mil", "21 000 → veintiún mil")
igual(F.numero(31), "treinta y uno", "31")
igual(F.numero(100), "cien", "100")
igual(F.numero(2026), "dos mil veintiséis", "2026")
igual(F.numero(1_000_000), "un millón", "un millón")
igual(F.numero(531_000_000), "quinientos treinta y un millones", "quinientos treinta y un millones")
igual(F.normalizar("A las 10:30 y a las 9:00"), "A las diez y treinta y a las nueve en punto", "horas")
igual(F.normalizar("subió 15%"), "subió quince por ciento", "porcentaje")
igual(F.normalizar("Cuesta Q250"), "Cuesta doscientos cincuenta quetzales", "quetzales")
igual(F.normalizar("Unidos 3 PRs"), "Unidos tres pe erres", "siglas en plural")
igual(F.normalizar("La IA y el OK"), "La i a y el OK", "siglas; OK se queda (excepción)")
igual(F.normalizar("NO lo hagas"), "NO lo hagas", "una palabra gritada no se deletrea")
igual(F.normalizar("1.500 y 3,5"), "mil quinientos y tres punto cinco", "miles con punto y decimales")

// MARK: - Fonemas → números del modelo

revisa(K.tokens("ˈola") == [156, 57, 54, 43], "ˈola → 156 57 54 43 (config.json de Kokoro)")
revisa(K.tokens("xwˈan, ¿") == [66, 65, 156, 43, 56, 3, 16], "lo que no conoce (¿) se salta")
revisa(K.tokens(String(repeating: "a", count: 900)).count == K.maxTokens, "una frase larguísima se corta en 508")

// MARK: - Por frases

revisa(K.frases("Listo. Ya quedó, Juan! ¿Seguimos?") == ["Listo.", "Ya quedó, Juan!", "¿Seguimos?"], "corta en . ! ?")
revisa(K.frases("Son las 10:30 y cuesta 3.5 dólares") == ["Son las 10:30 y cuesta 3.5 dólares"], "10:30 y 3.5 no cortan")
revisa(K.frases("") == [] && K.frases("  … ") == [], "nada que decir: ninguna frase")
let larga = String(repeating: "palabra ", count: 30) + "y aquí, termina todo esto con calma."
let partes = K.frases(larga, max: 60)
revisa(partes.count > 1 && partes.allSatisfy { $0.count <= 60 }, "una frase larga se parte (\(partes.count) partes)")
revisa(partes.joined(separator: " ").split(separator: " ").count == larga.split(separator: " ").count, "al partir no se pierde ninguna palabra")

// MARK: - El archivo de la voz

let total = K.filas * K.ancho
var nums = (0..<total).map { Float($0 % 97) / 97 }
let bin = nums.withUnsafeBufferPointer { Data(buffer: $0) }
revisa(K.estilos(bin) == nums, "un .bin de Kokoro (510 × 256 float32) sirve")
revisa(K.estilos(bin.dropLast(4)) == nil, "un .bin de otro tamaño no")
var enc = "{'descr': '<f4', 'fortran_order': False, 'shape': (510, 1, 256), }"
while (10 + enc.count + 1) % 64 != 0 { enc += " " }
enc += "\n"
var npy = Data([0x93]) + Data("NUMPY".utf8) + Data([1, 0, UInt8(enc.count & 0xFF), UInt8(enc.count >> 8)]) + Data(enc.utf8)
npy.append(bin)
revisa(K.estilos(npy) == nums, "un .npy de numpy (<f4, 510 × 1 × 256) sirve")
let npy64 = Data([0x93]) + Data("NUMPY".utf8) + Data([1, 0, UInt8(enc.count & 0xFF), UInt8(enc.count >> 8)]) + Data(enc.replacingOccurrences(of: "<f4", with: "<f8").utf8) + bin
revisa(K.estilos(npy64) == nil, "un .npy de float64 no")
nums[5] = .nan
revisa(K.estilos(nums.withUnsafeBufferPointer { Data(buffer: $0) }) == nil, "con un NaN no")
let tabla = (0..<total).map { Float($0 / K.ancho) }
revisa(K.estilo(tabla, tokens: 12) == [Float](repeating: 12, count: 256), "la fila del estilo = cuántos fonemas")
revisa(K.estilo(tabla, tokens: 9000).first == 509, "con muchos fonemas, la última fila")

// MARK: - El catálogo

let cat = """
{"voces": [{"id": "claudio_propio", "nombre": "Claudio propio", "url": "https://ejemplo.com/c.bin", "sha256": "\(String(repeating: "a", count: 64))", "acento": "es-419"},
           {"id": "mala/../x", "url": "https://ejemplo.com/x.bin"},
           {"id": "http", "url": "http://ejemplo.com/x.bin"},
           {"id": "em_alex", "nombre": "Alex nuevo", "url": "https://ejemplo.com/alex.bin", "genero": "hombre"}],
 "pronunciaciones": {"Spacio": "spˈasjo"}}
"""
let c = K.catalogo(Data(cat.utf8))
revisa(c.voces.contains { $0.id == "claudio_propio" && $0.nombre == "Claudio propio" }, "una voz nueva del catálogo se agrega")
revisa(!c.voces.contains { $0.id.contains("/") || $0.id == "http" }, "un id raro o un enlace sin https no")
revisa(c.voces.first { $0.id == "em_alex" }?.url == "https://ejemplo.com/alex.bin", "una del catálogo con el mismo id reemplaza a la de fábrica")
revisa(c.voces.count == K.incluidas.count + 1, "las de fábrica siguen")
revisa(c.pronunciaciones["spacio"] == "spˈasjo", "pronunciaciones del catálogo (en minúsculas)")
revisa(K.catalogo(nil).voces == K.incluidas && K.catalogo(Data("roto".utf8)).voces == K.incluidas, "sin catálogo o roto: las de fábrica")
revisa(K.incluidas.allSatisfy { $0.url.contains(K.revision) && $0.sha256?.count == 64 }, "las de fábrica: versión fija y suma de comprobación")

// MARK: - Ajustes por personaje

revisa(K.deFabrica(.claudio).voz == "em_alex" && K.deFabrica(.claudio).acento == .latino, "Claudio: em_alex, latino (provisional)")
revisa(K.deFabrica(.maricarmen).voz == "ef_dora" && K.deFabrica(.maricarmen).acento == .espana, "Maricarmen: ef_dora, de España")
revisa(K.deFabrica(.claudio).motor == .kokoro && K.deFabrica(.maricarmen).motor == .kokoro, "de fábrica, Kokoro")
let leido = K.leer(["motor": "iphone", "voz": "propia_1", "velocidad": 9, "acento": "es"], .claudio)
revisa(leido.motor == .iphone && leido.voz == "propia_1" && leido.velocidad == 1.4 && leido.acento == .espana, "se leen y la velocidad tiene tope")
revisa(K.leer(["voz": "../../etc", "motor": "otro"], .maricarmen) == K.deFabrica(.maricarmen), "lo que no sirve, de fábrica")
revisa(K.leer(K.guardar(leido), .claudio) == leido, "guardar y leer da lo mismo")

// MARK: - Cuándo cae a la voz del iPhone

let ak = K.deFabrica(.claudio)
revisa(K.usarKokoro(ak, modeloListo: true, vozLista: true, lentas: 0), "todo listo: Kokoro")
revisa(!K.usarKokoro(ak, modeloListo: false, vozLista: true, lentas: 0), "sin modelo: iPhone")
revisa(!K.usarKokoro(ak, modeloListo: true, vozLista: false, lentas: 0), "sin la voz: iPhone")
revisa(!K.usarKokoro(ak, modeloListo: true, vozLista: true, lentas: K.maxLentas), "lento en esta conversación: iPhone")
var ai = ak; ai.motor = .iphone
revisa(!K.usarKokoro(ai, modeloListo: true, vozLista: true, lentas: 0), "eligió el iPhone: iPhone")
revisa(K.limite(primeraFrase: true, enCola: 10) == K.primera, "la primera frase espera lo mismo siempre")
revisa(K.limite(primeraFrase: false, enCola: 6) == 7 && K.limite(primeraFrase: false, enCola: 0) == K.primera, "las demás: lo que falta por sonar + un respiro")
revisa(K.lenta(segundos: 3, audio: 2) && !K.lenta(segundos: 1, audio: 2) && K.lenta(segundos: 0.1, audio: 0), "lenta si tarda más de lo que dura")
let ahora = Date()
revisa(K.finCola(nil, ahora: ahora, dura: 2) == ahora.addingTimeInterval(2), "cola vacía: suena desde ahora")
revisa(K.finCola(ahora.addingTimeInterval(3), ahora: ahora, dura: 2) == ahora.addingTimeInterval(5), "con cola: se suma al final")
revisa(K.finCola(ahora.addingTimeInterval(-3), ahora: ahora, dura: 2) == ahora.addingTimeInterval(2), "la cola ya sonó: desde ahora")

// MARK: - El audio

let a24 = K.pcm16([0, 0.5, -1, 2], a: 24000)
let m = a24.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
revisa(m == [0, 16383, -32767, 32767], "a 24 kHz: tal cual y sin pasarse de 1")
revisa(K.pcm16([Float](repeating: 0.1, count: 2400), a: 16000).count == 1600 * 2, "a 16 kHz: dos tercios de muestras")
revisa(K.trozos(Data(count: 30000), hz: 24000).map { $0.count } == [12000, 12000, 6000], "trozos de un cuarto de segundo")
let w = K.wav(Data(count: 100), hz: 24000)
revisa(w.count == 144 && w.prefix(4) == Data("RIFF".utf8), "el WAV de la prueba: 44 de cabecera")
revisa(K.descripcion(ak, usa: true) == "Kokoro · em_alex · latino" && K.descripcion(ai, usa: true) == "voz del iPhone", "lo que se anota")

print(fallos == 0 ? "\nTodo bien." : "\n\(fallos) fallos.")
exit(fallos == 0 ? 0 : 1)
