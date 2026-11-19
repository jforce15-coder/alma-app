import Foundation

// Pruebas de PantallaVista (Hub #908): Alma no dice que ve la pantalla sin una lectura real. Lógica pura.
var fallos = 0
func ok(_ c: Bool, _ m: String) { if c { print("✓ " + m) } else { print("::error::" + m); fallos += 1 } }

let s = PantallaVista.saludo.lowercased()
ok(!s.contains("veo") && !s.contains("ya lo") && !s.isEmpty, "el saludo no dice que ya ve la pantalla")
let f = PantallaVista.ficha("«Mi banco» (https://banco.example)")
ok(f.contains("«Mi banco»") && f.contains(PantallaVista.saludo), "la ficha dice dónde está y qué saludo ya dijo")
ok(f.contains("Todavía NO ves su pantalla") && f.contains("no digas que la ves"), "la ficha dice que todavía no ve nada")
ok(!f.contains("dile que lo estás mirando"), "ya no le pide fingir que lo está mirando")
let l = PantallaVista.leida("Página de pagos.", aviso: "Juan te muestra otra pantalla: «X».")
ok(l.hasPrefix("Juan te muestra otra pantalla") && l.contains("LO QUE SE VE EN LA PANTALLA (la captura que te mandó Juan): Página de pagos."), "la lectura llega con su aviso")
ok(PantallaVista.leida("A", aviso: nil).hasPrefix("LO QUE SE VE EN LA PANTALLA"), "sin aviso, empieza con la lectura")
let n = PantallaVista.sinLectura("la sesión de la app venció")
ok(n.hasPrefix("NO VES LA PANTALLA") && n.contains("(la sesión de la app venció)"), "el aviso firme trae el motivo")
ok(n.contains("Nunca digas que la ves") && n.contains("no alcanzo a ver tu pantalla") && n.contains("leer_pagina") && n.contains("banco"), "el aviso prohíbe fingir, la corrige y ofrece leer de verdad")
ok(PantallaVista.motivo(respuesta: nil, http: nil, sinRed: "tardó más de 40 s") == "tardó más de 40 s", "error de red: tal cual")
ok(PantallaVista.motivo(respuesta: nil, http: 500, sinRed: nil) == "el Hub no contestó (HTTP 500)", "sin JSON: el código")
ok(PantallaVista.motivo(respuesta: ["ok": false, "error": "session"], http: 200, sinRed: nil).contains("sesión"), "sesión vencida")
ok(PantallaVista.motivo(respuesta: ["ok": false, "error": "foto"], http: 200, sinRed: nil).contains("muy grande"), "captura rechazada")
ok(PantallaVista.motivo(respuesta: ["ok": false, "error": "lectura"], http: 200, sinRed: nil).contains("IA"), "la IA no la describió")
ok(PantallaVista.motivo(respuesta: ["ok": false, "error": "Alma está en pausa por cupo", "cupo": true], http: 200, sinRed: nil) == "el cupo de Google", "cupo")
ok(PantallaVista.motivo(respuesta: ["ok": true, "texto": ""], http: 200, sinRed: nil) == "la lectura llegó vacía", "lectura vacía")
ok(PantallaVista.motivo(respuesta: ["ok": false, "error": String(repeating: "x", count: 300)], http: 200, sinRed: nil).count == 120, "otro error: recortado")
if fallos > 0 { exit(1) }
print("Todo bien: Alma solo habla de la pantalla con una lectura real.")
