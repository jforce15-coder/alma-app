import Foundation

// Modo calle: la lógica pura del oído (sin micrófono, sin iOS), para poder probarla sola (Pruebas/OidoCalle).
// Juan, 3-nov-2026 (TestFlight 135, audífonos Bluetooth «Gold»): el micrófono llegaba al 1 % y el detector oyó 1 de 5
// «Alma». Por eso:
//   · GananciaCalle sube el volumen de cada trozo antes del detector y del dictado (hasta ×20, sin saturar).
//   · SegmentadorCalle encuentra voces cortas y sueltas (0,3–2,5 s, con 0,4 s de silencio antes): el respaldo.
//   · RespaldoCalle decide si una de esas voces se le pasa al dictado aunque el detector no la oyó.
//   · PistaCalle dice si el micrófono de los audífonos llega tan bajo que conviene el del iPhone.

/// Ganancia automática: lleva el volumen de la voz hacia `objetivo`, con un máximo de ×20 y un limitador que nunca
/// deja pasar de `techo` (sin recortes). El volumen de referencia sube de golpe con la voz y baja despacio (2 s) en
/// el silencio: así no se infla el ruido entre palabra y palabra al nivel de la voz.
struct GananciaCalle {
    static let objetivo: Float = 0.08      // RMS de la voz después de la ganancia
    static let maxima: Float = 20
    static let techo: Float = 0.95         // el pico más alto que sale (limitador)
    static let soltar = 2.0                // segundos: lo que tarda en volver a subir la ganancia tras una voz fuerte

    private(set) var ganancia: Float = 1   // la del último trozo
    private var referencia: Float = 0

    mutating func reiniciar() { ganancia = 1; referencia = 0 }

    /// La ganancia de un trozo (con su RMS y su pico, sin ganancia, y lo que dura). Devuelve con cuál empezar y con cuál
    /// terminar el trozo: si sube, va subiendo poco a poco dentro del trozo (sin chasquidos); si baja, baja de inmediato
    /// (un golpe de voz fuerte nunca satura).
    mutating func siguiente(rms: Float, pico: Float, seg: Double) -> (desde: Float, hasta: Float) {
        guard rms.isFinite, pico.isFinite, rms > 0, pico > 0 else { return (ganancia, ganancia) }   // mudo: nada que subir
        let caida = Float(exp(-max(seg, 0) / GananciaCalle.soltar))
        referencia = max(rms, referencia * caida)
        var g = min(GananciaCalle.maxima, max(1, GananciaCalle.objetivo / referencia))
        g = min(g, max(1, GananciaCalle.techo / pico))   // limitador: el pico de este trozo no pasa del techo
        let desde = g > ganancia ? ganancia : g
        ganancia = g
        return (desde, g)
    }

    /// Aplica la ganancia a `cuenta` muestras (cada `paso`: 1 si es un canal, n si vienen intercaladas), de `desde` a
    /// `hasta` en rampa. El recorte final es solo una red: con `siguiente` el pico ya no pasa del techo.
    static func aplicar(_ p: UnsafeMutablePointer<Float>, cuenta: Int, paso: Int = 1, desde: Float, hasta: Float) {
        guard cuenta > 0, paso > 0 else { return }
        if desde == 1, hasta == 1 { return }
        let pasoG = cuenta > 1 ? (hasta - desde) / Float(cuenta - 1) : 0
        var g = desde, i = 0
        for _ in 0..<cuenta {
            for k in 0..<paso { p[i + k] = min(1, max(-1, p[i + k] * g)) }
            i += paso; g += pasoG
        }
    }

    /// RMS y pico del primer canal (cada `paso` muestras).
    static func medir(_ p: UnsafePointer<Float>, cuenta: Int, paso: Int = 1) -> (rms: Float, pico: Float) {
        guard cuenta > 0, paso > 0 else { return (0, 0) }
        var suma: Float = 0, pico: Float = 0, i = 0
        for _ in 0..<cuenta { let x = p[i]; suma += x * x; let a = abs(x); if a > pico { pico = a }; i += paso }
        return ((suma / Float(cuenta)).squareRoot(), pico)
    }

    /// Para las pruebas: mide, decide y aplica sobre un arreglo de un canal.
    mutating func procesar(_ x: inout [Float], seg: Double) -> (desde: Float, hasta: Float) {
        let n = x.count
        var m: (rms: Float, pico: Float) = (0, 0)
        x.withUnsafeBufferPointer { b in if let p = b.baseAddress { m = GananciaCalle.medir(p, cuenta: n) } }
        let r = siguiente(rms: m.rms, pico: m.pico, seg: seg)
        x.withUnsafeMutableBufferPointer { b in if let p = b.baseAddress { GananciaCalle.aplicar(p, cuenta: n, desde: r.desde, hasta: r.hasta) } }
        return r
    }
}

/// Encuentra voces: tramos con energía sobre el ruido de fondo. Recibe el audio en cuadros cortos (~20 ms, sin ganancia)
/// y avisa cuando termina una voz (0,3 s de silencio después). La voz es «corta» (candidata para el respaldo) si duró
/// 0,3–2,5 s y antes hubo al menos 0,4 s de silencio: una palabra suelta como «Alma», no una conversación.
struct SegmentadorCalle {
    struct Voz: Equatable {
        var duracion: Double        // del primer al último cuadro con voz
        var silencioAntes: Double
        var pico: Float             // el pico más alto (sin ganancia)
        var corta: Bool
    }

    static let sobreRuido: Float = 3       // la voz es 3 veces el ruido de fondo (≈ 10 dB)
    static let minimo: Float = 0.0002      // y nunca menos que esto (−74 dB): el silencio digital no es voz
    static let cola = 0.3                  // silencio que cierra una voz (los huecos más cortos son parte de ella)
    static let silencioMinimo = 0.4
    static let duracionMinima = 0.3, duracionMaxima = 2.5

    private(set) var ruido: Float?         // el ruido de fondo (RMS)
    private var enVoz = false
    private var silencio = 0.0             // silencio desde la última voz (al reiniciar empieza en 0: hay que esperar 0,4 s)
    private var voz = Voz(duracion: 0, silencioAntes: 0, pico: 0, corta: false)
    private var hueco = 0.0

    mutating func reiniciar() { enVoz = false; silencio = 0; hueco = 0 }   // el ruido de fondo se conserva

    /// ¿Habla? Un cuadro con este RMS.
    func esVoz(_ rms: Float) -> Bool {
        guard let r = ruido else { return false }
        return rms > max(r * SegmentadorCalle.sobreRuido, SegmentadorCalle.minimo)
    }

    /// Un cuadro (RMS y pico sin ganancia, y lo que dura). Devuelve la voz que acaba de terminar, si terminó una.
    mutating func oir(rms: Float, pico: Float, seg: Double) -> Voz? {
        guard rms.isFinite, seg > 0 else { return nil }
        guard let r = ruido else { ruido = max(rms, SegmentadorCalle.minimo / SegmentadorCalle.sobreRuido); silencio += seg; return nil }
        let habla = esVoz(rms)
        // El ruido de fondo: baja rápido y sube despacio (~3 s) en el silencio; con voz, apenas (~20 s), para que un ruido
        // que no se va (un camión, el metro) termine siendo fondo y no una voz eterna.
        let lento = habla ? 20.0 : 3.0
        ruido = rms < r ? r + (rms - r) * 0.3 : r + (rms - r) * Float(min(1, seg / lento))
        if !enVoz {
            if habla { enVoz = true; voz = Voz(duracion: seg, silencioAntes: silencio, pico: pico, corta: false); hueco = 0 }
            else { silencio += seg }
            return nil
        }
        if habla {
            voz.duracion += hueco + seg; hueco = 0; voz.pico = max(voz.pico, pico)
            return nil
        }
        hueco += seg
        guard hueco >= SegmentadorCalle.cola else { return nil }
        enVoz = false; silencio = hueco; hueco = 0
        var v = voz
        v.corta = v.silencioAntes >= SegmentadorCalle.silencioMinimo
            && v.duracion >= SegmentadorCalle.duracionMinima && v.duracion <= SegmentadorCalle.duracionMaxima
        return v
    }
}

/// ¿Se le pasa al dictado una voz corta que el detector no oyó? Solo si el Modo calle espera «Alma», el dictado es en el
/// teléfono (no se manda audio a internet), el detector no se disparó con esa misma voz y pasaron al menos 2 s desde
/// que terminó la última revisión del respaldo (para no gastar batería con la calle hablando).
enum RespaldoCalle {
    static let separacion = 2.0

    /// Tiempos en segundos de un mismo reloj. `ultimoGatillo`: cuándo se disparó el detector por última vez;
    /// `finUltima`: cuándo terminó la última revisión del respaldo.
    static func revisar(_ v: SegmentadorCalle.Voz, ahora: Double, esperando: Bool, dictadoEnTelefono: Bool,
                        ultimoGatillo: Double?, finUltima: Double?) -> Bool {
        guard v.corta, esperando, dictadoEnTelefono else { return false }
        if let f = finUltima, ahora - f < separacion { return false }
        // La voz empezó hace duracion + cola: si el detector se disparó desde entonces (o un poco antes), ya la tomó él.
        if let g = ultimoGatillo, ahora - g <= v.duracion + SegmentadorCalle.cola + 1 { return false }
        return true
    }

    /// Cuántos segundos del audio guardado se le pasan al dictado: la voz, su cola y un poco antes (máximo 3 s).
    static func segundosParaDictado(_ v: SegmentadorCalle.Voz) -> Double {
        min(3, v.duracion + SegmentadorCalle.cola + 0.3)
    }
}

/// La pista del diagnóstico: con el micrófono de los audífonos, si la última voz (de 0,3 s o más, en los últimos 30 s)
/// llegó por debajo de 10 % aun con la ganancia, es mejor el micrófono del iPhone.
enum PistaCalle {
    static let texto = "El micrófono de los audífonos llega muy bajo; prueba con el del iPhone"
    static let minimo: Float = 0.1

    /// `picoVoz`: el pico de la última voz con su ganancia (nil si no hubo voz reciente).
    static func audifonosBajos(esAudifono: Bool, picoVoz: Float?) -> Bool {
        guard esAudifono, let p = picoVoz else { return false }
        return p < minimo
    }
}
