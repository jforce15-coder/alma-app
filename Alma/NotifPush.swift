import Foundation

/// Notificaciones push reales (Hub, Ticket #28; Juan, 16-nov-2026). Lógica pura, sin iOS: la usan la app (PushAlma.swift,
/// VozNativa.swift, Notificaciones.swift) y la extensión de notificaciones (NotifAlma), y se prueba sola en Pruebas/NotifPush.
///   · El Hub (pushapp.js) manda un aviso por push SOLO si la app duerme (no preguntó en 100 s o avisó al dormirse) y su push
///     está listo. Despierta, la app arma la notificación local como siempre: Siri nunca habla encima de Alma.
///   · El push trae en `data.alma` el id del aviso, su tipo y el ajuste de ese tipo (y, con vista previa, el título y hasta 3
///     líneas). La extensión arma la notificación igual que la app (`contenido`) y con el plan de su tipo (`plan`).
///   · Sin duplicados: el aviso que salió por push llega a la app con `push: true` y la app no arma otra; además push y local
///     usan el mismo identificador (el id del aviso, `collapse_id` en OneSignal) y la app no arma una que ya esté en el centro.
///   · Sin datos del Hub (sin `alma`): la extensión deja el push tal cual.
///   · Al tocarla (Hub #583 T1.3): si habla de un anillo o un tema, trae su id (`orbita`: «mp…», «es…», «ob…», «tm…») y la app
///     abre el chat de la roca con ese id, el mismo camino que tocar el anillo en el inicio (SANav.chat con orbita).
struct DatosPush: Equatable {
    var id: String
    var tipo: TipoNotif
    var ajuste: AjusteNotif
    var prueba = false
    var titulo = ""
    var lineas: [String] = []
    var orbita = ""
}

/// Cómo se ve una notificación de Alma: título, subtítulo y cuerpo (lo mismo con push y local).
struct ContenidoNotif: Equatable {
    var titulo = "Alma"
    var subtitulo = ""
    var cuerpo = ""
}

enum NotifPush {
    /// Lo que el Hub puso en `data.alma`. OneSignal lo entrega en `custom.a` (formato de siempre) o arriba (formato nuevo).
    static func datos(_ userInfo: [AnyHashable: Any]) -> DatosPush? {
        let a = (userInfo["custom"] as? [String: Any])?["a"] as? [String: Any]
        guard let d = (a?["alma"] ?? userInfo["alma"]) as? [String: Any],
              let id = d["id"] as? String, !id.isEmpty, let tipo = AjustesNotif.tipo(d["tipo"] as? String) else { return nil }
        var x = DatosPush(id: id, tipo: tipo, ajuste: AjusteNotif.desde(d["aj"] as? [String: Any], tipo: tipo))
        x.prueba = (d["prueba"] as? Bool) == true
        x.titulo = (d["titulo"] as? String) ?? ""
        x.lineas = ((d["lineas"] as? [Any]) ?? []).compactMap { $0 as? String }
        x.orbita = idOrbita(d["orbita"] as? String) ?? ""
        return x
    }

    /// Un id de anillo o de tema como los manda el Hub (orbita.js, ORBITA_ID_RE_): «mp», «es», «ob» o «tm» y letras o
    /// números. Cualquier otra cosa, nil (nunca va al chat ni a la página).
    static func idOrbita(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), (4...82).contains(s.count),
              ["mp", "es", "ob", "tm"].contains(String(s.prefix(2))),
              s.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) && $0.isASCII }) else { return nil }
        return s
    }

    /// Al tocar una notificación: el id del anillo o del tema del que habla. Local: `orbita` en userInfo (Notificaciones.mostrar);
    /// push: `data.alma.orbita` (en `custom.a` o arriba). nil si no habla de uno.
    static func orbita(_ userInfo: [AnyHashable: Any]) -> String? {
        if let o = idOrbita(userInfo["orbita"] as? String) { return o }
        let a = (userInfo["custom"] as? [String: Any])?["a"] as? [String: Any]
        let d = (a?["alma"] ?? userInfo["alma"]) as? [String: Any]
        return idOrbita(d?["orbita"] as? String)
    }

    /// Lo que se le pregunta a Alma al abrir el chat desde la notificación (como al tocar el anillo: «¿Qué pasó con «X»?»).
    static func pregunta(titulo: String) -> String {
        let t = titulo.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "¿Qué pasó con esto? Cuéntame qué se hizo y en qué estado quedó." }
        return "¿Qué pasó con «" + String(t.prefix(60)) + "»? Cuéntame qué se hizo y en qué estado quedó."
    }

    /// El JavaScript que abre el chat de la roca con ese id (SANav.chat({ texto, orbita }), js/sa-nav.js). Si la página aún
    /// no está lista, reintenta cada medio segundo hasta 15 s. "" si no se puede armar.
    static func abrirChatJS(orbita: String, texto: String) -> String {
        guard let o = idOrbita(orbita), let data = try? JSONSerialization.data(withJSONObject: ["texto": texto, "orbita": o], options: [.sortedKeys]),
              let j = String(data: data, encoding: .utf8) else { return "" }
        let seguro = j.replacingOccurrences(of: "\u{2028}", with: "\\u2028").replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return "(function(o,n){function f(){try{if(window.SANav&&SANav.chat&&SANav.chat(o))return}catch(e){}if(--n>0)setTimeout(f,500)}f()})(" + seguro + ",30)"
    }

    /// El plan del push: la prueba siempre con Siri; lo demás con el ajuste de su tipo y la app dormida (AjustesNotif.planPush).
    static func plan(_ d: DatosPush) -> PlanNotif {
        d.prueba ? AjustesNotif.planPrueba() : AjustesNotif.planPush(tipo: d.tipo, ajuste: d.ajuste, id: d.id)
    }

    /// Título, subtítulo y cuerpo, como siempre (Notificaciones.mostrar): con líneas, «Alma · título», el aviso de subtítulo y
    /// las líneas con viñetas; sin ellas, el texto entero y, si es largo, su primera frase arriba.
    static func contenido(texto: String, titulo: String = "", lineas: [String] = []) -> ContenidoNotif {
        var c = ContenidoNotif()
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        let ls = lineas.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(3)
        let tit = titulo.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ls.isEmpty {
            if !tit.isEmpty { c.titulo = "Alma · " + String(tit.prefix(60)) }
            c.subtitulo = String(t.prefix(120))
            c.cuerpo = ls.map { "· " + $0 }.joined(separator: "\n")
        } else {
            let primera = t.components(separatedBy: CharacterSet(charactersIn: ".!?\n")).first ?? t
            if t.count > 90, !primera.isEmpty, primera.count <= 90 { c.subtitulo = primera }
            c.cuerpo = String(t.prefix(1000))
        }
        return c
    }

    /// ¿La app arma la notificación local de un aviso del Hub? No si ya salió por push (`push: true`) ni si una con su id ya
    /// está en el centro de notificaciones.
    static func mostrarLocal(_ aviso: [String: Any], enCentro: Set<String>) -> Bool {
        if (aviso["push"] as? Bool) == true { return false }
        guard let id = aviso["id"] as? String, !id.isEmpty else { return true }
        return !enCentro.contains(id)
    }

    /// Lo que la app le dice al Hub en vozAvisos: si su push está listo (permiso, suscripción de OneSignal y el external_id
    /// que mandó el Hub).
    static func listo(permiso: Bool, suscripcion: String?, optedIn: Bool, externoApp: String?, externoHub: String?) -> Bool {
        guard permiso, optedIn, let s = suscripcion, !s.isEmpty, let h = externoHub, !h.isEmpty else { return false }
        return externoApp == h
    }

    /// Lo que el Hub manda en vozAvisos para registrarse (`push`: { app_id, externo }). Sin él, nada: avisos locales.
    static func config(_ hub: Any?) -> (app: String, externo: String)? {
        guard let d = hub as? [String: Any], let app = d["app_id"] as? String, let ext = d["externo"] as? String else { return nil }
        let a = app.trimmingCharacters(in: .whitespaces), e = ext.trimmingCharacters(in: .whitespaces)
        return a.isEmpty || e.isEmpty ? nil : (a, e)
    }

    /// ¿Avisa al Hub que se duerme? Solo si nada la mantiene despierta (Modo calle, conferencia, el anillo esperando): así el
    /// Hub manda por push lo que nazca mientras duerme. Si sigue despierta, su próxima pregunta lo corrige sola.
    static func avisaQueDuerme(calle: Bool, conferencia: Bool, anillo: Bool) -> Bool { !calle && !conferencia && !anillo }
}
