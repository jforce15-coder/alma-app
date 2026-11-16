import Foundation

/// Conversación continua (Juan, 16-nov-2026: «cada vez que hablo con Alma, se corta en automático»). En el Modo calle y en
/// conferencia Alma no se despide y NO cuelga: responde y se queda escuchando, y Juan sigue sin volver a decir «Alma». La
/// app cierra sola la conversación de ElevenLabs (cada minuto abierto gasta créditos) tras un silencio real, sin despedida ni
/// mensaje de error, y vuelve a escuchar «Alma» en el teléfono; al nombrarla otra vez, lleva de contexto lo que se hablaba.
/// Antes («Sin despedidas», Hub #576) la ficha le pedía colgar con end_call apenas respondía: eso era el corte.
///   · Conferencia: `silencio` s sin que nadie hable después de que Alma habló (30 de fábrica; `conferencia_silencio_s` en la
///     ficha del Hub) o `tope` s sin que Alma hable, aunque sigan hablando entre ellos (60; `conferencia_tope_s`).
///   · Modo calle: los segundos del sueño de siempre (SuenoCalle; `calle_silencio_s`, `calle_tope_s`).
///   · Una llamada normal (la roca, el anillo) no la cierra el silencio; si su conexión se cae, la app la vuelve a abrir
///     sola con lo último que se dijo, y si Claudio no conecta vuelve Alma y lo dice en una frase.
/// Lógica pura, sin iOS: se prueba sola en Pruebas/LlamadaContinua.
enum LlamadaContinua {
    /// Lo que la ficha le dice a Alma en el Modo calle y en conferencia. El Hub (voz.js) habla de «CONVERSACIÓN CONTINUA
    /// (lo dice la ficha)»: con estas dos palabras Alma sabe que la app cierra sola y que ella no cuelga.
    static let regla = "CONVERSACIÓN CONTINUA: no te despidas, no digas «aquí sigo» y NUNCA uses end_call. Cuando ya respondiste, quédate escuchando en silencio: Juan puede seguir hablándote sin volver a decir «Alma». Si lo que oyes no es para ti (hablan entre ellos, ruido) o nadie dice nada, usa skip_turn y no contestes. Si lo dejas trabajando en segundo plano, di solo «Entendido, lo hago y te aviso cuando esté listo» y sigue escuchando: cuando esté, tú le avisas. La app cierra sola tras un silencio, sin que digas nada."

    // MARK: - Cuándo cierra sola la app

    /// 16-nov-2026 (23:43, Juan): con 30 s y el silencio contado desde lo último ESCRITO, la app cerraba mientras Juan
    /// explicaba un pedido largo. Ahora el silencio es silencio de verdad (nadie suena) y como mínimo 45 s.
    static let silencioConferencia: TimeInterval = 45
    static let silencioConferenciaMinimo: TimeInterval = 45
    /// En conferencia, la voz sin nada escrito cuenta como alguien hablando hasta 3 min (luego es ruido de fondo), y el tope
    /// sin que Alma hable solo cierra en una pausa de 8 s (no en la que se hace al pensar a media frase).
    static let ruidoConferencia: TimeInterval = 180
    static let pausaConferencia: TimeInterval = 8
    static let topeConferencia: TimeInterval = 60

    /// Un número de la ficha del Hub, entre sus límites; si no viene (un Hub de antes), el de fábrica.
    static func segundos(_ valor: Double?, fabrica: TimeInterval, desde: TimeInterval, hasta: TimeInterval) -> TimeInterval {
        guard let v = valor, v > 0 else { return fabrica }
        return Swift.min(hasta, Swift.max(desde, v))
    }

    struct Tiempos: Equatable {
        let silencio: TimeInterval
        let tope: TimeInterval
        /// Voz sin nada escrito en este tiempo: ruido (no alguien hablando). Y la pausa que tiene que haber para el tope.
        var ruido: TimeInterval = SuenoCalle.soloRuido
        var pausa: TimeInterval = SuenoCalle.oyendo
    }

    /// ¿La app cierra sola esta llamada, y con qué segundos? nil: una llamada normal (no la cierra el silencio).
    /// La que abrió un aviso en conferencia (Alma abre) usa los segundos cortos del sueño hasta que Juan conteste: si nadie
    /// contesta el aviso, no se queda abierta medio minuto.
    /// Con Claudio nunca: la app no cierra por silencio una llamada con Claudio (Juan le explica pedidos largos; 16-nov-2026).
    static func tiempos(calle: Bool, conferencia: Bool, porAviso: Bool, juanHablo: Bool, claudio: Bool = false, deCalle: Tiempos, deConferencia: Tiempos) -> Tiempos? {
        if claudio { return nil }
        if calle { return deCalle }
        if conferencia { return porAviso && !juanHablo ? deCalle : deConferencia }
        return porAviso ? deCalle : nil
    }

    /// El paso que queda en el registro cuando la app cierra sola (o algo corta el audio): dice el modo y el porqué.
    static func pasoCierre(_ motivo: String, calle: Bool, conferencia: Bool) -> String {
        if calle { return "Modo calle: cuelga (" + motivo + ") y vuelve a esperar «Alma»" }
        if conferencia { return "Conferencia: la llamada se cierra sola (" + motivo + ") y vuelve a escuchar «Alma»" }
        return "Alma abre: cuelga (" + motivo + ") y vuelve a escuchar"
    }

    /// Lo que se habló en la llamada pasa al contexto de la conferencia: si vuelven a decir «Alma», ella sabe de qué iban.
    static func contexto(_ reciente: [String], charla: [String], maximo: Int = 8) -> [String] {
        var todo = reciente
        for l in charla {
            let linea = "[con Alma] " + String(l.prefix(220))   // una respuesta larga no llena la ficha de la próxima llamada
            if !todo.contains(linea) { todo.append(linea) }
        }
        return Array(todo.suffix(maximo))
    }

    // MARK: - Si la conexión se cae

    enum TrasCorte: Equatable {
        /// Se vuelve a abrir la conversación de Alma sin colgar la llamada (el micrófono sigue).
        case reabrir
        /// Claudio no conectó o se cayó: vuelve Alma y lo dice en una frase.
        case volverConAlma
        /// Modo calle o conferencia: se cierra sin error y se vuelve a escuchar «Alma».
        case colgar
        /// No hay cómo seguir: se dice por qué y la llamada termina.
        case fallar
    }

    /// Una conexión de menos de esto que se cae no se reabre (algo la rechaza: reabrirla sería un bucle).
    static let minimoConectada: TimeInterval = 3
    /// Cuántas veces se reabre sola una misma llamada.
    static let maxReabrir = 2

    /// La conexión de la llamada se cayó (falló el socket, ElevenLabs cerró sin colgar o no contestó a tiempo): ¿qué sigue?
    /// `conectada`: cuánto llevaba conectada (nil si no llegó a conectar). `reabiertas`: las veces que ya se reabrió.
    static func trasCorte(claudio: Bool, calle: Bool, conferencia: Bool, conectada: TimeInterval?, reabiertas: Int, sinCreditos: Bool) -> TrasCorte {
        if sinCreditos { return .fallar }                                    // sin créditos no hay con quién volver
        if claudio { return reabiertas < maxReabrir ? .volverConAlma : .fallar }
        guard let c = conectada else { return .fallar }                      // Alma nunca contestó: se dice por qué
        if calle || conferencia { return .colgar }
        return c >= minimoConectada && reabiertas < maxReabrir ? .reabrir : .fallar
    }

    /// ElevenLabs cierra la conversación a los 15 min (max_duration_seconds 900) con un cierre normal, igual que cuando Alma
    /// cuelga. Si la llamada llevaba ese tiempo, no colgó ella: se vuelve a abrir.
    static let duracionMaxima: TimeInterval = 900
    static func cerroPorDuracion(conectada: TimeInterval) -> Bool { conectada >= duracionMaxima - 20 }

    /// Claudio «colgó» a los pocos segundos de entrar y sin que Juan le dijera nada: no es una despedida, algo cerró su
    /// conversación al empezar (una protección, un permiso). Se trata como un corte: vuelve Alma y lo dice.
    static let claudioRecienEntro: TimeInterval = 10
    static func cierreAlEmpezar(claudio: Bool, conectada: TimeInterval, juanHablo: Bool) -> Bool {
        claudio && conectada < claudioRecienEntro && !juanHablo
    }

    /// El reloj de «no contestó en 12 s» es de UN intento de conexión: el de un intento anterior (otra llamada, o el
    /// agente de antes de cambiar a Claudio) no puede cortar la conexión de ahora.
    static func vencio(intentoDelReloj: Int, intentoActual: Int, conectando: Bool) -> Bool {
        conectando && intentoDelReloj == intentoActual
    }

    /// Lo primero que dice Alma al reabrir: así Juan sabe qué pasó, en una frase.
    static let fraseTrasCorte = "Perdón, se cortó un momento. Sigue, te escucho."
    static func fraseSinClaudio(conectado: Bool) -> String {
        conectado ? "Se cortó la llamada con Claudio. Sigo yo contigo: ¿qué necesitas?" : "No pude pasarte con Claudio. Sigo yo contigo: ¿qué necesitas?"
    }

    /// La ficha de la conversación reabierta: lo último que se dijo va al final de quien_llama, para seguir donde iban.
    static func ficha(_ quienLlama: String, frase: String, charla: [String], porClaudio: Bool) -> String {
        let que = porClaudio ? "NO SE PUDO SEGUIR CON CLAUDIO y volviste tú" : "SE CORTÓ LA CONEXIÓN un momento y la app la volvió a abrir"
        var t = quienLlama + "\n\n" + que + ": ya le dijiste «" + frase + "». No saludes ni te presentes otra vez; sigue exactamente donde iban."
        if !charla.isEmpty { t += " LO ÚLTIMO QUE SE DIJO:\n" + charla.suffix(6).joined(separator: "\n") }
        return t
    }

    // MARK: - El saludo se oye entero (Juan, 16-nov-2026: «sale el subtítulo pero no la voz»)

    /// Al despertar con «Alma» (Modo Inicio, conferencia), lo que el micrófono guardó mientras conectaba (el «Alma», la
    /// señal, la reunión) llegaba a ElevenLabs junto con el saludo: lo tomaba como que Juan interrumpía y cortaba la voz al
    /// instante (el subtítulo sí salía completo). Mientras suena el saludo no se manda lo del micrófono (va silencio) y lo
    /// guardado se tira; después, todo como siempre. Como mucho `topeSaludo` s, por si el audio no llega.
    static let topeSaludo: TimeInterval = 8
    static let colaSaludo: TimeInterval = 0.3
    /// ¿Se protege este primer mensaje? Solo un saludo de Alma (no vacío: si Juan ya hablaba, Alma lo escucha).
    static func protegeSaludo(primero: String) -> Bool { !primero.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// ¿Sigue protegido? Hasta que el saludo terminó de sonar (y un respiro), o el tope desde que se pidió.
    static func saludoSigue(desde: Date, ahora: Date, sono: Bool, finVoz: Date) -> Bool {
        if ahora.timeIntervalSince(desde) >= topeSaludo { return false }
        if !sono { return true }
        return ahora < finVoz.addingTimeInterval(colaSaludo)
    }

    // MARK: - El registro de pasos (para saber por qué se cortó)

    /// Cuántos pasos se guardan en el teléfono para el Hub. Antes la lista se borraba al empezar cada llamada: si la
    /// siguiente empezaba antes de la vuelta de avisos (45 s), los pasos de la que se cortó se perdían.
    static let pasosGuardados = 60
    static func guardar(_ lista: [String], _ paso: String) -> [String] { Array((lista + [paso]).suffix(pasosGuardados)) }
}
