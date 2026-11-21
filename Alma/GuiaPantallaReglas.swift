import Foundation

/// La pantalla de dos paneles de la Guía de camino (Juan, 20-nov-2026: «A teléfono, A iPad y B teléfono girado»): la
/// lógica pura, sin pantalla ni GPS, para probarla sola (Pruebas/GuiaCamino). La usa MapaCamino.swift.
///   · Distribución: en vertical, A (arriba el panel del medio, abajo el mapa, la tarjeta del giro sobre la unión); con
///     la pantalla acostada, B (lado a lado: el panel del medio a la izquierda, ~40 %, y el mapa a la derecha). En el
///     iPad acostado también B; una ventana angosta (Slide Over) se queda en A.
///   · Luz de rumbo: el cono de luz que sale de la roca hacia donde mira el teléfono. Juan: «hay que incrementar el
///     ángulo de esa luz direccional» → 90° de apertura (el prototipo tenía 64°). Sigue el rumbo suavizado, por el
///     camino corto (de 359° a 1° avanza 2°, no da la vuelta).
///   · La tarjeta del giro: «En 80 m» · «gira a la derecha en la farmacia» · «Luego, a la izquierda en la iglesia».
///   · Velocidad (km/h) y, a pie, el ritmo por km.
enum GuiaPantalla {
    // MARK: - Distribución

    enum Distribucion: Equatable {
        case dividido      // A: vertical, panel arriba y mapa abajo
        case ladoALado     // B: acostado, panel a la izquierda y mapa a la derecha
    }

    /// Ancho mínimo para poner los paneles lado a lado (un teléfono acostado mide 640 o más).
    static let anchoLadoALado: Double = 560

    static func distribucion(ancho: Double, alto: Double) -> Distribucion {
        guard ancho > alto, ancho >= anchoLadoALado else { return .dividido }
        return .ladoALado
    }

    /// Qué parte del ancho lleva el panel del medio en B.
    static let partePanel: Double = 0.4

    // MARK: - A sin hueco (Juan, 21-nov-2026: «demasiado espacio muerto arriba»)

    /// Los cortes de A, de arriba abajo, sin hueco: la tarjeta del giro pegada al área segura, debajo el panel del medio
    /// (~40 % de lo que queda) y el mapa hasta abajo (~60 %), con la llegada encima del mapa.
    struct CortesA: Equatable {
        var tarjetaY: Double     // arriba de la tarjeta del giro
        var panelY: Double, panelAlto: Double
        var mapaY: Double, mapaAlto: Double
    }

    /// Qué parte de lo que queda (debajo de la tarjeta) lleva el panel del medio en A; el resto es del mapa.
    static let partePanelA: Double = 0.4
    /// Separación entre la tarjeta y el panel.
    static let separacionA: Double = 8

    static func cortesA(alto: Double, arriba: Double, tarjeta: Double) -> CortesA {
        let y = max(0, arriba) + 6
        let panelY = y + max(0, tarjeta) + separacionA
        let resto = max(0, alto - panelY)
        let panelAlto = (resto * partePanelA).rounded()
        return CortesA(tarjetaY: y, panelY: panelY, panelAlto: panelAlto, mapaY: panelY + panelAlto, mapaAlto: max(0, alto - panelY - panelAlto))
    }

    // MARK: - El mapa: la roca al centro del área visible, mirando adelante

    /// Los bordes del mapa (lo que lo tapa o lo que se deja libre a propósito), en puntos del mapa.
    struct Bordes: Equatable {
        var arriba: Double, izquierda: Double, abajo: Double, derecha: Double
    }

    /// Qué tan abajo va la roca en lo que se ve del mapa (0 = arriba, 0,5 = al centro, 1 = abajo): un poco abajo del
    /// centro para que se vean las calles que siguen (el mapa va girado hacia donde vas).
    static let adelante: Double = 0.64

    /// El margen que se le pone al mapa (Google: `padding`; Apple: `safeAreaPadding`) para que el centro de la cámara —
    /// donde va la roca— quede centrado a lo ancho y un poco abajo a lo alto, dentro de lo que se ve: entre lo que tapa
    /// arriba (`tapaArriba`) y lo que tapa abajo (la llegada, `tapaAbajo`). La cámara centra en el centro del margen.
    static func margenMapa(ancho: Double, alto: Double, tapaArriba: Double, tapaAbajo: Double, derecha: Double = 0, izquierda: Double = 0, adelante f: Double = adelante) -> Bordes {
        let libre = max(0, alto - tapaArriba - tapaAbajo)
        let y = tapaArriba + libre * min(max(f, 0), 1)     // donde queremos la roca
        // El centro del margen es (arriba + alto - abajo) / 2 = y. Se sube el borde de arriba o el de abajo, nunca negativo.
        var arriba = tapaArriba, abajo = tapaAbajo
        let centro = (arriba + alto - abajo) / 2
        if y > centro { arriba += 2 * (y - centro) } else { abajo += 2 * (centro - y) }
        // A lo ancho, los dos lados iguales: la roca cae en el centro horizontal del mapa.
        let lado = max(derecha, izquierda)
        return Bordes(arriba: arriba, izquierda: lado, abajo: abajo, derecha: lado)
    }

    /// Dónde queda el centro de la cámara (la roca) en el mapa con esos bordes.
    static func centroCamara(ancho: Double, alto: Double, _ b: Bordes) -> (x: Double, y: Double) {
        ((b.izquierda + ancho - b.derecha) / 2, (b.arriba + alto - b.abajo) / 2)
    }

    // MARK: - Ver ruta

    /// La caja de la ruta entera (y tu punto) con un margen de `margen` (fracción del tamaño, mínimo ~30 m) para la vista
    /// general en 2D. nil si no hay puntos.
    struct Caja: Equatable { var sur: Double, oeste: Double, norte: Double, este: Double }

    static func cajaRuta(_ puntos: [GuiaPunto], margen: Double = 0.12) -> Caja? {
        guard let a = puntos.first else { return nil }
        var s = a.lat, n = a.lat, o = a.lng, e = a.lng
        for p in puntos.dropFirst() { s = min(s, p.lat); n = max(n, p.lat); o = min(o, p.lng); e = max(e, p.lng) }
        let dLat = max((n - s) * margen, 0.0003), dLng = max((e - o) * margen, 0.0003)
        return Caja(sur: s - dLat, oeste: o - dLng, norte: n + dLat, este: e + dLng)
    }

    /// Tras cuántos segundos sin tocar el mapa vuelve a seguir a la roca (después de «Ver ruta» o de moverlo con el dedo).
    static let volverASeguir: Double = 10

    // MARK: - La escena animada del panel del medio (Juan, 21-nov-2026)

    /// Cómo se mueve tu figura en la escena según el medio y la velocidad.
    enum Paso: Equatable {
        case quieto     // 0 km/h
        case camina     // a pie, menos de ~7 km/h
        case corre      // a pie, más rápido
        case pedalea    // en bici
        case rueda      // carro, bus, metro: el camino avanza
    }

    /// Por debajo de esto (km/h) la figura está quieta (el GPS brinca un poco aunque no te muevas).
    static let quietoKmh: Double = 0.8
    static let correKmh: Double = 7

    static func paso(medio: String, kmh: Double) -> Paso {
        guard kmh.isFinite, kmh >= quietoKmh else { return .quieto }
        switch medio {
        case "caminando": return kmh < correKmh ? .camina : .corre
        case "bici": return .pedalea
        default: return .rueda
        }
    }

    /// Ciclos de piernas por segundo (un ciclo = las dos piernas): caminar ~1 por segundo, correr más rápido, pedalear
    /// según la velocidad. 0 si está quieto o va en carro, bus o metro.
    static func cadencia(medio: String, kmh: Double) -> Double {
        switch paso(medio: medio, kmh: kmh) {
        case .quieto, .rueda: return 0
        case .camina: return min(max(kmh / 5, 0.55), 1.25)
        case .corre: return min(1.35 + (kmh - correKmh) * 0.05, 1.8)
        case .pedalea: return min(max(kmh / 15 * 1.2, 0.5), 2)
        }
    }

    /// Lo que se mueve en la escena: cuánto avanzó el camino (metros de la escena) y en qué punto del ciclo van las
    /// piernas (0…1). Se integra cuadro a cuadro: si cambia la velocidad, nada brinca.
    struct Andar: Equatable {
        var recorrido: Double = 0
        var fase: Double = 0
        var tiempo: Double = 0

        /// Avanza `dt` segundos a `kmh`. Con «Reducir movimiento» (`suave`), sin ciclo de piernas y el camino despacio.
        mutating func avanzar(dt: Double, medio: String, kmh: Double, suave: Bool) {
            guard dt.isFinite, dt > 0 else { return }
            let d = min(dt, 0.25)   // si la pantalla se pausó, no salta de golpe
            tiempo += d
            let k = GuiaPantalla.paso(medio: medio, kmh: kmh) == .quieto ? 0 : kmh / 3.6
            recorrido += d * (suave ? min(k, 1.2) * 0.3 : k)
            if recorrido > 1_000_000 { recorrido = recorrido.truncatingRemainder(dividingBy: 1200) }
            if !suave {
                fase = (fase + d * GuiaPantalla.cadencia(medio: medio, kmh: kmh)).truncatingRemainder(dividingBy: 1)
            }
        }
    }

    /// La escena se pausa (batería) si no se ve o si todo está quieto.
    static func escenaPausada(activa: Bool, kmh: Double) -> Bool {
        !activa || paso(medio: "", kmh: kmh) == .quieto
    }

    /// Un número dentro de 0..<largo (para que lo que pasa de largo vuelva a aparecer adelante).
    static func vuelta(_ x: Double, _ largo: Double) -> Double {
        guard largo > 0, x.isFinite else { return 0 }
        let r = x.truncatingRemainder(dividingBy: largo)
        return r < 0 ? r + largo : r
    }

    // MARK: - Luz de rumbo

    /// Apertura total del cono (grados). El prototipo tenía 64°; Juan lo pidió más ancho.
    static let apertura: Double = 90

    /// El rumbo del teléfono: el verdadero si iOS lo da (≥ 0), si no el magnético; nil si no hay ninguno.
    static func rumbo(verdadero: Double, magnetico: Double) -> Double? {
        if verdadero.isFinite, verdadero >= 0 { return normal(verdadero) }
        if magnetico.isFinite, magnetico >= 0 { return normal(magnetico) }
        return nil
    }

    /// 0 ≤ g < 360.
    static func normal(_ g: Double) -> Double {
        guard g.isFinite else { return 0 }
        let r = g.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    /// La diferencia más corta de a hacia b (−180…180): de 359° a 1° es +2°.
    static func diferencia(de a: Double, a b: Double) -> Double {
        let d = normal(b - a)
        return d > 180 ? d - 360 : d
    }

    /// Un paso del suavizado: acerca `actual` a `objetivo` una fracción `k` por el camino corto. `actual` no se
    /// normaliza (puede pasar de 360 o bajar de 0) para que el cono nunca dé la vuelta entera al cruzar el norte.
    static func suavizar(_ actual: Double, hacia objetivo: Double, k: Double) -> Double {
        guard actual.isFinite else { return normal(objetivo) }
        let f = min(1, max(0, k))
        return actual + diferencia(de: actual, a: objetivo) * f
    }

    /// Hacia dónde apunta la luz en la pantalla: el rumbo del teléfono menos el giro del mapa (si el mapa va girado
    /// hacia donde vas, la luz se corrige para seguir apuntando al mundo real).
    static func luzEnPantalla(rumbo: Double, mapa: Double) -> Double { normal(rumbo - mapa) }

    // MARK: - La tarjeta del giro

    struct Tarjeta: Equatable {
        var titulo: String   // «En 80 m» · «Llegaste»
        var frase: String    // «gira a la derecha en la farmacia»
        var luego: String    // «Luego, a la izquierda en la iglesia» o ""
    }

    static func tarjeta(faltan: String, proximo: String, luego: String, llego: Bool) -> Tarjeta {
        if llego { return Tarjeta(titulo: "Llegaste", frase: minus(sinPunto(proximo)), luego: "") }
        let t = faltan.isEmpty ? "Ahora" : "En " + faltan
        let l = luego.isEmpty ? "" : "Luego, " + soloGiro(frase(luego))
        return Tarjeta(titulo: t, frase: frase(proximo), luego: l)
    }

    /// El paso como va en la tarjeta: la maniobra primero y el punto de referencia pegado al giro.
    ///   «En la farmacia, gira a la derecha.» → «gira a la derecha en la farmacia»
    ///   «En la tienda Polo, cruza a la izquierda hacia 6a Calle.» → «cruza a la izquierda en la tienda Polo hacia 6a Calle»
    ///   «Sigue recto hasta la farmacia; ahí cruzas a la izquierda. Yo te aviso.» → «sigue recto hasta la farmacia; ahí cruzas a la izquierda»
    static func frase(_ texto: String) -> String {
        var s = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        for p in ["En una cuadra, ", "En media cuadra, ", "Ahora, ", "Ahora: "] where s.hasPrefix(p) { s = String(s.dropFirst(p.count)); break }
        s = s.replacingOccurrences(of: " Yo te aviso.", with: "")
        s = sinPunto(s)
        // «En <referencia>, <maniobra>»: la referencia va después del giro.
        if s.hasPrefix("En ") || s.hasPrefix("en "), let coma = s.range(of: ", ") {
            let ref = String(s[s.index(s.startIndex, offsetBy: 3)..<coma.lowerBound])
            let man = String(s[coma.upperBound...])
            if let c = man.first, c.isLowercase, !ref.isEmpty {
                return minus(conReferencia(man, ref))
            }
        }
        return minus(s)
    }

    /// Pone «en <ref>» justo después del giro («a la derecha», «un poco a la izquierda»…); si no hay giro, al final.
    static func conReferencia(_ maniobra: String, _ ref: String) -> String {
        for g in ["bien a la izquierda", "bien a la derecha", "un poco a la izquierda", "un poco a la derecha", "a la izquierda", "a la derecha"] {
            if let r = maniobra.range(of: g) {
                return String(maniobra[..<r.upperBound]) + " en " + ref + String(maniobra[r.upperBound...])
            }
        }
        return maniobra + " en " + ref
    }

    /// Para el «Luego»: sin el verbo cuando hay giro («cruza a la izquierda en la iglesia» → «a la izquierda en la iglesia»).
    static func soloGiro(_ f: String) -> String {
        for v in ["gira ", "cruza ", "cruzas ", "dobla ", "voltea "] where f.hasPrefix(v) {
            let resto = String(f.dropFirst(v.count))
            if resto.hasPrefix("a la ") || resto.hasPrefix("un poco ") || resto.hasPrefix("bien ") { return resto }
        }
        return f
    }

    static func sinPunto(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while let u = t.last, u == "." || u == " " { t.removeLast() }
        return t
    }

    static func minus(_ s: String) -> String {
        guard let c = s.first else { return s }
        // Una sigla o un nombre propio al inicio («6a Calle», «OK») se queda como viene; solo la primera letra de una palabra común baja.
        let palabra = s.prefix(while: { $0 != " " })
        if palabra.count > 1, palabra.dropFirst().contains(where: { $0.isUppercase }) { return s }
        return c.lowercased() + s.dropFirst()
    }

    // MARK: - Velocidad y ritmo

    /// m/s → «4,8» (con un decimal por debajo de 10 km/h) o «38». Sin velocidad (negativa o rara): «0».
    static func velocidad(_ ms: Double) -> String {
        guard ms.isFinite, ms > 0.3 else { return "0" }
        let k = ms * 3.6
        if k < 10 { return String(format: "%.1f", k).replacingOccurrences(of: ".", with: ",") }
        return String(Int(k.rounded()))
    }

    /// A pie: minutos por km («12:30»); nil si va casi quieto.
    static func ritmo(_ ms: Double) -> String? {
        guard ms.isFinite, ms > 0.5 else { return nil }
        let s = Int((1000 / ms).rounded())
        guard s < 60 * 60 else { return nil }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: - El medio

    /// Los medios del selector, en orden: carro · bici · bus · metro · a pie. «metro» se le pide al Hub como «metro» (lo
    /// toma como transporte público, igual que el bus); en la pantalla se queda elegido el metro.
    static let medios = ["carro", "bici", "bus", "metro", "caminando"]

    static func medioVisto(hub: String, elegido: String) -> String {
        if elegido == "metro" && hub == "bus" { return "metro" }
        return medios.contains(hub) ? hub : "caminando"
    }
}
