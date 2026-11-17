// Pruebas de la limpieza de la voz en vivo (Alma/LimpiezaVoz.swift; Juan, 17-nov-2026: «como Adobe Enhance pero en vivo»).
//   swiftc Alma/LimpiezaVoz.swift Pruebas/LimpiezaVoz/main.swift -o /tmp/limpieza-voz && /tmp/limpieza-voz
// Las corre el robot en cada PR (testflight.yml, «Probar la limpieza de la voz»). Señales de prueba sintéticas.
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}
let sr = 48000.0
var semilla: UInt64 = 7
func azar() -> Float { semilla = semilla &* 6364136223846793005 &+ 1442695040888963407; return Float(Int64(bitPattern: semilla >> 11) % 2000) / 1000 - 1 }
func rms(_ a: ArraySlice<Float>) -> Float { (a.reduce(0) { $0 + $1 * $1 } / Float(max(1, a.count))).squareRoot() }
func tono(_ hz: Double, _ amp: Float, _ seg: Double, desde: Int = 0) -> [Float] {
    (0..<Int(seg * sr)).map { amp * Float(sin(2 * Double.pi * hz * Double($0 + desde) / sr)) }
}
func ruido(_ amp: Float, _ seg: Double) -> [Float] { (0..<Int(seg * sr)).map { _ in amp * azar() } }
/// Como se habla: sílabas de 0,4 s con huecos de 0,15 s (la voz sube y baja; un ruido parejo no).
func habla(_ amp: Float, _ seg: Double) -> [Float] {
    (0..<Int(seg * sr)).map { (Double($0) / sr).truncatingRemainder(dividingBy: 0.55) < 0.4 ? amp * Float(sin(2 * Double.pi * 220 * Double($0) / sr)) : 0 }
}
func mas(_ a: [Float], _ b: [Float]) -> [Float] { zip(a, b).map { $0 + $1 } }
/// Pasa la señal en pedazos de 2048 como el micrófono.
func pasar(_ l: LimpiezaVoz, _ s: [Float], aprender: Bool = true) -> [Float] {
    var out: [Float] = []; var i = 0
    while i < s.count { var p = Array(s[i..<min(i + 2048, s.count)]); l.limpiar(&p, aprender: aprender); out += p; i += 2048 }
    return out
}

// MARK: - Graves fuera

do {
    let l = LimpiezaVoz(frecuencia: sr), zumbido = tono(50, 0.2, 4)
    let o = pasar(l, zumbido)
    revisa(rms(o[Int(3 * sr)...]) < rms(zumbido[Int(3 * sr)...]) * 0.3, "un zumbido de 50 Hz (aire, carro) baja a menos de un tercio")
}

// MARK: - Ruido de fondo abajo cuando no hablas; tu voz pasa

do {
    let l = LimpiezaVoz(frecuencia: sr)
    let fondo = ruido(0.01, 3)
    let o = pasar(l, fondo)
    revisa(rms(o[Int(2 * sr)...]) < rms(fondo[Int(2 * sr)...]) * 0.4, "tras 2 s de solo ruido, el ruido sale a menos del 40 % (−8 dB o más)")
    let voz = mas(habla(0.08, 2), ruido(0.01, 2))
    let ov = pasar(l, voz)
    revisa(rms(ov[Int(0.3 * sr)...]) > rms(voz[Int(0.3 * sr)...]) * 0.8, "cuando hablas encima del ruido, tu voz pasa entera")
    let a = Int(0.03 * sr), b = Int(0.06 * sr)
    revisa(rms(ov[a..<b]) > rms(voz[a..<b]) * 0.6, "la compuerta abre rápido: a los 30 ms la palabra ya pasa")
}

// MARK: - Hablas bajito: sube; hablas fuerte: no satura

do {
    let l = LimpiezaVoz(frecuencia: sr)
    _ = pasar(l, ruido(0.001, 1))   // un cuarto callado
    let bajito = mas(habla(0.015, 6), ruido(0.001, 6))
    let o = pasar(l, bajito)
    revisa(rms(o[Int(4 * sr)...]) > rms(bajito[Int(4 * sr)...]) * 2.5, "voz bajita (lejos del teléfono): sale más del doble de fuerte")
    revisa(l.ganancia <= LimpiezaVoz.gananciaMaxima + 0.001, "el volumen automático no pasa de ×\(LimpiezaVoz.gananciaMaxima)")
    let fuerte = pasar(LimpiezaVoz(frecuencia: sr), tono(300, 1.5, 1))
    revisa(fuerte.allSatisfy { abs($0) < 1 }, "un grito (o un golpe) nunca pasa de 1: no se satura")
    let normal = habla(0.12, 4), on = pasar(LimpiezaVoz(frecuencia: sr), normal)
    let rn = rms(on[Int(2 * sr)...]) / rms(normal[Int(2 * sr)...])
    revisa(rn > 0.8 && rn < 1.3, "una voz normal casi no cambia")
}

// MARK: - El eco de Alma no se aprende

do {
    let l = LimpiezaVoz(frecuencia: sr)
    _ = pasar(l, ruido(0.002, 1))
    let ruidoAntes = l.ruido, vozAntes = l.nivelVoz
    _ = pasar(l, ruido(0.05, 2), aprender: false)
    revisa(l.ruido == ruidoAntes && l.nivelVoz == vozAntes, "mientras suena Alma no aprende ni ruido ni nivel de voz")
}

// MARK: - Nada raro

do {
    let l = LimpiezaVoz(frecuencia: sr)
    var raro: [Float] = [.nan, .infinity, -.infinity, 0, 0.5]; l.limpiar(&raro)
    revisa(raro.allSatisfy { $0.isFinite }, "un dato inválido del micrófono no rompe nada (sale silencio)")
    var vacio: [Float] = []; l.limpiar(&vacio)
    revisa(vacio.isEmpty, "un pedazo vacío no truena")
    var silencio = [Float](repeating: 0, count: 4800); LimpiezaVoz(frecuencia: sr).limpiar(&silencio)
    revisa(silencio.allSatisfy { $0 == 0 }, "silencio entra, silencio sale")
    revisa(LimpiezaVoz(frecuencia: 0).frecuencia == 48000, "sin frecuencia del micrófono usa 48 kHz")
    revisa(LimpiezaVoz.limitar(0.5) == 0.5 && LimpiezaVoz.limitar(-3) > -1, "el limitador deja igual lo normal y frena lo fuerte")
}

print(fallos == 0 ? "\nTodo bien." : "\n\(fallos) fallo(s).")
exit(fallos == 0 ? 0 : 1)
