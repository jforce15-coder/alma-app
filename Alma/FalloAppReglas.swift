import Foundation

/// El porqué de un cierre de la app a media llamada (guardia 21-nov-2026: la llamada del Modo calle con la Guía de camino
/// abierta terminó en 1006 y la app solo pudo decir «se cerró (iOS la terminó o falló)», sin la causa). Lógica pura, sin
/// iOS: se prueba sola en Pruebas/FalloApp. FalloApp.swift junta los datos (el informe de fallo de iOS por MetricKit y la
/// excepción de Objective-C que tumba la app) y estas reglas los vuelven pasos cortos para el registro del Hub.
///   · Cada paso cabe en lo que deja pasar PasosAnillo (140 letras con la hora): el motivo, la pila y las salidas raras.
///   · Sin datos de nadie: solo nombres de bibliotecas, direcciones y el texto de la excepción (recortado; correos y enlaces
///     los borra PasosAnillo.limpiar).
enum FalloAppReglas {
    /// Largo de cada paso (sin la hora «HH:mm:ss » que le pone el registro).
    static let largo = 120
    /// Cuántas líneas de la pila del hilo que falló se mandan (de arriba, lo último que corrió).
    static let marcos = 12

    /// Lo que se sabe del fallo. Todo opcional: el informe de iOS no siempre trae todo.
    struct Fallo: Equatable {
        var build: String?
        var tipo: Int?          // exceptionType (EXC_*, número de Mach)
        var codigo: Int?        // exceptionCode
        var senal: Int?         // signal (6 = SIGABRT, 11 = SIGSEGV…)
        var excepcion: String?  // nombre de la excepción de Objective-C (NSInternalInconsistencyException…)
        var motivo: String?     // su texto (required condition is false: …)
        var terminacion: String?
        var pila: [String] = [] // «AVFAudio +0x1a2b» de arriba hacia abajo
    }

    static func nombreSenal(_ s: Int) -> String {
        switch s {
        case 4: return "SIGILL"; case 5: return "SIGTRAP"; case 6: return "SIGABRT"; case 8: return "SIGFPE"
        case 9: return "SIGKILL"; case 10: return "SIGBUS"; case 11: return "SIGSEGV"; default: return "señal \(s)"
        }
    }
    static func nombreTipo(_ t: Int) -> String {
        switch t {
        case 1: return "EXC_BAD_ACCESS"; case 2: return "EXC_BAD_INSTRUCTION"; case 3: return "EXC_ARITHMETIC"
        case 6: return "EXC_BREAKPOINT"; case 10: return "EXC_CRASH"; case 11: return "EXC_RESOURCE"; case 12: return "EXC_GUARD"
        default: return "excepción \(t)"
        }
    }

    /// Las comillas «» las borra PasosAnillo.limpiar (ahí suele ir texto de Juan): aquí se cambian por comillas simples.
    static func recortar(_ s: String, _ n: Int = largo) -> String {
        let t = s.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "«", with: "'").replacingOccurrences(of: "»", with: "'")
            .trimmingCharacters(in: .whitespaces)
        return t.count <= n ? t : String(t.prefix(n - 1)) + "…"
    }

    /// Los pasos del fallo, en orden: qué fue, el motivo y la pila en tramos.
    static func pasos(_ f: Fallo, de origen: String) -> [String] {
        var partes: [String] = []
        if let t = f.tipo { partes.append(nombreTipo(t)) }
        if let s = f.senal { partes.append(nombreSenal(s)) }
        if let c = f.codigo, c != 0 { partes.append("código \(c)") }
        if let e = f.excepcion, !e.isEmpty { partes.append(e) }
        let build: String = f.build.map { ", build " + $0 } ?? ""
        let que: String = partes.isEmpty ? "sin tipo" : partes.joined(separator: " · ")
        let primero: String = "Fallo de la app (\(origen)\(build)): \(que)"
        var l: [String] = [primero]
        if let m = f.motivo, !m.isEmpty { l.append("Motivo del fallo: " + m) }
        if let t = f.terminacion, !t.isEmpty { l.append("iOS terminó la app: " + t) }
        let pila = Array(f.pila.prefix(marcos))
        var tramo: [String] = [], n = 1
        func cerrar() { if !tramo.isEmpty { l.append("Pila del fallo \(n): " + tramo.joined(separator: " < ")); n += 1; tramo = [] } }
        for m in pila {
            let unidos: String = (tramo + [m]).joined(separator: " < ")
            let candidato: String = "Pila del fallo \(n): \(unidos)"
            if candidato.count > largo && !tramo.isEmpty { cerrar() }
            tramo.append(m)
        }
        cerrar()
        return l.map { recortar($0) }
    }

    /// La pila del hilo que falló, del JSON de MXCallStackTree (callStacks → el hilo con threadAttributed → el primer marco y
    /// su primer subFrame, hacia abajo). Cada marco: «biblioteca +0xdesplazamiento».
    static func pila(json: Data) -> [String] {
        guard let raiz = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let hilos = raiz["callStacks"] as? [[String: Any]], !hilos.isEmpty else { return [] }
        let hilo = hilos.first { ($0["threadAttributed"] as? Bool) == true } ?? hilos[0]
        var marco = (hilo["callStackRootFrames"] as? [[String: Any]])?.first
        var l: [String] = []
        while let m = marco, l.count < marcos {
            let nombre = (m["binaryName"] as? String).map { String($0.prefix(28)) } ?? "?"
            let off = (m["offsetIntoBinaryTextSegment"] as? NSNumber)?.int64Value
            let hex: String = off.map { " +0x" + String($0, radix: 16) } ?? ""
            l.append(nombre + hex)
            marco = (m["subFrames"] as? [[String: Any]])?.first
        }
        return l
    }

    /// La excepción de Objective-C que tumbó la app (la guarda FalloApp en un archivo antes de morir), de vuelta en pasos.
    /// Formato del archivo: línea 1 nombre, línea 2 motivo, línea 3 build y el resto la pila (callStackSymbols).
    static func desdeArchivo(_ texto: String) -> Fallo? {
        let l = texto.components(separatedBy: "\n")
        guard l.count >= 2, !l[0].isEmpty else { return nil }
        var f = Fallo(); f.excepcion = l[0]; f.motivo = l[1]; f.senal = 6
        if l.count >= 3, !l[2].isEmpty { f.build = l[2] }
        f.pila = l.dropFirst(3).compactMap(marcoSimbolo)
        return f
    }
    /// «4   AVFAudio   0x00000001a2b3c4d5 -[AVAudioPlayerNode play] + 120» → «AVFAudio -[AVAudioPlayerNode play]».
    /// Sin el nombre de la función (la app sin símbolos), solo la biblioteca. Se saltan los marcos de la propia excepción.
    static func marcoSimbolo(_ s: String) -> String? {
        let p = s.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard p.count >= 3 else { return nil }
        let bib = p[1]
        if ["CoreFoundation", "libobjc.A.dylib", "libc++abi.dylib"].contains(bib) { return nil }
        var fn = p.count > 3 ? p[3...].joined(separator: " ") : ""
        if let r = fn.range(of: " + ", options: .backwards) { fn = String(fn[..<r.lowerBound]) }
        if fn.hasPrefix("0x") || fn.isEmpty { return String(bib.prefix(28)) }
        return String(bib.prefix(28)) + " " + String(fn.prefix(60))
    }

    /// Las salidas raras del día que cuenta iOS (MXAppExitMetric): memoria, vigilante, acceso malo… Solo las que no son
    /// cero. Así se sabe si a la app la mató iOS por memoria (el mapa en segundo plano) aunque no haya informe de fallo.
    static func salidas(fondo: [String: Int], frente: [String: Int]) -> String? {
        func parte(_ d: [String: Int]) -> String {
            d.filter { $0.value > 0 }.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        }
        let b = parte(fondo), a = parte(frente)
        guard !b.isEmpty || !a.isEmpty else { return nil }
        var t = "Salidas raras de ayer (iOS)"
        if !a.isEmpty { t += " · a la vista: " + a }
        if !b.isEmpty { t += " · en segundo plano: " + b }
        return recortar(t)
    }
}
