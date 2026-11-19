import Foundation
import UIKit

/// Alma maneja el anillo QRing (Juan, 16-nov-2026, rebanada 2 del anillo): las herramientas de cliente de la voz
/// (anillo_estado, anillo_medidas, anillo_medir_ahora, anillo_ajustes, anillo_buscar; las define el Hub en anillo.js),
/// la pantalla Wearables y la Lectura del anillo que va al Hub (action anilloResumen, como mucho cada 10 min).
/// · Escucha todo lo que manda el anillo (Anillo.swift → .almaAnillo) y guarda lo último con su hora (AnilloDatos.Memoria).
/// · Si el anillo no está conectado lo dice claro: lo que da es lo último leído, con su hora. Nunca inventa.
/// · Lo que se sabe leer está en AnilloDatos.swift (lógica pura, Pruebas/AnilloDatos).
final class AnilloAlma: ObservableObject {
    static let shared = AnilloAlma()
    static let herramientas: Set<String> = ["anillo_estado", "anillo_medidas", "anillo_medir_ahora", "anillo_ajustes", "anillo_buscar"]
    typealias Contestar = (String, Bool) -> Void
    typealias L = AnilloDatos.Lectura

    @Published private(set) var memoria = AnilloDatos.Memoria()
    @Published private(set) var conectado = false
    @Published private(set) var midiendo: AnilloDatos.Medida?
    /// Lo último que pasó (para la pantalla Wearables): «Midiendo…», «72 lpm», «El anillo parpadea».
    @Published var aviso = ""

    private let claveMemoria = "anillo_memoria", claveSubida = "anillo_subida"
    private var pasos = AnilloDatos.PasosDia(), hist = AnilloDatos.RitmoHist()
    private var diaPedido = 0
    private struct Espera { let id: Int; let quiere: (L) -> Bool; let listo: (L?) -> Void }
    private var esperas: [Espera] = []
    private var siguiente = 0
    private var medicion: (tipo: AnilloDatos.Medida, valores: [Int], inicio: Date, fin: (Int?, String?) -> Void)?
    private var relojMedicion: Timer?
    private var sincronizando = false

    private init() {
        if let d = UserDefaults.standard.data(forKey: claveMemoria), let m = try? JSONDecoder().decode(AnilloDatos.Memoria.self, from: d) { memoria = m }
        NotificationCenter.default.addObserver(forName: .almaAnillo, object: nil, queue: .main) { [weak self] n in self?.evento(n.userInfo as? [String: Any] ?? [:]) }
        conectado = Anillo.hayGuardado && Anillo.shared.listo
    }

    private var ahora: Double { Date().timeIntervalSince1970 }

    // MARK: - Lo que llega del anillo

    private func evento(_ e: [String: Any]) {
        let tipo = e["tipo"] as? String ?? ""
        switch tipo {
        case "listo":
            conectado = true
            // Al conectar: los pasos y el ritmo de hoy, como mucho cada 30 min (la batería y los ajustes ya los pide Anillo).
            if ahora - (memoria.sync ?? 0) > 1800 { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.sincronizar() } }
        case "desconectado", "sin_conexion", "estado", "error":
            conectado = Anillo.shared.listo
        case "firmware":
            if let f = e["firmware"] as? String { memoria.firmware = f; guardar() }
        default: break
        }
        guard let hex = e["hex"] as? String else { return }
        let l = AnilloDatos.leer(Anillo.bytes(hex))
        anotar(l)
        if let m = medicion, case .medida(let t, let v) = l, t == m.tipo { medicion?.valores.append(v); revisarMedicion() }
        if medicion != nil, case .medidaError(let c) = l { terminarMedicion(nil, "El anillo no pudo medir (código \(c)): que lo tenga bien puesto, ajustado y quieto.") }
        for w in esperas where w.quiere(l) { esperas.removeAll { $0.id == w.id }; w.listo(l) }
    }

    /// Guarda en la memoria lo que trae cada paquete.
    private func anotar(_ l: L) {
        let t = ahora
        switch l {
        case .bateria(let n, let c): memoria.bateria = .init(v: n, t: t); memoria.cargando = c
        case .ritmoAjustes(let a, let m): memoria.ritmoActivo = a; memoria.ritmoMinutos = m; memoria.ajustesT = t
        case .pasosInicio, .pasosSinDatos, .pasosParte:
            guard pasos.sumar(l) else { return }
            if diaPedido == 0 {
                memoria.pasos = .init(v: pasos.pasos, t: t); memoria.kcal = .init(v: pasos.kcalMostrar, t: t); memoria.metros = .init(v: pasos.metros, t: t)
                memoria.sync = t
            }
        case .ritmoHistInicio, .ritmoHistSinDatos, .ritmoHistParte:
            guard hist.sumar(l) else { return }
            if diaPedido == 0, let r = hist.resumen {
                memoria.ritmoMin = r.min; memoria.ritmoMax = r.max; memoria.ritmoProm = r.prom
                memoria.ritmoUltimoMin = r.ultimoMin; memoria.ritmoLecturas = r.lecturas; memoria.ritmoDiaT = t
                // La última lectura automática del día también es «el último ritmo», con su hora real.
                let tu = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970 + Double(r.ultimoMin * 60)
                if tu <= t + 60, tu > (memoria.ritmo?.t ?? 0) { memoria.ritmo = .init(v: r.ultimo, t: tu) }
                memoria.sync = t
            }
        default: return
        }
        guardar()
    }

    private func guardar() {
        if let d = try? JSONEncoder().encode(memoria) { UserDefaults.standard.set(d, forKey: claveMemoria) }
        subirSiToca()
    }

    // MARK: - Pedir y esperar

    /// Manda un comando y espera el paquete que lo contesta (o nada, a los `segundos`).
    private func pedir(_ comando: String, _ d: [String: Any] = [:], segundos: Double, hasta: @escaping (L) -> Bool, _ listo: @escaping (L?) -> Void) {
        siguiente += 1
        let id = siguiente
        esperas.append(Espera(id: id, quiere: hasta, listo: listo))
        Anillo.shared.comando(comando, d)
        DispatchQueue.main.asyncAfter(deadline: .now() + segundos) { [weak self] in
            guard let self, let w = self.esperas.first(where: { $0.id == id }) else { return }
            self.esperas.removeAll { $0.id == id }; w.listo(nil)
        }
    }

    /// Los pasos y el historial del ritmo de un día, uno tras otro.
    private func leerDia(_ dia: Int, _ listo: @escaping (_ pasosOk: Bool, _ ritmoOk: Bool) -> Void) {
        diaPedido = dia; pasos = .init(); hist = .init()
        pedir("pasos", ["dia": dia], segundos: 8, hasta: { [weak self] _ in self?.pasos.listo == true }) { [weak self] p in
            guard let self else { return }
            self.pedir("ritmoHistorial", ["dia": dia], segundos: 8, hasta: { [weak self] _ in self?.hist.listo == true }) { h in listo(p != nil, h != nil) }
        }
    }

    /// Lee hoy (pasos y ritmo) y la batería. La usan la conexión y la pantalla Wearables.
    func sincronizar() {
        guard Anillo.shared.listo, !sincronizando, medicion == nil else { return }
        sincronizando = true
        leerDia(0) { [weak self] _, _ in
            self?.pedir("bateria", segundos: 4, hasta: { if case .bateria = $0 { return true }; return false }) { _ in self?.sincronizando = false }
        }
    }

    // MARK: - Las herramientas de la voz

    func correr(_ nombre: String, _ p: [String: Any], _ contestar: @escaping Contestar) {
        switch nombre {
        case "anillo_estado": estadoHerramienta(p, contestar)
        case "anillo_medidas": medidasHerramienta(p, contestar)
        case "anillo_medir_ahora": medirHerramienta(p, contestar)
        case "anillo_ajustes": ajustesHerramienta(p, contestar)
        case "anillo_buscar":
            guard Anillo.shared.listo else { return contestar(json(sinConexion()), false) }
            buscar(); contestar(json(["ok": true, "hecho": "El anillo está parpadeando."]), false)
        default: contestar("Esta herramienta del anillo no existe en la app.", true)
        }
    }

    private func json(_ d: [String: Any]) -> String {
        (try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// Lo último que se leyó, en frases cortas con su hora.
    func loLeido() -> [String: Any] {
        let m = memoria, a = ahora
        let h = { (t: Double?) -> String in AnilloDatos.hace(t, ahora: a) ?? "" }
        var r: [String: Any] = [:]
        if let b = m.bateria { r["bateria"] = "\(b.v) %" + (m.cargando == true ? ", cargando" : "") + " (\(h(b.t)))" }
        if let p = m.pasos {
            r["actividad_hoy"] = "\(p.v) pasos" + (m.kcal.map { " · \($0.v) kcal" } ?? "") + (m.metros.map { String(format: " · %.1f km", Double($0.v) / 1000) } ?? "") + " (contados \(h(p.t)))"
        }
        if let x = m.ritmo { r["ultimo_ritmo"] = "\(x.v) lpm (\(h(x.t)))" }
        if let x = m.oxigeno { r["ultimo_oxigeno"] = "\(x.v) % (\(h(x.t)))" }
        if let mn = m.ritmoMin, let mx = m.ritmoMax, let pr = m.ritmoProm { r["ritmo_de_hoy"] = "mín \(mn) · máx \(mx) · promedio \(pr) (leído \(h(m.ritmoDiaT)))" }
        if let act = m.ritmoActivo { r["monitoreo_ritmo"] = act ? "encendido, cada \(m.ritmoMinutos ?? 0) min" : "apagado" }
        if let f = m.firmware, !f.isEmpty { r["firmware"] = f }
        if let s = m.sync { r["ultima_sincronizacion"] = h(s) }
        return r
    }

    private func sinConexion() -> [String: Any] {
        if !Anillo.hayGuardado { return ["conectado": false, "nota": "No hay un anillo conectado a la app. Dile que lo conecte desde Health → Anillo; después lo ve en Ajustes → Wearables."] }
        Anillo.shared.buscar()   // que intente reconectarse para la próxima
        var r: [String: Any] = ["conectado": false, "nota": "El anillo no está conectado ahora (lejos, sin batería o apagado). Dilo claro. Lo de lo_ultimo es lo último que se leyó, con su hora; no lo des como de ahora."]
        let l = loLeido(); if !l.isEmpty { r["lo_ultimo"] = l }
        return r
    }

    private func estadoHerramienta(_ p: [String: Any], _ contestar: @escaping Contestar) {
        if AnilloDatos.booleano(p["mostrar"]) == true { NotificationCenter.default.post(name: .abrirWearables, object: nil) }
        guard Anillo.shared.listo else { return contestar(json(sinConexion()), false) }
        pedir("bateria", segundos: 4, hasta: { if case .bateria = $0 { return true }; return false }) { [weak self] l in
            guard let self else { return }
            var r: [String: Any] = ["conectado": true]
            if case .bateria(let n, let c)? = l { r["bateria"] = "\(n) %"; r["cargando"] = c } else { r["bateria"] = "no respondió; lo último: " + ((self.loLeido()["bateria"] as? String) ?? "sin dato") }
            if let f = self.memoria.firmware, !f.isEmpty { r["firmware"] = f }
            if let s = self.memoria.sync { r["ultima_sincronizacion"] = AnilloDatos.hace(s, ahora: self.ahora) ?? "" }
            if AnilloDatos.booleano(p["mostrar"]) == true { r["pantalla"] = "Abrí la pantalla Wearables." }
            contestar(self.json(r), false)
        }
    }

    private func medidasHerramienta(_ p: [String: Any], _ contestar: @escaping Contestar) {
        let dia = max(0, min(6, AnilloDatos.entero(p["dia"]) ?? 0))
        guard Anillo.shared.listo, medicion == nil else {
            var r: [String: Any] = medicion != nil ? ["conectado": true, "nota": "El anillo está midiendo ahora; espera a que termine."] : sinConexion()
            if dia > 0 { r["dia_pedido"] = "Sin conexión no tengo ese día: solo lo último leído de hoy." }
            return contestar(json(r), false)
        }
        leerDia(dia) { [weak self] pOk, hOk in
            guard let self else { return }
            var r: [String: Any] = ["conectado": true, "dia": dia == 0 ? "hoy" : dia == 1 ? "ayer" : "hace \(dia) días"]
            if pOk { r["actividad"] = "\(self.pasos.pasos) pasos · \(self.pasos.kcalMostrar) kcal · " + String(format: "%.1f km", Double(self.pasos.metros) / 1000) }
            else { r["actividad"] = "el anillo no respondió los pasos" }
            if hOk, let h = self.hist.resumen {
                r["ritmo_del_dia"] = "mín \(h.min) · máx \(h.max) · promedio \(h.prom) (\(h.lecturas) lecturas); la última \(h.ultimo) lpm a las \(AnilloDatos.horaDelDia(h.ultimoMin))"
            } else { r["ritmo_del_dia"] = hOk ? "sin lecturas del ritmo ese día (¿monitoreo apagado?)" : "el anillo no respondió el ritmo" }
            if let x = self.memoria.ritmo { r["ultimo_ritmo"] = "\(x.v) lpm (\(AnilloDatos.hace(x.t, ahora: self.ahora) ?? ""))" }
            if let x = self.memoria.oxigeno { r["ultimo_oxigeno_en_vivo"] = "\(x.v) % (\(AnilloDatos.hace(x.t, ahora: self.ahora) ?? ""))" }
            else { r["oxigeno"] = "solo se tiene lo medido en vivo (anillo_medir_ahora con oxigeno)" }
            contestar(self.json(r), false)
        }
    }

    private func medirHerramienta(_ p: [String: Any], _ contestar: @escaping Contestar) {
        if AnilloDatos.booleano(p["cancelar"]) == true {
            let habia = medicion != nil
            terminarMedicion(nil, "Cancelada.")
            return contestar(json(["ok": true, "hecho": habia ? "Detuve la medición." : "No había una medición en curso."]), false)
        }
        guard Anillo.shared.listo else { return contestar(json(sinConexion()), false) }
        let tipo: AnilloDatos.Medida = (p["tipo"] as? String ?? "").lowercased().hasPrefix("ox") ? .oxigeno : .ritmo
        medir(tipo) { [weak self] valor, error in
            guard let self else { return }
            if let v = valor {
                contestar(self.json(["ok": true, "medida": tipo == .ritmo ? "ritmo cardíaco" : "oxígeno en sangre", "valor": tipo == .ritmo ? "\(v) lpm" : "\(v) %", "cuando": "ahora"]), false)
            } else {
                contestar(self.json(["ok": false, "error": error ?? "No se pudo medir."]), false)
            }
        }
    }

    private func ajustesHerramienta(_ p: [String: Any], _ contestar: @escaping Contestar) {
        guard Anillo.shared.listo else { return contestar(json(sinConexion()), false) }
        let cambiar = (p["accion"] as? String ?? "") == "cambiar" || p["activo"] != nil || p["minutos"] != nil
        let responder: (L?) -> Void = { [weak self] l in
            guard let self else { return }
            if case .ritmoAjustes(let a, let m)? = l {
                contestar(self.json(["ok": true, "monitoreo_ritmo": a ? "encendido, cada \(m) min" : "apagado", "cambiado": cambiar]), false)
            } else { contestar(self.json(["ok": false, "error": "El anillo no respondió sus ajustes."]), false) }
        }
        if cambiar {
            ajustar(activo: AnilloDatos.booleano(p["activo"]), minutos: AnilloDatos.entero(p["minutos"]), responder)
        } else {
            pedir("ritmoAjustes", segundos: 4, hasta: AnilloAlma.esAjustes, responder)
        }
    }
    private static func esAjustes(_ l: L) -> Bool { if case .ritmoAjustes = l { return true }; return false }

    // MARK: - Acciones (voz y pantalla Wearables)

    func buscar() { Anillo.shared.comando("buscarAnillo", [:]); aviso = "El anillo está parpadeando." }

    /// Cambia el monitoreo del ritmo y lo vuelve a leer para decir cómo quedó.
    func ajustar(activo: Bool?, minutos: Int?, _ listo: ((L?) -> Void)? = nil) {
        let a = activo ?? memoria.ritmoActivo ?? true
        let m = AnilloDatos.minutosValidos(minutos ?? memoria.ritmoMinutos ?? 30)
        Anillo.shared.comando("ritmoGuardar", ["activo": a, "minutos": m])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.pedir("ritmoAjustes", segundos: 4, hasta: AnilloAlma.esAjustes) { l in
                if case .ritmoAjustes(let a2, let m2)? = l { self?.aviso = a2 ? "Monitoreo encendido, cada \(m2) min." : "Monitoreo apagado." }
                listo?(l)
            }
        }
    }

    /// Mide en vivo (15 a 30 s): espera lecturas buenas, para el anillo y guarda el valor con su hora.
    func medir(_ tipo: AnilloDatos.Medida, _ fin: @escaping (Int?, String?) -> Void) {
        terminarMedicion(nil, "Se empezó otra medición.")
        guard Anillo.shared.listo else { return fin(nil, "El anillo no está conectado.") }
        midiendo = tipo; aviso = tipo == .ritmo ? "Midiendo tu ritmo… quédate quieto." : "Midiendo tu oxígeno… quédate quieto."
        medicion = (tipo, [], Date(), fin)
        Anillo.shared.comando(tipo == .ritmo ? "ritmoAhora" : "oxigenoAhora", [:])
        relojMedicion = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.revisarMedicion() }
    }

    private func revisarMedicion() {
        guard let m = medicion else { return }
        let cumplido = Date().timeIntervalSince(m.inicio) >= 30
        if let v = AnilloDatos.medicionLista(m.valores, tipo: m.tipo, tiempoCumplido: cumplido) { terminarMedicion(v, nil) }
        else if cumplido { terminarMedicion(nil, "El anillo no logró una lectura en 30 s: que lo tenga bien puesto y quieto, y lo intentamos otra vez.") }
    }

    private func terminarMedicion(_ valor: Int?, _ error: String?) {
        relojMedicion?.invalidate(); relojMedicion = nil
        guard let m = medicion else { return }
        medicion = nil; midiendo = nil
        Anillo.shared.comando("pararMedicion", ["tipo": m.tipo == .ritmo ? 1 : 3])
        if let v = valor {
            if m.tipo == .ritmo { memoria.ritmo = .init(v: v, t: ahora) } else { memoria.oxigeno = .init(v: v, t: ahora) }
            aviso = m.tipo == .ritmo ? "\(v) lpm, ahora." : "\(v) % de oxígeno, ahora."
            guardar()
        } else if let e = error { aviso = e }
        m.fin(valor, error)
    }

    // MARK: - La ficha de la llamada y el Hub

    /// «ANILLO DE JUAN …» en la ficha: solo si hay un anillo guardado (si no, Alma no ofrece sus herramientas).
    var ficha: String? {
        guard Anillo.hayGuardado else { return nil }
        return AnilloDatos.ficha(conectado: Anillo.shared.listo, m: memoria, ahora: ahora)
    }

    /// La Lectura del anillo al Hub (anillo.js · anilloResumenGuardar_), como mucho cada 10 min y solo con algo nuevo.
    private func subirSiToca() {
        let ultima = UserDefaults.standard.object(forKey: claveSubida) as? Double
        guard AnilloDatos.tocaSubir(ultimaSubida: ultima, ultimoDato: AnilloDatos.ultimoDato(memoria), ahora: ahora),
              let url = Llave.leer("voz_url"), let token = Llave.leer("voz_token"), let sesion = Llave.leer("voz_sesion"), let u = URL(string: url) else { return }
        UserDefaults.standard.set(ahora, forKey: claveSubida)
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type"); r.timeoutInterval = 30
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["hub": 1, "action": "anilloResumen", "token": token, "session": sesion,
                                                                  "resumen": AnilloDatos.resumenHub(memoria, conectado: Anillo.shared.listo)])
        URLSession.shared.dataTask(with: r).resume()
    }
}

extension Notification.Name {
    /// Ajustes → Wearables, o Alma con anillo_estado (mostrar: true): abre la pantalla Wearables (Wearables.swift). El objeto,
    /// si viene, es el wearable que se abre directo («anillo», «lentes», «agregar» o el id de unos audífonos).
    static let abrirWearables = Notification.Name("alma.wearables.abrir")
}
