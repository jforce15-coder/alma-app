// Pruebas de la lógica pura del oído del Modo calle (Alma/OidoCalle.swift). Corren solas, sin iOS:
//   swiftc Alma/OidoCalle.swift Pruebas/OidoCalle/main.swift -o /tmp/oido && /tmp/oido
// Las corre el robot en cada PR (testflight.yml, «Probar el oído del Modo calle»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}

let tasa = 16000.0
/// Un trozo de seno (una voz de mentira) de `seg` segundos con esta amplitud.
func seno(_ amp: Float, seg: Double, hz: Double = 220) -> [Float] {
    (0..<Int(seg * tasa)).map { amp * Float(sin(2 * Double.pi * hz * Double($0) / tasa)) }
}
func pico(_ x: [Float]) -> Float { x.map { abs($0) }.max() ?? 0 }
func rms(_ x: [Float]) -> Float { (x.reduce(0) { $0 + $1 * $1 } / Float(max(1, x.count))).squareRoot() }

// MARK: - Ganancia

do {
    // Lo de Juan: audífonos Bluetooth, la voz al 1 % (pico 0,01). Trozos de 256 ms (4096 a 16 kHz).
    var g = GananciaCalle()
    var ultimo: [Float] = []
    for _ in 0..<8 { var t = seno(0.01, seg: 0.256); _ = g.procesar(&t, seg: 0.256); ultimo = t }
    revisa(g.ganancia > 10, "voz al 1 %: la ganancia sube (×\(g.ganancia))")
    revisa(pico(ultimo) > 0.1 && pico(ultimo) <= GananciaCalle.techo, "voz al 1 %: después llega a \(Int(pico(ultimo) * 100)) %, sin saturar")
    revisa(abs(rms(ultimo) - GananciaCalle.objetivo) < 0.01, "voz al 1 %: el RMS llega al objetivo (\(rms(ultimo)))")
}
do {
    var g = GananciaCalle()
    for _ in 0..<8 { var t = seno(0.001, seg: 0.256); _ = g.procesar(&t, seg: 0.256) }
    revisa(g.ganancia == GananciaCalle.maxima, "voz muy baja: la ganancia no pasa de ×20 (×\(g.ganancia))")
}
do {
    var g = GananciaCalle()
    var t = seno(0.9, seg: 0.256); let antes = t
    _ = g.procesar(&t, seg: 0.256)
    revisa(g.ganancia == 1 && t == antes, "voz fuerte: no se toca (×1)")
}
do {
    // Limitador: una voz baja con un golpe fuerte en medio del trozo.
    var g = GananciaCalle()
    var t = seno(0.005, seg: 0.256); t[2000] = 0.6
    _ = g.procesar(&t, seg: 0.256)
    revisa(pico(t) <= GananciaCalle.techo + 0.0001, "golpe fuerte: el limitador no deja pasar del techo (\(pico(t)))")
}
do {
    // Después de una voz fuerte, la ganancia vuelve a subir despacio (≈ 2 s) y en rampa (sin saltos).
    var g = GananciaCalle()
    var a = seno(0.3, seg: 0.256); _ = g.procesar(&a, seg: 0.256)
    var primera: (desde: Float, hasta: Float)?, seg = 0.0
    while primera == nil, seg < 4 {
        var b = seno(0.005, seg: 0.256); let r = g.procesar(&b, seg: 0.256); seg += 0.256
        if r.hasta > 1 { primera = r }
    }
    revisa(seg >= 1.5, "no sube enseguida después de una voz fuerte (empieza a los \(seg) s)")
    if let r = primera { revisa(r.desde == 1 && r.hasta > 1 && r.hasta < 2, "sube en rampa: de ×\(r.desde) a ×\(r.hasta)") }
    else { revisa(false, "la ganancia vuelve a subir antes de 4 s") }
    let antes = g.ganancia
    var c = seno(0.3, seg: 0.256); let r2 = g.procesar(&c, seg: 0.256)
    revisa(r2.desde == r2.hasta && r2.hasta < antes && pico(c) <= GananciaCalle.techo, "baja de golpe con la voz fuerte (sin saturar)")
}
do {
    var g = GananciaCalle()
    var t = [Float](repeating: 0, count: 4096)
    _ = g.procesar(&t, seg: 0.256)
    revisa(t.allSatisfy { $0 == 0 } && g.ganancia == 1, "micrófono mudo: sigue en cero (el vigía lo nota)")
}
do {
    // Intercalado (2 canales): las dos muestras de cada cuadro reciben la misma ganancia.
    var x: [Float] = [0.1, 0.2, 0.1, 0.2]
    x.withUnsafeMutableBufferPointer { GananciaCalle.aplicar($0.baseAddress!, cuenta: 2, paso: 2, desde: 2, hasta: 2) }
    revisa(x == [0.2, 0.4, 0.2, 0.4], "intercalado: los dos canales con la misma ganancia")
    let m = x.withUnsafeBufferPointer { GananciaCalle.medir($0.baseAddress!, cuenta: 2, paso: 2) }
    revisa(abs(m.pico - 0.2) < 1e-6, "medir: solo el primer canal")
}

// MARK: - Voces cortas (respaldo)

/// Pasa audio por el segmentador en cuadros de 20 ms y junta las voces que terminaron.
func segmentar(_ s: inout SegmentadorCalle, _ partes: [(amp: Float, seg: Double)]) -> [SegmentadorCalle.Voz] {
    var voces: [SegmentadorCalle.Voz] = []
    let cuadro = 0.02
    for p in partes {
        let n = Int((p.seg / cuadro).rounded())
        for _ in 0..<n {
            let r = p.amp / Float(2).squareRoot()   // RMS de un seno
            if let v = s.oir(rms: r, pico: p.amp, seg: cuadro) { voces.append(v) }
        }
    }
    return voces
}
let ruido: Float = 0.0004, voz: Float = 0.01

do {
    var s = SegmentadorCalle()
    let v = segmentar(&s, [(ruido, 1.0), (voz, 0.6), (ruido, 0.6)])
    revisa(v.count == 1 && v[0].corta, "«Alma» suelta (0,6 s tras 1 s de silencio): voz corta")
    if let x = v.first { revisa(abs(x.duracion - 0.6) < 0.05, "dura lo que la voz (\(x.duracion) s)") }
}
do {
    var s = SegmentadorCalle()
    let v = segmentar(&s, [(ruido, 1.0), (voz, 3.0), (ruido, 0.6)])
    revisa(v.count == 1 && !v[0].corta, "3 s seguidos (una conversación): no es voz corta")
}
do {
    var s = SegmentadorCalle()
    let v = segmentar(&s, [(ruido, 1.0), (voz, 0.15), (ruido, 0.6)])
    revisa(v.allSatisfy { !$0.corta }, "un golpe de 0,15 s: no es voz corta")
}
do {
    var s = SegmentadorCalle()
    let v = segmentar(&s, [(ruido, 1.0), (voz, 1.0), (ruido, 0.32), (voz, 0.6), (ruido, 0.6)])
    revisa(v.count == 2 && v[0].corta && !v[1].corta, "sin 0,4 s de silencio antes: la segunda no cuenta")
}
do {
    var s = SegmentadorCalle()
    let v = segmentar(&s, [(ruido, 1.0), (voz, 0.3), (ruido, 0.1), (voz, 0.3), (ruido, 0.6)])
    revisa(v.count == 1 && v[0].corta && abs(v[0].duracion - 0.7) < 0.05, "«Al… ma» con un hueco de 0,1 s: una sola voz")
}
do {
    // Lo de Juan: cinco «Alma» con una pausa corta (1,2 s), al 1 %.
    var s = SegmentadorCalle()
    var partes: [(amp: Float, seg: Double)] = [(ruido, 1.0)]
    for _ in 0..<5 { partes += [(voz, 0.5), (ruido, 1.2)] }
    let v = segmentar(&s, partes)
    revisa(v.count == 5 && v.allSatisfy { $0.corta }, "cinco «Alma» con pausa: cinco voces cortas (\(v.count))")
}
do {
    // Un ruido que no se va (el metro): termina siendo fondo y no dispara voces cortas.
    var s = SegmentadorCalle()
    let v = segmentar(&s, [(ruido, 1.0), (voz, 60), (voz, 1.0)])
    revisa(v.allSatisfy { !$0.corta }, "ruido constante: nunca es voz corta")
}
do {
    var s = SegmentadorCalle()
    _ = segmentar(&s, [(ruido, 1.0)])
    s.reiniciar()
    let v = segmentar(&s, [(voz, 0.5), (ruido, 0.6)])
    revisa(v.allSatisfy { !$0.corta }, "recién vuelto a esperar: hace falta silencio antes (no la cola de la voz de Alma)")
}

// MARK: - Decidir el respaldo

do {
    let v = SegmentadorCalle.Voz(duracion: 0.6, silencioAntes: 1, pico: 0.01, corta: true)
    revisa(RespaldoCalle.revisar(v, ahora: 100, esperando: true, dictadoEnTelefono: true, ultimoGatillo: nil, finUltima: nil), "voz corta sin detector: al dictado")
    revisa(!RespaldoCalle.revisar(v, ahora: 100, esperando: true, dictadoEnTelefono: true, ultimoGatillo: 99.5, finUltima: nil), "el detector ya la oyó: no se repite")
    revisa(RespaldoCalle.revisar(v, ahora: 100, esperando: true, dictadoEnTelefono: true, ultimoGatillo: 90, finUltima: nil), "el detector se disparó hace rato: sí va")
    revisa(!RespaldoCalle.revisar(v, ahora: 100, esperando: true, dictadoEnTelefono: true, ultimoGatillo: nil, finUltima: 98.5), "menos de 2 s desde la última revisión: no")
    revisa(RespaldoCalle.revisar(v, ahora: 100, esperando: true, dictadoEnTelefono: true, ultimoGatillo: nil, finUltima: 97.9), "más de 2 s: sí")
    revisa(!RespaldoCalle.revisar(v, ahora: 100, esperando: false, dictadoEnTelefono: true, ultimoGatillo: nil, finUltima: nil), "no está esperando «Alma»: no")
    revisa(!RespaldoCalle.revisar(v, ahora: 100, esperando: true, dictadoEnTelefono: false, ultimoGatillo: nil, finUltima: nil), "dictado con internet: no (no se manda audio por cada voz)")
    var larga = v; larga.corta = false
    revisa(!RespaldoCalle.revisar(larga, ahora: 100, esperando: true, dictadoEnTelefono: true, ultimoGatillo: nil, finUltima: nil), "voz larga: no")
    revisa(RespaldoCalle.segundosParaDictado(v) <= 3 && RespaldoCalle.segundosParaDictado(v) >= v.duracion + SegmentadorCalle.cola, "al dictado va la voz entera, sin pasar de 3 s")
}

// MARK: - La pista de los audífonos

revisa(PistaCalle.audifonosBajos(esAudifono: true, picoVoz: 0.06), "audífonos y la voz al 6 % con ganancia: pista")
revisa(!PistaCalle.audifonosBajos(esAudifono: true, picoVoz: 0.3), "audífonos y la voz al 30 %: sin pista")
revisa(!PistaCalle.audifonosBajos(esAudifono: false, picoVoz: 0.02), "micrófono del iPhone: sin pista")
revisa(!PistaCalle.audifonosBajos(esAudifono: true, picoVoz: nil), "sin voz reciente: sin pista")

print(fallos == 0 ? "Todo bien." : "\(fallos) fallaron.")
exit(fallos == 0 ? 0 : 1)
