import Foundation

/// Guía de camino (Hub #661, pedido de Juan del 17-nov-2026): la lógica pura, sin GPS ni pantalla, para probarla sola
/// (Pruebas/GuiaCamino). GuiaCamino.swift le pasa cada ubicación y hace lo que devuelve: decir un paso, «llegaste» o
/// pedir otra ruta.
///   · Justo a tiempo: cada paso se dice cuando Juan llega a su punto (donde se gira): 25 m caminando, 45 m en bici, 40 m
///     en bus y 150 m en carro, más un poco si el GPS viene impreciso. Bajarse del bus se avisa antes (el Hub manda `antes`).
///   · Si se saltó un punto (iba rápido o el GPS brincó), se dice el último que alcanzó, no todos.
///   · Fuera del camino: 3 ubicaciones seguidas lejos de la línea → recalcular (GuiaCamino espera 20 s entre una y otra).
///   · Un GPS muy malo (más de 80 m) no cuenta.
struct GuiaPunto: Equatable {
    var lat: Double
    var lng: Double
}

struct GuiaPaso: Equatable {
    var texto: String
    var punto: GuiaPunto
    var antes: Double?   // metros antes del punto en que se avisa (la anticipación del Hub o bajarse del bus); nil = el del medio
    var giro = ""        // la flecha de la pantalla: izquierda | derecha | vuelta | rotonda | recto | bus | bajar (el Hub)
}

enum GuiaEvento: Equatable {
    case decir(Int, String)
    case llegaste
    case recalcular
}

struct GuiaCaminoReglas {
    let pasos: [GuiaPaso]
    let fin: GuiaPunto
    let modo: String
    let linea: [GuiaPunto]
    /// El paso que toca decir (el 0 lo dice Alma al empezar).
    private(set) var siguiente = 1
    private(set) var termino = false
    private var lejos = 0

    init(pasos: [GuiaPaso], fin: GuiaPunto, modo: String, linea: [GuiaPunto]) {
        self.pasos = pasos; self.fin = fin; self.modo = modo
        self.linea = linea.count >= 2 ? linea : pasos.map(\.punto) + [fin]
    }

    var umbral: Double {
        switch modo {
        case "carro": return 150
        case "bici": return 45
        case "bus": return 40
        default: return 25
        }
    }
    var tolerancia: Double {
        switch modo {
        case "carro": return 90
        case "bus": return 150
        case "bici": return 60
        default: return 50
        }
    }

    /// Una ubicación nueva → lo que hay que hacer (o nada).
    mutating func ubicacion(_ p: GuiaPunto, precision: Double) -> GuiaEvento? {
        guard !termino, precision >= 0, precision <= 80 else { return nil }
        let margen = min(precision, 30)
        if GuiaCaminoReglas.distancia(p, fin) <= max(umbral, 20) + margen { termino = true; return .llegaste }
        // El paso más adelantado (de los 3 que siguen) cuyo punto ya alcanzó.
        var dicho: Int?
        if siguiente < pasos.count {
            for j in siguiente..<min(siguiente + 3, pasos.count) {
                let r = (pasos[j].antes ?? umbral) + margen
                if GuiaCaminoReglas.distancia(p, pasos[j].punto) <= r { dicho = j }
            }
        }
        if let j = dicho { siguiente = j + 1; lejos = 0; return .decir(j, pasos[j].texto) }
        if GuiaCaminoReglas.aLaLinea(p, linea) > tolerancia + min(precision, 40) {
            lejos += 1
            if lejos >= 3 { lejos = 0; return .recalcular }
        } else { lejos = 0 }
        return nil
    }

    /// Cuánto falta para el próximo punto (para la pantalla).
    func faltan(desde p: GuiaPunto) -> Double? {
        siguiente < pasos.count ? GuiaCaminoReglas.distancia(p, pasos[siguiente].punto) : GuiaCaminoReglas.distancia(p, fin)
    }
    var proximoTexto: String? { siguiente < pasos.count ? pasos[siguiente].texto : nil }
    var proximoGiro: String { siguiente < pasos.count ? pasos[siguiente].giro : "llegar" }
    /// El paso que viene después del próximo (el «Luego» de la pantalla).
    var luegoTexto: String? { siguiente + 1 < pasos.count ? pasos[siguiente + 1].texto : nil }
    var luegoGiro: String { siguiente + 1 < pasos.count ? pasos[siguiente + 1].giro : "llegar" }

    // MARK: - La pantalla (estilo carro, Juan 20-nov-2026)

    /// En la pantalla la distancia ya va en grande: «En media cuadra, en la tienda Polo, cruza…» → «En la tienda Polo, cruza…».
    static func textoPantalla(_ t: String) -> String {
        var s = t
        for p in ["En una cuadra, ", "En media cuadra, ", "Ahora, ", "Ahora: "] where s.hasPrefix(p) {
            s = String(s.dropFirst(p.count)); break
        }
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    /// El símbolo (SF Symbols) de cada flecha.
    static func simbolo(_ giro: String) -> String {
        switch giro {
        case "izquierda": return "arrow.turn.up.left"
        case "derecha": return "arrow.turn.up.right"
        case "vuelta": return "arrow.uturn.down"
        case "rotonda": return "arrow.triangle.2.circlepath"
        case "bus": return "bus.fill"
        case "bajar": return "figure.walk.departure"
        case "llegar": return "flag.checkered"
        default: return "arrow.up"
        }
    }

    /// Metros que faltan por el camino (desde el punto de la línea más cercano a p hasta el final).
    static func restante(_ p: GuiaPunto, _ l: [GuiaPunto]) -> Double {
        guard l.count >= 2 else { return l.last.map { distancia(p, $0) } ?? 0 }
        let k = cos(p.lat * Double.pi / 180) * 111_320.0, m = 110_540.0
        var mejor = Double.infinity, seg = 0, tt = 0.0
        for i in 0..<(l.count - 1) {
            let ax = (l[i].lng - p.lng) * k, ay = (l[i].lat - p.lat) * m
            let bx = (l[i + 1].lng - p.lng) * k, by = (l[i + 1].lat - p.lat) * m
            let dx = bx - ax, dy = by - ay, d2 = dx * dx + dy * dy
            let t = d2 > 0 ? max(0, min(1, -(ax * dx + ay * dy) / d2)) : 0
            let x = ax + t * dx, y = ay + t * dy, d = x * x + y * y
            if d < mejor { mejor = d; seg = i; tt = t }
        }
        var total = distancia(l[seg], l[seg + 1]) * (1 - tt)
        for i in (seg + 1)..<(l.count - 1) { total += distancia(l[i], l[i + 1]) }
        return total
    }

    // MARK: - Geometría

    static func distancia(_ a: GuiaPunto, _ b: GuiaPunto) -> Double {
        let r = 6_371_000.0, rad = Double.pi / 180
        let dLat = (b.lat - a.lat) * rad, dLng = (b.lng - a.lng) * rad
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(a.lat * rad) * cos(b.lat * rad) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }

    /// Distancia (m) del punto a la línea del camino (aproximación plana: sobra para unos cientos de metros).
    static func aLaLinea(_ p: GuiaPunto, _ l: [GuiaPunto]) -> Double {
        guard l.count >= 2 else { return l.first.map { distancia(p, $0) } ?? .infinity }
        let k = cos(p.lat * Double.pi / 180) * 111_320.0, m = 110_540.0
        var mejor = Double.infinity
        for i in 0..<(l.count - 1) {
            let ax = (l[i].lng - p.lng) * k, ay = (l[i].lat - p.lat) * m
            let bx = (l[i + 1].lng - p.lng) * k, by = (l[i + 1].lat - p.lat) * m
            let dx = bx - ax, dy = by - ay, d2 = dx * dx + dy * dy
            let t = d2 > 0 ? max(0, min(1, -(ax * dx + ay * dy) / d2)) : 0
            let x = ax + t * dx, y = ay + t * dy
            mejor = min(mejor, (x * x + y * y).squareRoot())
        }
        return mejor
    }

    /// La línea que manda Google (polyline codificada) → puntos.
    static func decodificar(_ s: String) -> [GuiaPunto] {
        var out: [GuiaPunto] = [], lat = 0, lng = 0
        let b = Array(s.utf8)
        var i = 0
        func uno() -> Int? {
            var res = 0, shift = 0
            while i < b.count {
                let c = Int(b[i]) - 63; i += 1
                res |= (c & 0x1f) << shift; shift += 5
                if c < 0x20 { return (res & 1) != 0 ? ~(res >> 1) : (res >> 1) }
            }
            return nil
        }
        while i < b.count {
            guard let a = uno(), let c = uno() else { break }
            lat += a; lng += c
            out.append(GuiaPunto(lat: Double(lat) / 1e5, lng: Double(lng) / 1e5))
        }
        return out
    }

    /// «a 120 m» · «a 1,4 km» (para la pantalla).
    static func textoDistancia(_ m: Double) -> String {
        if m < 1000 { return "\(max(10, Int((m / 10).rounded()) * 10)) m" }
        let km = (m / 100).rounded() / 10
        return String(format: "%.1f km", km).replacingOccurrences(of: ".", with: ",")
    }
}
