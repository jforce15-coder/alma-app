// Pruebas de «La música vuelve» (Alma/MusicaVuelve.swift, Hub #822).
//   swiftc Alma/MusicaVuelve.swift Pruebas/MusicaVuelve/main.swift -o /tmp/musica-vuelve && /tmp/musica-vuelve
// Las corre el robot en cada PR (testflight.yml, «Probar que la música vuelve»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}
let t0 = Date(timeIntervalSince1970: 1_000_000)
func en(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

// MARK: - Encender el Modo calle pausa Spotify: vuelve al terminar

do {
    var r = MusicaVuelve()
    revisa(r.mirar(suena: true, almaOcupada: false, ahora: en(0)) == .nada, "Spotify sonando: nada")
    r.tomo("al encender el Modo calle", ahora: en(0.5))
    revisa(r.mirar(suena: false, almaOcupada: false, ahora: en(1)) == .paro(motivo: "al encender el Modo calle"), "paró justo después de encender el Modo calle: la paró Alma")
    revisa(r.mirar(suena: false, almaOcupada: false, ahora: en(2)) == .nada, "espera 1,5 s con Alma libre")
    revisa(r.mirar(suena: false, almaOcupada: false, ahora: en(3)) == .pedir(motivo: "al encender el Modo calle"), "Alma libre: le pide al Hub que Spotify siga")
    revisa(r.mirar(suena: false, almaOcupada: false, ahora: en(4)) == .nada, "una sola vez por pausa")
}

// MARK: - En la llamada: espera a que termine

do {
    var r = MusicaVuelve()
    _ = r.mirar(suena: true, almaOcupada: false, ahora: en(0))
    r.tomo("al abrir la llamada", ahora: en(1))
    revisa(r.mirar(suena: false, almaOcupada: true, ahora: en(2)) == .paro(motivo: "al abrir la llamada"), "la llamada pausó Spotify")
    revisa(r.mirar(suena: false, almaOcupada: true, ahora: en(60)) == .nada, "a media llamada no se retoma")
    r.tomo("al colgar", ahora: en(120))
    revisa(r.mirar(suena: false, almaOcupada: false, ahora: en(120.5)) == .nada, "recién colgó: espera un momento")
    revisa(r.mirar(suena: false, almaOcupada: false, ahora: en(122)) == .pedir(motivo: "al abrir la llamada"), "colgó: Spotify sigue")
}

// MARK: - Paró mientras Alma atendía (sin cambio de audio a la vista)

do {
    var r = MusicaVuelve()
    _ = r.mirar(suena: true, almaOcupada: true, ahora: en(0))
    revisa(r.mirar(suena: false, almaOcupada: true, ahora: en(30)) == .paro(motivo: "mientras Alma atendía"), "paró mientras Alma atendía")
    revisa(r.mirar(suena: false, almaOcupada: false, ahora: en(31)) == .nada, "Alma acaba de terminar")
    revisa(r.mirar(suena: false, almaOcupada: false, ahora: en(32.6)) == .pedir(motivo: "mientras Alma atendía"), "y vuelve")
}

// MARK: - Juan la pausó: no se toca

do {
    var r = MusicaVuelve()
    r.tomo("al abrir el audio para escuchar", ahora: en(0))
    _ = r.mirar(suena: true, almaOcupada: false, ahora: en(1))
    revisa(r.mirar(suena: false, almaOcupada: false, ahora: en(20)) == .nada, "paró sola, lejos de un cambio de Alma: Juan la pausó")
    revisa(r.mirar(suena: false, almaOcupada: false, ahora: en(30)) == .nada, "y no se retoma")
}

// MARK: - Volvió sola, vence y tope

do {
    var r = MusicaVuelve()
    _ = r.mirar(suena: true, almaOcupada: false, ahora: en(0))
    r.tomo("al colgar", ahora: en(0))
    _ = r.mirar(suena: false, almaOcupada: false, ahora: en(1))
    revisa(r.mirar(suena: true, almaOcupada: false, ahora: en(2)) == .nada, "volvió sola (iOS le avisó a Spotify): nada que pedir")
    revisa(r.mirar(suena: false, almaOcupada: false, ahora: en(30)) == .nada, "y si Juan la pausa después, no se toca")

    var v = MusicaVuelve()
    _ = v.mirar(suena: true, almaOcupada: true, ahora: en(0))
    _ = v.mirar(suena: false, almaOcupada: true, ahora: en(1))
    revisa(v.mirar(suena: false, almaOcupada: false, ahora: en(1 + 16 * 60)) == .nada, "una llamada de más de 15 min: ya no se retoma")

    var w = MusicaVuelve()
    _ = w.mirar(suena: true, almaOcupada: false, ahora: en(0)); w.tomo("x", ahora: en(0))
    _ = w.mirar(suena: false, almaOcupada: false, ahora: en(1)); _ = w.mirar(suena: false, almaOcupada: false, ahora: en(2))
    revisa(w.mirar(suena: false, almaOcupada: false, ahora: en(3)) == .pedir(motivo: "x"), "primera vuelta")
    _ = w.mirar(suena: true, almaOcupada: false, ahora: en(5)); w.tomo("y", ahora: en(6))
    _ = w.mirar(suena: false, almaOcupada: false, ahora: en(7)); _ = w.mirar(suena: false, almaOcupada: false, ahora: en(8))
    revisa(w.mirar(suena: false, almaOcupada: false, ahora: en(9)) == .nada, "otra pausa a los pocos segundos: espera (una vuelta cada 20 s)")
    revisa(w.mirar(suena: false, almaOcupada: false, ahora: en(24)) == .pedir(motivo: "y"), "pasados 20 s, sí")
}

// MARK: - Lo que contestó el Hub

revisa(MusicaVuelve.texto(["ok": true, "hecho": true]) == "La música vuelve: Spotify sigue donde iba", "hecho")
revisa(MusicaVuelve.texto(["ok": true, "hecho": false, "motivo": "la_pauso_alma"]).contains("se lo pediste"), "la pausó Alma a pedido de Juan")
revisa(MusicaVuelve.texto(["ok": true, "hecho": false, "motivo": "sin_dispositivo"]).contains("ya no aparece"), "sin dispositivo")
revisa(MusicaVuelve.texto(nil).contains("no contestó"), "sin respuesta")

if fallos > 0 { print("\(fallos) fallaron"); exit(1) }
print("Todo bien")
