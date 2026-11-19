import Foundation

// Modo compañero (Hub #607 T-C1, apps-script/vivo.js): la lógica pura (sin red ni iOS), para probarla sola (Pruebas/Companero).
// El dispositivo que está en la llamada es el único con micrófono y audio; publica lo que pasa (el estado y los subtítulos)
// para que el otro (el iPad con «Modo compañero» encendido) lo muestre en vivo. El tablero lo deja el Hub, no la app.
//   · Los subtítulos se juntan y salen en un solo envío: cada `cada` segundos si alguien está mirando, y cada `sinMirar`
//     si el Hub dijo que no hay compañero (así no gasta en una llamada que nadie ve). El estado (empezó, terminó) sale ya.
//   · Una llamada nueva empieza vacía; al terminar se manda «fin» y no queda nada pendiente.
//   · El latido (cada `latido` segundos, aunque nadie hable) también trae «colgar» si Juan tocó «Terminar» en el compañero
//     (Juan, 19-nov-2026: «si por error se activa, no puedo terminar la llamada»).
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

/// Una sola llamada (Juan, 17-nov-2026: «importante que en modo Companion sólo haya una llamada»). El dispositivo con el
/// Modo compañero encendido (normalmente el iPad) muestra la llamada del otro; no abre otra por su cuenta:
///   · Por voz o sola («Alma» en el inicio, el Modo calle, la conferencia, un aviso): nunca. Los dos oyen lo mismo y, si
///     los dos abrieran, habría dos llamadas con dos Almas hablando a la vez.
///   · En el iPad (Juan, 19-nov-2026: «en modo Companion en iPad… permite hacer llamadas y muestra notificaciones cuando
///     debería estar deshabilitado en ese modo»): a mano tampoco (la roca, el anillo) y no llegan notificaciones; las
///     llamadas y los avisos quedan en el teléfono. Para llamar desde el iPad, se apaga el Modo compañero.
///   · En el teléfono con el modo encendido, a mano sí, salvo que la página haya visto hace poco la llamada abierta en el otro.
///   · Sin Modo compañero, todo como antes.
///   · El iPhone nunca se detiene (Juan, 19-nov-2026: «si está activado el teléfono, por default el agente del teléfono»):
///     aunque tenga el Modo compañero encendido, «Alma» dicho en voz alta abre ahí. Si el iPad ya estaba en una llamada, el
///     Hub (vivoPublicar, apps-script/vivo.js) le dice al iPad que ceda y el iPad cuelga la suya (VozNativa.cederAlTelefono).
/// La página (alma/inicio.html, que pregunta al Hub con vivoLeer) le cuenta a la app si está encendido y si el otro
/// está en una llamada; lo que dijo vale `vigencia` segundos (la página lo repite cada 10 s mientras sigue).
enum UnaLlamada {
    static let vigencia: TimeInterval = 30
    static let enIPad = "Modo compañero: en el iPad no se abren llamadas; la llamada va en tu teléfono. Apágalo para llamar desde aquí"
    /// nil = puede abrir la llamada aquí; si no, la frase de por qué no (va al registro de la voz).
    static func motivo(companero: Bool, ipad: Bool = false, telefono: Bool = false, porVoz: Bool, otra: String, visto: Date?, ahora: Date) -> String? {
        guard companero, !telefono else { return nil }
        if ipad { return enIPad }
        if porVoz { return "Modo compañero: aquí no se abre una llamada por voz; la llamada es en tu otro dispositivo" }
        guard !otra.isEmpty, let v = visto, ahora.timeIntervalSince(v) < vigencia else { return nil }
        return "Modo compañero: la llamada sigue en tu \(otra); aquí no se abre otra"
    }
    /// ¿Este dispositivo calla sus notificaciones? Solo el iPad con el Modo compañero encendido: no pregunta por avisos al Hub
    /// (así no se los lleva y le llegan al teléfono), no arma notificaciones y su push queda apagado (PushAlma.callar).
    static func callaAvisos(companero: Bool, ipad: Bool) -> Bool { companero && ipad }
}
