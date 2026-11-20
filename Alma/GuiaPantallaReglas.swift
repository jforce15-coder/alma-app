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
