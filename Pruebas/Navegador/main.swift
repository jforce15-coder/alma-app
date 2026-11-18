// Pruebas de la lógica pura del Navegador de Alma en sus modos (Alma/NavegadorReglas.swift). Corren solas, sin iOS:
//   swiftc Alma/NavegadorReglas.swift Pruebas/Navegador/main.swift -o /tmp/navegador && /tmp/navegador
// Las corre el robot en cada PR (testflight.yml, «Probar el Navegador de Alma»). El JS de la página se prueba aparte en un
// navegador de verdad: node Pruebas/Navegador/pagina.mjs (ver ese archivo).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}
typealias R = NavegadorReglas

// Pausa de privacidad
do {
    revisa(R.motivo(R.Senales()) == nil, "sin nada sensible, Alma ve")
    revisa(R.motivo(R.Senales(clave: true)) == .clave, "una contraseña a la vista pausa")
    revisa(R.motivo(R.Senales(codigo: true)) == .codigo, "un código de verificación pausa")
    revisa(R.motivo(R.Senales(tarjeta: true)) == .tarjeta, "un dato de tarjeta pausa")
    revisa(R.motivo(R.Senales(clave: true, captcha: true)) == .captcha, "el captcha manda: siempre lo hace Juan")
    revisa(R.pausar(R.Senales(clave: true), liberada: true) == nil, "con «Listo» Alma vuelve a ver la página aunque el campo siga")
    revisa(R.pausar(R.Senales(clave: true, enfocado: true), liberada: true) == .clave, "si Juan vuelve al campo, se pausa otra vez")
    revisa(R.pausar(R.Senales(captcha: true), liberada: true) == .captcha, "«Listo» no salta un captcha a la vista")
    for m in [R.Motivo.clave, .codigo, .tarjeta, .captcha] {
        revisa(m.aviso.hasPrefix("Te toca a ti"), "el aviso de \(m.rawValue) dice «Te toca a ti»")
        revisa(m.paraAlma.contains("No la ves") && m.paraAlma.contains("nunca le pidas"), "a Alma: no ve y no pide que se lo digan (\(m.rawValue))")
    }
}

// Tarjeta de datos (modo guiado)
do {
    revisa(R.rechazoDato(etiqueta: "Número de reserva", valor: "HM4K2Q") == nil, "un número de reserva va en la tarjeta")
    revisa(R.rechazoDato(etiqueta: "Correo", valor: "reservas@ejemplo.com") == nil, "un correo va en la tarjeta")
    revisa(R.rechazoDato(etiqueta: "Contraseña", valor: "hola123") != nil, "una contraseña nunca")
    revisa(R.rechazoDato(etiqueta: "PIN", valor: "4321") != nil, "un PIN nunca")
    revisa(R.rechazoDato(etiqueta: "Código de verificación", valor: "883201") != nil, "un código de verificación nunca")
    revisa(R.rechazoDato(etiqueta: "Pintura", valor: "Blanco hueso") == nil, "«pin» dentro de otra palabra no cuenta")
    revisa(R.rechazoDato(etiqueta: "Número", valor: "4111 1111 1111 1111") != nil, "un número de tarjeta (Luhn) nunca, aunque la etiqueta no lo diga")
    revisa(R.rechazoDato(etiqueta: "Teléfono", valor: "5555 1234") == nil, "un teléfono corto no parece tarjeta")
    revisa(R.rechazoDato(etiqueta: "Nota", valor: "   ") != nil, "vacío no")
    revisa(R.rechazoDato(etiqueta: "Nota", valor: String(repeating: "a", count: 301)) != nil, "muy largo no")
    var l: [R.Dato] = []
    for i in 1...8 { l = R.agregar(R.Dato(etiqueta: "Dato \(i)", valor: "\(i)"), a: l) }
    revisa(l.count == R.maxDatos && l.first?.etiqueta == "Dato 3" && l.last?.etiqueta == "Dato 8", "como mucho 6 datos: salen los más viejos")
    l = R.agregar(R.Dato(etiqueta: "dato 5", valor: "nuevo"), a: l)
    revisa(l.count == R.maxDatos && l.last?.valor == "nuevo" && l.filter { $0.id == "dato 5" }.count == 1, "la misma etiqueta se reemplaza")
}

// Ritmo humano y tope por sitio (modo control)
do {
    revisa(R.pausa("tocar", azar: 0) == 0.6 && abs(R.pausa("tocar", azar: 1) - 1.5) < 0.001, "tocar espera de 0,6 a 1,5 s")
    revisa(R.pausa("escribir", azar: 0.5) > 0.4 && R.pausa("escribir", azar: 0.5) < 1.1, "escribir espera un poco")
    revisa(R.pausa("leer_pagina", azar: 1) == 0 && R.pausa("senalar", azar: 1) == 0, "leer y señalar no esperan")
    revisa(R.pausa("tocar", azar: 7) == R.pausa("tocar", azar: 1), "el azar fuera de rango se recorta")
    var t = R.Tope(porMinuto: 3, porDia: 5)
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    revisa(t.pedir("www.ejemplo.com", ahora: t0) == nil && t.pedir("ejemplo.com", ahora: t0 + 1) == nil && t.pedir("m.ejemplo.com", ahora: t0 + 2) == nil,
           "tres acciones en el mismo sitio (www y m. cuentan juntos)")
    let espera = t.pedir("ejemplo.com", ahora: t0 + 3)
    revisa(espera != nil && abs((espera ?? 0) - 57) < 0.01, "la cuarta en el mismo minuto espera (57 s)")
    revisa(t.pedir("otro.com", ahora: t0 + 3) == nil, "otro sitio tiene su propio tope")
    revisa(t.pedir("ejemplo.com", ahora: t0 + 61) == nil && t.pedir("ejemplo.com", ahora: t0 + 62) == nil, "pasado el minuto sigue")
    revisa(t.pedir("ejemplo.com", ahora: t0 + 200) != nil, "el tope del día también cuenta (5)")
    revisa(R.actuan == ["tocar", "escribir", "bajar"], "solo tocar, escribir y bajar actúan sobre la página")
}

print(fallos == 0 ? "OK: Navegador de Alma" : "FALLARON \(fallos)")
exit(fallos == 0 ? 0 : 1)
