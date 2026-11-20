import Foundation

/// Conversación continua (Juan, 16-nov-2026: «cada vez que hablo con Alma, se corta en automático»). En el Modo calle y en
/// conferencia Alma no se despide y NO cuelga: responde y se queda escuchando, y Juan sigue sin volver a decir «Alma». La
/// app cierra sola la conversación de ElevenLabs (cada minuto abierto gasta créditos) tras un silencio real, sin despedida ni
/// mensaje de error, y vuelve a escuchar «Alma» en el teléfono; al nombrarla otra vez, lleva de contexto lo que se hablaba.
/// Antes («Sin despedidas», Hub #576) la ficha le pedía colgar con end_call apenas respondía: eso era el corte.
///   · Conferencia: `silencio` s sin que nadie hable después de que Alma habló (45 de fábrica; `conferencia_silencio_s` en la
///     ficha del Hub) o `tope` s sin que Alma hable, aunque sigan hablando entre ellos (60; `conferencia_tope_s`), en una
///     pausa de 8 s; y si esa pausa no llega (una reunión), a los `tope` + 30 s en una pausa de 3 s (tope duro).
///   · Modo calle: los segundos del sueño de siempre (SuenoCalle; `calle_silencio_s`, `calle_tope_s`).
///   · Una llamada normal (la roca, el anillo) no la cierra el silencio; si su conexión se cae, la app la vuelve a abrir
///     sola con lo último que se dijo, y si Claudio no conecta vuelve Alma y lo dice en una frase.
/// Lógica pura, sin iOS: se prueba sola en Pruebas/LlamadaContinua.
enum LlamadaContinua {
    /// Lo que la ficha le dice a Alma en el Modo calle y en conferencia. El Hub (voz.js) habla de «CONVERSACIÓN CONTINUA
    /// (lo dice la ficha)»: con estas dos palabras Alma sabe que la app cierra sola y que ella no cuelga.
    static let regla = "CONVERSACIÓN CONTINUA: no te despidas, no digas «aquí sigo» y NUNCA uses end_call. Cuando ya respondiste, quédate escuchando en silencio: Juan puede seguir hablándote sin volver a decir «Alma». Si lo que oyes no es para ti (hablan entre ellos, ruido) o nadie dice nada, usa skip_turn y no contestes. Si lo dejas trabajando en segundo plano, di solo una frase corta y nueva cada vez de que lo haces y le avisas (como «Entendido, te aviso» o «Me encargo y te cuento»; nunca la misma seguida) y sigue escuchando: cuando esté, tú le avisas. La app cierra sola tras un silencio, sin que digas nada."

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
    /// 17-nov-2026 (Juan: «al finalizar la conversación con Alma debe colgar y regresar al modo conferencia en escucha»): en
    /// una reunión la gente sigue hablando entre ella y la pausa de 8 s no llegaba nunca: la llamada quedaba abierta sin fin.
    /// Ahora, `margenDuro` s después del tope (90 s sin que Alma hable ni trabaje, de fábrica), cierra en una pausa de 3 s
    /// aunque sigan hablando. La conferencia sigue escuchando y, si vuelven a decir «Alma», ella sabe de qué iban.
    static let margenDuro: TimeInterval = 30
    /// Guardia 20-nov-2026: Juan dictando una instrucción larga (SuenoCalle.dictando) no es ruido hasta 6 min, y el tope
    /// duro no lo corta si se detiene a pensar unos segundos. Pasado esto, cierra igual (cada minuto gasta créditos).
    static let ruidoDictado: TimeInterval = 360

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
        /// Tope duro (solo conferencia): sin que Alma hable en tanto tiempo, cierra en la primera pausa corta aunque hablen.
        var duro: TimeInterval? = nil
        /// Mientras Juan dicta (solo conferencia): la voz sin nada escrito cuenta como Juan hasta esto y no hay tope duro.
        var dictado: TimeInterval? = nil
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
    /// `hablando`: sonaba alguien al cerrar (guardia 20-nov-2026: así se ve en la guardia si se cortó a Juan a media frase).
    static func pasoCierre(_ motivo: String, calle: Bool, conferencia: Bool, hablando: Bool = false) -> String {
        let m = hablando ? motivo + ", cerró con Juan hablando" : motivo
        if calle { return "Modo calle: cuelga (" + m + ") y vuelve a esperar «Alma»" }
        if conferencia { return "Conferencia: la llamada se cierra sola (" + m + ") y vuelve a escuchar «Alma»" }
        return "Alma abre: cuelga (" + m + ") y vuelve a escuchar"
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
    /// `buscando`: Alma esperaba una herramienta (la secretaria) cuando se cortó. Guardia 19-nov-2026: Juan preguntó, Alma dijo
    /// «Déjame revisar…» y la llamada se cayó; tuvo que volver a llamar y repetirlo. Así se reabre sola también en el Modo
    /// calle y en conferencia (sin esto se cerraba y Juan se quedaba sin respuesta).
    /// `esperando`: Juan acababa de pedir algo y Alma todavía no le respondía (`juanEspera`). Juan, 19-nov-2026: en conferencia
    /// pidió algo, la conexión se cayó a los 11 s y la app colgó; Alma nunca contestó y tuvo que volver a abrir.
    /// `interrumpida`: la conexión se cayó mientras iOS tenía el audio interrumpido y el audio ya volvió (guardia 20-nov-2026):
    /// Juan no colgó ni se calló; otra app tomó el audio un momento. Se reabre también en conferencia y en el Modo calle.
    static func trasCorte(claudio: Bool, calle: Bool, conferencia: Bool, conectada: TimeInterval?, reabiertas: Int, sinCreditos: Bool, buscando: Bool = false, esperando: Bool = false, interrumpida: Bool = false) -> TrasCorte {
        if sinCreditos { return .fallar }                                    // sin créditos no hay con quién volver
        if claudio { return reabiertas < maxReabrir ? .volverConAlma : .fallar }
        guard let c = conectada else { return .fallar }                      // Alma nunca contestó: se dice por qué
        if (calle || conferencia) && !buscando && !esperando && !interrumpida { return .colgar }
        return c >= minimoConectada && reabiertas < maxReabrir ? .reabrir : .fallar
    }

    // MARK: - Si iOS interrumpe el audio a media llamada

    /// Guardia 20-nov-2026: Juan iba en la calle con la Guía de camino y la llamada en conferencia (en pausa); otra app tomó
    /// el audio un momento (iOS, motivo 0, con la app en segundo plano) y la app colgó en el acto: ElevenLabs lo vio como un
    /// corte (1006, porque iOS suspendió la app antes de que saliera el cierre). Ahora, en conferencia y en el Modo calle, la
    /// llamada espera hasta `esperaInterrupcion` s a que iOS devuelva el audio y sigue la misma conversación; si no vuelve,
    /// cuelga con un cierre limpio (1000) y con tiempo para que salga.
    static let esperaInterrupcion: TimeInterval = 10
    /// Tiempo que se le pide a iOS para que el aviso de cierre salga antes de que suspenda la app (en segundo plano).
    static let tiempoCierre: TimeInterval = 3

    /// ¿Se espera a que vuelva el audio en vez de colgar? Solo en una llamada que la app cierra sola (conferencia, Modo
    /// calle, la que abrió un aviso). No con una llamada de teléfono (Juan va a hablar por teléfono: se cuelga como antes) ni
    /// cuando iOS suspendió la app (motivo 1, appWasSuspended: no hay a qué volver).
    static func esperaTrasInterrupcion(continua: Bool, motivo: UInt?, telefono: Bool) -> Bool {
        continua && !telefono && motivo != 1
    }

    /// La conexión se cayó mientras el audio estaba interrumpido y la llamada se reabrió: Alma no saluda con frase fija.
    static let pedidoTrasInterrupcion = "(Otra app tomó el audio un momento y la llamada se reabrió. Si me estabas respondiendo algo, termínalo en una frase corta; si no, no digas nada y sigue escuchando.)"

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

    /// Se cortó mientras Alma buscaba algo: Alma no saluda con una frase fija (después se quedaría callada esperando a Juan);
    /// la app le manda este turno y ella dice en corto que se cortó y lo busca otra vez, sin que Juan lo repita.
    /// ¿Juan quedó esperando? Dijo algo (de 2 palabras o más) hace menos de `esperaMaxima` s y la voz todavía no le respondía.
    /// Más viejo que eso ya no es «lo que acaba de pedir» (en conferencia, la charla que no es para Alma también llega).
    static let esperaMaxima: TimeInterval = 45
    static func juanEspera(juan: Date?, voz: Date?, palabras: Int, ahora: Date) -> Bool {
        guard palabras >= 2, let e = esperaSinRespuesta(juan: juan, voz: voz, ahora: ahora) else { return false }
        return e <= esperaMaxima
    }

    /// Se cortó con Juan esperando respuesta: igual que al buscar, sin frase fija; Alma atiende lo último que le pidió. Si lo
    /// último no era para ella (conferencia), se queda callada.
    static let pedidoTrasCorteEsperando = "(Se cortó la llamada justo después de lo último que dije y no alcanzaste a responder. Si era un pedido o una pregunta para ti, dime en una frase corta que se cortó y atiéndelo ahora, sin preguntarme de nuevo: lo último que se dijo está en tu ficha. Si no era para ti, no digas nada y sigue escuchando.)"

    static let pedidoTrasCorteBuscando = "(Se cortó la llamada mientras buscabas lo que te pedí. Dime en una frase corta que se cortó y búscalo otra vez ahora, sin preguntarme de nuevo: lo último que se dijo está en tu ficha.)"

    /// Lo que se suma al paso de un corte para saber la causa (guardia 19-nov-2026: el 1006 no dejaba ver nada): qué
    /// herramienta corría y desde hace cuánto, por dónde salía el audio (el tipo, no el nombre del aparato), si la app estaba
    /// en segundo plano y si había una llamada de teléfono.
    static func notaCorte(herramienta: String?, desde: Date?, ahora: Date, salida: String, enFondo: Bool, telefono: Bool) -> String {
        var t = ""
        if let h = herramienta, !h.isEmpty {
            t += " · herramienta " + String(h.prefix(30)) + " en curso" + (desde.map { String(format: " hace %.0f s", max(0, ahora.timeIntervalSince($0))) } ?? "")
        }
        t += " · salida " + (salida.isEmpty ? "?" : String(salida.prefix(24)))
        t += enFondo ? " · app en segundo plano" : " · app a la vista"
        if telefono { t += " · había una llamada de teléfono" }
        return t
    }

    /// El audio cambió de ruta poco antes del corte (Juan, 19-nov-2026: el Modo compañero pasó el micrófono al del iPhone con
    /// audífonos Bluetooth y 11 s después se cayó el socket). Si fue en los últimos `rutaReciente` s, va en el paso del corte.
    static let rutaReciente: TimeInterval = 15
    static func notaRuta(cambio: Date?, motivo: UInt, salida: String, ahora: Date) -> String {
        guard let c = cambio else { return "" }
        let hace = ahora.timeIntervalSince(c)
        guard hace >= 0, hace <= rutaReciente else { return "" }
        return String(format: " · el audio cambió de ruta hace %.0f s (motivo %d → ", hace, Int(motivo)) + (salida.isEmpty ? "?" : String(salida.prefix(24))) + ")"
    }

    /// «Voz enviada» cada 10 s: lo normal (casi 10 s de 10) no se anota; con eso se llenaba el registro del Hub y se perdía
    /// el cierre de la llamada. Solo se anota cuando el micrófono mandó poco (ahí sí dice algo).
    static let vozNormal: Double = 9
    static func anotaVozEnviada(_ segundos: Double) -> Bool { segundos < vozNormal }

    /// La última señal de vida de la llamada (cada 10 s, en el teléfono): si iOS cierra la app o la app falla a media
    /// llamada no queda ningún paso del cierre (ElevenLabs solo ve un 1006). Al abrir otra vez, este paso dice dónde iba.
    static func pasoAppCerrada(ultimoPaso: String?, latido: String?) -> String {
        var t = "La app se cerró a media llamada (iOS la terminó o falló), sin que tocaras Terminar"
        if let l = latido, !l.isEmpty { t += " · última señal: " + String(l.prefix(120)) }
        if let p = ultimoPaso, !p.isEmpty { t += " · último paso: " + String(p.prefix(80)) }
        return t
    }

    /// La ficha de la conversación reabierta: lo último que se dijo va al final de quien_llama, para seguir donde iban.
    static func ficha(_ quienLlama: String, frase: String, charla: [String], porClaudio: Bool) -> String {
        let que = porClaudio ? "NO SE PUDO SEGUIR CON CLAUDIO y volviste tú" : "SE CORTÓ LA CONEXIÓN un momento y la app la volvió a abrir"
        let dijo = frase.isEmpty ? ". Lo que sigue te llega como un turno de Juan." : ": ya le dijiste «" + frase + "»."
        var t = quienLlama + "\n\n" + que + dijo + " No saludes ni te presentes otra vez; sigue exactamente donde iban."
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

    // MARK: - La voz de Alma se oye (Juan, 16-nov-2026: «todo el audio previo estaba en mute y el saludo no se escuchó»)

    /// El volumen de la voz de Alma en la llamada: siempre entero. El micrófono en pausa y el modo chat ya no lo bajan
    /// (antes el mudo la dejaba en 0 y Alma hablaba sin que se oyera).
    static let volumenVoz: Float = 1
    /// ¿Se pasa la voz al parlante? Solo si sale por el auricular de oreja (AVAudioSession.Port.builtInReceiver, «Receiver»):
    /// con la cancelación de eco iOS a veces la deja ahí y, lejos de la cara, suena como en mudo. Audífonos, Bluetooth,
    /// CarPlay o el parlante no se tocan.
    static func aParlante(salida: String) -> Bool { salida == "Receiver" }
    /// El volumen del teléfono casi en cero (menos de 10 %): se avisa en el registro.
    static func volumenBajo(_ v: Float) -> Bool { v < 0.1 }

    // MARK: - El registro de pasos (para saber por qué se cortó)

    /// Cuántos pasos se guardan en el teléfono para el Hub. Antes la lista se borraba al empezar cada llamada: si la
    /// siguiente empezaba antes de la vuelta de avisos (45 s), los pasos de la que se cortó se perdían.
    static let pasosGuardados = 60
    /// Guardia del 18-nov-2026: los pasos del anillo (música que suena o para, toques, el audio del anillo) se repiten mucho y
    /// empujaban fuera los de la voz: de dos llamadas cortadas ya no quedaba nada. Ahora los del anillo guardan como mucho
    /// `anilloGuardados` (los más nuevos) y nunca sacan a los de la voz.
    static let anilloGuardados = 15
    static func esPasoAnillo(_ linea: String) -> Bool {
        let n = linea.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
        return n.contains("anillo") || n.contains("toque repetido") || n.contains("musica de otra app") || n.contains("spotify")
    }
    static func guardar(_ lista: [String], _ paso: String) -> [String] {
        var l = lista + [paso]
        var anillo = l.filter { esPasoAnillo($0) }.count
        while anillo > anilloGuardados, let i = l.firstIndex(where: { esPasoAnillo($0) }) { l.remove(at: i); anillo -= 1 }
        return Array(l.suffix(pasosGuardados))
    }

    /// El último turno de Juan quedó sin respuesta de la voz: cuántos segundos lleva esperando (nil si contestó o no habló).
    /// Va en el paso del cierre: así se ve si la llamada se cayó con Juan esperando (guardia 18-nov: 40 s hablando y nada).
    static func esperaSinRespuesta(juan: Date?, voz: Date?, ahora: Date) -> TimeInterval? {
        guard let j = juan else { return nil }
        if let v = voz, v >= j { return nil }
        return max(0, ahora.timeIntervalSince(j))
    }
    /// El texto que se suma al paso del cierre (vacío si no hay nada que decir).
    static func notaCierre(juan: Date?, voz: Date?, ahora: Date, palabras: Int) -> String {
        guard let e = esperaSinRespuesta(juan: juan, voz: voz, ahora: ahora) else { return "" }
        return String(format: " · el último turno de Juan (%d palabras) quedó sin respuesta hace %.0f s", palabras, e)
    }

    // MARK: - Sin «¿sigues ahí?» (Juan, 17-nov-2026)

    /// «En modo conferencia y modo calle, eliminar completamente la pregunta de si Juan sigue ahí. Si hay silencio o ruido,
    /// quedarse en silencio esperando el llamado sin insistir.» La ficha ya se lo prohíbe, pero ElevenLabs le da un turno a
    /// Alma tras unos segundos de silencio y a veces lo usa para preguntarlo. La app lo calla: si lo que Alma va a decir es
    /// solo esa pregunta (una frase corta), su voz no suena y la llamada sigue escuchando hasta que Juan hable.
    /// Si la pregunta va pegada a una respuesta de verdad (más de `palabrasMaximas` palabras), se deja: no se pierde lo que respondió.
    static let palabrasMaximas = 12
    static let preguntasDeSilencio = ["sigues ahi", "siguen ahi", "sigue ahi", "seguis ahi", "sigues ahi juan", "estas ahi", "estan ahi",
                                      "esta ahi", "sigues conmigo", "siguen conmigo", "sigues en linea", "todavia estas", "aun estas",
                                      "me escuchas", "me oyes", "me escuchan", "me oyen", "hay alguien", "se corto", "se cayo",
                                      "sigues por ahi", "estas por ahi", "estas ocupado", "puedes hablar"]
    static func esPreguntaDeSilencio(_ texto: String) -> Bool {
        let n = texto.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
            .map { $0.isLetter || $0.isNumber ? String($0) : " " }.joined()
        let palabras = n.split(separator: " ").map(String.init)
        guard !palabras.isEmpty, palabras.count <= palabrasMaximas else { return false }
        let junto = " " + palabras.joined(separator: " ") + " "
        if preguntasDeSilencio.contains(where: { junto.contains(" " + $0 + " ") }) { return true }
        // Solo «¿Hola?» o «¿Juan?» (con o sin «Alma aquí»): también es preguntar si sigue ahí.
        let resto = palabras.filter { !["hola", "juan", "oye", "alma", "aqui", "estoy", "eh", "mm", "este"].contains($0) }
        return resto.isEmpty && (palabras.contains("hola") || palabras.contains("juan")) && texto.contains("?")
    }
}
