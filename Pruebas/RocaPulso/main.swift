import Foundation

// Prueba pura del pulso de la roca (Alma/RocaPulso.swift): xcrun swiftc Alma/RocaPulso.swift Pruebas/RocaPulso/main.swift
var fallas = 0
func ok(_ c: Bool, _ m: String) { if c { print("✓ " + m) } else { print("✗ " + m); fallas += 1 } }
func cerca(_ a: Double, _ b: Double, _ e: Double = 1e-9) -> Bool { abs(a - b) < e }

// 1 · el ciclo: 3,6 s, empieza y termina en 0, llega a 1 a la mitad, nunca sale de 0…1
ok(cerca(RocaPulso.fase(0), 0) && cerca(RocaPulso.fase(1.8), 1) && cerca(RocaPulso.fase(3.6), 0, 1e-6), "1 · fase: 0 al empezar, 1 a la mitad, 0 al terminar (3,6 s)")
ok(stride(from: -10.0, through: 50.0, by: 0.137).allSatisfy { let f = RocaPulso.fase($0); return f >= 0 && f <= 1 }, "1 · fase siempre entre 0 y 1 (también con reloj negativo)")
ok(RocaPulso.fase(.nan) == 0 && RocaPulso.fase(.infinity) == 0, "1 · un reloj inválido no rompe la fase")

// 2 · siempre respira: quieta y en llamada cambia de tamaño a lo largo del ciclo
let quieta = stride(from: 0.0, to: 3.6, by: 0.05).map { RocaPulso.respira($0, enLlamada: false, quieto: false) }
let llamada = stride(from: 0.0, to: 3.6, by: 0.05).map { RocaPulso.respira($0, enLlamada: true, quieto: false) }
ok((quieta.max()! - quieta.min()!) > 0.025 && quieta.min()! >= 0.97 - 1e-9 && quieta.max()! <= 1 + 1e-9, "2 · quieta respira (se encoge hasta 3 %)")
ok((llamada.max()! - llamada.min()!) > 0.015 && llamada.min()! >= 1 - 1e-9 && llamada.max()! <= 1.02 + 1e-9, "2 · en llamada respira (crece hasta 2 %)")
ok(RocaPulso.respira(0.9, enLlamada: true, quieto: true) == 1, "2 · con «reducir movimiento» se queda quieta")

// 3 · la voz: crece con el nivel (Alma, Claudio o tú), hasta 20 %, y un nivel malo no la congela
ok(RocaPulso.voz(0) == 1 && cerca(RocaPulso.voz(1), 1.2) && cerca(RocaPulso.voz(5), 1.2), "3 · la voz la agranda hasta 20 % y no más")
ok(RocaPulso.voz(0.25) < RocaPulso.voz(0.5) && RocaPulso.voz(0.5) < RocaPulso.voz(0.9), "3 · más voz, más grande")
ok(RocaPulso.voz(.nan) == 1 && RocaPulso.voz(-3) == 1, "3 · un nivel inválido cuenta como silencio")
ok(stride(from: 0.0, to: 7.2, by: 0.3).allSatisfy { RocaPulso.total($0, nivel: 0.7, enLlamada: true, quieto: false) > RocaPulso.total($0, nivel: 0, enLlamada: true, quieto: false) }, "3 · hablando, siempre más grande que callada (la respiración no tapa la voz)")
let conVoz = stride(from: 0.0, to: 3.6, by: 0.05).map { RocaPulso.total($0, nivel: 0.5, enLlamada: true, quieto: false) }
ok((conVoz.max()! - conVoz.min()!) > 0.015, "3 · con la voz sigue respirando (el pulso nunca se detiene)")

// 4 · el halo: su propia capa, respira y sube con la voz, nunca pasa de 1
ok(RocaPulso.halo(1.8, nivel: 0, quieto: false) > RocaPulso.halo(0, nivel: 0, quieto: false), "4 · el halo respira con la piedra")
ok(RocaPulso.halo(0, nivel: 1, quieto: false) > RocaPulso.halo(0, nivel: 0, quieto: false) && RocaPulso.halo(1.8, nivel: 1, quieto: false) <= 1, "4 · el halo sube con la voz y no pasa de 1")

if fallas > 0 { print("\(fallas) falla(s)"); exit(1) }
print("Todo bien.")
