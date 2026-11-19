import Foundation

// Modo compañero (Hub #607 T-C1, apps-script/vivo.js): la lógica pura (sin red ni iOS), para probarla sola (Pruebas/Companero).
// El dispositivo que está en la llamada es el único con micrófono y audio; publica lo que pasa (el estado y los subtítulos)
// para que el otro (el iPad con «Modo compañero» encendido) lo muestre en vivo. El tablero lo deja el Hub, no la app.
//   · Los subtítulos se juntan y salen en un solo envío: cada `cada` segundos si alguien está mirando, y cada `sinMirar`
//     si el Hub dijo que no hay compañero (así no gasta en una llamada que nadie ve). El estado (empezó, terminó) sale ya.
//   · Una llamada nueva empieza vacía; al terminar se manda «fin» y no queda nada pendiente.
struct ColaVivo {
    struct Sub: Equatable { let de: String; let t: String }
    private(set) var conv = ""
    private(set) var subs: [Sub] = []
    private(set) var estado = ""
    private(set) var estadoNuevo = false
    var mirando = true                 // lo último que dijo el Hub (al principio, sí: el primer envío lo averigua)
    var ultimoEnvio: Date = .distantPast
    static let cada: TimeInterval = 1.2, sinMirar: TimeInterval = 12, maxSubs = 8, largo = 280
    /// Latido sin novedades (Juan, 19-nov-2026: «no me está dejando terminar la llamada»): la respuesta del Hub trae si el
    /// compañero tocó «Terminar» (y si alguien mira). Con alguien mirando, cada 3 s; si no, cada 12 s.
    static let latido: TimeInterval = 3

    mutating func empezo(_ id: String) { conv = id; subs = []; estado = "conectando"; estadoNuevo = true; mirando = true; ultimoEnvio = .distantPast }
    mutating func cambiar(_ e: String) { guard !conv.isEmpty, e != estado else { return }; estado = e; estadoNuevo = true }
    mutating func sub(alma: Bool, _ texto: String) {
        let t = texto.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard !conv.isEmpty, !t.isEmpty else { return }
        subs.append(Sub(de: alma ? "alma" : "yo", t: String(t.prefix(ColaVivo.largo))))
        if subs.count > ColaVivo.maxSubs { subs.removeFirst(subs.count - ColaVivo.maxSubs) }
    }
    /// ¿Toca mandar ahora? El estado, siempre; los subtítulos, según si alguien mira.
    func toca(_ ahora: Date) -> Bool {
        guard !conv.isEmpty else { return false }
        if estadoNuevo { return true }
        if ahora.timeIntervalSince(ultimoEnvio) >= (mirando ? ColaVivo.latido : ColaVivo.sinMirar) { return true }
        guard !subs.isEmpty else { return false }
        return ahora.timeIntervalSince(ultimoEnvio) >= (mirando ? ColaVivo.cada : ColaVivo.sinMirar)
    }
    /// Lo que se manda (y se vacía la cola). Con «fin», la llamada queda cerrada aquí.
    mutating func sacar(_ ahora: Date) -> [String: Any]? {
        guard toca(ahora) else { return nil }
        var b: [String: Any] = ["conv_id": conv, "subs": subs.map { ["de": $0.de, "t": $0.t] }]
        if estadoNuevo { b["estado"] = estado }
        subs = []; estadoNuevo = false; ultimoEnvio = ahora
        if estado == "fin" { conv = "" }
        return b
    }
}

/// Una sola llamada (Juan, 17-nov-2026: «importante que en modo Companion sólo haya una llamada»). El dispositivo con el
/// Modo compañero encendido (normalmente el iPad) muestra la llamada del otro; no abre otra por su cuenta:
///   · Por voz o sola («Alma» en el inicio, el Modo calle, la conferencia, un aviso): nunca. Los dos oyen lo mismo y, si
///     los dos abrieran, habría dos llamadas con dos Almas hablando a la vez.
///   · A mano (la roca, el anillo): sí, salvo que la página haya visto hace poco la llamada abierta en el otro.
///   · Sin Modo compañero, todo como antes.
/// La página (alma/inicio.html, que pregunta al Hub con vivoLeer) le cuenta a la app si está encendido y si el otro
/// está en una llamada; lo que dijo vale `vigencia` segundos (la página lo repite cada 10 s mientras sigue).
enum UnaLlamada {
    static let vigencia: TimeInterval = 30
    /// nil = puede abrir la llamada aquí; si no, la frase de por qué no (va al registro de la voz).
    static func motivo(companero: Bool, porVoz: Bool, otra: String, visto: Date?, ahora: Date) -> String? {
        guard companero else { return nil }
        if porVoz { return "Modo compañero: aquí no se abre una llamada por voz; la llamada es en tu otro dispositivo" }
        guard !otra.isEmpty, let v = visto, ahora.timeIntervalSince(v) < vigencia else { return nil }
        return "Modo compañero: la llamada sigue en tu \(otra); aquí no se abre otra"
    }
}
