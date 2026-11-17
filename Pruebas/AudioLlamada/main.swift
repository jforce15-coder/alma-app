import Foundation

// Prueba del audio de la llamada (Juan, 17-nov-2026): con el Modo compañero, el micrófono del teléfono de fábrica; lo que
// Juan elige manda; si lo elegido no está, lo automático (AudioLlamadaReglas.swift).
var fallos = 0
func revisa(_ c: Bool, _ m: String) { print((c ? "✓ " : "✗ ") + m); if !c { fallos += 1 } }
typealias R = AudioLlamadaReglas
let propio = R.Puerto(tipo: "MicrophoneBuiltIn", nombre: "Micrófono del iPhone")
let airpods = R.Puerto(tipo: "BluetoothHFP", nombre: "AirPods de Juan")
let lentes = R.Puerto(tipo: "BluetoothHFP", nombre: "AURA 2")
let hay = [propio, airpods, lentes]
let hoy = Date()

revisa(R.entrada(preferencia: nil, companero: false, disponibles: hay) == nil, "sin compañero y en automático, iOS decide como antes")
revisa(R.entrada(preferencia: nil, companero: true, disponibles: hay) == propio, "con el Modo compañero, el micrófono del teléfono aunque haya audífonos")
revisa(R.entrada(preferencia: "auto", companero: true, disponibles: [airpods]) == nil, "si el teléfono no da su micrófono, no se pide nada")
revisa(R.entrada(preferencia: R.guardar(lentes), companero: true, disponibles: hay) == lentes, "lo que elige Juan manda, también con compañero")
revisa(R.entrada(preferencia: R.guardar(airpods), companero: false, disponibles: hay) == airpods, "y sin compañero")
revisa(R.entrada(preferencia: R.guardar(airpods), companero: true, disponibles: [propio, lentes]) == propio, "si lo elegido no está conectado, lo automático (con compañero, el teléfono)")
revisa(R.entrada(preferencia: R.guardar(airpods), companero: false, disponibles: [propio]) == nil, "y sin compañero, iOS decide")
revisa(R.entrada(preferencia: "telefono", companero: false, disponibles: hay) == propio, "«Este iPhone» siempre usa el micrófono del teléfono")
revisa(R.guardar(propio) == "telefono" && R.guardar(lentes) == "BluetoothHFP|AURA 2", "se guarda por tipo y nombre")
let otroPerfil = R.Puerto(tipo: "BluetoothLEOutput", nombre: "AURA 2")
revisa(R.entrada(preferencia: R.guardar(lentes), companero: false, disponibles: [propio, otroPerfil]) == otroPerfil, "el mismo aparato con otro perfil se reconoce por el nombre")
revisa(R.elegida(nil, preferencia: nil) && !R.elegida(propio, preferencia: nil), "de fábrica, «Automático» lleva la palomita")
revisa(R.elegida(lentes, preferencia: "BluetoothHFP|AURA 2") && !R.elegida(airpods, preferencia: "BluetoothHFP|AURA 2"), "la palomita va en lo elegido")

revisa(R.companeroActivo(ahora: true, ultimoVisto: nil, hoy: hoy), "el Hub dice que mira: activo")
revisa(!R.companeroActivo(ahora: false, ultimoVisto: hoy, hoy: hoy), "el Hub dice que no mira: no, aunque lo hiciera hace poco")
revisa(R.companeroActivo(ahora: nil, ultimoVisto: hoy.addingTimeInterval(-120), hoy: hoy), "antes del primer aviso, si miró hace 2 min: activo")
revisa(!R.companeroActivo(ahora: nil, ultimoVisto: hoy.addingTimeInterval(-3600), hoy: hoy), "si miró hace una hora: no")
revisa(!R.companeroActivo(ahora: nil, ultimoVisto: nil, hoy: hoy), "nunca miró: no")

revisa(R.clase(lentes, lentes: true) == .lentes, "los lentes se ven como lentes")
revisa(R.clase(airpods, lentes: false) == .audifonos, "los AirPods, como audífonos")
revisa(R.clase(R.Puerto(tipo: "BluetoothA2DPOutput", nombre: "JBL Flip 6"), lentes: false) == .bocina, "una salida Bluetooth sin nombre de audífonos, como bocina")
revisa(R.clase(R.Puerto(tipo: "CarAudio", nombre: "CarPlay"), lentes: false) == .carro, "el carro, como carro")
revisa(R.clase(propio, lentes: false) == .dispositivo, "el micrófono del teléfono, como el dispositivo")
revisa(R.bocinaFija("telefono") && !R.bocinaFija(nil) && !R.bocinaFija("auto"), "la bocina fija solo si Juan la eligió")
revisa(R.explicaAutomatico(companero: true, dispositivo: "iPhone").contains("este iPhone"), "en automático con compañero se dice que usa el teléfono")

print(fallos == 0 ? "Todo bien" : "\(fallos) fallos")
exit(fallos == 0 ? 0 : 1)
