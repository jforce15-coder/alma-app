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
    /// Aunque no haya nada nuevo, cada `latido` segundos se avisa que la llamada sigue: así, si la llamada se abrió también
    /// en el iPhone, el Hub se lo dice a esta enseguida («ceder») y solo queda una voz (UnaLlamada).
    static let latido: TimeInterval = 6

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
        if ahora.timeIntervalSince(ultimoEnvio) >= ColaVivo.latido { return true }
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

/// Una sola llamada (Juan, 17-nov-2026: «importante que en modo Companion sólo haya una llamada») y una voz a la vez (Juan,
/// 19-nov-2026: «solo debería haber un agente por voz activo; si está activado el teléfono, usar por default el agente del
/// teléfono»). **El iPhone manda**: nunca se le bloquea. En otro dispositivo (el iPad, el «escritorio»):
///   · Con el Modo compañero encendido, por voz o sola («Alma» en el inicio, el Modo calle, la conferencia, un aviso): nunca.
///   · Sin él, por voz no mientras el iPhone esté activo (la app abierta o escuchando: el Hub lo sabe por vivoTelefono) o
///     en una llamada. Los dos oyen lo mismo y, si los dos abrieran, habría dos Almas hablando a la vez.
///   · En el iPad con el Modo compañero encendido (Juan, 19-nov-2026: «en modo Companion en iPad… permite hacer llamadas y
///     muestra notificaciones cuando debería estar deshabilitado en ese modo»): a mano tampoco y no llegan notificaciones;
///     para llamar desde el iPad, se apaga el Modo compañero.
///   · A mano (la roca, el anillo): sí, salvo que la página haya visto hace poco la llamada abierta en el otro.
///   · Si el iPad ya estaba en una llamada y el iPhone abre otra, el Hub (vivoPublicar, apps-script/vivo.js) le dice al
///     iPad que ceda y el iPad cuelga la suya (VozNativa.cederAlTelefono).
/// La página (alma/inicio.html, que pregunta al Hub con vivoLeer) le cuenta a la app si el compañero está encendido, si el
/// otro está en una llamada y si el iPhone está activo; lo que dijo vale `vigencia` segundos (la página lo repite cada 10 s).
enum UnaLlamada {
    static let vigencia: TimeInterval = 30
    static let enIPad = "Modo compañero: en el iPad no se abren llamadas; la llamada va en tu teléfono. Apágalo para llamar desde aquí"
    /// nil = puede abrir la llamada aquí; si no, la frase de por qué no (va al registro de la voz).
    /// `telefono`: este dispositivo es el iPhone. `telActivo`: la página dijo que el iPhone está activo.
    static func motivo(companero: Bool, ipad: Bool = false, telefono: Bool = false, porVoz: Bool, otra: String, visto: Date?, ahora: Date, telActivo: Bool = false) -> String? {
        if telefono { return nil }
        if companero && ipad { return enIPad }
        let fresco = visto.map { ahora.timeIntervalSince($0) < vigencia } ?? false
        if porVoz {
            if companero { return "Modo compañero: aquí no se abre una llamada por voz; la llamada es en tu otro dispositivo" }
            if fresco && !otra.isEmpty { return "Una voz a la vez: la llamada sigue en tu \(otra); aquí no se abre otra por voz" }
            if fresco && telActivo { return "Una voz a la vez: tu iPhone está activo y contesta él; aquí no se abre una llamada por voz" }
            return nil
        }
        guard fresco, !otra.isEmpty else { return nil }
        return (companero ? "Modo compañero" : "Una voz a la vez") + ": la llamada sigue en tu \(otra); aquí no se abre otra"
    }
    /// ¿Este dispositivo calla sus notificaciones? Solo el iPad con el Modo compañero encendido: no pregunta por avisos al Hub
    /// (así no se los lleva y le llegan al teléfono), no arma notificaciones y su push queda apagado (PushAlma.callar).
    static func callaAvisos(companero: Bool, ipad: Bool) -> Bool { companero && ipad }
}
