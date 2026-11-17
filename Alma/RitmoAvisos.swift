import Foundation

/// El ritmo de los avisos hablados (Juan, 17-nov-2026, Hub #670): «una notificación a la vez, la más urgente; una pausa y
/// esperar respuesta; si no hay respuesta, silencio. Uno a tres minutos después, la segunda; luego retomar el ciclo
/// recordando la primera si sigue pendiente, o avanzar si ya se resolvió, rotando siempre las tres más urgentes».
/// Lógica pura (sin iOS), con sus pruebas en Pruebas/RitmoAvisos. ModoCalle la usa en el Modo calle, con la app abierta y en
/// conferencia:
///   · Uno a la vez: mientras se dice un aviso (y se escucha la respuesta, o sigue la conversación que abrió) no sale otro.
///   · El más urgente primero: nivel 1 urgente · 2 pide algo de ti · 3 aviso (NivelAvisos); a igual nivel, el que llegó antes.
///   · Silencio entre uno y otro: `pausa` (2 min, a la mitad de «uno a tres») desde que terminó el anterior. El primero de
///     una tanda sale enseguida si no hubo otro hace poco.
///   · Rotan los tres más urgentes que siguen pendientes: le toca al que menos veces se dijo (empate: el más urgente). Así
///     va 1 → 2 → 3 → 1… y uno nuevo y urgente entra al ciclo antes que un recordatorio.
///   · Resuelto = Juan contestó (cualquier cosa, también «luego») o Alma abrió la conversación por él: sale del ciclo.
///   · Sin respuesta sigue pendiente y vuelve en la rotación, hasta `maxVeces` (la primera y dos recordatorios) o `vence`
///     (2 h desde que llegó); después queda solo en Pendientes y en la notificación, sin insistir más.
struct RitmoAvisos {
    struct Item: Equatable {
        let id: String
        let nivel: Int
        let llego: Date
        var veces = 0
    }

    static let pausa: TimeInterval = 120
    static let ronda = 3
    static let maxVeces = 3
    static let vence: TimeInterval = 2 * 3600

    private(set) var items: [Item] = []
    /// El aviso que se está diciendo (o esperando respuesta): mientras tanto no sale otro.
    private(set) var enCurso: String?
    /// Cuándo terminó el último aviso: desde ahí corre el silencio.
    private(set) var silencioDesde: Date?

    var vacio: Bool { items.isEmpty }
    var ids: [String] { items.map { $0.id } }

    /// Llega un aviso nuevo (si ya estaba, no se repite).
    mutating func llegar(id: String, nivel: Int, ahora: Date = Date()) {
        guard !items.contains(where: { $0.id == id }) else { return }
        items.append(Item(id: id, nivel: max(1, min(3, nivel)), llego: ahora))
    }

    /// Los que todavía cuentan (sin vencer ni agotar sus veces), del más urgente al menos.
    mutating func limpiar(ahora: Date = Date()) {
        items.removeAll { $0.id != enCurso && ($0.veces >= RitmoAvisos.maxVeces || ahora.timeIntervalSince($0.llego) >= RitmoAvisos.vence) }
    }

    /// Los tres más urgentes que siguen pendientes, en orden.
    func rondaActual() -> [Item] {
        Array(items.sorted { ($0.nivel, $0.llego) < ($1.nivel, $1.llego) }.prefix(RitmoAvisos.ronda))
    }

    /// Cuántos segundos faltan para poder decir el siguiente (0: ya). nil: no hay nada que decir o hay uno en curso.
    func falta(ahora: Date = Date()) -> TimeInterval? {
        guard enCurso == nil, !items.isEmpty else { return nil }
        guard let s = silencioDesde else { return 0 }
        return max(0, RitmoAvisos.pausa - ahora.timeIntervalSince(s))
    }

    /// ¿A cuál le toca ahora? nil si todavía es silencio, si hay uno en curso o si no queda ninguno.
    mutating func siguiente(ahora: Date = Date()) -> String? {
        limpiar(ahora: ahora)
        guard falta(ahora: ahora) == 0 else { return nil }
        let r = rondaActual()
        guard let menos = r.map({ $0.veces }).min() else { return nil }
        return r.first { $0.veces == menos }?.id
    }

    /// Se empieza a decir: cuenta una vez más y no sale otro hasta que termine.
    mutating func decir(_ id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].veces += 1
        enCurso = id
    }

    /// Juan contestó (o Alma abrió la conversación por él): resuelto, sale del ciclo.
    mutating func resuelto(_ id: String) {
        items.removeAll { $0.id == id }
    }

    /// Terminó lo de ese aviso (lo dijo y escuchó, o terminó la conversación): empieza el silencio.
    mutating func termino(ahora: Date = Date()) {
        guard enCurso != nil else { return }
        enCurso = nil
        silencioDesde = ahora
    }

    /// Se apaga o ya no se puede hablar: el ciclo se vacía (quedan en Pendientes y en la notificación).
    mutating func vaciar() {
        items = []; enCurso = nil
    }
}
