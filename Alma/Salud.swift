import Foundation
import HealthKit

/// Apple Salud: lo que guardan el reloj, el iPhone, la app del anillo u otras apps, para la página Health.
/// La página pide { accion: "salud", que: "permiso" | "leer" | "historial" } y recibe AlmaSalud.datos({ permiso, hoy, sueno, ejercicios }).
/// Solo lee (nunca escribe en Apple Salud).
final class Salud {
    static let shared = Salud()
    private let store = HKHealthStore()

    private var tipos: Set<HKObjectType> {
        let q: [HKQuantityTypeIdentifier] = [.stepCount, .distanceWalkingRunning, .activeEnergyBurned, .heartRate,
                                             .heartRateVariabilitySDNN, .oxygenSaturation, .bodyTemperature, .restingHeartRate]
        var s = Set<HKObjectType>(q.map { HKQuantityType($0) })
        s.insert(HKCategoryType(.sleepAnalysis))
        s.insert(HKObjectType.workoutType())
        return s
    }

    func manejar(_ que: String, _ fin: @escaping ([String: Any]) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            fin(["permiso": false, "mensaje": "Apple Salud no está disponible en este equipo"]); return
        }
        if que == "permiso" {
            store.requestAuthorization(toShare: nil, read: tipos) { [weak self] _, _ in self?.leer(fin) }
            return
        }
        // Solo se lee si ya se pidió el permiso antes (iOS no dice qué aceptó; «ya preguntado» basta).
        store.getRequestStatusForAuthorization(toShare: [], read: tipos) { [weak self] estado, _ in
            guard estado == .unnecessary else { DispatchQueue.main.async { fin(["permiso": false]) }; return }
            if que == "historial" { self?.historial(fin) } else { self?.leer(fin) }
        }
    }

    /// El último año, un dato por día (lo que guardó cualquier fuente: QRing, el reloj, el iPhone…):
    /// { permiso, historial: [{ d: "2026-10-28", pasos, ritmo, ritmoMin, reposo, hrv, oxigeno, sueno }] }
    private func historial(_ fin: @escaping ([String: Any]) -> Void) {
        let cal = Calendar.current, ahora = Date(), hoy = cal.startOfDay(for: ahora)
        let desde = cal.date(byAdding: .day, value: -364, to: hoy) ?? hoy
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        let g = DispatchGroup(), cerrojo = NSLock()
        var dias: [String: [String: Any]] = [:]
        func pon(_ d: Date, _ k: String, _ v: Double) { cerrojo.lock(); dias[f.string(from: d), default: [:]][k] = v; cerrojo.unlock() }
        let rango = HKQuery.predicateForSamples(withStart: desde, end: ahora)

        let diarios: [(String, HKQuantityTypeIdentifier, HKUnit, HKStatisticsOptions, Double)] = [
            ("pasos", .stepCount, .count(), .cumulativeSum, 1),
            ("ritmo", .heartRate, HKUnit.count().unitDivided(by: .minute()), [.discreteAverage, .discreteMin], 1),
            ("reposo", .restingHeartRate, HKUnit.count().unitDivided(by: .minute()), .discreteAverage, 1),
            ("hrv", .heartRateVariabilitySDNN, .secondUnit(with: .milli), .discreteAverage, 1),
            ("oxigeno", .oxygenSaturation, .percent(), .discreteAverage, 100)
        ]
        for (k, id, unidad, op, factor) in diarios {
            g.enter()
            let q = HKStatisticsCollectionQuery(quantityType: HKQuantityType(id), quantitySamplePredicate: rango, options: op,
                                                anchorDate: hoy, intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, res, _ in
                res?.enumerateStatistics(from: desde, to: ahora) { st, _ in
                    if let v = (op.contains(.cumulativeSum) ? st.sumQuantity() : st.averageQuantity())?.doubleValue(for: unidad), v > 0 { pon(st.startDate, k, (v * factor).rounded()) }
                    if k == "ritmo", let m = st.minimumQuantity()?.doubleValue(for: unidad) { pon(st.startDate, "ritmoMin", m.rounded()) }
                }
                g.leave()
            }
            store.execute(q)
        }

        // Sueño por noche: la noche cuenta para el día en que despiertas; si hay varias fuentes, la que más registró.
        g.enter()
        let desdeNoche = cal.date(byAdding: .hour, value: -12, to: desde) ?? desde
        store.execute(HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis), predicate: HKQuery.predicateForSamples(withStart: desdeNoche, end: ahora),
                                    limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, m, _ in
            let dormido: Set<Int> = [HKCategoryValueSleepAnalysis.asleepREM.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                     HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue]
            let muestras = (m as? [HKCategorySample] ?? []).filter { dormido.contains($0.value) }
            let porNoche = Dictionary(grouping: muestras) { cal.startOfDay(for: $0.startDate.addingTimeInterval(12 * 3600)) }
            for (noche, lista) in porNoche {
                let porFuente = Dictionary(grouping: lista) { $0.sourceRevision.source.bundleIdentifier }
                let mejor = porFuente.values.map { $0.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } }.max() ?? 0
                if mejor > 0 { pon(noche, "sueno", (mejor / 60).rounded()) }
            }
            g.leave()
        })

        g.notify(queue: .main) {
            let lista = dias.keys.sorted().map { k -> [String: Any] in var o = dias[k] ?? [:]; o["d"] = k; return o }
            fin(["permiso": true, "historial": lista])
        }
    }

    private func leer(_ fin: @escaping ([String: Any]) -> Void) {
        let cal = Calendar.current, ahora = Date(), hoy = cal.startOfDay(for: ahora)
        let g = DispatchGroup(), cerrojo = NSLock()
        var dia: [String: Any] = ["fuente": "salud"]
        var sueno: [String: Any]?
        var ejercicios: [[String: Any]] = []
        func pon(_ k: String, _ v: Any) { cerrojo.lock(); dia[k] = v; cerrojo.unlock() }
        let deHoy = HKQuery.predicateForSamples(withStart: hoy, end: ahora)
        let minuto = { (d: Date) -> Double in d.timeIntervalSince(hoy) / 60 }

        // Totales del día
        let sumas: [(String, HKQuantityTypeIdentifier, HKUnit)] = [("pasos", .stepCount, .count()),
                                                                   ("km", .distanceWalkingRunning, .meterUnit(with: .kilo)),
                                                                   ("kcal", .activeEnergyBurned, .kilocalorie())]
        for (k, id, unidad) in sumas {
            g.enter()
            store.execute(HKStatisticsQuery(quantityType: HKQuantityType(id), quantitySamplePredicate: deHoy, options: .cumulativeSum) { _, r, _ in
                if let v = r?.sumQuantity()?.doubleValue(for: unidad) { pon(k, k == "km" ? (v * 100).rounded() / 100 : v.rounded()) }
                g.leave()
            })
        }

        // Pasos por hora
        g.enter()
        let porHora = HKStatisticsCollectionQuery(quantityType: HKQuantityType(.stepCount), quantitySamplePredicate: deHoy,
                                                  options: .cumulativeSum, anchorDate: hoy, intervalComponents: DateComponents(hour: 1))
        porHora.initialResultsHandler = { _, res, _ in
            var horas = Array(repeating: 0, count: 24)
            res?.enumerateStatistics(from: hoy, to: ahora) { s, _ in
                horas[cal.component(.hour, from: s.startDate)] = Int(s.sumQuantity()?.doubleValue(for: .count()) ?? 0)
            }
            pon("pasosHora", horas); g.leave()
        }
        store.execute(porHora)

        // Series del día: [{ t: minuto del día, v }]
        let series: [(String, HKQuantityTypeIdentifier, HKUnit, Double, Double)] = [
            ("ritmo", .heartRate, HKUnit.count().unitDivided(by: .minute()), 1, 1),
            ("hrv", .heartRateVariabilitySDNN, .secondUnit(with: .milli), 1, 1),
            ("oxigeno", .oxygenSaturation, .percent(), 100, 1),
            ("temp", .bodyTemperature, .degreeCelsius(), 1, 10)
        ]
        for (k, id, unidad, factor, redondeo) in series {
            g.enter()
            let orden = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            store.execute(HKSampleQuery(sampleType: HKQuantityType(id), predicate: deHoy, limit: 600, sortDescriptors: orden) { _, m, _ in
                let puntos: [[String: Double]] = (m as? [HKQuantitySample] ?? []).map {
                    ["t": minuto($0.startDate).rounded(), "v": ($0.quantity.doubleValue(for: unidad) * factor * redondeo).rounded() / redondeo]
                }
                if !puntos.isEmpty { pon(k, puntos) }
                g.leave()
            })
        }

        // Sueño: desde ayer a las 18:00. Si hay varias fuentes (reloj y anillo), se usa la que más registró.
        g.enter()
        let desde = cal.date(byAdding: .hour, value: -6, to: hoy) ?? hoy
        store.execute(HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis), predicate: HKQuery.predicateForSamples(withStart: desde, end: ahora),
                                    limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, m, _ in
            let codigo: [Int: String] = [HKCategoryValueSleepAnalysis.awake.rawValue: "d", HKCategoryValueSleepAnalysis.asleepREM.rawValue: "r",
                                         HKCategoryValueSleepAnalysis.asleepCore.rawValue: "l", HKCategoryValueSleepAnalysis.asleepDeep.rawValue: "p",
                                         HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: "l"]
            let todas = (m as? [HKCategorySample] ?? []).filter { codigo[$0.value] != nil }
            let porFuente = Dictionary(grouping: todas) { $0.sourceRevision.source.bundleIdentifier }
            if let mejor = porFuente.values.max(by: { a, b in a.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } < b.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } }),
               let primera = mejor.first, let ultima = mejor.last {
                var fases: [[Any]] = [], dormido = 0.0
                for s in mejor {
                    let c = codigo[s.value] ?? "l", min = s.endDate.timeIntervalSince(s.startDate) / 60
                    if c != "d" { dormido += min }
                    if let u = fases.last, u[0] as? String == c, let mu = u[1] as? Double { fases[fases.count - 1] = [c, mu + min] } else { fases.append([c, min]) }
                }
                let f = DateFormatter(); f.dateFormat = "HH:mm"
                cerrojo.lock()
                sueno = ["inicio": f.string(from: primera.startDate), "fin": f.string(from: ultima.endDate), "minutos": dormido.rounded(),
                         "fases": fases.map { [$0[0], (($0[1] as? Double) ?? 0).rounded()] }]
                cerrojo.unlock()
            }
            g.leave()
        })

        // Ejercicios de los últimos 7 días
        g.enter()
        let semana = cal.date(byAdding: .day, value: -6, to: hoy) ?? hoy
        store.execute(HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: HKQuery.predicateForSamples(withStart: semana, end: ahora),
                                    limit: 50, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, m, _ in
            let lista: [[String: Any]] = (m as? [HKWorkout] ?? []).map { w in
                let kcal = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                let hace = cal.dateComponents([.day], from: cal.startOfDay(for: w.startDate), to: hoy).day ?? 0
                return ["tipo": Salud.nombre(w.workoutActivityType), "min": (w.duration / 60).rounded(), "kcal": kcal.rounded(), "dia": max(0, 6 - hace)]
            }
            cerrojo.lock(); ejercicios = lista; cerrojo.unlock()
            g.leave()
        })

        g.notify(queue: .main) {
            var out: [String: Any] = ["permiso": true, "hoy": dia, "ejercicios": ejercicios]
            if let s = sueno { out["sueno"] = s }
            fin(out)
        }
    }

    static func nombre(_ t: HKWorkoutActivityType) -> String {
        switch t {
        case .running: return "Correr"
        case .walking: return "Caminata"
        case .cycling: return "Bicicleta"
        case .swimming: return "Natación"
        case .boxing, .kickboxing: return "Boxeo"
        case .yoga: return "Yoga"
        case .pilates: return "Pilates"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "Fuerza"
        case .highIntensityIntervalTraining: return "HIIT"
        case .hiking: return "Senderismo"
        case .dance: return "Baile"
        default: return "Ejercicio"
        }
    }
}
