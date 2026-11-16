// Pruebas de las notificaciones push (Alma/NotifPush.swift y AjustesNotif.planPush, Hub Ticket #28).
//   swiftc Alma/AjustesNotif.swift Alma/NotifPush.swift Pruebas/NotifPush/main.swift -o /tmp/notif-push && /tmp/notif-push
// Las corre el robot en cada PR (testflight.yml, «Probar las notificaciones push»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}

// MARK: - Lo que trae el push (data.alma del Hub, pushapp.js)

let aj: [String: Any] = ["siri": true, "sonido": false, "vista": "siempre", "agrupar": "tipo"]
let lineasHub: [Any] = ["Socio: Brunelo", 3, "Mes: octubre"]
let alma: [String: Any] = ["id": "av1", "tipo": "socios", "aj": aj, "titulo": "Estado de cuenta", "lineas": lineasHub]
let viejo: [AnyHashable: Any] = ["aps": ["alert": ["title": "Alma", "body": "x"]], "custom": ["i": "os1", "a": ["alma": alma]]]
let nuevo: [AnyHashable: Any] = ["aps": ["alert": ["title": "Alma", "body": "x"]], "os_data": ["i": "os1"], "alma": alma]
let d1 = NotifPush.datos(viejo), d2 = NotifPush.datos(nuevo)
revisa(d1 != nil && d1 == d2, "lee data.alma en los dos formatos de OneSignal (custom.a y arriba)")
revisa(d1?.id == "av1" && d1?.tipo == .socios && d1?.titulo == "Estado de cuenta" && d1?.lineas == ["Socio: Brunelo", "Mes: octubre"],
       "el id del aviso, su tipo, el título y las líneas (lo que no es texto se descarta)")
revisa(d1?.ajuste.siri == true && d1?.ajuste.sonido == false && d1?.ajuste.agrupar == .tipo && d1?.ajuste.banner == true,
       "el ajuste del tipo viaja con el push; lo que falta, de fábrica")
revisa(NotifPush.datos(["aps": ["alert": "hola"]]) == nil, "un push sin datos de Alma se deja tal cual")
revisa(NotifPush.datos(["alma": ["id": "", "tipo": "socios"]]) == nil && NotifPush.datos(["alma": ["id": "a", "tipo": "clima"]]) == nil,
       "sin id o con un tipo que no existe, tampoco se toca")

// MARK: - El plan del push (la app dormida; la extensión no sabe si está bloqueado)

var a = AjusteNotif.deFabrica(.socios); a.siri = true
var p = AjustesNotif.planPush(tipo: .socios, ajuste: a, id: "av1")
revisa(p.siri && p.mostrar && p.contenido == .completo && p.nivel == .activa && p.sonido, "con Siri en el tipo: la anuncia Siri (app dormida), completa y con sonido")
a = AjusteNotif.deFabrica(.huespedes)
p = AjustesNotif.planPush(tipo: .huespedes, ajuste: a, id: "av1")
revisa(!p.siri && p.nivel == .activa, "sin Siri en el tipo: notificación normal, sin anuncio")
p = AjustesNotif.planPush(tipo: .urgentes, ajuste: .deFabrica(.urgentes), id: "u1")
revisa(p.siri && p.nivel == .urgente, "lo urgente de fábrica: con Siri y time-sensitive")
a = AjusteNotif.deFabrica(.equipo); a.vista = .desbloqueado
p = AjustesNotif.planPush(tipo: .equipo, ajuste: a, id: "e1")
revisa(p.contenido == .generico, "«solo desbloqueado» sale genérica (no se puede destapar después)")
a.vista = .nunca
revisa(AjustesNotif.planPush(tipo: .equipo, ajuste: a, id: "e1").contenido == .generico, "«nunca»: genérica")
a = AjusteNotif.deFabrica(.equipo); a.bloqueada = false
p = AjustesNotif.planPush(tipo: .equipo, ajuste: a, id: "e1")
revisa(!p.esperarDesbloqueo && p.nivel == .pasiva && !p.sonido && p.mostrar, "sin «Bloqueada»: llega pasiva, al centro, sin sonido (no puede esperar al desbloqueo)")
a = AjusteNotif.deFabrica(.equipo); a.centro = false
revisa(!AjustesNotif.planPush(tipo: .equipo, ajuste: a, id: "e1").quitarDelCentro, "sin «Centro»: la extensión no la puede quitar después")
a = AjusteNotif.deFabrica(.equipo); a.agrupar = .tipo
revisa(AjustesNotif.planPush(tipo: .equipo, ajuste: a, id: "e1").hilo == "alma.equipo", "agrupar por tipo: el hilo de su tipo, como las locales")
a = AjusteNotif(); a.bloqueada = false; a.centro = false; a.banner = false
revisa(!AjustesNotif.planPush(tipo: .equipo, ajuste: a, id: "e1").mostrar, "los tres apagados: no se muestra (el Hub tampoco la manda)")
var dp = d1!; dp.prueba = true; dp.ajuste.siri = false
revisa(NotifPush.plan(dp) == AjustesNotif.planPrueba(), "«Probar con Siri» por push: el plan de la prueba (con Siri aunque el tipo no lo tenga)")
revisa(NotifPush.plan(d1!) == AjustesNotif.planPush(tipo: .socios, ajuste: d1!.ajuste, id: "av1"), "lo demás, el plan de su tipo")

// MARK: - Cómo se ve (igual con push y local)

var c = NotifPush.contenido(texto: "Ya está el cambio.", titulo: "Facturas", lineas: ["Pedido: botón", " ", "Qué falta: unir"])
revisa(c.titulo == "Alma · Facturas" && c.subtitulo == "Ya está el cambio." && c.cuerpo == "· Pedido: botón\n· Qué falta: unir", "con líneas: título, el aviso arriba y las líneas con viñetas")
c = NotifPush.contenido(texto: "Corto.")
revisa(c.titulo == "Alma" && c.subtitulo == "" && c.cuerpo == "Corto.", "sin líneas y corto: solo el texto")
let largo = "Juan, revisé lo que pediste. " + String(repeating: "Hay más detalle aquí y allá. ", count: 6)
c = NotifPush.contenido(texto: largo)
revisa(c.subtitulo == "Juan, revisé lo que pediste" && c.cuerpo.hasPrefix("Juan, revisé"), "largo: la primera frase arriba y el texto entero abajo")

// MARK: - Sin duplicados

revisa(!NotifPush.mostrarLocal(["id": "a1", "push": true], enCentro: []), "lo que ya salió por push no se arma otra vez en la app")
revisa(!NotifPush.mostrarLocal(["id": "a1"], enCentro: ["a1"]), "si una con su id ya está en el centro, tampoco")
revisa(NotifPush.mostrarLocal(["id": "a2"], enCentro: ["a1"]) && NotifPush.mostrarLocal(["texto": "x"], enCentro: []), "lo demás, como siempre")

// MARK: - Registro (lo que manda el Hub y lo que la app le dice)

let cf = NotifPush.config(["app_id": "app1", "externo": "alma_x"])
revisa(cf?.app == "app1" && cf?.externo == "alma_x", "con qué registrarse: el App ID y el external_id que manda el Hub")
revisa(NotifPush.config(nil) == nil && NotifPush.config(["app_id": "app1"]) == nil && NotifPush.config(["app_id": " ", "externo": "alma_x"]) == nil,
       "sin las dos (no hay llaves en el Hub), nada: avisos locales como hoy")
revisa(NotifPush.listo(permiso: true, suscripcion: "s1", optedIn: true, externoApp: "alma_x", externoHub: "alma_x"), "listo: permiso, suscripción y el mismo external_id")
revisa(!NotifPush.listo(permiso: false, suscripcion: "s1", optedIn: true, externoApp: "alma_x", externoHub: "alma_x")
       && !NotifPush.listo(permiso: true, suscripcion: nil, optedIn: true, externoApp: "alma_x", externoHub: "alma_x")
       && !NotifPush.listo(permiso: true, suscripcion: "s1", optedIn: false, externoApp: "alma_x", externoHub: "alma_x")
       && !NotifPush.listo(permiso: true, suscripcion: "s1", optedIn: true, externoApp: "alma_y", externoHub: "alma_x"),
       "sin permiso, sin suscripción, pausada o con otro usuario: no está lista (el Hub no manda push)")
revisa(NotifPush.avisaQueDuerme(calle: false, conferencia: false, anillo: false), "al dormirse sin nada encendido, avisa al Hub")
revisa(!NotifPush.avisaQueDuerme(calle: true, conferencia: false, anillo: false) && !NotifPush.avisaQueDuerme(calle: false, conferencia: true, anillo: false)
       && !NotifPush.avisaQueDuerme(calle: false, conferencia: false, anillo: true), "con Modo calle, conferencia o el anillo sigue despierta: no avisa")

// MARK: - Al tocarla: el chat con el id del anillo o del tema (Hub #583 T1.3)

let conId: [String: Any] = ["id": "av9", "tipo": "socios", "aj": aj, "titulo": "Cupos Google", "orbita": "mpmpcupos1"]
let pushViejo: [AnyHashable: Any] = ["custom": ["a": ["alma": conId]]], pushNuevo: [AnyHashable: Any] = ["alma": conId]
revisa(NotifPush.datos(pushViejo)?.orbita == "mpmpcupos1" && NotifPush.orbita(pushViejo) == "mpmpcupos1" && NotifPush.orbita(pushNuevo) == "mpmpcupos1",
       "el push trae el id del anillo en data.alma (en los dos formatos de OneSignal)")
revisa(NotifPush.orbita(["id": "av1", "orbita": "tm123abc"]) == "tm123abc", "la local lo lleva en userInfo")
revisa(NotifPush.orbita(viejo) == nil && NotifPush.datos(viejo)?.orbita == "" && NotifPush.orbita(["orbita": ""]) == nil, "sin id (un aviso suelto), nada: se abre la app como siempre")
revisa(NotifPush.idOrbita("xx123") == nil && NotifPush.idOrbita("mp\"><script>") == nil && NotifPush.idOrbita("mp") == nil && NotifPush.idOrbita("es-1") == nil
       && NotifPush.idOrbita("ob" + String(repeating: "a", count: 90)) == nil && NotifPush.idOrbita("esesc1") == "esesc1" && NotifPush.idOrbita("obk2x91") == "obk2x91",
       "solo ids del Hub («mp», «es», «ob», «tm» y letras o números): lo demás nunca llega a la página")
revisa(NotifPush.pregunta(titulo: "Cupos Google") == "¿Qué pasó con «Cupos Google»? Cuéntame qué se hizo y en qué estado quedó."
       && NotifPush.pregunta(titulo: " ").hasPrefix("¿Qué pasó con esto?"), "la pregunta, como la del anillo (con su nombre si lo trae)")
let js = NotifPush.abrirChatJS(orbita: "mpmpcupos1", texto: "¿Qué pasó con «Cupos \"Google\"»?")
revisa(js.contains("SANav.chat(o)") && js.contains("\"orbita\":\"mpmpcupos1\"") && js.contains("\\\"Google\\\"") && js.hasSuffix(",30)"),
       "el JavaScript llama a SANav.chat con texto y orbita (en JSON, las comillas escapadas) y reintenta mientras carga")
revisa(NotifPush.abrirChatJS(orbita: "malo", texto: "x") == "", "con un id raro no arma nada")

if fallos > 0 { print("\(fallos) fallaron"); exit(1) }
print("Todo bien")
