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

/// La revisión de «Alma» por el dictado (Juan, 3-nov-2026, TestFlight 142 con audífonos Bluetooth): la mitad de las veces
/// que el detector se disparó, el dictado no contestó en 3,5 s y ese «Alma» de verdad se perdía. Ahora:
///   · el dictado recibe solo los últimos segundos y se le cierra el audio enseguida (contesta lo que oyó sin esperar a
///     que la calle se calle);
///   · si el detector se disparó y el dictado no contesta a tiempo (o falla), se acepta igual: suena la señal y escucha.
///     Un falso despertar cuesta poco; un «Alma» perdido cuesta mucho. El respaldo (voces cortas que el detector no oyó)
///     sí necesita que el dictado confirme: sin eso despertaría con cada tos.
enum VerificacionCalle {
    static let plazo = 3.5

    /// En qué va el dictado: sigue · terminó (dio su resultado final, o dijo que no oyó voz) · falló (otro error).
    enum Fin: Equatable { case sigue, termino, fallo }
    enum Decision: Equatable { case esperar, confirmar, aceptarSinConfirmar, descartar }

    /// `oyoAlma`: algún resultado trae «Alma». `oyoOtraCosa`: el dictado ya dio palabras, sin «Alma». `lleva`: segundos
    /// desde que el dictado recibió el audio.
    static func decidir(oyoAlma: Bool, oyoOtraCosa: Bool, fin: Fin, porRespaldo: Bool, lleva: Double) -> Decision {
        if oyoAlma { return .confirmar }
        if fin == .termino { return .descartar }               // contestó, y no era «Alma»
        guard fin == .fallo || lleva > plazo else { return .esperar }
        if oyoOtraCosa && fin != .fallo { return .descartar }  // contestó otras palabras: no era «Alma»
        return porRespaldo ? .descartar : .aceptarSinConfirmar  // dictado lento o con error
    }
}

/// Cuánto tarda el dictado en dar su primer resultado al revisar «Alma» (ms), para el diagnóstico.
struct LatenciaCalle {
    private(set) var ultima: Int?
    private(set) var cuenta = 0, suma = 0, lentas = 0

    mutating func anotar(ms: Int) { ultima = max(0, ms); cuenta += 1; suma += max(0, ms) }
    /// No contestó a tiempo (cuenta aparte: no entra en la media).
    mutating func anotarLenta() { lentas += 1 }
    var media: Int? { cuenta > 0 ? Int((Double(suma) / Double(cuenta)).rounded()) : nil }

    /// «el dictado tarda 640 ms (media 700 ms de 3) · 1 sin contestar a tiempo»
    var texto: String {
        var t: String
        if let u = ultima, let m = media { t = "el dictado tarda \(u) ms" + (cuenta > 1 ? " (media \(m) ms de \(cuenta))" : "") }
        else { t = "el dictado todavía no contestó ninguna revisión" }
        if lentas > 0 { t += " · \(lentas) sin contestar a tiempo" }
        return t
    }
}

/// La frase que sigue a «Alma» (Juan, 3-nov-2026: «Sonó la señal, pero no oí un pedido»). El dictado de la frase empieza
/// con el audio guardado desde un poco antes de que se disparó el detector: así «Alma, anota pan» dicho de corrido se toma
/// entero aunque la señal suene encima, y la señal no se come el principio. Sin pedido, se espera `espera` s desde la señal.
enum PedidoCalle {
    static let antesDelGatillo = 0.25   // segundos de audio antes del gatillo (el final de «Alma» no estorba: se quita)
    static let espera = 6.0             // sin pedido, se rinde a los 6 s de la señal (al menos 5, decisión de Juan)
    static let esperaAviso = 8.0
    static let pausa = 1.2              // con pedido, la pausa que lo cierra
    static let maximo = 12.0

    /// Qué hacer cada vuelta: `pide` es lo que lleva el pedido (vacío si nada), `quieto` los segundos sin cambios del
    /// dictado y `lleva` los segundos desde la señal.
    enum Paso: Equatable { case sigue, mandar, rendirse }
    static func paso(pide: String, quieto: Double, lleva: Double, cerro: Bool, aviso: Bool) -> Paso {
        if !pide.isEmpty { return quieto > pausa || cerro || lleva > maximo ? .mandar : .sigue }
        return lleva > (aviso ? esperaAviso : espera) || cerro ? .rendirse : .sigue
    }

    /// El pedido sin la cola de «Alma» que se cuela al empezar un poco antes del gatillo («ma, anota pan» → «anota pan»).
    /// `despuesDeAlma`: lo que sigue a «Alma» si el dictado la oyó (Conferencia.pedidoAAlma); si no, el texto entero.
    static func limpiar(_ texto: String, despuesDeAlma: String?) -> String {
        let borde = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        var s = (despuesDeAlma ?? texto).trimmingCharacters(in: borde)
        let l = s.lowercased()
        for p in ["alma", "halma", "ma"] where l == p || l.hasPrefix(p + " ") || l.hasPrefix(p + ",") || l.hasPrefix(p + ".") {
            s = String(s.dropFirst(p.count)).trimmingCharacters(in: borde); break
        }
        return s.count < 2 ? "" : s
    }

    /// Los trozos que van al dictado de la frase: los que terminaron después de `desde` (tiempos de un mismo reloj).
    static func desde<T>(_ trozos: [(cuando: Double, trozo: T)], _ desde: Double) -> [T] {
        trozos.filter { $0.cuando > desde }.map { $0.trozo }
    }
}

/// El botón del caminante (Juan, 4-nov-2026: «el botón no llama a Alma»; antes un toque encendía o apagaba el Modo calle y,
/// si Alma estaba pensando, apagarlo tiraba la respuesta). Ahora un toque y Alma escucha ya, sin decir «Alma», con el Modo
/// calle encendido o apagado (apagado: escucha una vez y no lo deja encendido). Qué hacer según la fase del Modo calle.
enum BotonCalle {
    /// escuchar: abre la escucha ya · cortarYEscuchar: deja lo de ahora (lo que oía, la respuesta que esperaba o lo que
    /// decía) y escucha · nada: en llamada (la llamada ya escucha).
    enum Accion: Equatable { case escuchar, cortarYEscuchar, nada }
    /// `fase`: ModoCalle.Fase.rawValue.
    static func decidir(fase: String) -> Accion {
        switch fase {
        case "verificando", "oyendo", "pensando", "hablando": return .cortarYEscuchar
        case "llamada": return .nada
        default: return .escuchar   // quieta, esperando, pausa
        }
    }
}

/// Nunca en silencio (Juan, 4-nov-2026: «me reconoce y no me responde nada»): después de oír un pedido, si no llega
/// respuesta del Hub en `plazo` segundos, Alma dice `frase` (con su voz si ya la tiene guardada; si no, la del iPhone) y
/// el porqué queda en el diagnóstico. El Hub corta a los 15 s («Sigo en eso…») y deja de pedir el audio a los 20 s.
enum EsperaCalle {
    static let plazo = 25.0
    static let frase = "No me llegó la respuesta, ¿me lo repites?"
    /// El porqué, para el diagnóstico: el error de la red si lo hubo; si no, cuánto se esperó.
    static func motivo(red: String?, segundos: Double) -> String {
        if let r = red?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty { return "el Hub no contestó (" + r + ")" }
        return "el Hub no contestó en \(Int(segundos.rounded())) s"
    }
}
