// Pruebas del ritmo de los avisos hablados (Alma/RitmoAvisos.swift, Juan 17-nov-2026, Hub #670).
//   swiftc Alma/RitmoAvisos.swift Pruebas/RitmoAvisos/main.swift -o /tmp/ritmo-avisos && /tmp/ritmo-avisos
// Las corre el robot en cada PR (testflight.yml, «Probar el ritmo de los avisos»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}

let t0 = Date(timeIntervalSince1970: 1_800_000_000)
func en(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

// MARK: - Uno a la vez, el más urgente primero

var r = RitmoAvisos()
r.llegar(id: "aviso", nivel: 3, ahora: t0)
r.llegar(id: "accion", nivel: 2, ahora: t0)
r.llegar(id: "urgente", nivel: 1, ahora: en(1))
r.llegar(id: "urgente", nivel: 1, ahora: en(2))
revisa(r.ids.count == 3, "el mismo aviso dos veces no se repite")
revisa(r.siguiente(ahora: en(2)) == "urgente", "sale primero el más urgente aunque llegó después")
r.decir("urgente")
revisa(r.siguiente(ahora: en(3)) == nil, "mientras se dice uno (y se espera la respuesta) no sale otro")

// MARK: - Silencio entre uno y otro

r.termino(ahora: en(10))   // no contestó
revisa(r.siguiente(ahora: en(11)) == nil, "sin respuesta: silencio")
revisa(r.falta(ahora: en(70)) == 60, "faltan 60 s de los 2 min de silencio")
revisa(r.siguiente(ahora: en(10 + RitmoAvisos.pausa)) == "accion", "a los 2 min, el segundo más urgente")
r.decir("accion"); r.termino(ahora: en(140))
revisa(r.siguiente(ahora: en(141)) == nil, "otra vez silencio después del segundo")
revisa(RitmoAvisos.pausa >= 60 && RitmoAvisos.pausa <= 180, "la pausa está entre uno y tres minutos")

// MARK: - Rotan los tres más urgentes: recordar el que sigue pendiente o avanzar

revisa(r.siguiente(ahora: en(260)) == "aviso", "rota al tercero antes de repetir")
r.decir("aviso"); r.termino(ahora: en(270))
revisa(r.siguiente(ahora: en(390)) == "urgente", "vuelve al primero: sigue pendiente, se lo recuerda")
r.decir("urgente"); r.resuelto("urgente"); r.termino(ahora: en(400))
revisa(!r.ids.contains("urgente"), "contestó: sale del ciclo")
revisa(r.siguiente(ahora: en(520)) == "accion", "avanza al segundo porque el primero ya se resolvió")

// MARK: - Uno nuevo y urgente entra antes que un recordatorio

var n = RitmoAvisos()
n.llegar(id: "a", nivel: 2, ahora: t0); n.llegar(id: "b", nivel: 2, ahora: en(1))
let primero = n.siguiente(ahora: en(1))!
n.decir(primero); n.termino(ahora: en(5))
n.llegar(id: "nuevo", nivel: 1, ahora: en(30))
revisa(n.siguiente(ahora: en(130)) == "nuevo", "el urgente nuevo sale antes que el siguiente de la ronda")

// MARK: - Solo los tres más urgentes rotan

var c = RitmoAvisos()
for (i, nv) in [3, 1, 2, 3, 2].enumerated() { c.llegar(id: "x\(i)", nivel: nv, ahora: en(Double(i))) }
revisa(c.rondaActual().map { $0.id } == ["x1", "x2", "x4"], "la ronda son los tres más urgentes (a igual nivel, el que llegó antes)")
var dichos: [String] = []
var t = 10.0
for _ in 0..<6 { if let id = c.siguiente(ahora: en(t)) { dichos.append(id); c.decir(id); c.termino(ahora: en(t + 5)) }; t += 5 + RitmoAvisos.pausa }
revisa(dichos == ["x1", "x2", "x4", "x1", "x2", "x4"], "rotación 1 → 2 → 3 → 1 → 2 → 3")

// MARK: - No insiste para siempre

var v = RitmoAvisos()
v.llegar(id: "solo", nivel: 1, ahora: t0)
var veces = 0; t = 0
for _ in 0..<6 { if let id = v.siguiente(ahora: en(t)) { veces += 1; v.decir(id); v.termino(ahora: en(t + 5)) }; t += 5 + RitmoAvisos.pausa }
revisa(veces == RitmoAvisos.maxVeces, "cada aviso se dice como mucho \(RitmoAvisos.maxVeces) veces (la primera y dos recordatorios)")
revisa(v.vacio, "después queda solo en Pendientes")
var w = RitmoAvisos()
w.llegar(id: "viejo", nivel: 2, ahora: t0)
revisa(w.siguiente(ahora: en(RitmoAvisos.vence + 1)) == nil && w.vacio, "a las 2 h ya no se recuerda")

// MARK: - Apagar

var z = RitmoAvisos()
z.llegar(id: "a", nivel: 1, ahora: t0); z.decir("a"); z.vaciar()
revisa(z.vacio && z.enCurso == nil, "apagar vacía el ciclo y suelta el aviso en curso")
z.llegar(id: "b", nivel: 1, ahora: en(10))
revisa(z.siguiente(ahora: en(11)) == "b", "sin aviso reciente, el primero sale enseguida")

print(fallos == 0 ? "\nTodo bien" : "\n\(fallos) fallo(s)")
exit(fallos == 0 ? 0 : 1)
