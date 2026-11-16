// Pruebas de la parte pura del diagnóstico del anillo por Bluetooth (Alma/DiagnosticoAnilloPuro.swift).
//   swiftc Alma/DiagnosticoAnilloPuro.swift Pruebas/DiagnosticoAnillo/main.swift -o /tmp/diagnostico-anillo && /tmp/diagnostico-anillo
// Las corre el robot en cada PR (testflight.yml, «Probar el diagnóstico del anillo»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}
typealias D = DiagAnillo

// MARK: - UUID

revisa(D.corto("0000180F-0000-1000-8000-00805F9B34FB") == "180F", "un UUID de la base SIG se ve corto (180F)")
revisa(D.corto("6e40fff0-b5a3-f393-e0a9-e50e24dcca9e") == "6E40FFF0-B5A3-F393-E0A9-E50E24DCCA9E", "uno propio se ve completo")
revisa(!D.esPropio("180F") && !D.esPropio("1812") && !D.esPropio("180A"), "batería, HID e información son estándar")
revisa(D.esPropio("FFF0") && D.esPropio("FEE7"), "16 bits de fabricante (FE00–FFFF) son propios")
revisa(D.esPropio("6E40FFF0-B5A3-F393-E0A9-E50E24DCCA9E"), "128 bits fuera de la base SIG es propio")
revisa(D.nombreServicio("1812") == "Teclado o control (HID)" && D.nombreServicio("FFF0") == "Propio del fabricante", "nombres de servicio en simple")

// MARK: - Bytes

revisa(D.hex([0x01, 0xA0, 0xFF]) == "01a0ff", "bytes en hex")
revisa(D.hex([UInt8](repeating: 0xAB, count: 100)).count == D.maxHex, "un dato largo se corta a 32 bytes")
revisa(D.hexEspaciado("01a0ff") == "01 a0 ff", "hex con espacios para la pantalla")
revisa(D.texto(Array("COLMI".utf8) + [0]) == "COLMI", "fabricante en texto, sin el cero del final")
revisa(D.texto([0x01, 0x02]) == nil, "bytes que no son texto no se leen como texto")

// MARK: - Sin datos personales

revisa(D.nombreSeguro("iPhone de Juan") == D.quitado, "«iPhone de Juan»: se quita")
revisa(D.nombreSeguro("Juan's Ring") == D.quitado, "«Juan's Ring»: se quita")
revisa(D.nombreSeguro("Ana") == D.quitado, "un nombre suelto («Ana»): se quita")
revisa(D.nombreSeguro("Juan Pérez") == D.quitado, "nombre y apellido: se quita")
revisa(D.nombreSeguro("50212345678") == D.quitado, "un número de teléfono: se quita")
revisa(D.nombreSeguro("COLMI R02_1A2B") == "COLMI R02_1A2B", "el modelo del anillo se queda")
revisa(D.nombreSeguro("Smart Ring") == "Smart Ring" && D.nombreSeguro("QRing") == "QRing", "«Smart Ring» y «QRing» se quedan")
revisa(D.nombreSeguro("R11") == "R11", "un código de modelo se queda")
revisa(D.limpio("Hecho por ana@x.com +502 5555 1234") == "Hecho por (correo) (número)", "correo y teléfono fuera del fabricante")

// MARK: - Qué es este anillo

let hid = [D.Servicio(uuid: "180F", caracteristicas: [D.Caracteristica(uuid: "2A19", props: ["read", "notify"])]),
           D.Servicio(uuid: "180A", caracteristicas: [D.Caracteristica(uuid: "2A29", props: ["read"])])]
revisa(D.veredicto(hid, porHID: true) == .soloHID, "solo batería e información y vino por HID: solo teclado")
revisa(D.textoVeredicto(.soloHID, hid, porHID: true) == "Este anillo solo habla como teclado; iOS no deja leerlo directo.", "lo dice claro")
revisa(D.veredicto([], porHID: true) == .soloHID, "sin servicios a la vista pero conectado como teclado: solo teclado")
revisa(D.veredicto(hid, porHID: false) == .estandar, "solo servicios comunes, sin HID: estándar")
revisa(D.veredicto([], porHID: false) == .nada, "nada de nada: no se encontró")
let propio = hid + [D.Servicio(uuid: "6E40FFF0-B5A3-F393-E0A9-E50E24DCCA9E", caracteristicas: [D.Caracteristica(uuid: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E", props: ["notify"])])]
revisa(D.veredicto(propio, porHID: true) == .propio, "con un servicio propio: se puede leer (aunque también sea teclado)")
let tp = D.textoVeredicto(.propio, propio, porHID: true)
revisa(tp.contains("6E40FFF0") && tp.contains("teclado") && tp.contains("Toca el anillo"), "el texto nombra el servicio propio y la parte de teclado")

// MARK: - Marcas

let evs = [D.Evento(t: 2.1, servicio: "FFF0", caracteristica: "FFF7", hex: "01")]
let mks = [D.Marca(t: 1.5, gesto: "1 toque"), D.Marca(t: 10, gesto: "2 toques")]
revisa(D.marcasSinDatos(mks, evs) == 1, "una marca sin datos en 3 s se cuenta (el gesto no llegó por Bluetooth)")

// MARK: - El registro y el recorte

var disp = D.Dispositivo(); disp.nombre = "iPhone de Juan"; disp.fabricante = "COLMI"; disp.modelo = "R02"; disp.porHID = true
let muchos = (0..<2000).map { D.Evento(t: Double($0) * 0.1, servicio: "FFF0", caracteristica: "FFF7", hex: "0102030405060708") }
let r = D.registro(disp, servicios: propio, eventos: muchos, marcas: mks, fecha: Date(timeIntervalSince1970: 0), app: "1.0 (1)")
let dsp = r["dispositivo"] as? [String: Any] ?? [:]
revisa(dsp["nombre"] as? String == D.quitado && dsp["fabricante"] as? String == "COLMI" && dsp["modelo"] as? String == "R02", "va sin el nombre de persona; fabricante y modelo sí")
revisa((r["veredicto"] as? [String: String])?["clave"] == "propio", "el veredicto va en el registro")
revisa((r["eventos"] as? [[String: Any]])?.count == D.maxEventos, "en el teléfono se guardan a lo mucho \(D.maxEventos) datos")
let c = D.recortar(r)
let quedan = c["eventos"] as? [[String: Any]] ?? []
revisa(D.tamano(c) <= D.maxBytes, "recortado cabe en \(D.maxBytes) bytes (dio \(D.tamano(c)))")
revisa(!quedan.isEmpty && (quedan.last?["t"] as? Double) == D.redondo(199.9), "se quedan los datos más nuevos")
revisa((c["recortados"] as? Int ?? 0) > 0, "dice cuántos se quitaron")
revisa((c["marcas"] as? [[String: Any]])?.count == 2, "las marcas se quedan siempre")
let chico = D.registro(disp, servicios: hid, eventos: evs, marcas: mks, fecha: Date(), app: "1")
revisa(D.recortar(chico)["recortados"] as? Int == 0, "uno chico no se toca")
revisa(D.senal(-55) == "Señal fuerte (-55)" && D.senal(0) == "Conectado al iPhone", "la señal en palabras")

print(fallos == 0 ? "Todo bien" : "\(fallos) fallaron")
exit(fallos == 0 ? 0 : 1)
