// Pruebas de las notificaciones por tipo (Alma/AjustesNotif.swift, Hub #551).
//   swiftc Alma/AjustesNotif.swift Pruebas/AjustesNotif/main.swift -o /tmp/ajustes-notif && /tmp/ajustes-notif
// Las corre el robot en cada PR (testflight.yml, «Probar las notificaciones por tipo»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}

// MARK: - Lo que manda el Hub

let hub: [String: Any] = [
    "huespedes": ["bloqueada": true, "centro": true, "banner": false, "sonido": false, "numero": true, "siri": true, "vista": "nunca", "agrupar": "tipo"],
    "socios": ["siri": "sí", "vista": "raro", "agrupar": 3],
    "equipo": ["bloqueada": false, "centro": false, "banner": false]
]
let aj = AjustesNotif.todos(hub)
revisa(aj.count == 5 && TipoNotif.allCases.map(\.rawValue) == ["urgentes", "huespedes", "equipo", "socios", "pendientes"], "los 5 tipos de Juan")
let h = aj[.huespedes]!
revisa(!h.banner && !h.sonido && h.siri && h.vista == .nunca && h.agrupar == .tipo, "los ajustes de Huéspedes como los mandó el Hub")
revisa(aj[.socios]! == AjusteNotif.deFabrica(.socios), "lo que no sirve queda de fábrica")
revisa(aj[.urgentes]!.siri && !aj[.pendientes]!.siri && aj[.pendientes]!.llega && aj[.pendientes]!.sonido, "de fábrica: todo llega con sonido; Siri solo lo urgente")
revisa(AjustesNotif.todos(nil) == AjustesNotif.todos([:]) && AjustesNotif.tipo("HUESPEDES") == .huespedes && AjustesNotif.tipo("clima") == nil && AjustesNotif.tipo(nil) == nil,
       "sin ajustes, de fábrica; un tipo que no existe no se aplica (aviso de siempre)")
let datos = AjustesNotif.paraGuardar(hub)
revisa(datos != nil && AjustesNotif.guardados(datos) == aj && AjustesNotif.paraGuardar(nil) == nil && AjustesNotif.paraGuardar([String: Any]()) == nil,
       "se guardan para la próxima vez (y nada vacío pisa lo guardado)")

// MARK: - Dónde se ve (los tres teléfonos)

let cerrada = MomentoNotif()                                // app cerrada o en segundo plano, desbloqueado
let bloq = MomentoNotif(bloqueado: true)
func plan(_ t: TipoNotif, _ a: AjusteNotif, _ m: MomentoNotif = cerrada, id: String = "a1") -> PlanNotif { AjustesNotif.plan(tipo: t, ajuste: a, momento: m, id: id) }
var a = AjusteNotif.deFabrica(.huespedes)
var p = plan(.huespedes, a)
revisa(p.mostrar && p.nivel == .activa && p.sonido && p.hilo == "alma.retomar" && p.contenido == .completo && !p.esperarDesbloqueo && !p.quitarDelCentro,
       "de fábrica: como antes (activa, con sonido, el hilo de siempre)")
revisa(!plan(.equipo, aj[.equipo]!).mostrar, "los tres apagados: no se muestra")
a = AjusteNotif.deFabrica(.huespedes); a.bloqueada = false; a.banner = false
p = plan(.huespedes, a)
revisa(p.mostrar && p.nivel == .pasiva && !p.sonido && !p.bannerAbierta && p.listaAbierta, "solo centro: pasiva, sin sonido ni banner")
a = AjusteNotif.deFabrica(.huespedes); a.bloqueada = false
p = plan(.huespedes, a, bloq)
revisa(p.esperarDesbloqueo && p.nivel == .activa, "sin «Bloqueada» y bloqueado: espera a que lo desbloquees y sale con su banner")
revisa(!plan(.huespedes, a).esperarDesbloqueo, "sin «Bloqueada» y desbloqueado: sale ya")
a = AjusteNotif.deFabrica(.huespedes); a.banner = false
revisa(plan(.huespedes, a).nivel == .pasiva && plan(.huespedes, a, bloq).nivel == .activa, "sin «Banner»: desbloqueado va directo al centro; bloqueado se ve en la pantalla bloqueada")
a = AjusteNotif.deFabrica(.huespedes); a.centro = false
revisa(plan(.huespedes, a).quitarDelCentro && !plan(.huespedes, a).listaAbierta, "sin «Centro»: se quita del centro después de verse")

// MARK: - Sonido, urgente, agrupar

a = AjusteNotif.deFabrica(.socios); a.sonido = false
revisa(!plan(.socios, a).sonido && plan(.socios, a).nivel == .activa, "sin sonido: llega igual, callada")
revisa(plan(.urgentes, .deFabrica(.urgentes)).nivel == .urgente, "Urgentes con la app cerrada: time-sensitive")
var u = AjusteNotif.deFabrica(.urgentes); u.siri = false
revisa(plan(.urgentes, u).nivel == .activa, "Urgentes sin Siri: activa (time-sensitive lo anunciaría Siri de todos modos)")
revisa(plan(.urgentes, .deFabrica(.urgentes), MomentoNotif(calle: true)).nivel == .activa, "en Modo calle lo urgente no va time-sensitive (no se cruza con Alma)")
revisa(plan(.huespedes, .deFabrica(.huespedes)).nivel == .activa, "lo que no es urgente nunca va time-sensitive")
a = AjusteNotif.deFabrica(.socios); a.agrupar = .tipo
revisa(plan(.socios, a).hilo == "alma.socios", "agrupar por tipo: un hilo por tipo")
a.agrupar = .no
revisa(plan(.socios, a, id: "x1").hilo != plan(.socios, a, id: "x2").hilo, "agrupar «No»: cada una en su hilo")

// MARK: - Vista previa

a = AjusteNotif.deFabrica(.huespedes); a.vista = .nunca
revisa(plan(.huespedes, a).contenido == .generico && AjustesNotif.generico == "Alma te dejó un mensaje", "nunca: «Alma te dejó un mensaje»")
a.vista = .desbloqueado
revisa(plan(.huespedes, a, bloq).contenido == .tapado && plan(.huespedes, a).contenido == .completo, "solo desbloqueado: tapada con el teléfono bloqueado, completa desbloqueado")
a.bloqueada = false
revisa(plan(.huespedes, a, bloq).contenido == .completo, "si espera al desbloqueo, ya sale completa")

// MARK: - Siri y Alma no se pisan (Juan, 16-nov-2026)

let siriSi = AjusteNotif.deFabrica(.urgentes)
revisa(plan(.urgentes, siriSi, MomentoNotif(appActiva: false)).siri, "app cerrada o en segundo plano: Siri la anuncia")
revisa(plan(.urgentes, siriSi, bloq).siri, "teléfono bloqueado: Siri la anuncia")
revisa(!plan(.urgentes, siriSi, MomentoNotif(appActiva: true)).siri, "app abierta en primer plano: sin Siri")
revisa(!plan(.urgentes, siriSi, MomentoNotif(conferencia: true)).siri, "en conferencia: sin Siri")
revisa(!plan(.urgentes, siriSi, MomentoNotif(calle: true)).siri, "en Modo calle: sin Siri")
p = plan(.urgentes, siriSi, MomentoNotif(appActiva: true, seDice: true))
revisa(!p.siri && p.nivel == .pasiva && !p.sonido && !p.bannerAbierta && p.listaAbierta, "si Alma la dice: callada, pasiva, sin banner y sin Siri (como antes)")
revisa(!plan(.huespedes, .deFabrica(.huespedes), bloq).siri, "un tipo sin «Anunciar con Siri»: nunca Siri")
a = AjusteNotif.deFabrica(.huespedes); a.siri = true; a.bloqueada = false
p = plan(.huespedes, a, bloq)
revisa(p.siri && !p.esperarDesbloqueo, "con Siri encendido, sale ya aunque no vaya en la pantalla bloqueada (Siri la anuncia al llegar)")
revisa(!plan(.equipo, aj[.equipo]!, bloq).siri, "lo apagado no lo anuncia nadie")

// MARK: - «Probar con Siri» (Juan, 16-nov-2026)

let pp = AjustesNotif.planPrueba()
revisa(pp.siri && pp.mostrar && pp.contenido == .completo, "la prueba siempre va por el camino de Siri, completa (aunque el tipo no tenga Siri)")
revisa(!pp.esperarDesbloqueo && !pp.quitarDelCentro && pp.sonido, "la prueba sale aunque el teléfono esté bloqueado, suena y se queda en el centro")
revisa(pp.hilo != AjustesNotif.hiloDeSiempre, "la prueba va en su propio hilo, no se mezcla con los avisos")
revisa(AjustesNotif.pruebaEn == 15 && AjustesNotif.textoPrueba == "Prueba: si Siri te lee esto, los anuncios funcionan.", "a los 15 s, con el texto que pidió Juan")
revisa(AjustesNotif.pruebaDesdeHub > 0 && AjustesNotif.pruebaDesdeHub < AjustesNotif.pruebaEn, "la que pide el Hub web sale al llegar (iOS pide más de 0 s)")

if fallos > 0 { print("\(fallos) fallaron"); exit(1) }
print("Todo bien")
