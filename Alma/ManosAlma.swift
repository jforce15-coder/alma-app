import UIKit
import WebKit

extension Notification.Name {
    /// Alma usó sus manos en el navegador (ManosAlma): la pantalla de la llamada se baja para que Juan vea la página.
    static let manosAlma = Notification.Name("alma.manos")
}

/// Manos de Alma (navegador), #396 T3: durante la llamada, Alma maneja el navegador de la app con herramientas de cliente
/// (VozNativa.herramientaCliente): leer_pagina, senalar, tocar, escribir, bajar y abrir. Idea de Atticus («Draw on screen»
/// y el trabajo web en su propia ventana): se lee la página como una lista de elementos con número (data-alma-id), se
/// marca dónde tocar con un círculo durazno, paso a paso, y se actúa dentro del navegador de Alma, nunca en otra app.
/// · Lo que compra, paga, envía, borra o confirma no se toca: vuelve { necesita_permiso, que } y Alma le pregunta a Juan.
///   El sí vale solo para ese elemento, en esa página y por 2 minutos (la segunda llamada trae confirmado: true).
/// · Contraseñas y tarjetas: nunca se escriben; las escribe Juan.
/// · Después de actuar se dice qué cambió (página, título, aviso) o «no pude confirmar el resultado».
/// El JS corre en su propio mundo (WKContentWorld.defaultClient): la página no lo ve ni lo puede cambiar.
final class ManosAlma {
    static let shared = ManosAlma()
    weak var nav: Navegador?
    static let herramientas: Set<String> = ["leer_pagina", "senalar", "tocar", "escribir", "bajar", "abrir"]
    /// El permiso que Alma pidió (necesita_permiso): vale para ese elemento, en esa página, por 2 minutos.
    private var permiso: (id: String, url: String, hasta: Date)?

    /// Para la ficha de la llamada: qué tiene abierto el navegador (las reglas de Alma están en el Hub, voz.js).
    var ficha: String {
        guard let nav, UIApplication.shared.applicationState == .active else { return "" }
        if nav.enInicio { return "NAVEGADOR DE ALMA: está en el inicio, sin página abierta. Si Juan te pide abrir o buscar algo en una página, usa abrir." }
        let donde = nav.titulo.isEmpty ? nav.direccion : "«" + nav.titulo + "» (" + nav.direccion + ")"
        return "NAVEGADOR DE ALMA: Juan tiene abierta " + donde + ". Tus manos (leer_pagina, senalar, tocar, escribir, bajar, abrir) trabajan ahí."
    }

    /// Corre una herramienta y siempre contesta (texto JSON, ¿es error?): Alma nunca se queda esperando.
    func correr(_ nombre: String, _ p: [String: Any], _ fin: @escaping (String, Bool) -> Void) {
        guard UIApplication.shared.applicationState == .active else {
            fin(ManosAlma.json(["error": "Juan no tiene la pantalla a la vista (teléfono bloqueado): no puedo usar el navegador. Díselo por voz."]), true); return
        }
        guard let nav else { fin(ManosAlma.json(["error": "El navegador de Alma no está listo."]), true); return }
        NotificationCenter.default.post(name: .manosAlma, object: nil)
        if nombre == "abrir" { abrir(ManosAlma.texto(p["url"]), fin); return }
        guard !nav.enInicio else {
            fin(ManosAlma.json(["sin_pagina": true, "motivo": "El navegador de Alma está en el inicio, sin página abierta. Usa abrir con la dirección o con lo que hay que buscar."]), false); return
        }
        let id = ManosAlma.texto(p["id"])
        switch nombre {
        case "leer_pagina":
            js("leer", [:]) { r in fin(r.map(ManosAlma.json) ?? ManosAlma.sinRespuesta, r == nil) }
        case "senalar":
            js("senalar", ["id": id, "texto": ManosAlma.texto(p["texto"])]) { r in fin(r.map(ManosAlma.json) ?? ManosAlma.sinRespuesta, r == nil || r?["error"] != nil) }
        case "escribir":
            let enter = ManosAlma.si(p["enter"])
            js("escribir", ["id": id, "texto": ManosAlma.texto(p["texto"]), "enter": enter]) { [weak self] r in
                guard let r else { fin(ManosAlma.sinRespuesta, true); return }
                // Con Enter puede cambiar la página (una búsqueda): se espera y se dice qué cambió.
                if enter, (r["ok"] as? Bool) == true, r["nota"] == nil, let self { self.resultado(r, fin); return }
                fin(ManosAlma.json(r), r["error"] != nil)
            }
        case "bajar":
            js("bajar", ["cuanto": ManosAlma.texto(p["cuanto"])]) { r in fin(r.map(ManosAlma.json) ?? ManosAlma.sinRespuesta, r == nil) }
        case "tocar":
            tocar(id, confirmado: ManosAlma.si(p["confirmado"]), fin)
        default:
            fin(ManosAlma.json(["error": "Esta herramienta no existe en la app."]), true)
        }
    }

    private func tocar(_ id: String, confirmado: Bool, _ fin: @escaping (String, Bool) -> Void) {
        let url = nav?.direccion ?? ""
        let vale = confirmado && permiso.map { $0.id == id && $0.url == url && $0.hasta > Date() } == true
        js("tocar", ["id": id, "confirmado": vale]) { [weak self] r in
            guard let self else { return }
            guard var r else { fin(ManosAlma.sinRespuesta, true); return }
            if (r["necesita_permiso"] as? Bool) == true {
                self.permiso = (id, url, Date().addingTimeInterval(120))
                r["instruccion"] = (confirmado ? "Ese sí no vale para esto (otro elemento, otra página o pasó mucho tiempo). " : "No lo toqué. ")
                    + "Pregúntale a Juan por voz, en una frase, si lo haces (di qué es). Solo si dice que sí, llama tocar con el mismo id y confirmado: true."
                fin(ManosAlma.json(r), false); return
            }
            self.permiso = nil
            guard (r["ok"] as? Bool) == true else { fin(ManosAlma.json(r), true); return }
            self.resultado(r, fin)
        }
    }

    /// Después de tocar (o de Enter): espera a que la página reaccione y dice qué cambió, o que no se pudo confirmar.
    private func resultado(_ r: [String: Any], _ fin: @escaping (String, Bool) -> Void) {
        var o = r; o["antes"] = nil
        let antes = r["antes"] as? [String: Any] ?? [:]
        esperarCarga(desde: Date()) { [weak self] in
            guard let self else { return }
            self.js("estado", [:]) { e in
                let web = self.nav?.web
                let url = (e?["url"] as? String) ?? web?.url?.absoluteString ?? ""
                let titulo = (e?["titulo"] as? String) ?? web?.title ?? ""
                let aviso = e?["aviso"] as? String ?? ""
                var cambio: [String] = []
                if let u0 = antes["url"] as? String, u0 != url { cambio.append("La página cambió a «" + titulo + "» (" + url + ").") }
                else if let t0 = antes["titulo"] as? String, t0 != titulo { cambio.append("El título ahora es «" + titulo + "».") }
                if !aviso.isEmpty && aviso != (antes["aviso"] as? String ?? "") { cambio.append("Aviso en la página: «" + aviso + "».") }
                if let l = r["luego"] as? String { cambio.append("El elemento " + l + ".") }
                if cambio.isEmpty, let f = e?["firma"] as? String, let f0 = antes["firma"] as? String, f != f0 {
                    cambio.append("Algo cambió en la página (apareció o se movió algo); usa leer_pagina si necesitas saber qué.")
                }
                o["resultado"] = cambio.isEmpty ? "No pude confirmar el resultado: la página se ve igual. Díselo a Juan así." : cambio.joined(separator: " ")
                o["ahora"] = ["titulo": titulo, "url": url]
                fin(ManosAlma.json(o), false)
            }
        }
    }

    /// Abre una dirección (o busca en Google) en el navegador de Alma. Solo páginas web: nada de javascript:, file: ni data:.
    private func abrir(_ t0: String, _ fin: @escaping (String, Bool) -> Void) {
        let t = t0.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { fin(ManosAlma.json(["error": "Falta la dirección o lo que hay que buscar."]), true); return }
        if let s = URL(string: t)?.scheme?.lowercased(), t.contains("://") || ["javascript", "data", "file", "blob", "about"].contains(s), !["http", "https"].contains(s) {
            fin(ManosAlma.json(["error": "Solo abro páginas web (http o https)."]), true); return
        }
        guard let nav else { fin(ManosAlma.sinRespuesta, true); return }
        permiso = nil
        nav.abrir(texto: t)
        esperarCarga(desde: Date()) { [weak self] in
            let web = self?.nav?.web
            var o: [String: Any] = ["ok": true, "que": "Abrí la página en el navegador de Alma.",
                                    "ahora": ["titulo": web?.title ?? "", "url": web?.url?.absoluteString ?? ""]]
            if web?.isLoading == true { o["nota"] = "Sigue cargando; espera un momento antes de leer_pagina." }
            fin(ManosAlma.json(o), false)
        }
    }

    /// Un momento para que la página reaccione y, si está cargando, hasta 8 s para que termine.
    private func esperarCarga(desde: Date, _ listo: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            let t = Date().timeIntervalSince(desde)
            if t < 1.2 || (self?.nav?.web.isLoading == true && t < 8) { self?.esperarCarga(desde: desde, listo) } else { listo() }
        }
    }

    /// Corre el JS de las manos en la página (su propio mundo) y devuelve lo que contestó.
    private func js(_ cmd: String, _ args: [String: Any], _ fin: @escaping ([String: Any]?) -> Void) {
        guard let web = nav?.web, let d = try? JSONSerialization.data(withJSONObject: args), let a = String(data: d, encoding: .utf8) else { fin(nil); return }
        let codigo = ManosAlma.script + "\n;window.__almaManos('" + cmd + "', " + a + ");"
        web.evaluateJavaScript(codigo, in: nil, in: .defaultClient) { r in
            var o: [String: Any]?
            if case .success(let v) = r, let s = v as? String, let d = s.data(using: .utf8) {
                o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
            }
            fin(o)
        }
    }

    static let sinRespuesta = json(["error": "La página no contestó (quizá está cargando). No pude confirmar el resultado."])
    static func json(_ o: [String: Any]) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }
    /// ElevenLabs puede mandar un número como número o como texto.
    static func texto(_ v: Any?) -> String {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }
    static func si(_ v: Any?) -> Bool {
        if let b = v as? Bool { return b }
        if let s = v as? String { return ["true", "si", "sí", "1"].contains(s.lowercased()) }
        return false
    }

    /// El JS de las manos (probado aparte con una página de ejemplo): leer, senalar, tocar, escribir, bajar, estado.
    static let script = #"""
(function(){
  if (window.__almaManos) return;
  var CORAL = '#E9826A';
  /* Lo que compra, paga, envía, borra o confirma: nunca se toca sin el sí de Juan. */
  var RIESGO = /\b(comprar|compra|compralo|cómpralo|pagar|pago|paga|enviar|envíar|envía|envialo|envíalo|mandar|send|submit|checkout|check out|order|ordenar|delete|borrar|eliminar|quitar cuenta|confirmar|confirm|buy|purchase|pay|payment|transferir|transfer|donar|donate|publicar|publish|reservar|book now|suscribirme|subscribe|place order|finalizar compra)\b/i;
  var RIESGO_URL = /(checkout|\/pay\b|\/pago|payment|purchase|\/delete|\/remove|\/borrar|\/eliminar|unsubscribe|\/order)/i;
  var SENSIBLE = /(card|tarjeta|cvv|cvc|csc|cc-?num|cc-?exp|security.?code|c[oó]digo de seguridad|contraseña|password|passwd|\bclave\b|\bpin\b|iban|routing)/i;
  var n = 0;
  var reducido = function () { try { return matchMedia('(prefers-reduced-motion: reduce)').matches; } catch (e) { return false; } };
  var limpio = function (s, max) { s = String(s == null ? '' : s).replace(/\s+/g, ' ').trim(); return max && s.length > max ? s.slice(0, max - 1) + '…' : s; };
  var res = function (o) { return JSON.stringify(o); };

  function visible(e) {
    var r = e.getBoundingClientRect(); if (r.width < 2 || r.height < 2) return false;
    var s = getComputedStyle(e); if (s.visibility === 'hidden' || s.display === 'none' || +s.opacity < 0.05) return false;
    return true;
  }
  function enPantalla(r) { return r.bottom > 0 && r.top < innerHeight && r.right > 0 && r.left < innerWidth; }
  function rol(e) {
    var t = e.tagName, ty = (e.getAttribute('type') || '').toLowerCase(), ro = (e.getAttribute('role') || '').toLowerCase();
    if (ro === 'button') return 'botón'; if (ro === 'link') return 'enlace'; if (ro === 'checkbox') return 'casilla'; if (ro === 'switch') return 'interruptor';
    if (ro === 'tab') return 'pestaña'; if (ro === 'menuitem') return 'menú'; if (ro === 'option') return 'opción'; if (ro === 'radio') return 'opción';
    if (ro === 'textbox' || ro === 'searchbox' || ro === 'combobox') return 'campo';
    if (t === 'A') return 'enlace'; if (t === 'BUTTON' || t === 'SUMMARY') return 'botón'; if (t === 'SELECT') return 'lista'; if (t === 'TEXTAREA') return 'campo';
    if (t === 'INPUT') {
      if (ty === 'checkbox') return 'casilla'; if (ty === 'radio') return 'opción';
      if (ty === 'submit' || ty === 'button' || ty === 'reset' || ty === 'image') return 'botón';
      if (ty === 'password') return 'contraseña';
      return 'campo';
    }
    if (e.isContentEditable) return 'campo';
    return 'botón';
  }
  /* El texto de una etiqueta que envuelve al control, sin el texto del control (las opciones de una lista). */
  function sinControl(nodo, e) {
    if (nodo === e) return '';
    if (nodo.nodeType === 3) return nodo.nodeValue;
    var t = ''; for (var i = 0; i < nodo.childNodes.length; i++) t += ' ' + sinControl(nodo.childNodes[i], e);
    return t;
  }
  function etiqueta(e) {
    var l = e.getAttribute('aria-label') || '';
    if (!l && e.getAttribute('aria-labelledby')) { var x = document.getElementById(e.getAttribute('aria-labelledby')); if (x) l = x.innerText; }
    if (!l && e.labels && e.labels.length) l = sinControl(e.labels[0], e);
    var t = e.tagName;
    if (!l && (t === 'INPUT' || t === 'TEXTAREA' || t === 'SELECT')) {
      var ty = (e.type || '').toLowerCase();
      if (ty === 'submit' || ty === 'button' || ty === 'reset') l = e.value;
      if (!l) l = e.placeholder || e.title || e.name || e.id || '';
    }
    if (!l) l = e.innerText || e.textContent || '';
    if (!l) { var im = e.querySelector && e.querySelector('img[alt]'); if (im) l = im.alt; }
    if (!l) l = e.title || '';
    return limpio(l, 70);
  }
  function sensible(e) {
    if ((e.type || '').toLowerCase() === 'password') return 'es una contraseña';
    var ac = (e.getAttribute('autocomplete') || '').toLowerCase();
    if (/cc-|current-password|new-password/.test(ac)) return 'es un dato de tarjeta o una contraseña';
    var pista = [e.name, e.id, e.placeholder, e.getAttribute('aria-label'), e.labels && e.labels[0] && sinControl(e.labels[0], e)].join(' ');
    if (SENSIBLE.test(pista)) return 'parece un dato de tarjeta o una contraseña';
    return '';
  }
  function busqueda(f) {
    if (!f) return false;
    if ((f.getAttribute('role') || '') === 'search') return true;
    if ((f.method || 'get').toLowerCase() !== 'get') return false;
    return !!f.querySelector('input[type=search],input[name=q],input[name=query],input[name=search],input[name=s],input[name=k],input[name=buscar]');
  }
  /* ¿Este toque compra, paga, envía, borra o confirma? Devuelve qué haría, o "" si es seguro. */
  function riesgo(e) {
    var texto = etiqueta(e), t = e.tagName, ty = (e.type || '').toLowerCase();
    if (RIESGO.test(texto) || RIESGO.test(e.value || '') || RIESGO.test(e.title || '')) return 'Tocar «' + texto + '»';
    var href = t === 'A' ? (e.getAttribute('href') || '') : '';
    if (href && RIESGO_URL.test(href)) return 'Abrir «' + texto + '» (' + limpio(href, 60) + ')';
    var f = e.form || (e.closest && e.closest('form'));
    var envia = (t === 'BUTTON' && (ty === 'submit' || !e.getAttribute('type')) && e.form) || (t === 'INPUT' && (ty === 'submit' || ty === 'image'));
    if (f) {
      var clave = f.querySelector('input[type=password]');
      if (envia && clave) return 'Enviar el formulario con contraseña («' + texto + '»)';
      if (envia && RIESGO_URL.test(f.getAttribute('action') || '')) return 'Enviar el formulario a ' + limpio(f.getAttribute('action'), 60);
      if (envia && RIESGO.test(f.getAttribute('action') || '')) return 'Enviar el formulario a ' + limpio(f.getAttribute('action'), 60);
      if (envia && !busqueda(f)) return 'Enviar el formulario («' + texto + '»)';
    }
    return '';
  }
  function marcar(e) { var id = e.getAttribute('data-alma-id'); if (!id) { id = String(++n); e.setAttribute('data-alma-id', id); } return id; }
  function buscar(id) { return document.querySelector('[data-alma-id="' + String(id).replace(/[^0-9]/g, '') + '"]'); }
  var SEL = 'a[href],button,input:not([type=hidden]),select,textarea,summary,[role=button],[role=link],[role=checkbox],[role=switch],[role=tab],[role=menuitem],[role=option],[role=radio],[role=textbox],[role=searchbox],[role=combobox],[contenteditable=""],[contenteditable=true],[onclick]';

  function estado() {
    var avisos = [];
    document.querySelectorAll('[role=alert],[role=status],[aria-live=assertive],[aria-live=polite],.toast,.snackbar,.alert,.notification,.flash,.notice').forEach(function (a) {
      if (a.closest('#__alma_senal')) return;
      var t = limpio(a.innerText, 160); if (t && visible(a) && avisos.indexOf(t) < 0) avisos.push(t);
    });
    var b = document.body ? document.body.innerText || '' : '';
    return { url: location.href, titulo: document.title, firma: b.length + ':' + document.getElementsByTagName('*').length, aviso: limpio(avisos.join(' · '), 300) };
  }

  function leer() {
    limpiarSenal();
    var dentro = [], fuera = [];
    document.querySelectorAll(SEL).forEach(function (e) {
      if (e.closest('#__alma_senal') || e.disabled || !visible(e)) return;
      var r = e.getBoundingClientRect(), R = rol(e), txt = etiqueta(e);
      if (!txt && R !== 'campo' && R !== 'contraseña') return;
      var l = marcar(e) + ' · ' + R + ' · ' + (txt || 'sin nombre');
      if (R === 'casilla' || (R === 'opción' && e.tagName === 'INPUT')) l += e.checked ? ' (marcada)' : ' (sin marcar)';
      else if (R === 'contraseña') l += ' (la escribe Juan)';
      else if (R === 'lista' && e.selectedIndex >= 0) l += ' = «' + limpio(e.options[e.selectedIndex].text, 40) + '»';
      else if (R === 'campo' && e.tagName !== 'A' && !sensible(e)) { var v = limpio(e.isContentEditable ? e.innerText : e.value, 40); if (v) l += ' = «' + v + '»'; }
      else if (R === 'campo' && sensible(e)) l += ' (dato sensible: lo escribe Juan)';
      if (riesgo(e)) l += ' ⚠';
      if (enPantalla(r)) dentro.push({ y: r.top, l: l }); else fuera.push({ y: r.top, l: l + (r.top < 0 ? ' (más arriba)' : ' (más abajo)') });
    });
    dentro.sort(function (a, b) { return a.y - b.y; });
    fuera.sort(function (a, b) { return Math.abs(a.y) - Math.abs(b.y); });
    var lista = dentro.slice(0, 60).concat(fuera.slice(0, Math.max(10, 80 - Math.min(60, dentro.length)))).map(function (x) { return x.l; });
    var raiz = document.querySelector('main,[role=main],article') || document.body;
    var texto = raiz ? String(raiz.innerText || '').replace(/[ \t]+/g, ' ').replace(/\n\s*\n+/g, '\n').trim() : '';
    var sc = document.scrollingElement || document.documentElement;
    var pos = sc.scrollHeight > innerHeight ? Math.round(100 * sc.scrollTop / Math.max(1, sc.scrollHeight - innerHeight)) : 100;
    return { titulo: document.title, url: location.href, elementos: lista, total: dentro.length + fuera.length,
      texto: texto.length > 4000 ? texto.slice(0, 3999) + '…' : texto, bajado: pos + '%', nota: '⚠ = compra, paga, envía, borra o confirma: pide permiso antes de tocarlo.' };
  }

  /* ── El señalador: un círculo durazno con su etiqueta y una flechita, encima de todo, sin tapar los toques ── */
  var senal = null, reloj = 0;
  function limpiarSenal() { cancelAnimationFrame(reloj); if (senal) { senal.host.remove(); senal = null; } }
  document.addEventListener('pointerdown', function (ev) { if (senal) limpiarSenal(); }, true);
  function senalar(id, texto) {
    limpiarSenal();
    var e = buscar(id); if (!e) return { error: 'No encuentro ese elemento. Vuelve a leer la página (leer_pagina).' };
    var quieto = reducido();
    try { e.scrollIntoView({ block: 'center', inline: 'nearest', behavior: quieto ? 'auto' : 'smooth' }); } catch (x) { e.scrollIntoView(); }
    var host = document.createElement('div'); host.id = '__alma_senal';
    host.style.cssText = 'all:initial;position:fixed;inset:0;pointer-events:none;z-index:2147483647';
    var sh = host.attachShadow ? host.attachShadow({ mode: 'closed' }) : host;
    sh.innerHTML = '<style>' +
      '.aro{position:fixed;border:3px solid ' + CORAL + ';border-radius:16px;box-shadow:0 0 0 4px rgba(233,130,106,.25),0 6px 18px rgba(0,0,0,.18);box-sizing:border-box}' +
      '.pulso{animation:p 1.6s ease-out infinite}@keyframes p{0%{box-shadow:0 0 0 0 rgba(233,130,106,.55),0 6px 18px rgba(0,0,0,.18)}100%{box-shadow:0 0 0 16px rgba(233,130,106,0),0 6px 18px rgba(0,0,0,.18)}}' +
      '.et{position:fixed;max-width:min(78vw,320px);background:' + CORAL + ';color:#fff;font:600 15px/1.3 -apple-system,system-ui,Montserrat,sans-serif;padding:9px 13px;border-radius:14px;box-shadow:0 6px 18px rgba(0,0,0,.22);box-sizing:border-box}' +
      '.fl{position:fixed;width:0;height:0;border-left:9px solid transparent;border-right:9px solid transparent}' +
      '.ab{border-top:10px solid ' + CORAL + '}.ar{border-bottom:10px solid ' + CORAL + '}' +
      '</style><div class="aro' + (quieto ? '' : ' pulso') + '"></div><div class="fl"></div><div class="et"></div>';
    var aro = sh.querySelector('.aro'), et = sh.querySelector('.et'), fl = sh.querySelector('.fl');
    et.textContent = limpio(texto, 90) || 'Aquí';
    (document.body || document.documentElement).appendChild(host);
    senal = { host: host };
    function pintar() {
      if (!senal || !e.isConnected) { limpiarSenal(); return; }
      var r = e.getBoundingClientRect(), m = 6;
      var x = Math.max(2, r.left - m), y = r.top - m, w = Math.min(innerWidth - 4, r.width + 2 * m), h = r.height + 2 * m;
      if (r.width < 40 && r.height < 40) { var c = Math.max(r.width, r.height) + 2 * m + 8; x = r.left + r.width / 2 - c / 2; y = r.top + r.height / 2 - c / 2; w = h = c; aro.style.borderRadius = '50%'; }
      aro.style.left = x + 'px'; aro.style.top = y + 'px'; aro.style.width = w + 'px'; aro.style.height = h + 'px';
      var eh = et.offsetHeight, ew = et.offsetWidth, arriba = y - eh - 14 > 8;
      var ex = Math.min(Math.max(8, x + w / 2 - ew / 2), innerWidth - ew - 8);
      var ey = arriba ? y - eh - 12 : y + h + 12;
      et.style.left = ex + 'px'; et.style.top = ey + 'px';
      var fx = Math.min(Math.max(ex + 12, x + w / 2 - 9), ex + ew - 30);
      fl.className = 'fl ' + (arriba ? 'ab' : 'ar');
      fl.style.left = fx + 'px'; fl.style.top = (arriba ? ey + eh - 1 : ey - 9) + 'px';
      reloj = requestAnimationFrame(pintar);
    }
    pintar();
    return { ok: true, que: 'Marqué «' + etiqueta(e) + '» en la pantalla de Juan.', riesgo: riesgo(e) || undefined };
  }

  function tocar(id, confirmado) {
    var e = buscar(id); if (!e) return { error: 'No encuentro ese elemento. Vuelve a leer la página (leer_pagina).' };
    var r = riesgo(e);
    if (r && !confirmado) return { necesita_permiso: true, que: r };
    if (sensible(e) && (e.tagName === 'INPUT')) { /* tocar un campo sensible solo lo enfoca */ }
    limpiarSenal();
    var antes = estado();
    try { e.scrollIntoView({ block: 'center', inline: 'nearest' }); } catch (x) {}
    var o = { bubbles: true, cancelable: true, view: window };
    try { e.dispatchEvent(new PointerEvent('pointerdown', o)); } catch (x) {}
    e.dispatchEvent(new MouseEvent('mousedown', o));
    try { e.dispatchEvent(new PointerEvent('pointerup', o)); } catch (x) {}
    e.dispatchEvent(new MouseEvent('mouseup', o));
    if (e.focus) try { e.focus({ preventScroll: true }); } catch (x) {}
    e.click();
    var luego = '';
    if (e.tagName === 'INPUT' && /checkbox|radio/.test(e.type)) luego = e.checked ? 'quedó marcada' : 'quedó sin marcar';
    else if (e.getAttribute('aria-expanded')) luego = e.getAttribute('aria-expanded') === 'true' ? 'se abrió' : 'se cerró';
    else if (e.getAttribute('aria-checked')) luego = e.getAttribute('aria-checked') === 'true' ? 'quedó activado' : 'quedó apagado';
    return { ok: true, que: 'Toqué «' + etiqueta(e) + '»', luego: luego || undefined, antes: antes };
  }

  function escribir(id, texto, enter) {
    var e = buscar(id); if (!e) return { error: 'No encuentro ese elemento. Vuelve a leer la página (leer_pagina).' };
    texto = String(texto == null ? '' : texto);
    var s = sensible(e);
    if (s) return { rechazado: true, motivo: 'No escribo ahí: ' + s + '. Que Juan lo escriba él mismo.' };
    if (/^[\d\s-]{13,23}$/.test(texto.trim()) && texto.replace(/\D/g, '').length >= 13) return { rechazado: true, motivo: 'Parece un número de tarjeta: no lo escribo. Que Juan lo escriba él mismo.' };
    limpiarSenal();
    try { e.scrollIntoView({ block: 'center', inline: 'nearest' }); } catch (x) {}
    var t = e.tagName, nombre = etiqueta(e);
    if (t === 'SELECT') {
      var q = limpio(texto).toLowerCase(), elegida = -1;
      for (var i = 0; i < e.options.length; i++) { var ot = limpio(e.options[i].text).toLowerCase(); if (ot === q) { elegida = i; break; } if (elegida < 0 && ot.indexOf(q) >= 0) elegida = i; }
      if (elegida < 0) return { error: 'Esa lista no tiene «' + texto + '». Opciones: ' + Array.prototype.slice.call(e.options, 0, 15).map(function (o) { return limpio(o.text, 30); }).join(', ') };
      e.selectedIndex = elegida; e.dispatchEvent(new Event('input', { bubbles: true })); e.dispatchEvent(new Event('change', { bubbles: true }));
      return { ok: true, que: 'Elegí «' + limpio(e.options[elegida].text, 40) + '» en «' + nombre + '»', confirmado: true };
    }
    if (t === 'INPUT' && /checkbox|radio/.test(e.type)) {
      var quiere = !/^(no|false|0|desmarcar|quitar|apagar)$/i.test(limpio(texto));
      if (e.checked !== quiere) e.click();
      return { ok: true, que: (e.checked ? 'Marqué' : 'Desmarqué') + ' «' + nombre + '»', confirmado: e.checked === quiere };
    }
    if (e.focus) try { e.focus({ preventScroll: true }); } catch (x) {}
    if (e.isContentEditable) {
      var sel = getSelection(), rg = document.createRange(); rg.selectNodeContents(e); sel.removeAllRanges(); sel.addRange(rg);
      document.execCommand('insertText', false, texto);
      return { ok: true, que: 'Escribí en «' + nombre + '»', confirmado: limpio(e.innerText) === limpio(texto) };
    }
    if (t !== 'INPUT' && t !== 'TEXTAREA') return { error: 'Ahí no se escribe (es un ' + rol(e) + '). Usa tocar.' };
    var p = t === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    Object.getOwnPropertyDescriptor(p, 'value').set.call(e, texto);
    e.dispatchEvent(new Event('input', { bubbles: true })); e.dispatchEvent(new Event('change', { bubbles: true }));
    var out = { ok: true, que: 'Escribí en «' + nombre + '»', confirmado: e.value === texto, valor: e.value === texto ? undefined : limpio(e.value, 60) };
    if (enter) {   // «búscame…»: Enter solo en una búsqueda; un formulario de verdad se envía con su botón (y pide permiso)
      var f = e.form || e.closest('form');
      if (f && !busqueda(f)) { out.nota = 'No di Enter: este formulario envía algo. Toca su botón (pide permiso).'; return out; }
      out.antes = estado();   // para decir después qué cambió
      var k = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true };
      var sigue = e.dispatchEvent(new KeyboardEvent('keydown', k)); e.dispatchEvent(new KeyboardEvent('keyup', k));
      if (f && sigue) { if (f.requestSubmit) f.requestSubmit(); else f.submit(); }
      out.que += ' y di Enter';
    }
    return out;
  }

  function bajar(cuanto) {
    limpiarSenal();
    var sc = document.scrollingElement || document.documentElement, caja = null;
    if (sc.scrollHeight <= innerHeight + 4) {   // la página no se mueve: se busca la caja que sí (apps de una sola pantalla)
      var mejor = 0;
      document.querySelectorAll('body *').forEach(function (x) {
        if (x.scrollHeight > x.clientHeight + 20 && x.clientHeight > 150) { var oy = getComputedStyle(x).overflowY; if ((oy === 'auto' || oy === 'scroll') && x.clientHeight > mejor) { mejor = x.clientHeight; caja = x; } }
      });
    }
    var el = caja || sc, alto = caja ? caja.clientHeight : innerHeight, c = String(cuanto || 'pantalla').toLowerCase(), dy;
    if (c === 'inicio' || c === 'arriba del todo') dy = -el.scrollHeight;
    else if (c === 'final' || c === 'fin' || c === 'abajo del todo') dy = el.scrollHeight;
    else if (c === 'subir' || c === 'arriba') dy = -alto * 0.85;
    else if (c === 'poco' || c === 'un poco') dy = alto * 0.4;
    else if (!isNaN(parseFloat(c))) dy = alto * Math.max(-5, Math.min(5, parseFloat(c)));
    else dy = alto * 0.85;
    var y0 = el.scrollTop;
    el.scrollBy({ top: dy, behavior: 'auto' });
    var max = Math.max(1, el.scrollHeight - alto), y1 = el.scrollTop;
    return { ok: true, que: Math.abs(y1 - y0) < 2 ? (dy > 0 ? 'Ya está hasta abajo' : 'Ya está hasta arriba') : (dy > 0 ? 'Bajé' : 'Subí'),
      bajado: Math.round(100 * y1 / max) + '%', al_final: y1 >= max - 2 };
  }

  window.__almaManos = function (cmd, a) {
    a = a || {};
    try {
      if (cmd === 'leer') return res(leer());
      if (cmd === 'senalar') return res(senalar(a.id, a.texto));
      if (cmd === 'tocar') return res(tocar(a.id, a.confirmado === true));
      if (cmd === 'escribir') return res(escribir(a.id, a.texto, a.enter === true));
      if (cmd === 'bajar') return res(bajar(a.cuanto));
      if (cmd === 'estado') return res(estado());
      if (cmd === 'limpiar') { limpiarSenal(); return res({ ok: true }); }
      return res({ error: 'No sé hacer «' + cmd + '».' });
    } catch (x) { return res({ error: 'La página no me dejó: ' + String(x && x.message || x).slice(0, 160) }); }
  };
})();
"""#
}
