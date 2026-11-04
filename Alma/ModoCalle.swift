import AVFoundation
import Speech
import SherpaOnnx
import UIKit

/// Modo calle (issue #50): el teléfono bloqueado en la bolsa, audífonos puestos, caminando.
///   · Mientras espera, solo un detector liviano en el teléfono escucha la palabra «Alma» (sherpa-onnx, código abierto y
///     gratis, DetectorAlma). No transcribe todo, no graba, no sube nada y no gasta tokens. El audio se mezcla con las otras
///     apps: TikTok, la música o Claude siguen sonando.
///   · El detector deja pasar de más a propósito (para no perderse un «Alma»). Cada vez que cree oírla, el dictado del iPhone
///     (en el teléfono, listo de antemano) revisa en silencio los últimos 2 s: si dice «Alma» suena la señal; si oyó otra
///     cosa, nada. Si no contesta en 3,5 s, se acepta igual (Juan, 3-nov-2026: un «Alma» perdido cuesta más que un falso
///     despertar); el respaldo, en cambio, sí necesita que el dictado confirme (VerificacionCalle en OidoCalle.swift).
///   · Después de «Alma»: el dictado escucha la frase desde el gatillo (dicha de corrido también), hasta una pausa (1,2 s;
///     12 s como mucho; sin pedido, 6 s desde la señal), y la manda al
///     Hub (acción «calle»). Alma contesta corto y hablado («Listo, …»). Si hace falta conversar, se abre la llamada real de
///     ElevenLabs y, al colgar, el Modo calle vuelve a esperar.
///   · Avisos hablados: lo importante que llega del Hub (vozAvisos) Alma lo dice al oído y escucha 8 s la respuesta, sin
///     «Alma». También con la app abierta (inicio o conferencia). Los niveles están en NivelAvisos.
///   · Se enciende con la app a la vista (iOS no deja abrir el micrófono con el teléfono bloqueado) y sigue bloqueado.
///   · No va junto con el modo conferencia ni con el Modo Inicio: encender uno apaga el otro.
///   · Sueño (Juan, 3-nov-2026): la llamada que abre el Modo calle (por «Alma» o por un aviso) se cuelga sola, rápido, para
///     no gastar créditos de ElevenLabs: 6 s de silencio de Juan después de que Alma habló, «espera» / «luego» / «es todo»,
///     45 s sin que Alma hable, u otra llamada, Siri o los audífonos que se desconectan (las reglas, en SuenoCalle.swift).
///     Al colgar, vuelve a esperar «Alma» solo con el detector; si fue otra llamada o Siri, espera a que iOS devuelva el
///     micrófono. Mientras no hay llamada, todo lo que Alma dice al oído es su voz (el audio de ElevenLabs que manda el Hub).
///   · La voz (Juan, 3-nov-2026: «me responde una voz de hombre»): la voz por defecto del iPhone para «es-MX» puede ser de
///     hombre. Si una respuesta llega sin audio, se pide aparte al Hub (acción «calleVoz»); las frases fijas quedan guardadas
///     en memoria. Solo sin internet habla el iPhone, y siempre con una voz de mujer elegida a mano (VozIphone).
///   · Medición (T3): cada sesión guarda minutos, batería al empezar y al terminar, despertares y falsos despertares, y los
///     segundos de llamada con ElevenLabs (cuántas colgó el sueño); al apagarlo se manda el resumen al Hub (acción
///     «calleUso») y queda en el teléfono (`calle_usos`), con un diagnóstico corto.
///   · Diagnóstico (Juan, 3-nov-2026: «no responde» y nadie sabía por qué): la página muestra bajo el botón en qué va
///     (esperando «Alma», te oí, te escucho…) y cualquier error; nada se calla. Cada segundo un vigía revisa que llegue
///     audio y que se escuche por el micrófono correcto (si la voz abre o suelta el suyo, se cambia). «Probar el Modo
///     calle» (Ajustes o toque largo en el botón) muestra el nivel del micrófono, la fuerza con la que el detector oyó
///     «Alma», lo que oyó el dictado al revisar y por qué se descartó, para calibrar el umbral.
///   · Ganancia y respaldo (Juan, 3-nov-2026, TestFlight 135 con audífonos Bluetooth: el micrófono llegaba al 1 % y el
///     detector oyó 1 de 5 «Alma»): cada trozo pasa por una ganancia automática (hasta ×20, sin saturar) antes del
///     detector y del dictado. Si aparece una voz corta y suelta (0,3–2,5 s, con silencio antes) y el detector no se
///     disparó, el dictado la revisa igual que siempre (el respaldo; una revisión cada 2 s como mucho, solo con el dictado
///     en el teléfono). La lógica pura está en OidoCalle.swift, con sus pruebas en Pruebas/OidoCalle. Calibrar en
///     «Probar el Modo calle» cambia el detector en vivo, sin apagar el Modo calle.
///   · El botón del caminante (Juan, 4-nov-2026, TestFlight 144): un toque y Alma escucha ya, sin «Alma» (escucharAhora),
///     con la señal al empezar y el sonido de fin al terminar de oír; manda el pedido al Hub y contesta en voz alta, igual
///     que después de «Alma». Con el Modo calle apagado escucha una vez y no lo deja encendido. Encender y apagar el Modo
///     calle queda en Ajustes → Modo calle y en Siri. Antes el toque lo apagaba y, si Alma esperaba al Hub, la respuesta
///     se perdía sin decir nada (ALMA_CALLE_USO, 3-nov-2026 22:21 UTC).
///   · Nunca en silencio (EsperaCalle): si a los 25 s de oír el pedido no llegó respuesta, Alma dice «No me llegó la
///     respuesta, ¿me lo repites?» y vuelve a escuchar; el porqué queda en el diagnóstico.
final class ModoCalle: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    static let shared = ModoCalle()
    var alEvento: (([String: Any]) -> Void)?

    /// quieta: sin micrófono · esperando: solo el detector · verificando: el dictado revisa si dijeron «Alma» ·
    /// oyendo: escucha la frase · pensando: espera al Hub · hablando: Alma contesta · llamada: la llamada real ·
    /// pausa: iOS quitó el micrófono (otra llamada, por ejemplo) y se espera para volver.
    enum Fase: String { case quieta, esperando, verificando, oyendo, pensando, hablando, llamada, pausa }
    private(set) var encendido = false
    private(set) var fase: Fase = .quieta { didSet { if fase != oldValue { emitir() } } }
    /// Un aviso hablado con la app abierta (sin el Modo calle): usa el micrófono solo mientras lo dice y escucha la respuesta.
    private var temporal = false
    /// ¿Ocupa el micrófono? Entonces el Modo Inicio no abre otro y el audio no se suelta.
    var ocupaMicrofono: Bool { encendido || temporal }

    // MARK: - El micrófono

    private var motor = AVAudioEngine()          // se rehace si iOS reinicia el audio (mediaServicesWereReset)
    private var micAbierto = false
    /// Escucha por el micrófono de la voz (VozNativa, ya abierto con «Alma con el anillo») en vez de abrir otro.
    private var compartido = false
    private let candado = NSLock()               // lo de abajo también lo usa el hilo del micrófono
    private var alimentarDetector = false
    /// Los últimos 6 s (solo en memoria), cada trozo con cuándo terminó (systemUptime): con ellos se revisa si dijeron
    /// «Alma» y, después, la frase empieza desde el gatillo (lo que dijo mientras el dictado revisaba no se pierde).
    private var previo: [(cuando: Double, trozo: AVAudioPCMBuffer)] = []
    private var previoSeg = 0.0
    private static let previoMax = 6.0
    private var ganancia = GananciaCalle()       // con `candado`: sube el volumen antes del detector y del dictado
    private var segmentador = SegmentadorCalle() // con `candado`: las voces cortas para el respaldo
    private var segmentando = false              // con `candado`
    private var pedido: SFSpeechAudioBufferRecognitionRequest?
    private var convertidor: AVAudioConverter?   // solo en el hilo del micrófono
    private var formatoConvertidor: AVAudioFormat?
    private let formato16k = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    // MARK: - El detector (en su propia cola)

    private let colaDetector = DispatchQueue(label: "com.spacioam.alma.calle", qos: .userInitiated)
    private var detector: DetectorAlma?          // solo en colaDetector
    private var detectorListo = false            // en el hilo principal

    // MARK: - El dictado de la frase

    private let reconocedor = SFSpeechRecognizer(locale: Locale(identifier: "es-MX"))
    private var tarea: SFSpeechRecognitionTask?
    private var vuelta = 0                       // el id de la tarea del dictado que cuenta ahora (0: ninguna)
    private var ids = 0                          // de dónde salen los ids de las tareas
    /// El dictado listo de antemano para revisar «Alma» (Juan, 3-nov-2026, TestFlight 142: la mitad de las veces no
    /// contestaba en 3,5 s). Se crea al volver a esperar, sin audio: al dispararse el detector solo recibe los últimos
    /// segundos y se le cierra el audio, sin el arranque en frío de una tarea nueva. Se renueva cada 45 s.
    private var armado: (pedido: SFSpeechAudioBufferRecognitionRequest, tarea: SFSpeechRecognitionTask, id: Int, desde: Date)?
    private var fallosArmado = 0, armarDesde = Date.distantPast
    private var marcaGatillo = 0.0               // systemUptime del gatillo: la frase empieza un poco antes
    private var finDictado = VerificacionCalle.Fin.sigue
    private var primeraRespuesta = false         // ya llegó el primer resultado de esta revisión (para medir)
    private var latencia = LatenciaCalle()
    private var textoAlma: String?               // la versión del dictado donde se oyó «Alma»
    private var textoMejor = ""
    private var ultimoCambio = Date(), desde = Date()
    private var avisoActual: String?             // se responde a un aviso: se escucha sin «Alma»
    private var porBoton = false                 // la escucha la abrió el botón del caminante: sin «Alma» ni audio de antes
    private var turnoPedido = 0                  // sube con cada pedido: una respuesta del Hub que llega tarde ya no suena
    private var relojRespuesta: Timer?           // nunca en silencio: el plazo de la respuesta del Hub (EsperaCalle)
    private var pedidoDesde = Date()
    private var errorRed: String?                // por qué falló la última llamada al Hub (para el diagnóstico)
    private var reloj: Timer?
    private var reintentos = 0
    private var hubSinCalle = false              // el Hub todavía no tiene la acción «calle»: se usa el chat
    private var hubSinAviso = false              // el Hub todavía no tiene «avisoHablar»: se dice con la voz del iPhone
    private var llamadaVista = false, llamadaDesde = Date()

    // MARK: - La voz

    private let sintetizador = AVSpeechSynthesizer()
    private var reproductor: AVAudioPlayer?
    private var trasHablar: (() -> Void)?
    private var turnoVoz = 0                     // sube con cada frase y con callar(): una voz pedida tarde ya no suena
    private var vozGuardada: [String: Data] = [:]   // frases con la voz de Alma ya pedidas (solo en memoria)
    private var hubSinVoz = false                // el Hub todavía no tiene «calleVoz»: sin audio, habla el iPhone
    private var vozUsada = ""                    // con qué voz se dijo lo último (para «Probar el Modo calle»)
    /// Lo que contestó Alma a un atajo («Mándale a Alma») con el Modo calle encendido: se dice con su voz, no con la de Siri.
    private var deFuera: (texto: String, desde: Date)?
    /// Las frases que la app dice por su cuenta: se piden con la voz de Alma al encender, así suenan con ella aunque falle la red.
    private static let frasesFijas = ["Listo.", "No pude hablar con el Hub. Intenta otra vez.", "No pude hacerlo ahora.", EsperaCalle.frase]

    // MARK: - Medición (T3)

    private struct Uso {
        var inicio = Date()
        var bateriaInicio: Int?
        var gatillos = 0, despertares = 0, descartes = 0, falsos = 0, pedidos = 0, llamadas = 0, avisos = 0, errores = 0
        /// El respaldo: cuántas voces cortas revisó el dictado y cuántas eran «Alma» (también cuentan en `despertares`).
        var respaldos = 0, despertaresRespaldo = 0
        /// Lo que se gasta en ElevenLabs: segundos de llamada conectada; cuántas colgó el sueño y cuántas se cortaron.
        var llamadaSeg = 0.0, dormidas = 0, cortadas = 0
    }
    private var uso = Uso()

    // MARK: - Avisos hablados

    private var colaAvisos: [(id: String, texto: String, resultado: Bool)] = []
    /// iOS quitó el audio (otra llamada, Siri) y todavía no lo devuelve: al colgar la llamada de Alma se espera en pausa.
    private var interrumpido = false
    private var relojAvisos: Timer?

    // MARK: - Diagnóstico
    // Solo números y textos cortos, en memoria: nada de audio se guarda ni se manda.

    private var probando = false                 // «Probar el Modo calle» abierto: el estado va a la página cada segundo
    private var probarLoEncendio = false         // al cerrar la prueba se apaga si fue ella la que lo encendió
    private var arrancando = false               // pidiendo permisos y cargando el detector (la página no lo da por apagado)
    private var relojVigia: Timer?
    private var ultimoTramo = Date.distantPast   // con `candado`: el último trozo que llegó del micrófono
    private var picoTramos: Float = 0            // con `candado`: lo más fuerte desde la última vuelta del vigía (con ganancia)
    private var picoTramosAntes: Float = 0       // con `candado`: lo mismo, sin ganancia
    private var tramos = 0                       // con `candado`
    private var segCeros = 0.0                   // con `candado`: segundos seguidos en cero exacto (un micrófono mudo)
    private var nivel: Float = 0                 // el último pico (0…1), con la ganancia: lo que oye el detector
    private var nivelAntes: Float = 0            // el mismo, como llega del micrófono
    private var gananciaVista: Float = 1         // la ganancia en la última vuelta del vigía
    // El respaldo (tiempos de ProcessInfo.systemUptime): cuándo se disparó el detector, cuándo terminó la última revisión
    // del respaldo, si la revisión de ahora es del respaldo y cuántos despertares vinieron del detector y del respaldo.
    private var ultimoGatillo: Double?, finRespaldo: Double?, porRespaldo = false
    private var revisionesRespaldo = 0, despertaresDetector = 0, despertaresRespaldo = 0
    private var sinConfirmar = 0                 // despertares del detector aceptados sin que el dictado contestara
    private var ultimaVoz: (pico: Float, cuando: Double)?   // la última voz de 0,3 s o más, con su ganancia (para la pista)
    private var pista = false, pistaAnotada = false
    private var formatoMic = ""
    private var golpes = 0, ultimoGolpe: Date?
    private var fuerza: Float?, fuerzaHasta = Date.distantPast
    private var escalera: [(umbral: Float, detector: DetectorAlma)] = []   // solo en colaDetector, con «Probar»
    private var dictadoOido = "", veredicto = "", errorDictado: String?
    private var sinDictado = 0                   // revisiones seguidas en que el dictado no contestó a tiempo
    private var errorDiag = "", eventos: [String] = []
    private var avisadoMudo = false

    private override init() {
        super.init()
        sintetizador.delegate = self
        let nc = NotificationCenter.default
        // Otra app (o una llamada de teléfono) tomó el audio: se suelta y, cuando lo devuelve, se vuelve a esperar «Alma».
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, self.ocupaMicrofono, let t = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
            let empezo = t == AVAudioSession.InterruptionType.began.rawValue
            if self.encendido { self.interrumpido = empezo }
            // En llamada, la cuelga VozNativa (sueño: corte); al terminar, revisarLlamada espera en pausa a que vuelva el audio.
            guard self.fase != .llamada else { return }
            if empezo {
                if self.temporal { self.terminarTemporal(); return }
                self.cerrarEscucha(); self.callar(); self.cerrarMicrofono(); self.fase = .pausa
            } else { self.reabrir(tras: 0.6) }
        }
        // Se conectaron o quitaron los audífonos (o iOS reacomodó el audio): el motor se detiene solo; se vuelve a abrir.
        nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] n in
            guard let self, let e = n.object as? AVAudioEngine, e === self.motor, self.micAbierto, !self.compartido else { return }
            self.reabrir(tras: 0.3)
        }
        // iOS reinició el audio: el motor viejo ya no sirve; se hace otro.
        nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.micAbierto = false; self.motor = AVAudioEngine()
            if self.ocupaMicrofono { self.reabrir(tras: 1) }
        }
        // Al volver a la app con el Modo calle en pausa (iOS no dejó volver a abrir el micrófono bloqueado), se reintenta.
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.encendido, self.fase == .pausa else { return }
            self.interrumpido = false   // con la app a la vista, iOS ya devolvió el audio (aunque no avisó que terminó)
            self.reintentos = 0; self.reabrir(tras: 0.3)
        }
    }

    // MARK: - Encender y apagar

    var resumen: [String: Any] {
        // «ahora»: esta versión escucha al tocar el botón (que: "ahora"); la página deja de usar el toque para encender o apagar.
        var r: [String: Any] = ["tipo": "calle", "activa": encendido, "fase": fase.rawValue, "ahora": true]
        if encendido {
            r["minutos"] = Int(Date().timeIntervalSince(uso.inicio) / 60)
            r["despertares"] = uso.despertares; r["falsos"] = uso.falsos; r["pedidos"] = uso.pedidos
        }
        r["usos"] = Array((UserDefaults.standard.array(forKey: "calle_usos") ?? []).suffix(5))
        if arrancando { r["encendiendo"] = true }
        if encendido || probando || arrancando || !errorDiag.isEmpty { r["diag"] = diag }
        return r
    }

    /// Lo que la página muestra bajo el botón y en «Probar el Modo calle».
    private var diag: [String: Any] {
        let (linea, umbral, puntaje) = DetectorAlma.ajustes()
        candado.lock(); let ultimo = ultimoTramo, n = tramos; candado.unlock()
        var d: [String: Any] = [
            "mic": micAbierto ? formatoMic + textoGanancia() : "cerrado", "tramos": n, "nivel": Int((nivel * 100).rounded()), "golpes": golpes,
            "nivelAntes": ModoCalle.porciento(nivelAntes), "ganancia": (Double(gananciaVista) * 10).rounded() / 10,
            "despertaresDetector": despertaresDetector, "despertaresRespaldo": despertaresRespaldo, "respaldos": revisionesRespaldo,
            "modelo": DetectorAlma.modelo(), "linea": linea, "umbral": Double(umbral), "puntaje": Double(puntaje),
            "umbralFabrica": Double(DetectorAlma.umbralDeFabrica), "puntajeFabrica": Double(DetectorAlma.puntajeDeFabrica),
            "dictadoEnTelefono": reconocedor?.supportsOnDeviceRecognition == true, "eventos": eventos,
            "sinConfirmar": sinConfirmar, "latencia": latencia.texto
        ]
        if let ms = latencia.ultima { d["dictadoMs"] = ms }   // la página lo muestra en el veredicto (va en el texto)
        if let ms = latencia.media { d["dictadoMsMedia"] = ms }
        if micAbierto, ultimo != .distantPast { d["audioHace"] = (Date().timeIntervalSince(ultimo) * 10).rounded() / 10 }
        if let g = ultimoGolpe { d["golpeHace"] = Int(Date().timeIntervalSince(g)) }
        if let f = fuerza, Date() < fuerzaHasta.addingTimeInterval(10) { d["fuerza"] = Int((f * 100).rounded()) }
        if !dictadoOido.isEmpty { d["dictado"] = dictadoOido }
        if !veredicto.isEmpty { d["veredicto"] = veredicto }
        if !errorDiag.isEmpty { d["error"] = errorDiag }
        if !vozUsada.isEmpty { d["voz"] = vozUsada }
        if probando { d["probando"] = true }
        if pista { d["pista"] = PistaCalle.texto }
        return d
    }

    /// Lo que se agrega a la línea del micrófono (la página ya la muestra tal cual): el nivel sin ganancia, la ganancia y,
    /// si hace falta, la pista de los audífonos. El «nivel» que sigue en la página es el de después de la ganancia.
    private func textoGanancia() -> String {
        var t = " · sin ganancia \(ModoCalle.porciento(nivelAntes)) % · ganancia ×" + String(format: "%.0f", Double(gananciaVista))
        if pista { t += " · " + PistaCalle.texto }
        return t
    }

    /// Un nivel en por ciento: con un decimal si es menos de 10 % (al 1 % de los audífonos se ve la diferencia).
    private static func porciento(_ x: Float) -> Double {
        let p = Double(x) * 100
        return p < 10 ? (p * 10).rounded() / 10 : p.rounded()
    }

    /// Cuántos despertares vinieron de cada lado (va con el veredicto, que la página muestra tal cual).
    private var textoDespertares: String {
        "despertó \(despertaresDetector) por el detector" + (sinConfirmar > 0 ? " (\(sinConfirmar) sin confirmar)" : "")
            + " · \(despertaresRespaldo) por el respaldo · " + latencia.texto
    }

    func poner(_ on: Bool) { if on { encender() } else { apagar() } }

    /// El botón del caminante: Alma escucha ya, sin «Alma» (BotonCalle). Con el Modo calle encendido, lo de ahora se deja
    /// (la respuesta que esperaba ya no se dice); apagado, abre el micrófono solo para este pedido (como un aviso con la
    /// app abierta) y lo suelta al terminar, sin encender el Modo calle.
    func escucharAhora() {
        let accion = BotonCalle.decidir(fase: encendido || temporal ? fase.rawValue : "quieta")
        guard accion != .nada else { anotar("Botón: en llamada, la llamada ya te escucha"); emitir(); return }
        if encendido || temporal {
            if fase == .pensando { anotar("Botón: dejo la respuesta que esperaba y te escucho") }
            soltarEspera(); turnoPedido += 1
            cerrarEscucha(); callar()
            porRespaldo = false
            if !micAbierto { guard abrirMicrofono() else { reintentar(); return } }
            anotar("Botón: te escucho")
            escucharFrase(aviso: nil, boton: true)
            VozNativa.shared.senal()
            return
        }
        guard UIApplication.shared.applicationState != .background else { return }   // un toque en la página: la app está a la vista
        let v = VozNativa.shared.estado
        guard v != .hablando, v != .conectando else { anotar("Botón: hay una llamada con Alma, ella ya te escucha"); emitir(); return }
        guard reconocedor?.isAvailable == true else {
            fallar("El dictado del iPhone no está disponible ahora (español de México). Revisa Ajustes → General → Teclado → Dictado."); return
        }
        guard AVAudioSession.sharedInstance().recordPermission == .granted, SFSpeechRecognizer.authorizationStatus() == .authorized else {
            // La primera vez: se piden los permisos con la app abierta y se vuelve a intentar.
            SFSpeechRecognizer.requestAuthorization { st in
                AVAudioSession.sharedInstance().requestRecordPermission { mic in
                    DispatchQueue.main.async {
                        guard mic else { self.fallar("Activa el micrófono para Alma en Ajustes del iPhone → Alma → Micrófono."); return }
                        guard st == .authorized else { self.fallar("Activa el reconocimiento de voz para Alma en Ajustes del iPhone → Alma → Reconocimiento de voz."); return }
                        self.escucharAhora()
                    }
                }
            }
            return
        }
        if Conferencia.shared.activa { Conferencia.shared.poner(false) }   // uno a la vez
        temporal = true
        EscuchaInicio.shared.detener()
        errorDiag = ""
        guard abrirMicrofono() else {
            temporal = false; fase = .quieta; cerrarMicrofono(); VozNativa.soltarAudio()
            fallar("No pude abrir el micrófono. Intenta de nuevo."); return
        }
        anotar("Botón: te escucho (una vez, sin encender el Modo calle)")
        escucharFrase(aviso: nil, boton: true)
        VozNativa.shared.senal()
        guardarFrasesFijas()   // la próxima vez «No me llegó la respuesta…» ya suena con la voz de Alma
    }

    /// alma://calle?on=1 · alma://calle?on=0 · alma://calle (cambia): para un atajo de iOS.
    func abrirEnlace(_ u: URL) {
        let on = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "on" })?.value
        if on == "1" { poner(true) } else if on == "0" { poner(false) } else { poner(!encendido) }
    }

    /// Ajustar el detector sin otra versión de la app (para calibrar en la calle): la línea de «Alma» en sonidos del
    /// modelo, el umbral y el puntaje. Vacío = lo de fábrica (DetectorAlma).
    /// «Probar el Modo calle» (Ajustes o toque largo en el botón): el estado va a la página cada segundo y, junto al detector
    /// de siempre, corren otros con umbrales de 50 %, 30 %, 15 % y 5 %: la «fuerza» es el más alto que oyó «Alma». Si el Modo
    /// calle estaba apagado, la prueba lo enciende y lo apaga al cerrarse.
    func probar(_ on: Bool) {
        let antes = probando
        probando = on
        if on != antes { armarEscalera(on); anotar(on ? "Empieza la prueba" : "Termina la prueba") }
        if on, !encendido, !arrancando { probarLoEncendio = true; encender() }
        if !on, probarLoEncendio { probarLoEncendio = false; if encendido { apagar() } }
        emitir()
    }

    private func armarEscalera(_ on: Bool) {
        let (linea, _, puntaje) = DetectorAlma.ajustes()
        colaDetector.async { [weak self] in
            self?.escalera = on ? DetectorAlma.escalones.compactMap { u in DetectorAlma(linea: linea, umbral: u, puntaje: puntaje).map { (umbral: u, detector: $0) } } : []
        }
    }

    func calibrar(linea: String?, umbral: Double?, puntaje: Double?) {
        let d = UserDefaults.standard
        if let l = linea { if l.trimmingCharacters(in: .whitespaces).isEmpty { d.removeObject(forKey: "calle_kws_linea") } else { d.set(l, forKey: "calle_kws_linea") } }
        if let u = umbral { if u <= 0 { d.removeObject(forKey: "calle_kws_umbral") } else { d.set(u, forKey: "calle_kws_umbral") } }
        if let p = puntaje { if p <= 0 { d.removeObject(forKey: "calle_kws_puntaje") } else { d.set(p, forKey: "calle_kws_puntaje") } }
        let (l, u, p) = DetectorAlma.ajustes()
        let enVivo = encendido || arrancando
        anotar("Calibrado: umbral \(u) · puntaje \(p)" + (l == DetectorAlma.lineaDeFabrica ? "" : " · línea «\(l)»") + (enVivo ? " · en vivo" : ""))
        if enVivo {
            // En vivo (Juan, 3-nov-2026: cada calibración apagaba y encendía el Modo calle): el detector nuevo reemplaza al
            // de ahora en su cola, sin tocar el micrófono, la fase ni la medición. Si todavía no cargó, al cargar lee lo nuevo.
            colaDetector.async { [weak self] in
                guard let self, self.detector != nil else { return }
                if let d = DetectorAlma(linea: l, umbral: u, puntaje: p) { self.detector = d; return }
                let m = DetectorAlma.fallo
                DispatchQueue.main.async { self.avisarError(m + " Sigue el detector de antes.") }
            }
        } else {
            // Apagado: se vuelve a cargar con lo nuevo al encender.
            detectorListo = false
            colaDetector.async { [weak self] in self?.detector = nil }
        }
        if probando { armarEscalera(true) }
        emitir()
    }

    private func encender() {
        guard !encendido, !arrancando else { emitir(); return }
        guard UIApplication.shared.applicationState != .background else {
            fallar("Abre Alma para encender el Modo calle: con el teléfono bloqueado iOS no deja abrir el micrófono."); return
        }
        arrancando = true; errorDiag = ""; veredicto = ""; dictadoOido = ""
        anotar("Encendiendo")
        emitir()
        SFSpeechRecognizer.requestAuthorization { st in
            AVAudioSession.sharedInstance().requestRecordPermission { mic in
                DispatchQueue.main.async {
                    // Cada permiso con su mensaje: así se sabe cuál falta.
                    guard mic else { self.fallar("Activa el micrófono para Alma en Ajustes del iPhone → Alma → Micrófono."); return }
                    guard st == .authorized else { self.fallar("Activa el reconocimiento de voz para Alma en Ajustes del iPhone → Alma → Reconocimiento de voz."); return }
                    guard self.reconocedor?.isAvailable == true else {
                        self.fallar("El dictado del iPhone no está disponible ahora (español de México). Revisa Ajustes → General → Teclado → Dictado y que haya internet la primera vez."); return
                    }
                    self.cargarDetector { ok in
                        guard ok else { self.fallar(DetectorAlma.fallo); return }
                        self.arrancar()
                    }
                }
            }
        }
    }

    private func cargarDetector(_ listo: @escaping (Bool) -> Void) {
        if detectorListo { listo(true); return }
        let (linea, umbral, puntaje) = DetectorAlma.ajustes()
        colaDetector.async { [weak self] in
            let d = DetectorAlma(linea: linea, umbral: umbral, puntaje: puntaje)
            self?.detector = d
            let ok = d != nil
            DispatchQueue.main.async { self?.detectorListo = ok; listo(ok) }
        }
    }

    private func arrancar() {
        arrancando = false
        guard !encendido else { return }
        if temporal { terminarTemporal() }
        encendido = true   // antes de apagar los otros modos: así no sueltan el audio ni vuelven a escuchar
        if Conferencia.shared.activa { Conferencia.shared.poner(false) }
        EscuchaInicio.shared.detener()
        uso = Uso()
        UIDevice.current.isBatteryMonitoringEnabled = true
        uso.bateriaInicio = ModoCalle.bateria()
        reintentos = 0; interrumpido = false
        guard abrirMicrofono() else {
            encendido = false; cerrarMicrofono(); UIDevice.current.isBatteryMonitoringEnabled = false
            fallar("No pude abrir el micrófono. Intenta de nuevo."); return
        }
        golpes = 0; ultimoGolpe = nil; sinDictado = 0
        ultimoGatillo = nil; finRespaldo = nil; porRespaldo = false; ultimaVoz = nil; pista = false; pistaAnotada = false
        revisionesRespaldo = 0; despertaresDetector = 0; despertaresRespaldo = 0; sinConfirmar = 0
        latencia = LatenciaCalle(); fallosArmado = 0; armarDesde = .distantPast
        anotar("Encendido · micrófono " + formatoMic + " · dictado " + (reconocedor?.supportsOnDeviceRecognition == true ? "en el teléfono" : "con internet"))
        relojVigia?.invalidate()
        relojVigia = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.vigilar() }
        volverAEsperar()
        emitir()
        guardarFrasesFijas()
        VozNativa.shared.buscarAvisosAhora()   // los avisos que ya esperan se dicen enseguida, sin esperar la vuelta de 45 s
    }

    private func apagar() {
        guard encendido else { emitir(); return }
        encendido = false; probarLoEncendio = false
        reloj?.invalidate(); reloj = nil
        relojVigia?.invalidate(); relojVigia = nil
        if fase == .pensando { anotar("Apagado mientras esperaba la respuesta del Hub (ya no se dirá)") }
        soltarEspera()
        anotar("Apagado")
        cerrarEscucha(); soltarArmado(); callar(); cerrarMicrofono()
        if fase == .llamada { VozNativa.shared.desdeCalle = false }   // la llamada sigue; al colgar ya no vuelve al Modo calle
        fase = .quieta
        // El detector se suelta (unos MB de memoria) hasta la próxima vez.
        detectorListo = false
        colaDetector.async { [weak self] in self?.detector = nil }
        cerrarUso()
        UIDevice.current.isBatteryMonitoringEnabled = false
        VozNativa.soltarAudio()            // avisa a las otras apps (notifyOthersOnDeactivation) si nadie más escucha
        EscuchaInicio.shared.evaluar()     // de vuelta al Modo Inicio si está a la vista
        emitir()
    }

    /// Un error que impide encender (o seguir): la página lo dice con un aviso y queda en la línea del botón.
    private func fallar(_ m: String) {
        arrancando = false
        if encendido { uso.errores += 1 }
        errorDiag = m; anotar("Error: " + m)
        var r = resumen; r["error"] = m
        alEvento?(r)
    }

    /// Un problema con el Modo calle encendido: queda en la línea del botón y en la prueba (sin aviso que interrumpa).
    private func avisarError(_ m: String) {
        if m != errorDiag { if encendido { uso.errores += 1 }; anotar("Error: " + m) }
        errorDiag = m
        emitir()
    }

    private static let hora: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f }()
    private func anotar(_ t: String) {
        eventos.append(ModoCalle.hora.string(from: Date()) + " " + t)
        if eventos.count > 14 { eventos.removeFirst(eventos.count - 14) }
    }

    /// Cada segundo con el Modo calle encendido: ¿llega audio? ¿se escucha por el micrófono que toca? Si la voz de Alma
    /// abrió (o soltó) su micrófono, se cambia a ese: con dos micrófonos abiertos iOS deja mudo a uno.
    private func vigilar() {
        candado.lock()
        let ultimo = ultimoTramo, ceros = segCeros
        nivel = picoTramos; nivelAntes = picoTramosAntes; picoTramos = 0; picoTramosAntes = 0; gananciaVista = ganancia.ganancia
        candado.unlock()
        guard encendido else { return }
        revisarPista()
        let v = VozNativa.shared.estado
        if fase == .esperando, micAbierto, v != .hablando, v != .conectando {
            let deLaVoz = VozNativa.shared.microfonoListo
            if compartido != deLaVoz || (!compartido && !motor.isRunning) {
                anotar(compartido ? "La voz soltó su micrófono: abro el mío" : deLaVoz ? "La voz abrió su micrófono: escucho por el suyo" : "El micrófono se detuvo: lo vuelvo a abrir")
                reabrir(tras: 0.2); return
            }
            let sinAudio = Date().timeIntervalSince(ultimo)
            if sinAudio > 4 { avisarError("No me llega audio del micrófono (\(Int(sinAudio)) s). Lo vuelvo a abrir."); reabrir(tras: 0.3); return }
            if ceros > 5, !avisadoMudo {
                avisadoMudo = true
                avisarError("El micrófono llega mudo (todo en cero): otra app o la voz de Alma lo tiene. Apaga y vuelve a encender el Modo calle.")
                reabrir(tras: 0.3); return
            }
        }
        if fase == .esperando { armarVerificacion() }   // si falta o ya tiene un minuto
        if probando { emitir() }
    }

    /// La pista de los audífonos: si su micrófono llega muy bajo aun con la ganancia, se dice en el diagnóstico (una vez
    /// en «Lo que pasó» por sesión; en la línea del micrófono mientras siga así).
    private func revisarPista() {
        let ahora = ProcessInfo.processInfo.systemUptime
        let voz = ultimaVoz.flatMap { ahora - $0.cuando <= 30 ? $0.pico : nil }
        let antes = pista
        pista = micAbierto && PistaCalle.audifonosBajos(esAudifono: ModoCalle.esAudifono(), picoVoz: voz)
        if pista, !antes, !pistaAnotada { pistaAnotada = true; anotar(PistaCalle.texto) }
    }

    /// ¿El micrófono es el de unos audífonos (Bluetooth o con cable)?
    private static func esAudifono() -> Bool {
        guard let t = AVAudioSession.sharedInstance().currentRoute.inputs.first?.portType else { return false }
        return t == .bluetoothHFP || t == .headsetMic || t == .bluetoothLE
    }

    // MARK: - Abrir y cerrar el micrófono

    /// Abre el micrófono (el de la voz si ya está abierto, o el propio con la sesión que se mezcla). Con la app a la vista
    /// se usa VozNativa.sesionEscucha (suelta antes una sesión que no se mezcla, avisando a las otras apps); bloqueado solo
    /// se cambia la categoría: soltar el audio con el teléfono bloqueado haría que iOS no deje volver a abrir el micrófono.
    private func abrirMicrofono() -> Bool {
        let voz = VozNativa.shared
        candado.lock(); convertidor = nil; formatoConvertidor = nil; candado.unlock()
        candado.lock(); ultimoTramo = Date(); segCeros = 0; candado.unlock()   // el vigía da unos segundos al micrófono nuevo
        // Otro micrófono, otro volumen: la ganancia y el ruido de fondo se aprenden de nuevo.
        candado.lock(); ganancia = GananciaCalle(); segmentador = SegmentadorCalle(); segmentando = false; candado.unlock()
        if voz.microfonoListo {
            compartido = true
            voz.ponerOyente("calle") { [weak self] b in self?.oir(b) }
            formatoMic = "el de la voz de Alma (\(Int(voz.formatoOyente?.sampleRate ?? 0)) Hz) · " + ModoCalle.entrada()
            micAbierto = true; return true
        }
        compartido = false
        let s = AVAudioSession.sharedInstance()
        if temporal {
            // Aviso con la app abierta: las otras apps bajan el volumen mientras Alma habla y escucha; vuelven al soltar el audio.
            try? s.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker, .allowBluetoothA2DP])
            try? s.setActive(true)
        } else if UIApplication.shared.applicationState == .active {
            VozNativa.sesionEscucha()
        } else {
            try? s.setCategory(.playAndRecord, mode: .default, options: VozNativa.opcionesEscucha)
            try? s.setActive(true)
        }
        let entrada = motor.inputNode, f = entrada.outputFormat(forBus: 0)
        guard f.sampleRate > 0, f.channelCount > 0 else { anotar("El micrófono no dio formato (0 Hz)"); return false }
        entrada.removeTap(onBus: 0)
        // Trozos de ~85 ms: menos despertares del procesador que con trozos chicos.
        entrada.installTap(onBus: 0, bufferSize: 4096, format: f) { [weak self] b, _ in self?.oir(b) }
        motor.prepare()
        do { try motor.start() } catch {
            entrada.removeTap(onBus: 0)
            anotar("El micrófono no arrancó: " + ModoCalle.textoError(error)); return false
        }
        formatoMic = "propio (\(Int(f.sampleRate)) Hz, \(f.channelCount) canal\(f.channelCount == 1 ? "" : "es")) · " + ModoCalle.entrada()
        micAbierto = true
        return true
    }

    /// Por dónde entra el audio (micrófono del iPhone, AirPods…), para el diagnóstico.
    private static func entrada() -> String {
        AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName ?? "sin entrada"
    }

    /// Un error de iOS en corto: dominio, código y lo que dice.
    static func textoError(_ e: Error) -> String {
        let n = e as NSError
        return "\(n.domain) \(n.code): " + String(n.localizedDescription.prefix(90))
    }

    private func cerrarMicrofono() {
        candado.lock(); alimentarDetector = false; let p = pedido; pedido = nil; previo = []; previoSeg = 0; candado.unlock()
        soltarArmado()   // otro micrófono: el dictado listo se vuelve a crear al esperar
        p?.endAudio()
        if compartido { VozNativa.shared.quitarOyente("calle"); compartido = false }
        else if micAbierto { motor.inputNode.removeTap(onBus: 0); if motor.isRunning { motor.stop() } }
        micAbierto = false
    }

    /// Vuelve a abrir el micrófono (audífonos que cambian, una interrupción que terminó).
    private func reabrir(tras t: TimeInterval) {
        guard ocupaMicrofono, fase != .llamada else { return }
        if fase == .verificando || fase == .oyendo {
            cerrarEscucha()
            if temporal { terminarTemporal(); return }
            fase = .esperando
        }
        cerrarMicrofono()
        DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
            guard let self, self.ocupaMicrofono, self.fase != .llamada, !self.micAbierto else { return }
            if self.abrirMicrofono() {
                self.reintentos = 0
                if self.fase == .esperando || self.fase == .pausa { self.volverAEsperar() }
            } else { self.reintentar() }
        }
    }

    /// iOS no devolvió el micrófono: se reintenta unas veces; si no, queda en pausa y avisa.
    private func reintentar() {
        guard encendido else { if temporal { terminarTemporal() }; return }
        reintentos += 1
        fase = .pausa
        if reintentos <= 5 { reabrir(tras: 2); return }
        fallar("El Modo calle se detuvo: iOS no devolvió el micrófono.")
        Notificaciones.shared.mostrar(id: "calle-pausa", texto: "El Modo calle está en pausa. Abre Alma para que vuelva a esperar «Alma».")
    }

    // MARK: - Lo que oye el micrófono (hilo del micrófono)

    private func oir(_ b: AVAudioPCMBuffer) {
        guard let copia = ModoCalle.copiar(b), let ch = copia.floatChannelData else { return }
        let seg = Double(copia.frameLength) / copia.format.sampleRate
        let n = Int(copia.frameLength), canales = Int(copia.format.channelCount)
        let paso = copia.format.isInterleaved ? canales : 1
        let crudo = GananciaCalle.medir(ch[0], cuenta: n, paso: paso)
        candado.lock()
        // Las voces cortas (el respaldo), con el audio como llega: solo mientras el detector escucha. Al volver a esperar se
        // empieza de cero (hace falta silencio antes), para que la cola de la voz de Alma o la señal no cuenten.
        var voces: [SegmentadorCalle.Voz] = []
        if alimentarDetector {
            if !segmentando { segmentador.reiniciar(); segmentando = true }
            let cuadro = max(1, Int(copia.format.sampleRate * 0.02))   // cuadros de ~20 ms
            var i = 0
            while i < n {
                let c = min(cuadro, n - i)
                let cm = GananciaCalle.medir(ch[0].advanced(by: i * paso), cuenta: c, paso: paso)
                if let v = segmentador.oir(rms: cm.rms, pico: cm.pico, seg: Double(c) / copia.format.sampleRate) { voces.append(v) }
                i += c
            }
        } else { segmentando = false }
        let g = ganancia.siguiente(rms: crudo.rms, pico: crudo.pico, seg: seg)
        let gAhora = ganancia.ganancia
        candado.unlock()
        // La ganancia, antes del detector y del dictado (los dos reciben esta copia).
        if paso > 1 || canales == 1 { GananciaCalle.aplicar(ch[0], cuenta: n, paso: paso, desde: g.desde, hasta: g.hasta) }
        else { for k in 0..<canales { GananciaCalle.aplicar(ch[k], cuenta: n, desde: g.desde, hasta: g.hasta) } }
        let pico = g.desde == 1 && g.hasta == 1 ? crudo.pico : GananciaCalle.medir(ch[0], cuenta: n, paso: paso).pico
        candado.lock()
        ultimoTramo = Date(); tramos += 1; picoTramos = max(picoTramos, pico); picoTramosAntes = max(picoTramosAntes, crudo.pico)
        segCeros = crudo.pico == 0 ? segCeros + seg : 0
        previo.append((ProcessInfo.processInfo.systemUptime, copia)); previoSeg += seg
        while previoSeg > ModoCalle.previoMax, previo.count > 1 { let x = previo.removeFirst().trozo; previoSeg -= Double(x.frameLength) / x.format.sampleRate }
        let p = pedido, alDetector = alimentarDetector
        let m = alDetector ? a16k(copia) : nil
        candado.unlock()
        p?.append(copia)
        if let m { colaDetector.async { [weak self] in self?.decodificar(m) } }
        if !voces.isEmpty { DispatchQueue.main.async { [weak self] in self?.oyoVoces(voces, ganancia: gAhora) } }
    }

    /// Copia el trozo: iOS reusa los suyos, aquí se guardan los últimos 3 s y la ganancia se aplica sobre la copia.
    private static func copiar(_ b: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard b.frameLength > 0, let src = b.floatChannelData,
              let c = AVAudioPCMBuffer(pcmFormat: b.format, frameCapacity: b.frameLength), let dst = c.floatChannelData else { return nil }
        c.frameLength = b.frameLength
        let n = Int(b.frameLength), canales = Int(b.format.channelCount)
        if b.format.isInterleaved { dst[0].update(from: src[0], count: n * canales) }
        else { for k in 0..<canales { dst[k].update(from: src[k], count: n) } }
        return c
    }

    /// A 16 kHz y un canal, como lo pide el detector (con `candado`).
    private func a16k(_ b: AVAudioPCMBuffer) -> [Float]? {
        if convertidor == nil || formatoConvertidor != b.format {
            convertidor = AVAudioConverter(from: b.format, to: formato16k); formatoConvertidor = b.format
            convertidor?.downmix = true
        }
        guard let conv = convertidor else { return nil }
        let cap = AVAudioFrameCount(Double(b.frameLength) * 16000 / b.format.sampleRate) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: formato16k, frameCapacity: cap) else { return nil }
        var dado = false
        conv.convert(to: out, error: nil) { _, st in
            if dado { st.pointee = .noDataNow; return nil }
            dado = true; st.pointee = .haveData; return b
        }
        guard out.frameLength > 0, let ch = out.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
    }

    /// El detector (en su cola): ¿sonó algo como «Alma»?
    private func decodificar(_ m: [Float]) {
        for e in escalera where e.detector.oir(m) { let u = e.umbral; DispatchQueue.main.async { [weak self] in self?.anotarFuerza(u) } }
        guard let d = detector, d.oir(m) else { return }
        DispatchQueue.main.async { [weak self] in self?.gatillo() }
    }

    /// Con «Probar»: uno de los detectores de la escalera oyó «Alma»; la fuerza es el umbral más alto en 2 s.
    private func anotarFuerza(_ u: Float) {
        fuerza = Date() < fuerzaHasta ? max(fuerza ?? 0, u) : u
        fuerzaHasta = Date().addingTimeInterval(2)
        emitir()
    }

    // MARK: - «Alma» y la frase

    /// El detector cree que oyó «Alma»: el dictado lo revisa en silencio con los últimos 2 s.
    private func gatillo() {
        guard encendido, fase == .esperando else { return }
        uso.gatillos += 1
        golpes += 1; ultimoGolpe = Date(); ultimoGatillo = ProcessInfo.processInfo.systemUptime
        if probando, Date() >= fuerzaHasta { fuerza = nil }   // ningún escalón la oyó: menos de 5 %
        anotar("El detector oyó «Alma»" + (probando ? (fuerza.map { " · fuerza \(Int($0 * 100)) % o más" } ?? " · fuerza menos de 5 %") : ""))
        verificar(respaldo: nil)
    }

    /// Terminaron una o más voces (del hilo del micrófono, con la ganancia de ese momento). La última de 0,3 s o más queda
    /// para la pista de los audífonos; si una es corta y el detector no se disparó, el respaldo se la pasa al dictado.
    private func oyoVoces(_ voces: [SegmentadorCalle.Voz], ganancia g: Float) {
        let ahora = ProcessInfo.processInfo.systemUptime
        if let v = voces.last(where: { $0.duracion >= SegmentadorCalle.duracionMinima }) { ultimaVoz = (min(1, v.pico * g), ahora) }
        guard encendido, let v = voces.last(where: { $0.corta }),
              RespaldoCalle.revisar(v, ahora: ahora, esperando: fase == .esperando, dictadoEnTelefono: reconocedor?.supportsOnDeviceRecognition == true,
                                    ultimoGatillo: ultimoGatillo, finUltima: finRespaldo) else { return }
        uso.respaldos += 1; revisionesRespaldo += 1
        finRespaldo = ahora
        verificar(respaldo: RespaldoCalle.segundosParaDictado(v))
    }

    /// Un pedido nuevo al dictado (en el teléfono si se puede). `revisar`: solo para revisar «Alma» (corto, sin puntuación).
    private func nuevoPedido(revisar: Bool) -> SFSpeechAudioBufferRecognitionRequest {
        let p = SFSpeechAudioBufferRecognitionRequest(); p.shouldReportPartialResults = true
        if reconocedor?.supportsOnDeviceRecognition == true { p.requiresOnDeviceRecognition = true }
        if revisar { p.taskHint = .search } else if #available(iOS 16, *) { p.addsPunctuation = true }
        p.contextualStrings = ["Alma"]   // que el reconocedor espere oír «Alma» (no «palma» ni «al ma»)
        return p
    }

    /// Crea la tarea del dictado con el id `mia`: lo que contesta solo cuenta mientras `vuelta == mia`.
    private func nuevaTarea(_ p: SFSpeechAudioBufferRecognitionRequest, id mia: Int) -> SFSpeechRecognitionTask? {
        reconocedor?.recognitionTask(with: p) { [weak self] r, e in
            DispatchQueue.main.async { self?.respuestaDictado(id: mia, r, e) }
        }
    }

    /// Deja listo el dictado que revisará el próximo «Alma» (sin audio todavía). Solo con el Modo calle esperando; si ya
    /// hay uno de menos de 45 s, nada. Si iOS lo cierra solo varias veces seguidas, se deja de armar (se crea al momento).
    private func armarVerificacion() {
        guard encendido, fase == .esperando, reconocedor?.isAvailable == true, Date() >= armarDesde else { return }
        if let a = armado, Date().timeIntervalSince(a.desde) < 45 { return }
        soltarArmado()
        ids += 1; let mia = ids
        let p = nuevoPedido(revisar: true)
        guard let t = nuevaTarea(p, id: mia) else { return }
        armado = (p, t, mia, Date())
    }

    private func soltarArmado() {
        guard let a = armado else { return }
        armado = nil
        a.tarea.cancel(); a.pedido.endAudio()
    }

    /// Revisa con el dictado si dijeron «Alma»: el dictado listo (o uno nuevo) recibe los últimos 2 s (o la voz corta del
    /// respaldo) y se le cierra el audio enseguida, así contesta con lo que oyó. La frase se escucha después, aparte.
    private func verificar(respaldo: Double?) {
        cerrarEscucha()
        let usado: (pedido: SFSpeechAudioBufferRecognitionRequest, tarea: SFSpeechRecognitionTask, id: Int)
        if let a = armado { armado = nil; usado = (a.pedido, a.tarea, a.id) }
        else {
            ids += 1
            let p = nuevoPedido(revisar: true)
            guard let t = nuevaTarea(p, id: ids) else { descartar(); volverAEsperar(); return }
            usado = (p, t, ids)
        }
        marcaGatillo = ProcessInfo.processInfo.systemUptime
        candado.lock()
        alimentarDetector = false
        // Del final hacia atrás, sin pasar de lo que toca (2 s para el detector, como siempre).
        let hasta = respaldo ?? 2.0
        var tomar: [AVAudioPCMBuffer] = [], seg = 0.0
        for x in previo.reversed() {
            let d = Double(x.trozo.frameLength) / x.trozo.format.sampleRate
            if !tomar.isEmpty, seg + d > hasta + 0.001 { break }
            tomar.append(x.trozo); seg += d
        }
        candado.unlock()
        for b in tomar.reversed() { usado.pedido.append(b) }
        usado.pedido.endAudio()
        colaDetector.async { [weak self] in self?.detector?.reiniciar() }
        vuelta = usado.id; tarea = usado.tarea
        textoAlma = nil; textoMejor = ""; avisoActual = nil; ultimoCambio = Date(); desde = Date(); errorDictado = nil
        finDictado = .sigue; primeraRespuesta = false
        porRespaldo = respaldo != nil
        fase = .verificando
        reloj?.invalidate()
        reloj = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.revisar(cerro: false) }
    }

    /// Escucha la frase: tras «Alma», con el audio desde un poco antes del gatillo (lo dicho de corrido no se pierde y la
    /// señal no se come el principio) y lo que siga llegando; para un aviso, solo lo que llega (no hace falta «Alma»).
    /// `boton`: la abrió el botón del caminante: solo lo que llega desde ahora, sin «Alma» (si la dice, se quita).
    private func escucharFrase(aviso: String?, boton: Bool = false) {
        cerrarEscucha(); soltarArmado()   // un solo dictado a la vez; se vuelve a armar al esperar
        ids += 1; let mia = ids
        let p = nuevoPedido(revisar: false)
        candado.lock()
        alimentarDetector = false
        let guardado = aviso == nil && !boton ? PedidoCalle.desde(previo, marcaGatillo - PedidoCalle.antesDelGatillo) : []
        for b in guardado { p.append(b) }
        pedido = p   // desde aquí el hilo del micrófono le pasa cada trozo
        candado.unlock()
        colaDetector.async { [weak self] in self?.detector?.reiniciar() }
        vuelta = mia
        textoAlma = nil; textoMejor = ""; avisoActual = aviso; porBoton = boton; ultimoCambio = Date(); desde = Date(); errorDictado = nil
        finDictado = .sigue
        fase = .oyendo
        tarea = nuevaTarea(p, id: mia)
        reloj?.invalidate()
        reloj = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.revisar(cerro: false) }
    }

    /// Lo que contesta el dictado (en el hilo principal).
    private func respuestaDictado(id mia: Int, _ r: SFSpeechRecognitionResult?, _ e: Error?) {
        if vuelta != mia {
            // El dictado listo de antemano se cerró solo (sin audio): se vuelve a armar, con calma si pasa seguido.
            if let a = armado, a.id == mia, e != nil {
                armado = nil
                fallosArmado += 1
                armarDesde = Date().addingTimeInterval(fallosArmado >= 3 ? 300 : 3)
                if fallosArmado == 3 { anotar("El dictado listo de antemano se cierra solo: lo creo al momento") }
            }
            return
        }
        if fase == .verificando, !primeraRespuesta, r != nil || e != nil {
            primeraRespuesta = true; if r != nil { fallosArmado = 0 }
            latencia.anotar(ms: Int((Date().timeIntervalSince(desde) * 1000).rounded()))
        }
        if let e {
            errorDictado = ModoCalle.textoError(e)
            // «No speech detected» (1110): contestó que no oyó voz. Otro error: el dictado no pudo revisar.
            if finDictado == .sigue { finDictado = ModoCalle.sinVoz(e) ? .termino : .fallo }
        }
        if let r {
            let t = r.bestTranscription.formattedString
            if t != textoMejor { textoMejor = t; ultimoCambio = Date() }
            if let a = Conferencia.versionConAlma(r) { textoAlma = a }
            if r.isFinal { finDictado = .termino }
        }
        if fase == .verificando { revisar(cerro: false) }
        else if r?.isFinal == true || (r == nil && e != nil) { revisar(cerro: true) }
    }

    private static func sinVoz(_ e: Error) -> Bool {
        let n = e as NSError
        return n.domain == "kAFAssistantErrorDomain" && n.code == 1110
    }

    /// El dictado confirmó «Alma» (o el detector la oyó y el dictado no contestó a tiempo): suena la señal y se escucha
    /// lo que pide.
    private func confirmar(sinConfirmarlo: Bool = false) {
        uso.despertares += 1
        let respaldo = porRespaldo
        if respaldo {
            uso.despertaresRespaldo += 1; despertaresRespaldo += 1; finRespaldo = ProcessInfo.processInfo.systemUptime
        } else { despertaresDetector += 1 }
        errorDiag = ""
        let ms = latencia.ultima.map { " en \($0) ms" } ?? ""
        if sinConfirmarlo {
            sinConfirmar += 1; sinDictado += 1
            if !primeraRespuesta { latencia.anotarLenta() }
            dictadoOido = ""
            let porque = errorDictado.map { "el dictado falló: \($0)" } ?? "no contestó en 3,5 s"
            veredicto = "Aceptado sin confirmar (dictado lento: \(porque)) · " + textoDespertares
        } else {
            sinDictado = 0
            dictadoOido = String((textoAlma ?? "").prefix(120))
            veredicto = (respaldo ? "Confirmado por el respaldo (el detector no la oyó): el dictado oyó «Alma»" : "Confirmado: el dictado oyó «Alma»") + ms + " · " + textoDespertares
        }
        anotar(veredicto)
        if sinDictado == 3 { anotar("El dictado del iPhone tarda: tres veces seguidas no contestó a tiempo (igual acepto «Alma» del detector)") }
        porRespaldo = false
        escucharFrase(aviso: nil)
        VozNativa.shared.senal()
    }

    /// Cada 0,1–0,2 s: ¿qué dijo el dictado de «Alma»? ¿terminó la frase (pausa de 1,2 s)? ¿nadie dijo nada?
    private func revisar(cerro: Bool) {
        let quieto = Date().timeIntervalSince(ultimoCambio), lleva = Date().timeIntervalSince(desde)
        switch fase {
        case .verificando:
            let otraCosa = textoAlma == nil && !textoMejor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            switch VerificacionCalle.decidir(oyoAlma: textoAlma != nil, oyoOtraCosa: otraCosa, fin: finDictado, porRespaldo: porRespaldo, lleva: lleva) {
            case .esperar: break
            case .confirmar: confirmar()
            case .aceptarSinConfirmar: confirmar(sinConfirmarlo: true)
            case .descartar: descartar(); volverAEsperar()   // no era «Alma»: nada suena
            }
        case .oyendo:
            let pide: String
            if avisoActual != nil { pide = textoMejor.trimmingCharacters(in: .whitespacesAndNewlines) }
            else { pide = PedidoCalle.limpiar(textoMejor, despuesDeAlma: Conferencia.pedidoAAlma(textoMejor)) }
            // Con el botón se espera como con un aviso (8 s): no hubo «Alma» antes, Juan puede tardar en empezar.
            switch PedidoCalle.paso(pide: pide, quieto: quieto, lleva: lleva, cerro: cerro, aviso: avisoActual != nil || porBoton) {
            case .sigue: break
            case .mandar: listo(pide)
            case .rendirse: sinPedido()
            }
        default: break
        }
    }

    /// El dictado no confirmó «Alma»: no suena nada, pero queda dicho por qué (en la prueba y en el diagnóstico).
    private func descartar() {
        let oido = textoMejor.trimmingCharacters(in: .whitespacesAndNewlines), error = errorDictado
        let contesto = primeraRespuesta
        cerrarEscucha()
        if !contesto { latencia.anotarLenta() }
        if porRespaldo {
            // El respaldo revisa cualquier voz corta (una tos, una puerta): que no era «Alma» es lo normal. No cuenta como
            // descarte del detector ni como dictado que no contesta; queda en «Lo que pasó» solo durante la prueba.
            porRespaldo = false; finRespaldo = ProcessInfo.processInfo.systemUptime
            if probando {
                anotar("Respaldo: " + (oido.isEmpty ? (contesto ? "una voz corta, sin palabras" : "el dictado no contestó en 3,5 s") : "«\(ModoCalle.corto(oido, palabras: 12))», sin «Alma»"))
            }
            return
        }
        uso.descartes += 1
        sinDictado = 0
        dictadoOido = String(oido.prefix(120))
        let ms = latencia.ultima.map { " (\($0) ms)" } ?? ""
        if oido.isEmpty { veredicto = "Descartado: el dictado no oyó voz" + ms }
        else { veredicto = "Descartado: el dictado oyó «\(ModoCalle.corto(oido, palabras: 12))», sin «Alma»" + ms }
        if let error, !oido.isEmpty || !error.contains("1110") { veredicto += " · " + error }
        anotar(veredicto)
    }

    private func cerrarEscucha() {
        reloj?.invalidate(); reloj = nil
        vuelta = 0
        tarea?.cancel(); tarea = nil
        candado.lock(); let p = pedido; pedido = nil; candado.unlock()
        p?.endAudio()
    }

    /// Sonó la señal, pero no pidieron nada (o nadie respondió al aviso).
    private func sinPedido() {
        cerrarEscucha()
        let boton = porBoton; porBoton = false
        if avisoActual != nil { avisoActual = nil }   // el aviso queda en Pendientes
        else if boton { VozNativa.shared.sonar("alma-fin"); anotar("Botón: no oí un pedido") }   // no es un falso despertar
        else { uso.falsos += 1; VozNativa.shared.sonar("alma-fin"); anotar("Sonó la señal, pero no oí un pedido") }
        volverAEsperar()
    }

    /// La frase terminó: va al Hub.
    private func listo(_ pide: String) {
        cerrarEscucha()
        let aviso = avisoActual; avisoActual = nil
        let boton = porBoton; porBoton = false
        if encendido { uso.pedidos += 1 }
        anotar((boton ? "Pedido (botón): «" : "Pedido: «") + ModoCalle.corto(pide, palabras: 12) + "»")
        VozNativa.shared.sonar("alma-fin")   // el sonido de fin: te oí y lo mando (antes, silencio hasta la respuesta)
        fase = .pensando
        turnoPedido += 1
        esperarRespuesta(turnoPedido)
        preguntar(pide, aviso: aviso, turno: turnoPedido)
    }

    /// Nunca en silencio (EsperaCalle): si a los 25 s no llegó la respuesta del Hub, Alma lo dice y vuelve a escuchar,
    /// sin «Alma». La respuesta que llegue después ya no suena (queda en el Chat con Alma o en Pendientes).
    private func esperarRespuesta(_ mio: Int) {
        soltarEspera()
        pedidoDesde = Date(); errorRed = nil
        relojRespuesta = Timer.scheduledTimer(withTimeInterval: EsperaCalle.plazo, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.relojRespuesta = nil
            guard self.ocupaMicrofono, self.fase == .pensando, self.turnoPedido == mio else { return }
            self.turnoPedido += 1
            self.sinRespuesta(EsperaCalle.motivo(red: self.errorRed, segundos: Date().timeIntervalSince(self.pedidoDesde)))
        }
    }

    private func soltarEspera() { relojRespuesta?.invalidate(); relojRespuesta = nil }

    /// No llegó la respuesta (o el Hub no contestó): la frase corta y a escuchar de nuevo. El porqué, en el diagnóstico.
    private func sinRespuesta(_ motivo: String) {
        soltarEspera()
        if encendido { uso.errores += 1 }
        avisarError("No llegó la respuesta: " + motivo)
        decir(EsperaCalle.frase, audio: nil, pedirVoz: false) { [weak self] in
            guard let self, self.ocupaMicrofono else { return }
            if !self.micAbierto { guard self.abrirMicrofono() else { self.reintentar(); return } }
            self.escucharFrase(aviso: nil, boton: true)
            VozNativa.shared.senal()
        }
    }

    /// De vuelta a esperar «Alma» (o, si era un aviso con la app abierta, se suelta el micrófono).
    private func volverAEsperar() {
        if temporal { terminarTemporal(); return }
        guard encendido else { return }
        if !micAbierto { guard abrirMicrofono() else { reintentar(); return } }
        fase = .esperando
        colaDetector.async { [weak self] in self?.detector?.reiniciar() }
        // Un respiro: que el final de la voz de Alma (o la señal) no despierte al detector.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.encendido, self.fase == .esperando else { return }
            if let f = self.deFuera {
                self.deFuera = nil
                if Date().timeIntervalSince(f.desde) < 120 { self.decir(f.texto, audio: nil) { [weak self] in self?.volverAEsperar() }; return }
            }
            self.candado.lock(); self.alimentarDetector = true; self.candado.unlock()
            self.armarVerificacion()
            self.procesarAvisos()
        }
    }

    // MARK: - El Hub

    /// La frase al Hub: acción «calle» → { ok, hablar, conversar, audio? }. Si el Hub todavía no la tiene, va al chat con
    /// Alma (opEnviar, canal «calle») y se dice corto lo que contestó.
    private func preguntar(_ texto: String, aviso: String?, turno: Int) {
        if hubSinCalle { porChat(texto, aviso: aviso, turno: turno); return }
        var b: [String: Any] = ["texto": texto, "canal": "calle"]
        if let aviso { b["aviso_id"] = aviso }
        llamarHub(b, accion: "calle", timeout: EsperaCalle.plazo + 5) { [weak self] j in
            guard let self, self.ocupaMicrofono else { return }
            guard self.vigente(turno) else { return }
            if j == nil { self.sinRespuesta(EsperaCalle.motivo(red: self.errorRed, segundos: Date().timeIntervalSince(self.pedidoDesde))); return }
            if let j, (j["ok"] as? Bool) == true {
                self.responder(hablar: j["hablar"] as? String ?? "", conversar: (j["conversar"] as? Bool) ?? false, audio: j["audio"] as? String, pedido: texto)
            } else if (j?["error"] as? String) == "accion" {
                self.hubSinCalle = true; self.porChat(texto, aviso: aviso, turno: turno)
            } else {
                if self.encendido { self.uso.errores += 1 }
                let e = (j?["error"] as? String).map { ModoCalle.corto($0, palabras: 20) } ?? ""
                self.responder(hablar: j == nil ? "No pude hablar con el Hub. Intenta otra vez." : (e.isEmpty ? "No pude hacerlo ahora." : e), conversar: false, audio: nil, pedido: texto, pedirVoz: j != nil)
            }
        }
    }

    /// ¿La respuesta es del pedido de ahora? Si llegó tarde (ya se dijo «No me llegó…» o se tocó el botón), no suena.
    private func vigente(_ turno: Int) -> Bool {
        guard turno == turnoPedido, fase == .pensando else {
            anotar("La respuesta del Hub llegó tarde (\(Int(Date().timeIntervalSince(pedidoDesde))) s): ya no la digo")
            return false
        }
        soltarEspera()
        return true
    }

    private func porChat(_ texto: String, aviso: String?, turno: Int) {
        var t = texto
        if let aviso, let a = UserDefaults.standard.dictionary(forKey: "avisos_textos")?[aviso] as? String { t = "Sobre el aviso «\(a)»: \(texto)" }
        var b: [String: Any] = ["texto": t, "canal": "calle"]
        if let email = ModoCalle.correoDeSesion() { b["email"] = email }
        llamarHub(b, accion: "opEnviar", timeout: EsperaCalle.plazo + 5) { [weak self] j in
            guard let self, self.ocupaMicrofono, self.vigente(turno) else { return }
            if j == nil { self.sinRespuesta(EsperaCalle.motivo(red: self.errorRed, segundos: Date().timeIntervalSince(self.pedidoDesde))); return }
            let alma = (j?["alma"] as? [String: Any])?["texto"] as? String ?? ""
            if (j?["ok"] as? Bool) == true {
                self.responder(hablar: alma.isEmpty ? "Listo." : ModoCalle.corto(alma, palabras: 40), conversar: false, audio: nil, pedido: texto)
            } else {
                if self.encendido { self.uso.errores += 1 }
                self.responder(hablar: j == nil ? "No pude hablar con el Hub. Intenta otra vez." : "No pude hacerlo ahora.", conversar: false, audio: nil, pedido: texto, pedirVoz: j != nil)
            }
        }
    }

    private func responder(hablar: String, conversar: Bool, audio: String?, pedido: String, pedirVoz: Bool = true) {
        let frase = hablar.isEmpty && !conversar && audio == nil ? "Listo." : hablar
        decir(frase, audio: audio, pedirVoz: pedirVoz) { [weak self] in
            guard let self, self.ocupaMicrofono else { return }
            if conversar { self.abrirLlamada(pedido) } else { self.volverAEsperar() }
        }
    }

    private func llamarHub(_ cuerpo: [String: Any], accion: String, timeout: TimeInterval, _ listo: @escaping ([String: Any]?) -> Void) {
        guard let url = Llave.leer("voz_url"), let token = Llave.leer("voz_token"), let sesion = Llave.leer("voz_sesion"), let u = URL(string: url) else {
            DispatchQueue.main.async { self.errorRed = "falta la sesión del Hub: abre Alma con sesión"; listo(nil) }; return
        }
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.timeoutInterval = timeout
        r.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        var b = cuerpo; b["hub"] = 1; b["action"] = accion; b["token"] = token; b["session"] = sesion; b["app"] = "alma"
        r.httpBody = try? JSONSerialization.data(withJSONObject: b)
        URLSession.shared.dataTask(with: r) { d, resp, err in
            let j = d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            // Por qué no hubo respuesta (para el diagnóstico): el error de la red, el código HTTP o que no vino JSON.
            var porque: String?
            if j == nil {
                if let err { porque = (err as NSError).code == NSURLErrorTimedOut ? "la red tardó más de \(Int(timeout)) s" : ModoCalle.textoError(err) }
                else if let h = resp as? HTTPURLResponse, h.statusCode != 200 { porque = "HTTP \(h.statusCode)" }
                else { porque = "la respuesta no era JSON" }
            }
            DispatchQueue.main.async { if j == nil, accion == "calle" || accion == "opEnviar" { self.errorRed = porque }; listo(j) }
        }.resume()
    }

    /// El correo de la sesión firmada (va dentro, en base64): el chat con Alma (opEnviar) lo pide.
    private static func correoDeSesion() -> String? {
        guard let s = Llave.leer("voz_sesion"), let i = s.lastIndex(of: ".") else { return nil }
        var b = String(s[..<i]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        guard let d = Data(base64Encoded: b), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        if let p = j["p"] as? [String: Any], let e = p["email"] as? String, !e.isEmpty { return e }
        return j["e"] as? String
    }

    /// Lo que se dice al oído: sin marcas del chat, la primera parte y corto (cortado en una frase si se puede).
    static func corto(_ t: String, palabras: Int) -> String {
        var s = t.replacingOccurrences(of: "[*_#`>]", with: "", options: .regularExpression)
        s = s.components(separatedBy: "\n\n").first ?? s
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        let p = s.split(separator: " ")
        guard p.count > palabras else { return s }
        let recorte = p.prefix(palabras).joined(separator: " ")
        if let fin = recorte.lastIndex(where: { ".!?".contains($0) }), recorte.distance(from: recorte.startIndex, to: fin) > 20 {
            return String(recorte[...fin])
        }
        return recorte + "…"
    }

    // MARK: - Hablar

    /// Alma contesta al oído, siempre con su voz (ElevenLabs): el audio que mandó el Hub; si no vino, el que ya se guardó
    /// para esa frase; si no, se pide aparte (acción «calleVoz», 6 s como mucho). Solo sin nada de eso habla el iPhone, con
    /// una voz de mujer elegida a mano (VozIphone), nunca la de por defecto. `pedirVoz`: false si el Hub no contesta (sin red).
    private func decir(_ texto: String, audio: String?, pedirVoz: Bool = true, luego: @escaping () -> Void) {
        fase = .hablando
        candado.lock(); alimentarDetector = false; candado.unlock()
        trasHablar = luego
        turnoVoz += 1; let mio = turnoVoz
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        if let a = audio, let d = Data(base64Encoded: a), tocar(d, voz: "Alma (ElevenLabs)") { guardarVoz(t, d); return }
        guard !t.isEmpty else { terminoDeHablar(); return }
        if let d = vozGuardada[t], tocar(d, voz: "Alma (ElevenLabs, guardada)") { return }
        guard pedirVoz, !hubSinVoz else { hablarIphone(t, por: hubSinVoz ? "el Hub no tiene «calleVoz»" : "sin conexión con el Hub"); return }
        llamarHub(["texto": t], accion: "calleVoz", timeout: 8) { [weak self] j in
            guard let self, self.turnoVoz == mio, self.fase == .hablando, self.trasHablar != nil else { return }   // ya se calló
            if (j?["error"] as? String) == "accion" { self.hubSinVoz = true }
            if (j?["ok"] as? Bool) == true, let a = j?["audio"] as? String, let d = Data(base64Encoded: a),
               self.tocar(d, voz: "Alma (ElevenLabs, pedida aparte)") { self.guardarVoz(t, d); return }
            // El Hub dice por qué no hubo voz (sin llave, sin permiso, sin créditos, ElevenLabs falló…): queda en el diagnóstico.
            let motivo = (j?["motivo"] as? String).map { ": " + ModoCalle.corto($0, palabras: 18) } ?? ((j?["error"] as? String).map { ": " + $0 } ?? "")
            self.hablarIphone(t, por: j == nil ? "el Hub no contestó a tiempo" : "el Hub no mandó la voz" + motivo)
        }
    }

    /// Suena el mp3 de la voz de Alma. false si no se pudo (entonces se intenta lo siguiente).
    private func tocar(_ d: Data, voz: String) -> Bool {
        guard let p = try? AVAudioPlayer(data: d) else { return false }
        reproductor = p; p.delegate = self; p.volume = 1
        guard p.play() else { reproductor = nil; return false }
        vozUsada = voz
        return true
    }

    /// La voz del iPhone, solo de respaldo: de mujer, en español, elegida a mano. Queda anotado por qué.
    private func hablarIphone(_ t: String, por: String) {
        let u = AVSpeechUtterance(string: t)
        u.voice = VozIphone.elegida
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        vozUsada = "iPhone: " + VozIphone.nombre + " (" + por + ")"
        anotar("Voz del iPhone: " + VozIphone.nombre + " · " + por)
        sintetizador.speak(u)
    }

    /// Las frases cortas quedan con la voz de Alma (en memoria, 40 como mucho): la próxima vez suenan sin esperar al Hub.
    private func guardarVoz(_ t: String, _ d: Data) {
        guard !t.isEmpty, t.count <= 160, d.count <= 200_000 else { return }
        if vozGuardada.count >= 40, vozGuardada[t] == nil, let k = vozGuardada.keys.first(where: { !ModoCalle.frasesFijas.contains($0) }) { vozGuardada[k] = nil }
        vozGuardada[t] = d
    }

    /// Al encender: las frases que dice la app por su cuenta se piden una vez con la voz de Alma (el Hub las guarda 6 h).
    private func guardarFrasesFijas() {
        guard !hubSinVoz else { return }
        for f in ModoCalle.frasesFijas where vozGuardada[f] == nil {
            llamarHub(["texto": f], accion: "calleVoz", timeout: 15) { [weak self] j in
                guard let self else { return }
                if (j?["error"] as? String) == "accion" { self.hubSinVoz = true }
                if (j?["ok"] as? Bool) == true, let a = j?["audio"] as? String, let d = Data(base64Encoded: a), (try? AVAudioPlayer(data: d)) != nil { self.guardarVoz(f, d) }
            }
        }
    }

    /// Lo que contestó Alma a un atajo de Siri con el Modo calle encendido: lo dice el Modo calle con la voz de Alma, en
    /// cuanto vuelve a esperar «Alma» (Siri tiene el audio mientras corre el atajo). true si lo toma; si está apagado, false.
    func decirDeFuera(_ texto: String) -> Bool {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard encendido, !t.isEmpty else { return false }
        deFuera = (t, Date())
        if fase == .esperando { volverAEsperar() }
        return true
    }

    private func callar() {
        trasHablar = nil
        turnoVoz += 1
        if sintetizador.isSpeaking { sintetizador.stopSpeaking(at: .immediate) }
        reproductor?.stop(); reproductor = nil
    }

    private func terminoDeHablar() {
        reproductor = nil
        let f = trasHablar; trasHablar = nil
        f?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.terminoDeHablar() }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.terminoDeHablar() }
    }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { self.terminoDeHablar() }
    }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async { self.terminoDeHablar() }
    }

    // MARK: - La llamada real

    /// Hace falta conversar: se abre la llamada de ElevenLabs (la de siempre, VozNativa) con lo que pidió y, al colgar,
    /// el Modo calle vuelve a esperar «Alma».
    private func abrirLlamada(_ pedido: String) {
        cerrarMicrofono()
        fase = .llamada
        if encendido { uso.llamadas += 1 }
        let v = VozNativa.shared
        v.desdeCalle = encendido
        v.ultimaLlamada = (0, nil)   // si la llamada no llega a empezar, no se cuenta la anterior
        v.hablarAlOir(pedido)
        llamadaVista = false; llamadaDesde = Date()
        reloj?.invalidate()
        reloj = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.revisarLlamada() }
    }

    private func revisarLlamada() {
        guard fase == .llamada else { reloj?.invalidate(); reloj = nil; return }
        let e = VozNativa.shared.estado
        if e == .hablando || e == .conectando { llamadaVista = true; return }
        guard llamadaVista || Date().timeIntervalSince(llamadaDesde) > 5 else { return }
        reloj?.invalidate(); reloj = nil
        let v = VozNativa.shared
        v.desdeCalle = false
        if encendido {
            uso.llamadaSeg += v.ultimaLlamada.seg
            switch v.ultimaLlamada.motivo {
            case .silencio?, .cierre?, .tope?: uso.dormidas += 1
            case .corte?: uso.cortadas += 1
            case nil: break
            }
            v.ultimaLlamada = (0, nil)
        }
        // Otra llamada o Siri todavía tienen el audio: se espera en pausa; vuelve con el aviso de iOS o al abrir Alma.
        if encendido && interrumpido { cerrarMicrofono(); fase = .pausa; return }
        if encendido || temporal { volverAEsperar() } else { fase = .quieta }
    }

    // MARK: - Avisos hablados

    /// Llegó un aviso importante (VozNativa.novedades, ya filtrado por NivelAvisos): Alma lo dice al oído con el Modo calle,
    /// con la app abierta o en modo conferencia (también con el teléfono bloqueado); si no, queda solo la notificación.
    /// Nunca interrumpe una llamada: espera y lo dice después. `resultado`: terminó algo que Alma trabajaba en segundo plano.
    func avisoHablado(id: String, texto: String, resultado: Bool = false) {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, encendido || Conferencia.shared.activa || UIApplication.shared.applicationState == .active else { return }
        let dichos = UserDefaults.standard.stringArray(forKey: "avisos_dichos") ?? []
        guard !dichos.contains(id), !colaAvisos.contains(where: { $0.id == id }) else { return }
        colaAvisos.append((id, t, resultado))
        procesarAvisos()
    }

    private func procesarAvisos() {
        guard let a = colaAvisos.first else { relojAvisos?.invalidate(); relojAvisos = nil; return }
        let app = UIApplication.shared.applicationState == .active, conf = Conferencia.shared.activa
        if !encendido && !app && !temporal && !conf { colaAvisos = []; relojAvisos?.invalidate(); relojAvisos = nil; return }   // ya no: queda la notificación
        let v = VozNativa.shared.estado
        let vozLibre = v == .lista || v == .apagada
        // En modo conferencia no hace falta la app abierta: la conferencia ya tiene el micrófono (también bloqueado).
        let puede = encendido ? (fase == .esperando && vozLibre) : (!temporal && fase == .quieta && (app || conf) && vozLibre && MejoraCampo.shared.estado == .apagada)
        guard puede else {
            if relojAvisos == nil { relojAvisos = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.procesarAvisos() } }
            return
        }
        relojAvisos?.invalidate(); relojAvisos = nil
        colaAvisos.removeFirst()
        marcarDicho(a)
        if encendido {
            uso.avisos += 1
            decirAviso(a) { [weak self] in self?.escucharFrase(aviso: a.id) }
            return
        }
        if conf {
            // El modo conferencia ya escucha: se dice y, durante unos segundos, lo que contestes («sí», «dime») abre la
            // llamada con el aviso de contexto, sin tener que decir «Alma».
            decirAviso(a) { [weak self] in
                self?.fase = .quieta
                Conferencia.shared.esperarRespuesta(aviso: a.texto)
                self?.procesarAvisos()
            }
            return
        }
        temporal = true
        EscuchaInicio.shared.detener()
        guard abrirMicrofono() else { temporal = false; fase = .quieta; cerrarMicrofono(); VozNativa.soltarAudio(); return }
        decirAviso(a) { [weak self] in
            guard let self, self.temporal else { return }
            self.escucharFrase(aviso: a.id)
        }
    }

    /// Lo dice con la voz de Alma si el Hub la manda (acción «avisoHablar»: solo arma la frase y su audio, no responde
    /// el aviso); si no, con la voz del iPhone, corto. Lo que terminó en segundo plano suena «Ya quedó listo… ¿Quieres verlo?».
    private func decirAviso(_ a: (id: String, texto: String, resultado: Bool), luego: @escaping () -> Void) {
        let limpio = a.resultado ? "Ya quedó listo: " + ModoCalle.corto(a.texto, palabras: 16) + " ¿Quieres verlo ahora?" : ModoCalle.corto(a.texto, palabras: 22)
        guard !hubSinAviso else { decir(limpio, audio: nil, luego: luego); return }
        fase = .pensando
        var cuerpo: [String: Any] = ["aviso_id": a.id]
        if a.resultado { cuerpo["resultado"] = true }
        llamarHub(cuerpo, accion: "avisoHablar", timeout: 12) { [weak self] j in
            guard let self else { return }
            if (j?["error"] as? String) == "accion" { self.hubSinAviso = true }
            let ok = (j?["ok"] as? Bool) == true
            let hablar = ok ? ((j?["hablar"] as? String) ?? "") : ""
            self.decir(hablar.isEmpty ? limpio : hablar, audio: ok ? j?["audio"] as? String : nil, luego: luego)
        }
    }

    private func marcarDicho(_ a: (id: String, texto: String, resultado: Bool)) {
        let d = UserDefaults.standard
        d.set(Array(((d.stringArray(forKey: "avisos_dichos") ?? []) + [a.id]).suffix(60)), forKey: "avisos_dichos")
        var textos = d.dictionary(forKey: "avisos_textos") ?? [:]
        textos[a.id] = String(a.texto.prefix(300))
        if textos.count > 20 { for k in textos.keys.prefix(textos.count - 20) where k != a.id { textos[k] = nil } }
        d.set(textos, forKey: "avisos_textos")
    }

    /// El aviso con la app abierta terminó: se suelta el micrófono (y las otras apps vuelven a su volumen).
    private func terminarTemporal() {
        soltarEspera(); porBoton = false
        cerrarEscucha(); callar(); cerrarMicrofono()
        temporal = false; fase = .quieta
        VozNativa.soltarAudio()
        EscuchaInicio.shared.evaluar()
        procesarAvisos()
    }

    // MARK: - Medición (T3)

    private static func bateria() -> Int? {
        let l = UIDevice.current.batteryLevel
        return l < 0 ? nil : Int((l * 100).rounded())
    }

    /// Al apagar: el resumen de la sesión queda en el teléfono (`calle_usos`, las últimas 30) y va al Hub («calleUso»).
    private func cerrarUso() {
        let fin = Date(), seg = fin.timeIntervalSince(uso.inicio), horas = max(seg / 3600, 1.0 / 60)
        let iso = ISO8601DateFormatter()
        func porHora(_ n: Int) -> Double { (Double(n) / horas * 10).rounded() / 10 }
        var r: [String: Any] = [
            "inicio": iso.string(from: uso.inicio), "fin": iso.string(from: fin), "minutos": Int((seg / 60).rounded()),
            "gatillos": uso.gatillos, "despertares": uso.despertares, "descartes": uso.descartes, "falsos": uso.falsos,
            "pedidos": uso.pedidos, "llamadas": uso.llamadas, "avisos": uso.avisos, "errores": uso.errores,
            "llamadaSeg": Int(uso.llamadaSeg.rounded()), "llamadasSleep": uso.dormidas, "llamadasCorte": uso.cortadas,
            "despertaresHora": porHora(uso.despertares), "falsosHora": porHora(uso.falsos), "gatillosHora": porHora(uso.gatillos),
            "respaldos": uso.respaldos, "despertaresRespaldo": uso.despertaresRespaldo,
            "despertaresDetector": uso.despertares - uso.despertaresRespaldo, "despertaresSinConfirmar": sinConfirmar,
            "detector": DetectorAlma.nombre, "enviado": false, "diag": diagCorto()
        ]
        let fin100 = ModoCalle.bateria()
        if let ms = latencia.media { r["dictadoMs"] = ms }
        if let b = uso.bateriaInicio { r["bateriaInicio"] = b }
        if let b = fin100 { r["bateriaFin"] = b }
        if let a = uso.bateriaInicio, let b = fin100 { r["bateriaGastada"] = a - b; r["bateriaHora"] = porHora(a - b) }
        var lista = UserDefaults.standard.array(forKey: "calle_usos") as? [[String: Any]] ?? []
        lista.append(r)
        UserDefaults.standard.set(Array(lista.suffix(30)), forKey: "calle_usos")
        mandarUsos()
    }

    /// El diagnóstico de la salida en una línea (columna «diagnostico» de ALMA_CALLE_USO): micrófono, golpes, el último
    /// veredicto y error, y lo último que pasó.
    private func diagCorto() -> String {
        let (l, u, p) = DetectorAlma.ajustes()
        candado.lock(); let n = tramos; candado.unlock()
        var partes = ["mic: " + formatoMic + textoGanancia(), "trozos: \(n)", "golpes: \(golpes)", textoDespertares + " (revisó \(revisionesRespaldo))", "detector: umbral \(u) puntaje \(p)" + (l == DetectorAlma.lineaDeFabrica ? "" : " «\(l)»"),
                      "modelo: " + DetectorAlma.modelo()]
        if !veredicto.isEmpty { partes.append("último: " + veredicto) }
        if !errorDiag.isEmpty { partes.append("error: " + errorDiag) }
        if !vozUsada.isEmpty { partes.append("voz: " + vozUsada) }
        partes.append("pasos: " + eventos.suffix(8).joined(separator: " | "))
        return String(partes.joined(separator: " · ").prefix(1800))
    }

    /// Manda al Hub los resúmenes que todavía no llegaron (si el Hub no tiene «calleUso», quedan en el teléfono).
    private func mandarUsos() {
        let lista = UserDefaults.standard.array(forKey: "calle_usos") as? [[String: Any]] ?? []
        let faltan = lista.filter { ($0["enviado"] as? Bool) != true }
        guard !faltan.isEmpty else { return }
        let usos = faltan.map { u -> [String: Any] in var x = u; x["enviado"] = nil; return x }
        llamarHub(["usos": usos], accion: "calleUso", timeout: 30) { j in
            guard (j?["ok"] as? Bool) == true else { return }
            let enviados = Set(faltan.compactMap { $0["inicio"] as? String })
            let todo = (UserDefaults.standard.array(forKey: "calle_usos") as? [[String: Any]] ?? []).map { u -> [String: Any] in
                var x = u; if let i = u["inicio"] as? String, enviados.contains(i) { x["enviado"] = true }; return x
            }
            UserDefaults.standard.set(todo, forKey: "calle_usos")
        }
    }

    private func emitir() { alEvento?(resumen) }
}

/// El detector de la palabra «Alma» en el teléfono: sherpa-onnx (Apache-2.0) con el modelo de palabras clave
/// zipformer zh-en 3M (2025-12-20; ~5 MB, va dentro de la app en Recursos «Calle»). El modelo escribe el inglés con sonidos
/// (fonemas ARPAbet): «Alma» se escribe «AE1 L M AH0», la combinación que mejor la oyó en voces en español de México (las
/// pruebas están en el PR). El umbral es bajo a propósito: deja pasar de más y el dictado del iPhone confirma.
/// Puntaje 15 (antes 8; 3-nov-2026): con el audio en trozos como llega del micrófono, sin fin de audio, el 8 oía 9 de 12
/// llamadas de prueba y el 15 oye 11 (los falsos pasan de 5 a 6 de 16, y esos los descarta el dictado).
final class DetectorAlma {
    static let nombre = "sherpa-onnx kws zipformer zh-en 3M 2025-12-20"
    static let encoder = "encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx"
    static let decoder = "decoder-epoch-13-avg-2-chunk-16-left-64.onnx"
    static let joiner = "joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx"
    static let lineaDeFabrica = "AE1 L M AH0 @ALMA"
    static let umbralDeFabrica: Float = 0.01
    static let puntajeDeFabrica: Float = 15.0
    static let archivos = [encoder, decoder, joiner, "tokens.txt"]
    /// Los umbrales de «Probar»: la fuerza con que se oyó «Alma» es el más alto que la detectó.
    static let escalones: [Float] = [0.5, 0.3, 0.15, 0.05]
    /// Por qué no cargó el detector la última vez (el mensaje que ve Juan).
    static var fallo = "No pude cargar el detector de «Alma»."

    /// ¿Vienen los archivos del modelo dentro de la app? Para el diagnóstico.
    static func modelo() -> String {
        guard let c = Bundle.main.url(forResource: "Calle", withExtension: nil) else { return "falta la carpeta Calle" }
        let fm = FileManager.default
        let faltan = archivos.filter { !fm.fileExists(atPath: c.appendingPathComponent($0).path) }
        if !faltan.isEmpty { return "faltan " + faltan.joined(separator: ", ") }
        let bytes = archivos.reduce(0) { $0 + (((try? fm.attributesOfItem(atPath: c.appendingPathComponent($1).path))?[.size] as? NSNumber)?.intValue ?? 0) }
        return String(format: "%d archivos, %.1f MB", archivos.count, Double(bytes) / 1_048_576)
    }

    /// Lo de fábrica, o lo que se calibró (ModoCalle.calibrar).
    static func ajustes() -> (String, Float, Float) {
        let d = UserDefaults.standard
        let l = d.string(forKey: "calle_kws_linea") ?? lineaDeFabrica
        let u = d.object(forKey: "calle_kws_umbral") != nil ? Float(d.double(forKey: "calle_kws_umbral")) : umbralDeFabrica
        let p = d.object(forKey: "calle_kws_puntaje") != nil ? Float(d.double(forKey: "calle_kws_puntaje")) : puntajeDeFabrica
        return (l, u, p)
    }

    private let kws: SherpaOnnxKeywordSpotterWrapper

    /// nil si faltan los archivos del modelo o la línea trae un sonido que el modelo no conoce (sherpa-onnx cerraría la app).
    init?(linea: String, umbral: Float, puntaje: Float) {
        guard let carpeta = Bundle.main.url(forResource: "Calle", withExtension: nil) else {
            DetectorAlma.fallo = "Falta el modelo del detector de «Alma» en esta versión de la app (no trae la carpeta Calle). Actualiza Alma desde TestFlight."
            return nil
        }
        let ruta: (String) -> String = { carpeta.appendingPathComponent($0).path }
        for n in DetectorAlma.archivos where !FileManager.default.fileExists(atPath: ruta(n)) {
            DetectorAlma.fallo = "Falta el modelo del detector de «Alma» (\(n)). Actualiza Alma desde TestFlight."
            return nil
        }
        guard let tokens = try? String(contentsOfFile: ruta("tokens.txt"), encoding: .utf8) else {
            DetectorAlma.fallo = "No pude leer el modelo del detector de «Alma» (tokens.txt)."; return nil
        }
        let conocidos = Set(tokens.split(whereSeparator: { $0.isNewline }).compactMap { $0.split(separator: " ").first.map(String.init) })
        let lineas = linea.split(whereSeparator: { $0.isNewline }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lineas.isEmpty else { DetectorAlma.fallo = "La línea de «Alma» está vacía: restablece la calibración."; return nil }
        for l in lineas {
            for w in l.split(separator: " ") where !(w.hasPrefix("@") || w.hasPrefix(":") || w.hasPrefix("#")) {
                guard conocidos.contains(String(w)) else {
                    DetectorAlma.fallo = "La línea de «Alma» calibrada trae «\(w)», un sonido que el modelo no conoce: restablece la calibración."
                    return nil
                }
            }
        }
        let texto = lineas.joined(separator: "\n")
        let transducer = sherpaOnnxOnlineTransducerModelConfig(encoder: ruta(DetectorAlma.encoder), decoder: ruta(DetectorAlma.decoder), joiner: ruta(DetectorAlma.joiner))
        let modelo = sherpaOnnxOnlineModelConfig(tokens: ruta("tokens.txt"), transducer: transducer, numThreads: 1)
        let rasgos = sherpaOnnxFeatureConfig(sampleRate: 16000, featureDim: 80)
        var config = sherpaOnnxKeywordSpotterConfig(featConfig: rasgos, modelConfig: modelo, keywordsFile: "", maxActivePaths: 4,
                                                    numTrailingBlanks: 1, keywordsScore: puntaje, keywordsThreshold: umbral,
                                                    keywordsBuf: texto, keywordsBufSize: texto.utf8.count)
        let k = SherpaOnnxKeywordSpotterWrapper(config: &config)
        guard k.spotter != nil, k.stream != nil else { DetectorAlma.fallo = "El detector de «Alma» no arrancó (sherpa-onnx no aceptó el modelo)."; return nil }
        kws = k
    }

    /// Audio a 16 kHz: ¿dijeron «Alma»?
    func oir(_ m: [Float]) -> Bool {
        kws.acceptWaveform(samples: m)
        var hallada = false
        while kws.isReady() {
            kws.decode()
            if !kws.getResult().keyword.isEmpty { kws.reset(); hallada = true }
        }
        return hallada
    }

    func reiniciar() { kws.reset() }
}

/// Niveles de las notificaciones, con dos selectores en Ajustes: «Notificaciones habladas» (hablado) y «Notificaciones del
/// teléfono» (telefono). Cada nivel incluye los anteriores:
///   0 Silencio · 1 Solo urgente · 2 Lo que pide algo de ti · 3 Todo (de fábrica).
/// Cada aviso del Hub (vozAvisos) trae `nivel`: 1 urgente · 2 accion · 3 aviso (sin nivel = 2).
/// Bajar el nivel dura un rato (1 h, 4 h o hasta mañana a las 7:00) y después vuelve solo a «Todo»: se revisa cada vez
/// que se lee (al abrir la app, en la vuelta de los avisos y al mostrar Ajustes), aunque la app se haya cerrado.
enum NivelAvisos {
    static let tipos = ["hablado", "telefono"]
    private static func clave(_ tipo: String) -> String { "aviso_nivel_" + tipo }

    static func nivel(_ tipo: String) -> Int {
        let d = UserDefaults.standard, k = clave(tipo)
        if let h = d.object(forKey: k + "_hasta") as? Date, h <= Date() { d.removeObject(forKey: k); d.removeObject(forKey: k + "_hasta") }
        return (d.object(forKey: k) as? Int) ?? 3
    }

    static func hasta(_ tipo: String) -> Date? {
        _ = nivel(tipo)
        return UserDefaults.standard.object(forKey: clave(tipo) + "_hasta") as? Date
    }

    /// `por`: "1h" · "4h" (de fábrica) · "manana" (hasta las 7:00). Nivel 3 = Todo, sin plazo.
    static func poner(_ tipo: String, nivel n: Int, por: String) {
        guard tipos.contains(tipo) else { return }
        let d = UserDefaults.standard, k = clave(tipo), v = max(0, min(3, n))
        if v >= 3 { d.removeObject(forKey: k); d.removeObject(forKey: k + "_hasta"); return }
        d.set(v, forKey: k); d.set(fin(por), forKey: k + "_hasta")
    }

    static func fin(_ por: String, desde: Date = Date()) -> Date {
        switch por {
        case "1h": return desde.addingTimeInterval(3600)
        case "manana":
            return Calendar.current.nextDate(after: desde, matching: DateComponents(hour: 7, minute: 0), matchingPolicy: .nextTime) ?? desde.addingTimeInterval(4 * 3600)
        default: return desde.addingTimeInterval(4 * 3600)
        }
    }

    /// El nivel de un aviso del Hub: 1 urgente · 2 accion · 3 aviso (sin nivel = 2).
    static func deAviso(_ a: [String: Any]) -> Int {
        if let n = a["nivel"] as? NSNumber { return max(1, min(3, n.intValue)) }
        switch (a["nivel"] as? String ?? "").lowercased() {
        case "1", "urgente": return 1
        case "3", "aviso": return 3
        default: return 2
        }
    }

    static var resumen: [String: Any] {
        var r: [String: Any] = ["tipo": "avisos"]
        for t in tipos {
            var x: [String: Any] = ["nivel": nivel(t)]
            if let h = hasta(t) { x["hasta"] = Int(h.timeIntervalSince1970 * 1000); x["minutos"] = max(0, Int((h.timeIntervalSinceNow / 60).rounded(.up))) }
            r[t] = x
        }
        return r
    }
}

/// La voz del iPhone, solo de respaldo (sin internet o sin audio del Hub). Nunca la de por defecto: con
/// `AVSpeechSynthesisVoice(language: "es-MX")` iOS da la que esté puesta en el teléfono, y en el de Juan era de hombre
/// (3-nov-2026). Se elige a mano: de mujer, en español (es-MX, luego es-US, luego es-ES), la de mejor calidad que haya
/// (premium, mejorada, normal), sin voces de juguete. Si no hay ninguna marcada como de mujer, Paulina o Mónica por nombre.
enum VozIphone {
    static let elegida: AVSpeechSynthesisVoice? = elegir()
    /// Para el diagnóstico: «Paulina · es-MX · mujer · mejorada».
    static var nombre: String {
        guard let v = elegida else { return "la de por defecto (no encontré una voz de mujer en español)" }
        let calidad: String
        switch v.quality {
        case .premium: calidad = "premium"
        case .enhanced: calidad = "mejorada"
        default: calidad = "normal"
        }
        return v.name + " · " + v.language + " · " + (v.gender == .female ? "mujer" : "elegida por nombre") + " · " + calidad
    }

    private static let idiomas = ["es-MX", "es-US", "es-ES"]
    private static let deRespaldo = ["com.apple.voice.premium.es-MX.Paulina", "com.apple.voice.enhanced.es-MX.Paulina",
                                     "com.apple.voice.compact.es-MX.Paulina", "com.apple.ttsbundle.Paulina-compact",
                                     "com.apple.voice.compact.es-ES.Monica", "com.apple.ttsbundle.Monica-compact"]

    private static func elegir() -> AVSpeechSynthesisVoice? {
        func puntos(_ v: AVSpeechSynthesisVoice) -> Int? {
            guard v.gender == .female, let i = idiomas.firstIndex(of: v.language) else { return nil }
            if v.voiceTraits.contains(.isNoveltyVoice) || v.voiceTraits.contains(.isPersonalVoice) { return nil }
            let calidad: Int
            switch v.quality {
            case .premium: calidad = 0
            case .enhanced: calidad = 1
            default: calidad = 2
            }
            // El acento latino (México, EE. UU.) antes que el de España; dentro de cada uno, la mejor calidad.
            return (i == 2 ? 100 : 0) + calidad * 10 + i
        }
        let todas = AVSpeechSynthesisVoice.speechVoices()
        if let v = todas.compactMap({ v in puntos(v).map { (v, $0) } }).min(by: { $0.1 < $1.1 })?.0 { return v }
        for id in deRespaldo { if let v = AVSpeechSynthesisVoice(identifier: id) { return v } }
        return nil
    }
}
