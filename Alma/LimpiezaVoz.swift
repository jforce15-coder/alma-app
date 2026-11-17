import Foundation

/* Limpieza de la voz en vivo (Juan, 17-nov-2026: «como Adobe Enhance pero en vivo»): lo que dices en la llamada con Alma
   pasa por aquí antes de salir hacia ElevenLabs. iOS ya quita el eco y algo de ruido (la cancelación de eco); esto suma
   tres pasos, en el teléfono y sin internet, cada 10 ms:
   1. Filtro de graves: quita lo que está por debajo de la voz (el aire acondicionado, el carro, el golpe al micrófono).
   2. Compuerta suave: aprende cuánto ruido de fondo hay y, cuando no hablas, lo baja (no lo corta en seco: tu voz no
      pierde el principio ni el final de las palabras).
   3. Volumen automático: si hablas bajito o lejos, sube tu voz hasta un nivel parejo; un limitador evita que se sature.
   Mientras suena Alma (su eco) o la señal de la llamada no aprende nada: solo aplica lo que ya sabía.
   Solo usa Foundation: se prueba sola (Pruebas/LimpiezaVoz). */
final class LimpiezaVoz {
    static let corteGraves: Float = 90          // Hz: la voz de Juan empieza más arriba
    static let nivelObjetivo: Float = 0.08      // RMS al que se lleva la voz
    static let gananciaMaxima: Float = 6        // +15,6 dB como mucho: más subiría el ruido
    static let pisoCompuerta: Float = 0.15      // −16,5 dB al ruido cuando no hablas (no silencio total)
    static let margenVoz: Float = 2.5           // voz = 2,5 veces más fuerte que el ruido de fondo (+8 dB)
    static let vozMinima: Float = 0.003         // por debajo de esto nunca es voz
    static let ventanaRuido = 200               // bloques de 10 ms (2 s) para aprender el ruido de fondo
    static let sosten = 25                      // bloques de 10 ms que la compuerta sigue abierta tras la voz (250 ms)

    let frecuencia: Double
    private let bloque: Int
    // Filtro de graves (biquad Butterworth de 2.º orden)
    private let b0: Float, b1: Float, b2: Float, a1: Float, a2: Float
    private var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0
    private(set) var ruido: Float = 0.002       // ruido de fondo aprendido (RMS)
    private(set) var nivelVoz: Float = nivelObjetivo
    private(set) var ganancia: Float = 1        // volumen automático
    private(set) var compuerta: Float = 1
    private(set) var esVoz = false
    private var abierta = 0                     // bloques que le quedan abiertos a la compuerta
    private var historial: [Float] = []         // el nivel de cada bloque de los últimos 2 s
    private var pos = 0
    private var energia: Float = 0, medidas = 0  // el bloque de 10 ms que se está midiendo
    private var gAntes: Float = 1, gAhora: Float = 1

    init(frecuencia: Double) {
        let sr = frecuencia > 0 ? frecuencia : 48000
        self.frecuencia = sr
        bloque = max(32, Int(sr / 100))
        let w = 2 * Double.pi * Double(LimpiezaVoz.corteGraves) / sr, cw = cos(w), alfa = sin(w) / (2 * 0.7071)
        let a0 = 1 + alfa
        b0 = Float((1 + cw) / 2 / a0); b1 = Float(-(1 + cw) / a0); b2 = b0
        a1 = Float(-2 * cw / a0); a2 = Float((1 - alfa) / a0)
    }

    /// Limpia `cuenta` muestras en su lugar. `aprender` = false mientras suena Alma o la señal: no toca lo aprendido.
    /// Mide en bloques de 10 ms exactos aunque el micrófono entregue pedazos de otro tamaño (lo que sobra sigue en el
    /// siguiente pedazo); lo que decide un bloque se aplica en el siguiente, con una rampa para que no haya chasquidos.
    func limpiar(_ x: UnsafeMutablePointer<Float>, cuenta n: Int, aprender: Bool = true) {
        for k in 0..<max(0, n) {
            // 1. Graves fuera
            var v = x[k]; if !v.isFinite { v = 0 }
            let y = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = v; y2 = y1; y1 = y.isFinite ? y : 0
            energia += y1 * y1; medidas += 1
            // La compuerta y el volumen, en rampa de lo de antes a lo nuevo; al final el limitador.
            let g = gAntes + (gAhora - gAntes) * min(1, Float(medidas) / Float(bloque))
            x[k] = LimpiezaVoz.limitar(y1 * g)
            if medidas >= bloque { decidir(rms: (energia / Float(medidas)).squareRoot(), aprender: aprender); energia = 0; medidas = 0 }
        }
    }

    /// Lo mismo sobre un arreglo (para las pruebas).
    func limpiar(_ a: inout [Float], aprender: Bool = true) {
        let n = a.count
        a.withUnsafeMutableBufferPointer { p in if let b = p.baseAddress { limpiar(b, cuenta: n, aprender: aprender) } }
    }

    private func decidir(rms: Float, aprender: Bool) {
        // 2. ¿Es voz o ruido de fondo?
        if aprender {
            /* El ruido de fondo es lo más bajo que se oyó en los últimos 2 s (entre palabras siempre hay huecos): un ruido
               nuevo y parejo (el aire, la calle) se aprende en 2 s, y la voz, que sube y baja, nunca se vuelve «ruido». */
            if historial.count < LimpiezaVoz.ventanaRuido { historial.append(rms) } else { historial[pos] = rms }
            pos = (pos + 1) % LimpiezaVoz.ventanaRuido
            let minimo = (historial.min() ?? rms) * 1.2   // el mínimo queda un poco bajo del promedio del ruido
            ruido += (minimo - ruido) * (minimo < ruido ? 0.5 : 0.1)
            ruido = min(max(ruido, 0.0001), 0.2)
        }
        esVoz = rms > LimpiezaVoz.vozMinima && rms > ruido * LimpiezaVoz.margenVoz
        if esVoz { abierta = LimpiezaVoz.sosten } else if abierta > 0 { abierta -= 1 }
        let metaCompuerta: Float = abierta > 0 ? 1 : LimpiezaVoz.pisoCompuerta
        compuerta += (metaCompuerta - compuerta) * (metaCompuerta > compuerta ? 0.6 : 0.08)   // abre rápido, cierra suave
        // 3. Volumen automático: solo aprende de la voz, nunca del ruido ni del eco de Alma
        if aprender && esVoz { nivelVoz = nivelVoz * 0.92 + rms * 0.08 }
        let metaGanancia = min(max(LimpiezaVoz.nivelObjetivo / max(nivelVoz, 0.0001), 1), LimpiezaVoz.gananciaMaxima)
        ganancia += (metaGanancia - ganancia) * 0.05
        gAntes = gAhora; gAhora = compuerta * ganancia
    }

    /// Limitador suave: hasta 0,9 pasa igual; arriba se curva y nunca llega a 1 (sin saturar).
    static func limitar(_ v: Float) -> Float {
        let a = abs(v)
        guard a > 0.9 else { return v }
        let c = 0.9 + 0.0999 * Float(tanh(Double((a - 0.9) / 0.1)))
        return v < 0 ? -c : c
    }

    /// Para el registro de la llamada.
    var resumen: String {
        String(format: "ruido %.0f dB · volumen ×%.1f", 20 * log10(Double(max(ruido, 0.00001))), Double(ganancia))
    }
}
