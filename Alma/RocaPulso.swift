import Foundation

// UNA ROCA (Juan, 16-nov-2026): «el pulse de la roca es súper importante: siempre tiene que hacerlo y no tiene que tener
// ningún conflicto con las animaciones de alrededor. El pulse de Alma y los cambios de tamaño conforme a la voz deben
// funcionar perfectos; también cuando habla Claudio». La cuenta pura (sin pantalla, sin iOS), para probarla sola
// (Pruebas/RocaPulso). Son los mismos números de la roca de la web (js/sa-nav.js): un ciclo de 3,6 s con la curva
// (1 − cos) / 2; quieta se encoge 3 %, en llamada respira 2 % y la voz la agranda hasta 20 %.
enum RocaPulso {
    /// Un ciclo de respiración (s): el mismo PULSE de la web.
    static let periodo: Double = 3.6

    /// 0 → 1 → 0 en cada ciclo. `t` es el reloj (segundos); nunca devuelve algo fuera de 0…1.
    static func fase(_ t: Double) -> Double {
        guard t.isFinite else { return 0 }
        var x = t.truncatingRemainder(dividingBy: periodo) / periodo
        if x < 0 { x += 1 }
        return (1 - cos(2 * Double.pi * x)) / 2
    }

    /// La respiración de la piedra (escala). Quieta: se encoge hasta 3 %. En llamada: crece hasta 2 %. Con «reducir
    /// movimiento», quieta en 1.
    static func respira(_ t: Double, enLlamada: Bool, quieto: Bool) -> Double {
        if quieto { return 1 }
        let p = fase(t)
        return enLlamada ? 1 + 0.02 * p : 1 - 0.03 * p
    }

    /// El nivel de la voz (Alma, Claudio o la tuya) llevado a 0…1: un nivel inválido (NaN, negativo) cuenta como silencio,
    /// así la roca nunca se queda congelada.
    static func nivel(_ n: Double) -> Double { n.isFinite ? min(1, max(0, n)) : 0 }

    /// Cuánto crece con la voz: hasta 20 % (la gelatina de la web también para en .2).
    static func voz(_ n: Double) -> Double { 1 + 0.2 * nivel(n) }

    /// El brillo del halo (0…1): respira con la piedra y sube con la voz. Es su propia capa (no comparte transform).
    static func halo(_ t: Double, nivel n: Double, quieto: Bool) -> Double {
        let p = quieto ? 0.5 : fase(t)
        return min(1, 0.42 + 0.3 * p + 0.45 * nivel(n))
    }

    /// Escala total que se ve (para revisar que nunca se achica de más ni crece sin voz).
    static func total(_ t: Double, nivel n: Double, enLlamada: Bool, quieto: Bool) -> Double {
        respira(t, enLlamada: enLlamada, quieto: quieto) * voz(n)
    }
}
