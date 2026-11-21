import Foundation
import MetricKit

/// El porqué de un cierre de la app (guardia 21-nov-2026, FalloAppReglas.swift). Dos fuentes, las dos llegan al abrir otra vez:
///   · El informe de fallo de iOS (MetricKit, MXCrashDiagnostic): tipo, señal, excepción, motivo y la pila del hilo que falló.
///     iOS lo entrega al volver a abrir la app; se anota en el registro de la voz y va al Hub con los pasos (vozAvisos).
///   · La excepción de Objective-C que tumba la app (AVAudioPlayerNode, el motor de audio…): se guarda en un archivo antes
///     de morir (nombre, motivo y pila con nombres de funciones del sistema) y se anota al abrir.
///   · Una vez al día, las salidas raras que cuenta iOS (memoria, vigilante): por si iOS la mató sin informe de fallo.
final class FalloApp: NSObject, MXMetricManagerSubscriber {
    static let shared = FalloApp()
    private static let claveVistos = "fallo_app_vistos"

    static var archivoExcepcion: URL {
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("fallo-excepcion.txt")
    }

    func empezar() {
        try? FileManager.default.createDirectory(at: FalloApp.archivoExcepcion.deletingLastPathComponent(), withIntermediateDirectories: true)
        NSSetUncaughtExceptionHandler { e in
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
            let t = [e.name.rawValue, (e.reason ?? "").replacingOccurrences(of: "\n", with: " "), build].joined(separator: "\n")
                + "\n" + e.callStackSymbols.prefix(30).joined(separator: "\n")
            try? t.write(to: FalloApp.archivoExcepcion, atomically: true, encoding: .utf8)
        }
        // Lo que dejó la vez anterior (después de un instante: el registro de la voz ya está listo).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.excepcionGuardada()
            MXMetricManager.shared.add(FalloApp.shared)
            self?.diagnosticos(MXMetricManager.shared.pastDiagnosticPayloads)
        }
    }

    private func excepcionGuardada() {
        let u = FalloApp.archivoExcepcion
        guard let t = try? String(contentsOf: u, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: u)
        guard let f = FalloAppReglas.desdeArchivo(t) else { return }
        anotar(FalloAppReglas.pasos(f, de: "excepción"))
    }

    // MARK: - MetricKit (llega en un hilo cualquiera)

    func didReceive(_ payloads: [MXDiagnosticPayload]) { DispatchQueue.main.async { self.diagnosticos(payloads) } }

    func didReceive(_ payloads: [MXMetricPayload]) {
        DispatchQueue.main.async {
            for p in payloads {
                guard let s = p.applicationExitMetrics else { continue }
                let b = s.backgroundExitData, a = s.foregroundExitData
                let fondo = ["memoria": b.cumulativeMemoryResourceLimitExitCount, "presión de memoria": b.cumulativeMemoryPressureExitCount,
                             "vigilante": b.cumulativeAppWatchdogExitCount, "acceso malo": b.cumulativeBadAccessExitCount,
                             "instrucción": b.cumulativeIllegalInstructionExitCount, "anormal": b.cumulativeAbnormalExitCount,
                             "tarea de fondo": b.cumulativeBackgroundTaskAssertionTimeoutExitCount, "CPU": b.cumulativeCPUResourceLimitExitCount]
                let frente = ["memoria": a.cumulativeMemoryResourceLimitExitCount, "vigilante": a.cumulativeAppWatchdogExitCount,
                              "acceso malo": a.cumulativeBadAccessExitCount, "instrucción": a.cumulativeIllegalInstructionExitCount,
                              "anormal": a.cumulativeAbnormalExitCount]
                if let t = FalloAppReglas.salidas(fondo: fondo, frente: frente) { self.anotar([t]) }
            }
        }
    }

    private func diagnosticos(_ payloads: [MXDiagnosticPayload]) {
        let d = UserDefaults.standard
        var vistos = d.stringArray(forKey: FalloApp.claveVistos) ?? []
        for p in payloads {
            for c in p.crashDiagnostics ?? [] {
                // Cada informe una sola vez (pastDiagnosticPayloads trae otra vez los de antes).
                let marca = "\(Int(p.timeStampEnd.timeIntervalSince1970))-\(c.signal?.intValue ?? 0)-\(c.exceptionType?.intValue ?? 0)"
                guard !vistos.contains(marca) else { continue }
                vistos.append(marca)
                var f = FalloAppReglas.Fallo()
                f.build = c.metaData.applicationBuildVersion
                f.tipo = c.exceptionType?.intValue; f.codigo = c.exceptionCode?.intValue; f.senal = c.signal?.intValue
                f.terminacion = c.terminationReason
                if let r = c.exceptionReason { f.excepcion = r.exceptionName; f.motivo = r.composedMessage }
                f.pila = FalloAppReglas.pila(json: c.callStackTree.jsonRepresentation())
                let cuando = DateFormatter(); cuando.dateFormat = "d-MMM HH:mm"
                anotar(FalloAppReglas.pasos(f, de: "informe de iOS, " + cuando.string(from: p.timeStampEnd)))
            }
        }
        d.set(Array(vistos.suffix(30)), forKey: FalloApp.claveVistos)
    }

    /// Al registro de la voz (va al Hub con los avisos) y se manda ya, sin esperar la vuelta de 45 s.
    private func anotar(_ pasos: [String]) {
        guard !pasos.isEmpty else { return }
        for t in pasos { VozNativa.shared.anotar(t) }
        VozNativa.shared.mandarPasosYa()
    }
}
