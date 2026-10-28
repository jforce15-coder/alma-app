import Foundation
import SwiftUI
import UIKit

/// Lo que muestra Health (nativo): Apple Salud (Salud.swift) + el anillo en vivo (Anillo.swift).
/// Todo llega en el hilo principal: Salud responde en .main y el anillo avisa por NotificationCenter en .main.
final class SaludModelo: ObservableObject {
    struct Punto: Identifiable { let t: Double; let v: Double; var id: Double { t } }
    struct Fase: Identifiable { let id: Int; let c: String; let min: Double }
    struct Sueno { let inicio: String; let fin: String; let minutos: Double; let fases: [Fase] }
    struct Ejercicio: Identifiable { let id: Int; let tipo: String; let min: Double; let kcal: Double; let dia: Int }
    struct Dia: Identifiable { let id: String; let fecha: Date; let valores: [String: Double] }
    struct Encontrado: Identifiable { let id: String; let nombre: String; let detalle: String }

    // Apple Salud
    @Published var permiso: Bool?
    @Published var pasos: Double?
    @Published var km: Double?
    @Published var kcal: Double?
    @Published var pasosHora: [Double] = []
    @Published var series: [String: [Punto]] = [:]   // ritmo, hrv, oxigeno, temp
    @Published var sueno: Sueno?
    @Published var ejercicios: [Ejercicio] = []
    @Published var dias: [Dia] = []

    // Anillo
    @Published var conectado = false
    @Published var guardado = false
    @Published var nombreAnillo = ""
    @Published var bateria: Int?
    @Published var cargando = false
    @Published var auto = true
    @Published var minutos = 5
    @Published var vivo: [String: Double] = [:]       // ritmo / oxigeno medidos ahora
    @Published var midiendo: String?
    @Published var pasoConexion = 0                    // 0 ponte · 1 buscando · 2 elige · 3 conectando · 4 listo
    @Published var textoConexion = ("Ponte tu anillo", "En el índice, con el sensor hacia la palma. Cierra la app del anillo para que quede libre.")
    @Published var encontrados: [Encontrado] = []

    private var oyente: NSObjectProtocol?

    init() {
        oyente = NotificationCenter.default.addObserver(forName: .almaAnillo, object: nil, queue: .main) { [weak self] n in
            self?.evento(n.userInfo as? [String: Any] ?? [:])
        }
        var e = Anillo.shared.estado; e["tipo"] = "estado"; evento(e)
    }
    deinit { if let o = oyente { NotificationCenter.default.removeObserver(o) } }

    // MARK: - Apple Salud

    func cargar() {
        Salud.shared.manejar("leer") { [weak self] d in self?.recibir(d) }
        Salud.shared.manejar("historial") { [weak self] d in self?.recibir(d) }
        if conectado { Anillo.shared.comando("bateria", [:]); Anillo.shared.comando("ritmoAjustes", [:]) }
    }

    func pedirPermiso() {
        Salud.shared.manejar("permiso") { [weak self] d in
            self?.recibir(d)
            Salud.shared.manejar("historial") { [weak self] d in self?.recibir(d) }
        }
    }

    private func recibir(_ d: [String: Any]) {
        permiso = (d["permiso"] as? Bool) ?? false
        if let h = d["historial"] as? [[String: Any]] {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
            dias = h.compactMap { o in
                guard let k = o["d"] as? String, let fecha = f.date(from: k) else { return nil }
                var v: [String: Double] = [:]
                for (kk, x) in o where kk != "d" { if let n = SaludModelo.num(x) { v[kk] = n } }
                return Dia(id: k, fecha: fecha, valores: v)
            }
            return
        }
        if let hoy = d["hoy"] as? [String: Any] {
            pasos = SaludModelo.num(hoy["pasos"]); km = SaludModelo.num(hoy["km"]); kcal = SaludModelo.num(hoy["kcal"])
            pasosHora = (hoy["pasosHora"] as? [Any] ?? []).compactMap { SaludModelo.num($0) }
            var s: [String: [Punto]] = [:]
            for k in ["ritmo", "hrv", "oxigeno", "temp"] {
                s[k] = (hoy[k] as? [[String: Any]] ?? []).compactMap { p in
                    guard let t = SaludModelo.num(p["t"]), let v = SaludModelo.num(p["v"]) else { return nil }
                    return Punto(t: t, v: v)
                }
            }
            series = s
        }
        if let z = d["sueno"] as? [String: Any], let m = SaludModelo.num(z["minutos"]), m > 0 {
            let fases = (z["fases"] as? [[Any]] ?? []).enumerated().compactMap { i, f -> Fase? in
                guard f.count > 1, let c = f[0] as? String, let n = SaludModelo.num(f[1]) else { return nil }
                return Fase(id: i, c: c, min: n)
            }
            sueno = Sueno(inicio: z["inicio"] as? String ?? "", fin: z["fin"] as? String ?? "", minutos: m, fases: fases)
        }
        if let e = d["ejercicios"] as? [[String: Any]] {
            ejercicios = e.enumerated().map { i, x in
                Ejercicio(id: i, tipo: x["tipo"] as? String ?? "Ejercicio", min: SaludModelo.num(x["min"]) ?? 0, kcal: SaludModelo.num(x["kcal"]) ?? 0, dia: Int(SaludModelo.num(x["dia"]) ?? 0))
            }
        }
    }

    static func num(_ x: Any?) -> Double? {
        if let d = x as? Double { return d }
        if let i = x as? Int { return Double(i) }
        if let n = x as? NSNumber { return n.doubleValue }
        return nil
    }

    // MARK: - Lecturas para la vista

    func serie(_ k: String) -> [Punto] { series[k] ?? [] }
    func ultimo(_ k: String) -> Double? { vivo[k] ?? serie(k).last?.v }
    func estadisticas(_ k: String) -> (prom: Double, min: Double, max: Double)? {
        let v = serie(k).map(\.v); guard !v.isEmpty else { return nil }
        return (v.reduce(0, +) / Double(v.count), v.min() ?? 0, v.max() ?? 0)
    }
    func suma(_ c: String) -> Double { sueno?.fases.filter { $0.c == c }.reduce(0) { $0 + $1.min } ?? 0 }

    /// Un valor por día (30 días) o un promedio por mes (12 meses).
    func historia(_ campo: String, anio: Bool) -> [(fecha: Date, valor: Double?)] {
        let cal = Calendar.current, hoy = cal.startOfDay(for: Date())
        if !anio {
            let porDia = Dictionary(uniqueKeysWithValues: dias.map { ($0.fecha, $0.valores[campo]) })
            return (0..<30).reversed().map { i in
                let d = cal.date(byAdding: .day, value: -i, to: hoy) ?? hoy
                return (d, porDia[d] ?? nil)
            }
        }
        let inicioMes = cal.date(from: cal.dateComponents([.year, .month], from: hoy)) ?? hoy
        return (0..<12).reversed().map { i in
            let m = cal.date(byAdding: .month, value: -i, to: inicioMes) ?? inicioMes
            let v = dias.filter { cal.isDate($0.fecha, equalTo: m, toGranularity: .month) }.compactMap { $0.valores[campo] }
            return (m, v.isEmpty ? nil : v.reduce(0, +) / Double(v.count))
        }
    }

    // MARK: - Anillo

    func buscar() {
        encontrados = []; pasoConexion = 1; textoConexion = ("Buscando…", "Acerca el anillo al teléfono.")
        Anillo.shared.buscar()
    }
    func elegir(_ e: Encontrado) {
        encontrados = []; pasoConexion = 3; textoConexion = ("Un toque…", "Alma está conociendo tu anillo.")
        Anillo.shared.elegir(e.id)
    }
    func reiniciarConexion() {
        pasoConexion = 0; encontrados = []
        textoConexion = ("Ponte tu anillo", "En el índice, con el sensor hacia la palma. Cierra la app del anillo para que quede libre.")
    }
    func olvidar() { Anillo.shared.olvidar(); conectado = false; guardado = false; bateria = nil }
    func guardarRitmo() { Anillo.shared.comando("ritmoGuardar", ["activo": auto, "minutos": minutos]) }
    func encontrarAnillo() { Anillo.shared.comando("buscarAnillo", [:]) }
    func igualarHora() { Anillo.shared.comando("hora", [:]) }

    /// Medición en vivo (30 s) de ritmo u oxígeno.
    func medir(_ tipo: String) {
        guard conectado, midiendo == nil else { return }
        midiendo = tipo
        Anillo.shared.comando(tipo == "ritmo" ? "ritmoAhora" : "oxigenoAhora", [:])
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            Anillo.shared.comando("pararMedicion", ["tipo": tipo == "ritmo" ? 1 : 3])
            self?.midiendo = nil
        }
    }

    private func evento(_ e: [String: Any]) {
        switch e["tipo"] as? String ?? "" {
        case "estado":
            conectado = (e["conectado"] as? Bool) ?? false; guardado = (e["guardado"] as? Bool) ?? false
            if let n = e["nombre"] as? String, !n.isEmpty { nombreAnillo = n }
        case "encontrado":
            guard pasoConexion <= 2, let id = e["id"] as? String, !encontrados.contains(where: { $0.id == id }) else { return }
            let senal = SaludModelo.num(e["senal"]) ?? -90
            let det = (e["yaConectado"] as? Bool) == true ? "Conectado al iPhone" : senal > -60 ? "Muy cerca" : senal > -80 ? "Cerca" : "Lejos"
            encontrados.append(Encontrado(id: id, nombre: e["nombre"] as? String ?? "Anillo", detalle: det))
            pasoConexion = 2; textoConexion = ("Elige tu anillo", "Toca el tuyo para conectarlo.")
        case "busqueda_fin":
            if pasoConexion == 1 {
                pasoConexion = 0
                textoConexion = ("No lo encontré", "Revisa que tenga batería y esté cerca. Si sigue sin aparecer, olvídalo en Ajustes → Bluetooth del iPhone y vuelve a intentar.")
            }
        case "conectado", "listo":
            conectado = true; guardado = true
            if let n = e["nombre"] as? String, !n.isEmpty { nombreAnillo = n }
            if e["tipo"] as? String == "listo" {
                if pasoConexion == 3 { pasoConexion = 4; textoConexion = ("Ya son uno.", "Tu anillo y Alma están conectados. Ahora te cuida también cuando no lo miras.") }
                Anillo.shared.comando("bateria", [:])
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { Anillo.shared.comando("pasos", ["dia": 0]) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { Anillo.shared.comando("ritmoAjustes", [:]) }
            }
        case "desconectado": conectado = false; guardado = true
        case "error":
            if pasoConexion == 3 { pasoConexion = 0; textoConexion = ("No se pudo conectar", e["mensaje"] as? String ?? "Intenta de nuevo.") }
        case "bateria": bateria = Int(SaludModelo.num(e["nivel"]) ?? 0); cargando = (e["cargando"] as? Bool) ?? false
        case "ritmo", "oxigeno":
            if let v = SaludModelo.num(e["valor"]), v > 0, let k = e["tipo"] as? String { vivo[k] = v }
        case "ritmoAjustes":
            auto = (e["activo"] as? Bool) ?? auto
            if let m = SaludModelo.num(e["minutos"]), m > 0 { minutos = Int(m) }
        case "pasos":
            // Solo si Apple Salud no dio pasos: los del anillo
            if (e["fin"] as? Bool) == true, pasos == nil, let p = SaludModelo.num(e["pasos"]), p > 0 {
                pasos = p; km = (SaludModelo.num(e["metros"]) ?? 0) / 1000
                let c = SaludModelo.num(e["calorias"]) ?? 0; kcal = c > 20000 ? c / 1000 : c
            }
        default: break
        }
    }
}
