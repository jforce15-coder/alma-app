// Pruebas de lo que el anillo manda (batería, pasos, ritmo) con paquetes de ejemplo, y de lo que Alma dice y sube al Hub
// (Alma/AnilloDatos.swift).
//   swiftc Alma/AnilloDatos.swift Pruebas/AnilloDatos/main.swift -o /tmp/anillo-datos && /tmp/anillo-datos
// Las corre el robot en cada PR (testflight.yml, «Probar lo que lee el anillo»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}
typealias D = AnilloDatos
/// Un paquete de 16 bytes como los manda el anillo: los datos, ceros y la suma al final.
func paquete(_ d: [UInt8]) -> [UInt8] {
    var b = Array(d.prefix(15)); while b.count < 15 { b.append(0) }
    return b + [UInt8(b.reduce(0) { $0 + Int($1) } & 0xFF)]
}

// MARK: - Batería

revisa(D.leer(paquete([0x03, 64, 0])) == .bateria(nivel: 64, cargando: false), "batería: 64 %, sin cargar")
revisa(D.leer(paquete([0x03, 100, 1])) == .bateria(nivel: 100, cargando: true), "batería: 100 %, cargando")

// MARK: - Ajustes del ritmo

revisa(D.leer(paquete([0x16, 0x01, 0x01, 30])) == .ritmoAjustes(activo: true, minutos: 30), "monitoreo del ritmo: encendido cada 30 min")
revisa(D.leer(paquete([0x16, 0x01, 0x02, 15])) == .ritmoAjustes(activo: false, minutos: 15), "monitoreo del ritmo: apagado")
revisa(D.leer(paquete([0x16, 0x02, 0x01, 30])) == .otro(comando: 0x16), "la respuesta de guardar no se confunde con la lectura")
revisa(D.minutosValidos(1) == 5 && D.minutosValidos(90) == 60 && D.minutosValidos(15) == 15, "el intervalo queda entre 5 y 60 min")

// MARK: - En vivo

revisa(D.leer(paquete([0x69, 0x01, 0x00, 72])) == .medida(.ritmo, valor: 72), "ritmo en vivo: 72")
revisa(D.leer(paquete([0x69, 0x03, 0x00, 97])) == .medida(.oxigeno, valor: 97), "oxígeno en vivo: 97")
revisa(D.leer(paquete([0x69, 0x01, 0x02, 0])) == .medidaError(codigo: 2), "error al medir (anillo flojo)")
revisa(D.medicionLista([0, 0, 80], tipo: .ritmo, tiempoCumplido: false) == nil, "ritmo: una sola lectura buena todavía no basta")
revisa(D.medicionLista([0, 80, 76, 74], tipo: .ritmo, tiempoCumplido: false) == 74, "ritmo: con 3 lecturas buenas, la última")
revisa(D.medicionLista([0, 0, 81], tipo: .ritmo, tiempoCumplido: true) == 81, "ritmo: con el tiempo cumplido vale la última buena")
revisa(D.medicionLista([0, 0], tipo: .ritmo, tiempoCumplido: true) == nil, "ritmo: sin ninguna buena no se inventa nada")
revisa(D.medicionLista([96, 97], tipo: .oxigeno, tiempoCumplido: false) == 97, "oxígeno: con 2 lecturas buenas")
revisa(D.medicionLista([250, 40], tipo: .oxigeno, tiempoCumplido: true) == nil, "oxígeno: valores imposibles no cuentan")

// MARK: - Pasos (0x43): inicio, cuartos de hora y fin

do {
    var p = D.PasosDia()
    revisa(!p.sumar(D.leer(paquete([0x43, 0xF0, 0x05, 0x00]))), "pasos: el primer paquete solo avisa que empieza")
    // [0x43, año, mes, día, cuarto, índice, total, kcal(2), pasos(2), metros(2)]
    revisa(!p.sumar(D.leer(paquete([0x43, 0x26, 0x11, 0x16, 0x20, 0, 2, 40, 0, 0xE8, 0x03, 0x20, 0x03]))), "pasos: primer cuarto (1 000 pasos)")
    revisa(p.sumar(D.leer(paquete([0x43, 0x26, 0x11, 0x16, 0x21, 1, 2, 10, 0, 0xF4, 0x01, 0x90, 0x01]))), "pasos: el último cuarto termina")
    revisa(p.pasos == 1500 && p.kcal == 50 && p.metros == 1200 && p.listo, "pasos: 1 500 pasos, 50 kcal, 1,2 km")
    var n = D.PasosDia()
    _ = n.sumar(D.leer(paquete([0x43, 0xF0, 0x05, 0x01])))
    _ = n.sumar(D.leer(paquete([0x43, 0x26, 0x11, 0x16, 0x20, 0, 1, 12, 0, 0x64, 0x00, 0x50, 0x00])))
    revisa(n.porDiez && n.kcal == 120 && n.kcalMostrar == 120, "pasos: con el protocolo nuevo las kcal vienen en decenas")
    var x = D.PasosDia(); x.kcal = 350_000
    revisa(x.kcalMostrar == 350, "pasos: una suma imposible como kcal se pasa de calorías a kcal")
    var v = D.PasosDia()
    revisa(v.sumar(D.leer(paquete([0x43, 0xFF]))) && v.pasos == 0 && v.listo, "pasos: un día sin datos termina en 0")
}

// MARK: - Historial del ritmo (0x15)

do {
    var h = D.RitmoHist()
    revisa(!h.sumar(D.leer(paquete([0x15, 0x00, 3, 5]))), "historial: la cabecera (3 paquetes, cada 5 min)")
    revisa(!h.sumar(D.leer(paquete([0x15, 0x01, 0x00, 0x00, 0x00, 0x00, 60, 62, 0, 0, 0, 0, 0, 0, 0]))), "historial: el paquete 1 trae la hora y 9 valores")
    revisa(h.sumar(D.leer(paquete([0x15, 0x02, 0, 0, 70, 110, 0, 0, 0, 0, 0, 0, 0, 0, 0]))), "historial: el último paquete termina")
    revisa(h.valores.count == 9 + 13, "historial: 9 + 13 valores")
    let r = h.resumen
    revisa(r == D.RitmoHist.Resumen(min: 60, max: 110, prom: 76, ultimo: 110, ultimoMin: 12 * 5, lecturas: 4), "historial: mín 60, máx 110, promedio 76, la última a las 1:00")
    revisa(D.horaDelDia(r?.ultimoMin ?? 0) == "1:00" && D.horaDelDia(14 * 60 + 35) == "14:35", "la hora del día de una lectura")
    var s = D.RitmoHist()
    revisa(s.sumar(D.leer(paquete([0x15, 0xFF]))) && s.resumen == nil, "historial: sin datos, sin resumen (no se inventa)")
}

// MARK: - Lo que dice Alma

do {
    let gt = TimeZone(identifier: "America/Guatemala")!
    let ahora = 1_794_859_200.0   // 16-nov-2026 14:00 en Guatemala (20:00 UTC)
    revisa(D.hace(ahora - 30, ahora: ahora, zona: gt) == "hace un momento", "«hace un momento»")
    revisa(D.hace(ahora - 600, ahora: ahora, zona: gt) == "hace 10 min", "«hace 10 min»")
    revisa(D.hace(ahora - 7200, ahora: ahora, zona: gt) == "hace 2 h", "«hace 2 h»")
    revisa(D.hace(ahora - 86400 - 60, ahora: ahora, zona: gt) == "ayer a las 13:59", "«ayer a las 13:59»")
    revisa(D.hace(ahora - 3 * 86400, ahora: ahora, zona: gt) == "el 13-nov a las 14:00", "«el 13-nov a las 14:00»")
    revisa(D.hace(nil, ahora: ahora) == nil, "sin dato, sin hora")
    var m = D.Memoria(); m.bateria = .init(v: 64, t: ahora - 7200)
    let f = D.ficha(conectado: false, m: m, ahora: ahora)
    revisa(f.hasPrefix("ANILLO DE JUAN") && f.contains("no conectado") && f.contains("64 %") && f.contains("nunca inventes"), "la ficha dice «ANILLO DE JUAN», si está conectado y la batería con su hora")
    revisa(D.entero(NSNumber(value: 3)) == 3 && D.entero("15") == 15 && D.entero("x") == nil, "los enteros de ElevenLabs (número o texto)")
    revisa(D.booleano("true") == true && D.booleano(false) == false && D.booleano("quizá") == nil, "los sí/no de ElevenLabs")
}

// MARK: - Lo que va al Hub

do {
    var m = D.Memoria()
    revisa(!D.tocaSubir(ultimaSubida: nil, ultimoDato: D.ultimoDato(m), ahora: 1000), "sin datos no se sube nada")
    m.bateria = .init(v: 80, t: 1000); m.cargando = true; m.pasos = .init(v: 3200, t: 1000); m.firmware = "R08_3.10.48 (x)"
    m.ritmoMin = 58; m.ritmoMax = 110; m.ritmoProm = 74; m.ritmoDiaT = 1000; m.ritmoActivo = true; m.ritmoMinutos = 30; m.ajustesT = 1000
    revisa(D.tocaSubir(ultimaSubida: nil, ultimoDato: D.ultimoDato(m), ahora: 1000), "la primera lectura se sube")
    revisa(!D.tocaSubir(ultimaSubida: 900, ultimoDato: 1000, ahora: 1000), "como mucho cada 10 min")
    revisa(D.tocaSubir(ultimaSubida: 900, ultimoDato: 1600, ahora: 1600), "a los 10 min, si hay algo nuevo")
    revisa(!D.tocaSubir(ultimaSubida: 1600, ultimoDato: 1000, ahora: 5000), "sin nada nuevo no se sube")
    let r = D.resumenHub(m, conectado: true)
    let b = r["bateria"] as? [String: Any]
    revisa(b?["v"] as? Int == 80 && b?["cargando"] as? Bool == true && (r["pasos"] as? [String: Any])?["v"] as? Int == 3200, "al Hub: batería y pasos con su hora")
    revisa((r["ritmo_dia"] as? [String: Any])?["min"] as? Int == 58 && (r["ajustes"] as? [String: Any])?["minutos"] as? Int == 30, "al Hub: el ritmo del día y el monitoreo")
    revisa(r["firmware"] as? String == "R08_3.10.48x" && r["nombre"] == nil && r["mac"] == nil, "al Hub: firmware limpio, sin nombre ni dirección del anillo")
}

// MARK: - Los lentes

revisa(LentesDatos.sonLentes("iTOUCH AURA") && LentesDatos.sonLentes("Aura Glasses") && !LentesDatos.sonLentes("AirPods de Juan"), "los lentes se reconocen por su nombre")
revisa(LentesDatos.horasMusica(bateria: nil) == "4–6 h de música con la carga llena", "lentes sin batería: lo que dice el fabricante, sin inventar un porcentaje")
revisa(LentesDatos.horasMusica(bateria: 50) == "2–3 h de música", "lentes al 50 %: 2–3 h")

if fallos > 0 { print("\(fallos) fallaron"); exit(1) }
print("Todo bien")
