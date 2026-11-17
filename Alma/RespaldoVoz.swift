import Foundation

/// Voz de respaldo de Alma (Hub #657; Juan, 17-nov-2026: «implementar voz local de respaldo para Alma, al igual que Claudio,
/// de modo que se monitoree la señal de Internet y solo se active la voz local cuando haya problemas o caída de conexión»).
/// Lógica pura, con sus pruebas en Pruebas/RespaldoVoz. Lo que toca iOS: Conexion.swift (la conexión), ClaudioLocal.swift (el
/// dictado y la voz del iPhone, el mismo motor de Claudio local) y VozNativa.swift (cuándo entra y cuándo sale).
/// · Normal: la llamada con Alma va por ElevenLabs, como siempre. La app vigila la conexión todo el tiempo (Conexion).
/// · Entra el respaldo cuando la conexión falla en una llamada normal: sin internet (el internet se fue unos segundos o el socket
///   se cayó sin red), o la voz se cortó varias veces seguidas (conexión inestable). Alma lo dice en una frase y sigue con la voz
///   del iPhone: la oye el dictado del teléfono y contesta el Hub (acción «calle», sin audio: solo texto, poco internet).
/// · Sin nada de internet: lo que dice Juan se guarda (hasta `maxCola`) y se manda solo en cuanto vuelve el internet.
/// · Sale cuando la conexión vuelve y se queda estable: Alma vuelve a su voz de ElevenLabs sin colgar (y lo dice).
/// · No aplica en el Modo calle ni en conferencia: esos ya cierran y vuelven a esperar «Alma» con su propia voz del iPhone.
enum RespaldoVoz {

    // MARK: - Cuándo entra

    /// Segundos sin internet (con la llamada en curso) para dar la conexión por caída: un parpadeo al cambiar de wifi a datos no cuenta.
    static let sinRedTras = 2.5
    /// Cortes de la voz en `ventanaCortes` segundos que ya cuentan como conexión inestable (aunque el teléfono diga que hay red).
    static let cortesInestable = 2, ventanaCortes = 90.0

    /// ¿La llamada sigue con la voz de respaldo en vez de reabrir ElevenLabs (o colgar con error)?
    static func usar(hayRed: Bool, cortes: [Date], ahora: Date, calle: Bool, conferencia: Bool, sinCreditos: Bool) -> Bool {
        if calle || conferencia || sinCreditos { return false }
        return !hayRed || recientes(cortes, ahora: ahora) >= cortesInestable
    }
    static func recientes(_ cortes: [Date], ahora: Date) -> Int { cortes.filter { ahora.timeIntervalSince($0) <= ventanaCortes }.count }

    // MARK: - Cuándo sale

    /// Segundos con conexión estable para volver a la voz de siempre; cada vez que vuelve y se cae otra vez, espera más (tope 60 s).
    static func estableTras(vueltas: Int) -> Double { min(60, 6 * pow(2, Double(max(0, vueltas)))) }
    /// ¿Ya vuelve a ElevenLabs? Con internet desde hace `estableTras`, sin nada guardado por mandar y sin que Alma esté pensando o hablando.
    static func puedeVolver(hayRed: Bool, redDesde: Date, ahora: Date, vueltas: Int, ocupada: Bool, pendientes: Int) -> Bool {
        hayRed && !ocupada && pendientes == 0 && ahora.timeIntervalSince(redDesde) >= estableTras(vueltas: vueltas)
    }

    // MARK: - Lo que dice

    static let entra = "Se me fue el internet. Sigo contigo con la voz del teléfono."
    static let inestable = "La conexión está fallando. Sigo contigo con la voz del teléfono."
    static let guardado = "Sin internet no puedo hacerlo todavía. Lo guardo y lo mando en cuanto vuelva."
    static let lleno = "Ya tengo varias cosas guardadas. Espera a que vuelva el internet y seguimos."
    static let vuelve = "Ya volvió el internet. Sigo con mi voz de siempre."
    static let noLlego = "No me llegó la respuesta. ¿Me lo repites?"
    static func frase(hayRed: Bool) -> String { hayRed ? inestable : entra }

    /// La voz del iPhone que hace de Alma: de mujer, en español de México (luego Estados Unidos, Latinoamérica y España), la de
    /// mejor calidad instalada. Mismo formato que voz_local de Claudio local (ClaudioLocalReglas.Ajustes).
    static let voz: [String: Any] = ["idiomas": ["es-MX", "es-US", "es-419", "es-ES"], "genero": "mujer", "velocidad": 0.5, "tono": 1.0, "volumen": 1]

    // MARK: - Lo que se guarda sin internet

    static let maxCola = 5
    /// Suma una frase a lo guardado. Devuelve la cola nueva y si cupo.
    static func guardar(_ cola: [String], _ t: String) -> (cola: [String], cupo: Bool) {
        let x = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !x.isEmpty else { return (cola, true) }
        guard cola.count < maxCola else { return (cola, false) }
        return (cola + [String(x.prefix(600))], true)
    }
    /// Lo que dice al guardar: la primera vez, completo; después, corto (no repite la explicación).
    static func trasGuardar(cuantas: Int, cupo: Bool) -> String { !cupo ? lleno : cuantas <= 1 ? guardado : "Guardado." }
    /// Lo guardado, en un solo pedido (así el Hub lo ve junto y contesta una vez).
    static func juntar(_ cola: [String]) -> String {
        guard cola.count > 1 else { return cola.first ?? "" }
        return "Te lo dije mientras no había internet: " + cola.joined(separator: " · ")
    }

    // MARK: - El Hub

    /// La frase al Hub: la misma acción del Modo calle (respuesta corta para decir), sin audio de ElevenLabs.
    static func pedido(token: String, sesion: String, texto: String) -> [String: Any] {
        ["hub": 1, "action": "calle", "token": token, "session": sesion, "app": "alma", "canal": "calle", "sin_audio": true,
         "texto": String(texto.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))]
    }
    /// Lo que se dice con la respuesta del Hub (sin frase: «¿me lo repites?»).
    static func hablar(_ j: [String: Any]?) -> String {
        let h = (j?["hablar"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return h.isEmpty ? noLlego : h
    }
}
