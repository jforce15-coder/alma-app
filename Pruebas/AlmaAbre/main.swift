// Pruebas de «Alma abre la conversación» (Alma/AlmaAbre.swift, Hub #509 T4).
//   swiftc Alma/AlmaAbre.swift Pruebas/AlmaAbre/main.swift -o /tmp/alma-abre && /tmp/alma-abre
// Las corre el robot en cada PR (testflight.yml, «Probar Alma abre»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}

// MARK: - Lo que manda el Hub

let conAbre: [String: Any] = ["id": "rt1", "texto": "Ya quedó listo…",
                              "abre": ["primer_mensaje": "  Juan, ya quedó listo el cambio para «Botón de facturas»; solo falta que lo unas. ¿Lo vemos ahora?  ",
                                       "contexto": "ALMA ABRE: {\"alma_abre\":{\"pedido\":\"Botón de facturas\"}}"]]
let d = AlmaAbre.desde(conAbre)
revisa(d?.primer.hasPrefix("Juan, ya quedó listo") == true && d?.primer.hasSuffix("¿Lo vemos ahora?") == true, "el primer mensaje del Hub, sin espacios de más")
revisa(d?.contexto.hasPrefix("ALMA ABRE: ") == true, "el contexto para seguir la conversación")
revisa(AlmaAbre.desde(["id": "rt2", "texto": "Hola"]) == nil, "un aviso sin «abre» (no califica): la notificación de siempre")
revisa(AlmaAbre.desde(["abre": ["primer_mensaje": "   ", "contexto": "x"]]) == nil, "sin frase no se abre nada")

// MARK: - Dónde (Juan: solo en conferencia, en llamada o en Modo calle)

revisa(AlmaAbre.pedir(calle: true, conferencia: false, hablado: 3) && AlmaAbre.pedir(calle: false, conferencia: true, hablado: 1), "en Modo calle o en conferencia se le pide al Hub que marque lo que abre")
revisa(!AlmaAbre.pedir(calle: false, conferencia: false, hablado: 3), "con la app abierta en el inicio (sin esos modos) no")
revisa(!AlmaAbre.pedir(calle: true, conferencia: true, hablado: 0), "con las habladas en «Silencio», nunca")
revisa(AlmaAbre.donde(calle: true, conferencia: false) == .calle && AlmaAbre.donde(calle: false, conferencia: true) == .conferencia && AlmaAbre.donde(calle: false, conferencia: false) == .otro, "dónde está la app")

// MARK: - Le toca al aviso

revisa(AlmaAbre.decidir(d, donde: .calle, espera: 2) == .abrir, "Modo calle: abre la conversación con su primer mensaje")
revisa(AlmaAbre.decidir(d, donde: .conferencia, espera: 2) == .abrir, "conferencia: activa a Alma y habla primero")
revisa(AlmaAbre.decidir(d, donde: .otro, espera: 2) == .avisoDeSiempre, "fuera de esos modos: la notificación hablada de siempre")
revisa(AlmaAbre.decidir(nil, donde: .calle, espera: 2) == .avisoDeSiempre, "si el Hub no lo marcó (inicio, pedido viejo, otro administrador): la de siempre")
revisa(AlmaAbre.decidir(d, donde: .conferencia, espera: 2, mudo: true) == .avisoDeSiempre, "con la conferencia silenciada no abre el micrófono")
revisa(AlmaAbre.decidir(d, donde: .calle, espera: 9 * 60) == .abrir, "Juan hablaba con Alma: esperó y al terminar se abre")
revisa(AlmaAbre.decidir(d, donde: .calle, espera: AlmaAbre.vence + 1) == .avisoDeSiempre, "si esperó demasiado, lo deja para después (la de siempre)")

// MARK: - Nunca dos veces

revisa(AlmaAbre.nuevo("rt1", dichos: [], enFila: []), "un aviso nuevo entra")
revisa(!AlmaAbre.nuevo("rt1", dichos: ["rt0", "rt1"], enFila: []), "el que ya se dijo o se abrió no vuelve")
revisa(!AlmaAbre.nuevo("rt1", dichos: [], enFila: ["rt1"]), "el que ya espera en la fila no entra otra vez")

// MARK: - La conversación

if let d {
    let f = AlmaAbre.ficha("Quien habla es Juan.", d)
    revisa(f.hasPrefix("Quien habla es Juan.") && f.hasSuffix(d.contexto), "el contexto del Hub va al final de la ficha")
    revisa(AlmaAbre.primerMensaje(d, deSiempre: "") == d.primer && AlmaAbre.primerMensaje(nil, deSiempre: "Hola, cuéntame.") == "Hola, cuéntame.",
           "Alma habla primero con la frase del aviso, aunque haya ruido al conectar")
} else { revisa(false, "no llegó el aviso de prueba") }
revisa(AlmaAbre.sueno(calle: false, porAviso: true) && AlmaAbre.sueno(calle: true, porAviso: false) && !AlmaAbre.sueno(calle: false, porAviso: false),
       "el sueño cuelga solo si Juan no contesta: Modo calle y lo que abrió un aviso; las demás llamadas no cambian")

if fallos > 0 { print("\(fallos) fallaron"); exit(1) }
print("Todo bien")
