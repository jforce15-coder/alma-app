import AVFoundation
import AudioToolbox
import Foundation
import MediaPlayer
import Security
import UIKit
import UserNotifications

/// Alma por voz dentro de la app, también con el teléfono bloqueado.
/// · «Alma con el anillo» encendido: la app queda lista en segundo plano como la app de audio del teléfono
///   (un audio en silencio la mantiene viva y en «Reproduciendo»). El anillo en modo Music manda su toque como el botón
///   de unos audífonos → doble toque: Alma escucha y responde · otro doble toque: pausa · otro: retoma.
/// · La voz es el mismo agente de ElevenLabs del Hub (websocket con la URL firmada del Hub). La ficha (quién eres, saludo y
///   contexto reciente) se pide al Hub con tu sesión, igual que la voz de las web apps, y la llamada se liga a tu chat.
/// · Más rápido: la ficha y la URL firmada quedan pedidas de antemano (cada 9 min); al doble toque suena la señal
///   enseguida y lo que dices se guarda mientras conecta.
/// · Pausa: dos toques mientras hablan pausan (Alma espera). Otros dos la retoman. Si no se retoma en 25 s, lo dicho se
///   toma como enviado: Alma responde y la conversación se cierra sola.
/// · Si un pedido tarda más de lo que la llamada aguanta, Alma lo sigue en segundo plano y cuelga (end_call). Al colgar así,
///   la app queda lista para el anillo mientras Alma trabaja: dos toques y vuelves a hablar (y queda «Alma con el anillo»).
/// · Avisos: cada 45 s pregunta al Hub si terminó algo que necesita algo de ti y lo muestra como notificación. Alma no lo
///   dice sola: al volver a hablarle empieza por el tema por retomar más importante (lo elige el Hub).
final class VozNativa: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    static let shared = VozNativa()

    enum Estado: String { case apagada, lista, conectando, hablando }
    @Published private(set) var estado: Estado = .apagada { didSet { avisar(); if estado != .hablando { nivel = 0 }; DispatchQueue.main.async { EscuchaInicio.shared.evaluar() } } }
    /// Para la pantalla de la llamada: cuánto suena la voz (0…1), quién habla y lo último que se dijo.
    @Published private(set) var nivel: CGFloat = 0 { didSet { nivelAPagina() } }
    @Published private(set) var almaHabla = false
    struct Linea: Identifiable { let id: Int; let alma: Bool; let texto: String }
    @Published private(set) var lineas: [Linea] = []
    private var campanas: [String: AVAudioPlayer] = [:]
    private var finHabla: DispatchWorkItem?
    private var contador = 0
    private func linea(_ alma: Bool, _ t: String) { contador += 1; lineas = Array((lineas + [Linea(id: contador, alma: alma, texto: t)]).suffix(6)) }
    var alEvento: (([String: Any]) -> Void)?

    private var modoAnillo: Bool { UserDefaults.standard.bool(forKey: "voz_modo_anillo") }
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var formatoSalida = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    private let formatoEntrada = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    private var convertidor: AVAudioConverter?
    private var ws: URLSessionWebSocketTask?
    private var sesionURL: URLSession?
    private var silencio: AVAudioPlayer?
    private var ultimoToque = Date.distantPast
    private var motorListo = false
    private var formatoMono: AVAudioFormat?
    private var sinEco = false
    /// Hasta cuándo suena la voz de Alma (lo que ya está en cola en el parlante, no solo lo que llegó).
    private var finVozAlma = Date.distantPast
    private var vozEnviada = 0.0          // segundos de tu voz mandados a Alma en este tramo
    private var ultimaVoz = Date.distantPast
    private var vigia: Timer?   // si la cancelación de eco falló una vez, ya no se intenta
    private var sono = false
    // ficha pedida de antemano (la URL firmada de ElevenLabs dura ~15 min; se usa si tiene menos de 9)
    private var fichaLista: (j: [String: Any], t: Date)?
    private var pidiendoFicha = false
    private var precarga: Timer?
    private var colaVoz: [String] = []      // lo que dices mientras conecta
    /// ¿Ya se mandó conversation_initiation_client_data? Antes de eso no va ningún audio al socket (ElevenLabs espera la
    /// ficha primero): tu voz se guarda en colaVoz y se manda justo después (el saludo se decide hasta 1.4 s tarde).
    private var inicioEnviado = false
    /// Lo que se quiso mandar antes de la ficha (InicioVoz): sale en orden justo después de ella.
    private var antesDeFicha: [[String: Any]] = []
    // pausa: Alma espera; si no se retoma en 25 s, responde a lo dicho y se cierra
    @Published private(set) var pausada = false
    private var pausaT: DispatchWorkItem?
    private var cerrarTrasRespuesta = false
    private var desdeCierre = Date.distantPast
    private var ultimoAudioAlma = Date.distantPast
    // avisos al oído
    private var avisosT: Timer?
    /// Lista para el anillo «un rato» sin tener el modo anillo: mientras Alma trabaja en segundo plano o hay temas por retomar.
    private var unRato = false
    /// ¿Se queda lista «un rato» sin el modo anillo? Apagado: tomaría el audio que no se mezcla con el anillo apagado.
    static let listaUnRato = false
    private var trabajando = 0, porRetomar = 0
    private var ultimaNovedad = Date.distantPast
    /// La conversación la abrió la roca del inicio (no el anillo): Alma saluda y no lleva las reglas del modo anillo.
    private var desdePantalla = false
    /// Modo conferencia (Conferencia.swift): la llamada la abrió alguien diciendo «Alma, …» en una reunión. Con la señal, sin
    /// saludo; lo último que se dijo va de contexto y lo que le pidieron, como primer mensaje.
    private var conferencia: String?
    /// Llamada larga: pasados unos minutos, al terminar de responder Alma se despide y la llamada pasa al modo conferencia
    /// (escucha en silencio hasta que la vuelvan a llamar con «Alma»).
    private var aConferencia = false, relojLargo: Timer?, vigiaLargo: Timer?, ultimaActividad = Date()
    /// Alma espera una herramienta (la secretaria tarda de 15 a 57 s): ese silencio no es una pausa larga.
    private var herramienta = false {
        didSet { if herramienta && !oldValue { herramientaDesde = Date() } else if !herramienta && oldValue { herramientaDesde = nil; finHerramienta = Date() } }
    }
    private var herramientaDesde: Date?, finHerramienta = Date.distantPast
    /// Modo conferencia: la secretaria espera hasta 45 s (el Hub lo sabe por vozWebVincular). Si una herramienta pasa de
    /// `tras` segundos, la app dice una vez «Sigo en eso, ya casi» con la voz de Alma (el audio PCM llega del Hub al vincular,
    /// en el mismo formato de la llamada). Sin audio no se dice nada: queda el tecleo de siempre.
    private var espera: (pcm: Data, hz: Double, tras: Double)?
    private var relojEspera: Timer?
    /// T: desde cuándo una llamada «larga» deja de rendir (lo calcula el Hub con los datos de las llamadas y lo manda en la
    /// ficha como `conferencia_tras`, en segundos). Pasado T la llamada sigue igual; solo cambia la primera pausa larga.
    private var segundosLargo: Double = 240
    /// Las despedidas para la pausa larga, en vez de «¿sigues ahí?»; rotan para no repetir siempre la misma.
    static let despedidas = ["Estaré aquí; si necesitas algo más, solo llámame.", "Aquí sigo. Cuando me necesites, solo di «Alma».",
                             "Te dejo seguir; si se te ofrece algo, me llamas.", "Quedo atenta; dime «Alma» cuando quieras.",
                             "Sigo cerca. Si necesitas algo, solo llámame."]
    private func despedida() -> String {
        let i = UserDefaults.standard.integer(forKey: "voz_despedida_i"); UserDefaults.standard.set(i + 1, forKey: "voz_despedida_i")
        return VozNativa.despedidas[i % VozNativa.despedidas.count]
    }
    /// El saludo al abrirla con tres toques a la roca del navegador (hablarSobrePantalla), pedido de Juan: «Hola, ahora lo veo».
    static let saludoPantalla = "Hola, ahora lo veo."
    /// Saludo variado (#410, decisión de Juan): una frase natural y completa que cambia cada vez, nunca la misma dos veces
    /// seguidas. Vienen en la ficha del Hub (`saludos`, con su nombre); si no, estas.
    static let saludosBase = ["Hola, cuéntame.", "Aquí estoy, ¿qué necesitas?", "Dime, ¿en qué te ayudo?", "Hola, ¿cómo vamos?",
                              "Te escucho.", "Hola, aquí contigo. ¿Qué se te ofrece?", "¿Qué tal? Cuéntame.", "Aquí estoy. ¿Por dónde empezamos?"]
    static func saludoVariado(_ ficha: [String: Any]) -> String {
        let deFicha = ((ficha["saludos"] as? [Any]) ?? []).compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let lista = deFicha.isEmpty ? saludosBase : deFicha
        let d = UserDefaults.standard, ultimo = d.string(forKey: "voz_saludo_ultimo") ?? ""
        let opciones = lista.count > 1 ? lista.filter { $0 != ultimo } : lista
        let s = opciones.randomElement() ?? lista[0]
        d.set(s, forKey: "voz_saludo_ultimo")
        return s
    }
    private var textoInicial: String?
    private var alOir = false
    /// Micrófono en mudo (el botón del micrófono): no se manda nada de lo que oyes.
    private var mudo = false
    private var nivelT = Date.distantPast
    /// Nivel de la voz de Alma en ventanas de 50 ms, con la hora en que suena cada una (la roca late con lo que se oye ahora).
    private var ventanasAlma: [(inicio: Date, nivel: CGFloat)] = []
    private var relojAlma: Timer?
    private var inicioLlamada = Date.distantPast
    /// Cuándo Alma quedó conectada: un toque que llega justo al conectar (el mismo gesto, o iOS al tomar el audio) no la pausa.
    private var conectadaDesde = Date.distantPast
    /// Cuánto llevas hablando con la conversación en pausa: si hablas, Alma vuelve a escucharte sola.
    private var vozEnPausa = 0.0
    private var ultimoSonido: [String: Date] = [:]
    /// La llamada la abre el Modo calle (ModoCalle.swift) con el teléfono bloqueado: el micrófono del Modo calle acaba de
    /// soltarse y la sesión sigue activa, así que se intenta abrir el de la llamada aunque la app esté en segundo plano.
    var desdeCalle = false
    /// Sueño del Modo calle (SuenoCalle.swift): en una llamada que abrió el Modo calle, la app cuelga sola tras un silencio de
    /// Juan, si dice «espera» o «es todo», a los 45 s sin que Alma hable o si algo corta el audio. Los segundos vienen en la
    /// ficha del Hub (calle_silencio_s, calle_tope_s). Las llamadas fuera del Modo calle no cambian.
    private var vigiaCalle: Timer?, motivoCalle: SuenoCalle.Motivo?
    private var calleSilencio = SuenoCalle.silencioDeFabrica, calleTope = SuenoCalle.topeDeFabrica
    private var vozJuanCalle = Date.distantPast, sonidoCalle = Date.distantPast
    /// Cómo terminó la última llamada (el Modo calle lo suma a su uso): segundos conectada a ElevenLabs y si colgó el sueño.
    var ultimaLlamada: (seg: Double, motivo: SuenoCalle.Motivo?) = (0, nil)
    /// Tres toques a la roca del navegador (hablarSobrePantalla): la página que se ve («título» (dirección)). La lectura de la
    /// captura llega después; si la llamada aún conecta, espera aquí y se manda al conectar.
    private var pantalla: String?
    private var vistaPendiente: String?
    /// «Mostrar en el chat» (herramienta de cliente mostrar_en_chat): lo que Alma pone en pantalla durante la llamada.
    /// ContentView abre el chat con esto y la llamada sigue; al cerrar ese chat se cuelga y la app vuelve al inicio.
    struct Mostrado: Equatable { let id: Int; let titulo: String; let contenido: String }
    @Published private(set) var mostrado: Mostrado?
    /// Tarjeta de la llamada (#446 T2, TarjetaLlamada.swift): lo que el Hub armó con lo que la secretaria trajo (una reserva,
    /// una conversación o un apartamento). La pintan LlamadaVista y la roca del inicio (AlmaVoz.evento «tarjeta»).
    @Published private(set) var tarjeta: TarjetaVoz?
    @Published private(set) var tarjetaVista: ReglasTarjeta.Vista = .nada
    private var reglasTarjeta = ReglasTarjeta()
    private var relojTarjeta: Timer?
    /// La conversación de ElevenLabs de esta llamada (para pedir su tarjeta y decir si Juan ve la pantalla).
    private var idLlamada: String?
    private var avisoPantalla: [NSObjectProtocol] = []
    /// Medidor de personalidad (#410): en qué nivel de Modo Weebo va Alma en esta llamada (lo cuenta ella con la herramienta
    /// de cliente nivel_weebo) y cuánto se adapta a Juan (viene en la ficha del Hub). Solo con el administrador principal.
    @Published private(set) var weebo: Int?
    /// +1 subió · −1 bajó · 0 sin cambio reciente (la flecha ▲/▼ se ve unos segundos).
    @Published private(set) var weeboCambio = 0
    @Published private(set) var adaptacion: Int?
    private var adaptTope = 60, weeboModo = "auto"
    private var flechaT: DispatchWorkItem?
    /// Saludo variado: cuánto de tu voz se oyó mientras conectaba (si ya hablabas, Alma no saluda y escucha).
    private var vozAlConectar = 0.0
    /// La señal de la llamada (alma-inicio) suena fuerte ~1 s: lo que el micrófono oye en ese rato no es Juan.
    static let finSenal = 1.0
    /// Desde el toque hasta decidir si Alma saluda: la señal más 0.4 s para ver si Juan ya empezó a hablar.
    static let ventanaSaludo = 1.4

    // MARK: - Lo que pide la página

    /// Datos para pedir la ficha al Hub: dirección del Apps Script, llave de la app y la sesión firmada.
    func configurar(url: String, token: String, sesion: String) {
        Llave.guardar("voz_url", url); Llave.guardar("voz_token", token); Llave.guardar("voz_sesion", sesion)
    }

    func ponerModoAnillo(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "voz_modo_anillo")
        if on {
            // El permiso del micrófono se pide ahora, con la app abierta: con el teléfono bloqueado iOS no puede preguntar.
            AVAudioSession.sharedInstance().requestRecordPermission { _ in }
            prepararMandos(); quedarLista()
        } else { terminar(); apagar() }
    }

    func arrancarSiHaceFalta() {
        let d = UserDefaults.standard
        if d.bool(forKey: "voz_abierta") {   // la app se cerró a media conversación (iOS la volvió a abrir por el anillo)
            d.set("Alma se cerró sola en el paso: " + (d.string(forKey: "voz_paso") ?? "?"), forKey: "voz_ultimo_error"); d.set(false, forKey: "voz_abierta")
        }
        prepararMandos()
        UNUserNotificationCenter.current().delegate = Notificaciones.shared; Notificaciones.shared.registrarCategorias()
        if modoAnillo { quedarLista() }
        empezarAvisos()
    }

    /// Lo último que hizo la voz (se ve en Ajustes y ayuda a saber dónde se queda).
    private func paso(_ t: String) {
        let d = UserDefaults.standard; d.set(t, forKey: "voz_paso")
        var lista = d.stringArray(forKey: "voz_pasos") ?? []
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        lista.append(f.string(from: Date()) + " " + t); d.set(Array(lista.suffix(14)), forKey: "voz_pasos")
        emitir(["tipo": "paso", "texto": t])
    }

    /// Doble toque del anillo: enciende o apaga el modo conferencia (ya no abre una llamada propia). Si Alma está
    /// hablando (por ejemplo, la despertaron en la reunión), el doble toque sigue pausando o retomando, como siempre.
    private var ultimoCambioConf = Date.distantPast
    private func toqueAnillo() {
        if estado == .hablando || estado == .conectando { alternar(); return }
        // Un mismo gesto puede llegar dos veces (o iOS manda «reproducir» al tomar el audio): no se prende y apaga de golpe.
        if Date().timeIntervalSince(ultimoCambioConf) < 3 { paso("Toque repetido ignorado: el modo conferencia acaba de cambiar"); return }
        ultimoCambioConf = Date()
        let c = Conferencia.shared
        paso(c.activa ? "El anillo apagó el modo conferencia" : "El anillo encendió el modo conferencia")
        c.poner(!c.activa)
    }
    /// ¿El micrófono queda listo para el anillo? Al apagar el modo conferencia no se suelta el audio (con el teléfono
    /// bloqueado iOS no deja volver a tomarlo) y Alma queda lista otra vez.
    var anilloListo: Bool { modoAnillo || unRato }
    func listaTrasConferencia() { if modoAnillo || unRato { quedarLista() } }

    /// Un solo micrófono a la vez. Con «Alma con el anillo» (o lista «un rato») el micrófono de la voz queda abierto, con
    /// cancelación de eco; si el Modo Inicio o el modo conferencia abrieran otro, iOS deja mudo a uno de los dos y Alma no
    /// oye «Alma». Por eso, mientras está lista, la voz le pasa lo que oye a quien escucha (EscuchaInicio o Conferencia).
    private let candadoOyente = NSLock()
    private var oyente: (id: String, f: (AVAudioPCMBuffer) -> Void)?
    func ponerOyente(_ id: String, _ f: @escaping (AVAudioPCMBuffer) -> Void) { candadoOyente.lock(); oyente = (id, f); candadoOyente.unlock() }
    func quitarOyente(_ id: String) { candadoOyente.lock(); if oyente?.id == id { oyente = nil }; candadoOyente.unlock() }
    /// ¿El micrófono de la voz está abierto y libre (sin llamada)? Entonces se escucha por él.
    var microfonoListo: Bool { estado == .lista && engine.isRunning && formatoMono != nil }
    var formatoOyente: AVAudioFormat? { formatoMono }
    /// Lo último de la llamada (para que el modo conferencia sepa de qué se hablaba).
    var charlaReciente: [String] { lineas.map { ($0.alma ? "Alma: " : "Juan: ") + $0.texto } }
    private func darAOyente(_ buf: AVAudioPCMBuffer) {
        candadoOyente.lock(); let o = oyente; candadoOyente.unlock()
        guard let o, let mf = formatoMono, let src = buf.floatChannelData,
              let mono = AVAudioPCMBuffer(pcmFormat: mf, frameCapacity: buf.frameLength), let dst = mono.floatChannelData else { return }
        mono.frameLength = buf.frameLength
        dst[0].update(from: src[0], count: Int(buf.frameLength))   // primer canal, como lo que se manda a Alma
        o.f(mono)
    }

    /// Botón de la página (y el anillo durante una llamada): habla o pausa.
    func alternar() {
        // Un mismo gesto del anillo puede llegar dos veces: como botón de audífonos (aquí) y como toque en la pantalla (la
        // roca de la página abre la voz). En los primeros segundos de una llamada, otro toque no la cuelga ni la pausa.
        if (estado == .hablando || estado == .conectando) && (Date().timeIntervalSince(inicioLlamada) < 4 || Date().timeIntervalSince(conectadaDesde) < 4) {
            paso("Toque repetido ignorado: la llamada acaba de empezar"); return
        }
        switch estado {
        case .hablando: if cerrarTrasRespuesta { terminar() } else if pausada { reanudar() } else { pausar() }
        case .conectando: terminar()
        case .lista, .apagada: desdePantalla = false; hablar()
        }
    }

    /// La roca del inicio (sa-nav en la página): la misma conversación que el anillo, abierta desde la pantalla.
    func hablarDesdePantalla() {
        guard estado == .lista || estado == .apagada else { avisar(); return }
        desdePantalla = true; hablar()
    }
    /// «Inicio con escucha activa» (EscuchaInicio.swift): dijiste «Alma, …» en el inicio. Sin saludo: lo que pediste es el
    /// primer mensaje y Alma responde a eso.
    func hablarAlOir(_ texto: String) {
        guard estado == .lista || estado == .apagada else { return }
        desdePantalla = true; alOir = true; textoInicial = texto; hablar()
    }
    /// Tres toques a la roca del navegador: Alma solo por voz (sin el chat), sobre lo que se ve. La página (título y dirección)
    /// va en la ficha de la llamada; la captura la lee el Hub (almaFoto, la misma del chat) y llega como contexto en unos
    /// segundos. Con la llamada ya abierta, la captura nueva va como contexto («mira esto ahora»).
    func hablarSobrePantalla(captura: String?, titulo: String, direccion: String) {
        let donde = titulo.isEmpty ? direccion : "«" + titulo + "»" + (direccion.isEmpty ? "" : " (" + direccion + ")")
        if estado == .hablando || estado == .conectando {
            if let captura { describir(captura, aviso: "Juan te muestra otra pantalla: " + donde + ".") }
            return
        }
        // Sin el permiso del micrófono (nunca se preguntó), se pide ahora con la app abierta y después se llama.
        if AVAudioSession.sharedInstance().recordPermission == .undetermined {
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] ok in
                DispatchQueue.main.async { if ok { self?.hablarSobrePantalla(captura: captura, titulo: titulo, direccion: direccion) } }
            }
            return
        }
        desdePantalla = true; pantalla = donde
        hablar()
        guard estado == .conectando else { pantalla = nil; return }
        if let captura { describir(captura, aviso: nil) }
    }
    /// ¿Ya tiene cómo pedir la ficha al Hub? (la guarda el inicio la primera vez que se abre la app con sesión)
    var puedeHablar: Bool { Llave.leer("voz_url") != nil && Llave.leer("voz_token") != nil && Llave.leer("voz_sesion") != nil }
    func hablarDesdeConferencia(contexto: String, texto: String) {
        guard estado == .lista || estado == .apagada else { return }
        desdePantalla = true; conferencia = contexto; textoInicial = texto; hablar()
    }
    /// Lo que escribes en el chat de la roca, durante la conversación.
    func escribir(_ t: String) {
        guard estado == .hablando, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        mandar(["type": "user_message", "text": t])
    }
    private var enChat = false
    func silenciar(_ on: Bool) { mudo = on; player.volume = (on || enChat) ? 0 : 1 }
    /// Modo chat de la roca: Alma sigue oyendo (el micrófono sigue) pero no suena; responde por escrito en la página.
    func sinVoz(_ on: Bool) { enChat = on; player.volume = (on || mudo) ? 0 : 1 }

    /// Cuánto suena la voz, para que la roca de la página lata con ella (unas 10 veces por segundo).
    private func nivelAPagina() {
        guard estado == .hablando, Date().timeIntervalSince(nivelT) > 0.045 else { return }
        nivelT = Date(); emitir(["tipo": "nivel", "v": Double(nivel), "alma": almaHabla])
    }

    /// «Terminar» en la pantalla: cierra la conversación (el doble toque, en cambio, pausa).
    func colgar() { if estado == .hablando || estado == .conectando { terminar() } }

    var resumen: [String: Any] {
        var r: [String: Any] = ["tipo": "estado", "estado": estado.rawValue, "modoAnillo": modoAnillo, "pausada": pausada, "ultimoError": UserDefaults.standard.string(forKey: "voz_ultimo_error") ?? "",
                                "pasos": UserDefaults.standard.stringArray(forKey: "voz_pasos") ?? [],
                                "microfono": AVAudioSession.sharedInstance().recordPermission == .granted ? "si" : AVAudioSession.sharedInstance().recordPermission == .denied ? "no" : "sin preguntar"]
        // la página que se abre a media llamada (o se recarga) pinta los chips con esto
        if estado == .hablando || estado == .conectando, let p = personalidad { r["personalidad"] = p }
        if estado == .hablando || estado == .conectando, let t = tarjeta, tarjetaVista != .nada { r["tarjeta"] = t.crudo; r["tarjetaVista"] = tarjetaVista.rawValue }
        return r
    }
    /// Lo que se cuenta a la página: Ajustes → Personalidad de Alma muestra «en la llamada: 2» (los chips en la llamada ya no
    /// existen: Juan, 6-nov-2026). nil = no hay medidores (no es el principal).
    private var personalidad: [String: Any]? {
        guard weebo != nil || adaptacion != nil else { return nil }
        return ["weebo": weebo.map { $0 as Any } ?? NSNull(), "cambio": weeboCambio, "adapt": adaptacion.map { $0 as Any } ?? NSNull(),
                "tope": adaptTope, "modo": weeboModo]
    }
    private func emitirPersonalidad() {
        guard var p = personalidad else { return }
        p["tipo"] = "personalidad"; emitir(p)
    }
    /// Nuevo nivel de Modo Weebo: la flecha ▲/▼ se ve unos segundos y se va.
    private func ponerWeebo(_ n: Int) {
        if let w = weebo, w != n { weeboCambio = n > w ? 1 : -1 } else if weebo == nil { weeboCambio = 0 }
        weebo = n
        flechaT?.cancel()
        if weeboCambio != 0 {
            let w = DispatchWorkItem { [weak self] in self?.weeboCambio = 0 }
            flechaT = w; DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: w)
        }
    }
    /// Juan cambió el Modo Weebo en la hoja de la llamada (alma/inicio.html): Alma se entera ya, sin esperar a otra llamada.
    func ajustarWeebo(modo: String, nivel: Int) {
        guard estado == .hablando || estado == .conectando else { return }
        let n = max(0, min(3, nivel))
        weeboModo = modo == "fijo" ? "fijo" : "auto"
        if weeboModo == "fijo" { ponerWeebo(n) }
        paso(weeboModo == "fijo" ? "Juan fijó el Modo Weebo en \(n)" : "Juan dejó el Modo Weebo en automático")
        guard estado == .hablando else { return }
        mandar(["type": "contextual_update", "text": weeboModo == "fijo"
            ? "MODO WEEBO FIJO: Juan acaba de fijar tu Modo Weebo en el nivel \(n). Úsalo desde ahora (con un problema o una urgencia, vuelve a tu centro). No lo comentes."
            : "MODO WEEBO AUTOMÁTICO: Juan dejó tu Modo Weebo en automático: vuelve a medirlo tú. No lo comentes."])
    }
    /// La sesión de la llamada (y la del anillo): no se mezcla, así que pausa la música o los videos de otras apps.
    static let opciones: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
    /// La sesión para solo escuchar (Modo Inicio, conferencia, Mejora): se mezcla con las otras apps (TikTok, Facebook, la voz
    /// de Claude siguen sonando). Sin `.allowBluetooth` (manos libres): así los audífonos siguen en alta calidad para la otra
    /// app y se escucha por el micrófono del teléfono.
    static let opcionesEscucha: AVAudioSession.CategoryOptions = [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP]

    /// Abre el audio para solo escuchar, sin quitarle el sonido a las otras apps. Si quedó la sesión de la llamada (que no se
    /// mezcla), primero se suelta avisando a las otras apps, para que retomen solas lo que sonaba.
    /// Con «Alma con el anillo» (o lista «un rato») no se toca: esa sesión tiene que seguir para el anillo con el teléfono bloqueado.
    static func sesionEscucha() {
        let s = AVAudioSession.sharedInstance()
        let v = VozNativa.shared
        if v.anilloListo || v.estado == .hablando || v.estado == .conectando {
            try? s.setCategory(.playAndRecord, mode: .default, options: opciones)
            try? s.setActive(true); return
        }
        if s.category == .playAndRecord && !s.categoryOptions.contains(.mixWithOthers) {
            try? s.setActive(false, options: .notifyOthersOnDeactivation)
        }
        try? s.setCategory(.playAndRecord, mode: .default, options: opcionesEscucha)
        try? s.setActive(true)
    }

    /// Suelta el audio cuando ya nadie lo usa (ni llamada, ni anillo, ni Modo Inicio, ni conferencia, ni Mejora), avisando a las
    /// otras apps para que sigan con lo suyo. Espera un momento y vuelve a mirar: así no corta un sonido que está terminando ni
    /// suelta el audio justo cuando otro modo lo va a tomar.
    static func soltarAudio() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            let v = VozNativa.shared
            guard !v.anilloListo, v.estado == .apagada, !Conferencia.shared.activa, !EscuchaInicio.shared.escuchando,
                  !ModoCalle.shared.ocupaMicrofono, MejoraCampo.shared.estado == .apagada, !v.campanas.values.contains(where: { $0.isPlaying }) else { return }
            let s = AVAudioSession.sharedInstance()
            try? s.setActive(false, options: .notifyOthersOnDeactivation)
            // Queda la sesión que se mezcla: un sonido suelto (la señal de la voz de las páginas) ya no pausa a las otras apps.
            try? s.setCategory(.playAndRecord, mode: .default, options: opcionesEscucha)
        }
    }

    // MARK: - Estar lista (audio en silencio + mandos de la pantalla de bloqueo)

    private func quedarLista() {
        guard estado != .hablando, estado != .conectando else { return }
        do {
            let s = AVAudioSession.sharedInstance()
            // Desde que queda lista ya es «hablar y escuchar»: con la pantalla bloqueada iOS no deja cambiar a micrófono después.
            try s.setCategory(.playAndRecord, mode: .default, options: VozNativa.opciones)
            try s.setActive(true)
        } catch {}
        if silencio == nil, let wav = VozNativa.wavSilencio() { silencio = try? AVAudioPlayer(data: wav); silencio?.numberOfLoops = -1; silencio?.volume = 0.01 }
        silencio?.play()
        estado = .lista
        encenderMicrofono()
        precargarSiToca()
        if precarga == nil { precarga = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.precargarSiToca() } }
        empezarAvisos()
    }

    /// iOS no deja *empezar* a usar el micrófono con el teléfono bloqueado; sí deja seguir usándolo.
    /// Por eso, con «Alma con el anillo», el micrófono queda abierto desde que la app está a la vista (no se manda nada
    /// hasta el doble toque) y sigue listo al bloquear.
    private func encenderMicrofono() {
        if engine.isRunning { infoBloqueo("Dos toques del anillo: modo conferencia"); return }
        guard UIApplication.shared.applicationState != .background else {
            paso("Esperando a que abras Alma para dejar el micrófono listo")
            infoBloqueo("Abre Alma una vez para dejarla lista"); return
        }
        do { try prepararMotor(); paso("Micrófono listo para el anillo"); infoBloqueo("Dos toques del anillo: modo conferencia") }
        catch { paso("No pude dejar listo el micrófono (\((error as NSError).code))"); infoBloqueo("Abre Alma para dejarla lista") }
    }

    private func apagar() {
        precarga?.invalidate(); precarga = nil; fichaLista = nil; unRato = false
        silencio?.stop()
        engine.inputNode.removeTap(onBus: 0); player.stop(); if engine.isRunning { engine.stop() }
        // Sin anillo no queda nada que no se mezcle: se suelta el audio en cuanto nadie más escucha (las otras apps siguen).
        VozNativa.soltarAudio()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        estado = .apagada
    }

    private var mandosListos = false
    private func prepararMandos() {
        guard !mandosListos else { return }; mandosListos = true
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let t = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, t == AVAudioSession.InterruptionType.began.rawValue else { return }
            guard self.estado == .hablando || self.estado == .conectando else { return }
            // Modo calle: otra llamada o Siri cortan sin error ni reintento; el Modo calle vuelve a esperar cuando regrese el micrófono.
            if self.desdeCalle { self.colgarCalle(.corte) } else { self.fallo("Otra app o una llamada tomó el audio.") }
        }
        // Al abrir la app (o al volver a ella) el micrófono queda listo otra vez.
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.buscarAvisos()
            self.precargarSiToca()   // al abrir la app ya se pide la ficha: si la llaman, no espera al Hub
            guard self.modoAnillo || self.unRato, self.estado == .lista || self.estado == .apagada else { return }
            self.quedarLista()
        }
        // Si iOS reinicia el audio (cambio de audífonos, por ejemplo), se vuelve a encender.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, self.modoAnillo else { return }
            self.paso("iOS reacomodó el audio" + (self.engine.isRunning ? "" : " y apagó el micrófono"))
            self.revivirMicrofono()
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, self.estado == .hablando, let r = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt else { return }
            let salida = AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? "?"
            self.paso("Cambió la salida de audio (motivo \(r)) → \(salida)")
            // Modo calle: se desconectaron los audífonos: cuelga sin reintentar y el Modo calle vuelve a esperar «Alma».
            if self.desdeCalle && r == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self.colgarCalle(.corte) }
        }
        let c = MPRemoteCommandCenter.shared()
        // El anillo (modo Music) llega como reproducir/pausar. Un doble toque puede llegar como dos avisos: se cuentan como uno.
        let toque: (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus = { [weak self] _ in
            guard let self else { return .commandFailed }
            if Date().timeIntervalSince(self.ultimoToque) < 0.9 { return .success }
            self.ultimoToque = Date()
            DispatchQueue.main.async {
                // Lista «un rato» (sin el modo anillo): el toque del anillo enciende «Alma con el anillo» y habla.
                if !self.modoAnillo && self.unRato { UserDefaults.standard.set(true, forKey: "voz_modo_anillo"); self.unRato = false; self.paso("El anillo encendió «Alma con el anillo»") }
                self.toqueAnillo()
            }
            return .success
        }
        c.togglePlayPauseCommand.isEnabled = true; c.togglePlayPauseCommand.addTarget(handler: toque)
        c.playCommand.isEnabled = true; c.playCommand.addTarget(handler: toque)
        c.pauseCommand.isEnabled = true; c.pauseCommand.addTarget(handler: toque)
    }

    private func infoBloqueo(_ texto: String) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: "Alma", MPMediaItemPropertyArtist: texto,
                                                           MPNowPlayingInfoPropertyPlaybackRate: estado == .hablando ? 1.0 : 0.0]
    }

    // MARK: - Hablar

    private func hablar() {
        guard let url = Llave.leer("voz_url"), let token = Llave.leer("voz_token"), let sesion = Llave.leer("voz_sesion"), let u = URL(string: url) else {
            emitir(["tipo": "error", "mensaje": "Abre Alma una vez con tu sesión para que pueda hablar con el teléfono bloqueado."]); return
        }
        UserDefaults.standard.set([String](), forKey: "voz_pasos"); UserDefaults.standard.set(true, forKey: "voz_abierta"); lineas = []
        inicioLlamada = Date()
        // Un solo micrófono: el Modo Inicio se calla ya (con la ficha pedida de antemano, la llamada abre el suyo enseguida).
        EscuchaInicio.shared.detener()
        estado = .conectando; colaVoz = []; pausada = false; cerrarTrasRespuesta = false; vozAlConectar = 0; inicioEnviado = false; antesDeFicha = []
        ultimaLlamada = (0, nil); motivoCalle = nil
        weebo = nil; weeboCambio = 0; adaptacion = nil; flechaT?.cancel()
        idLlamada = nil; reglasTarjeta.terminar(); publicarTarjeta()
        sonido("alma-inicio", llamada: true)   // el segundo beep: el de la llamada a Alma, suena siempre (también en conferencia): lo que digas se guarda mientras conecta
        infoBloqueo("Te escucho…")
        if let f = fichaLista, Date().timeIntervalSince(f.t) < 540 {
            fichaLista = nil; paso("Ficha lista de antemano"); conectar(agente: f.j["agent_id"] as? String ?? "", ficha: f.j); return
        }
        paso("Pidiendo tu ficha al Hub" + (UIApplication.shared.applicationState == .active ? "" : " (en segundo plano)"))
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["hub": 1, "action": "vozWeb", "app": "alma", "token": token, "session": sesion])
        URLSession.shared.dataTask(with: r) { [weak self] data, resp, err in
            guard let self else { return }
            guard let d = data, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], (j["ok"] as? Bool) == true,
                  let agente = j["agent_id"] as? String else {
                let por = err?.localizedDescription ?? (data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["error"] as? String) ?? "sin respuesta del Hub"
                DispatchQueue.main.async { self.fallo("No pude pedir tu ficha: \(por)") }; return
            }
            DispatchQueue.main.async { self.paso("Ficha lista" + (j["signed_url"] != nil ? " (URL firmada)" : "")); self.conectar(agente: agente, ficha: j) }
        }.resume()
    }

    private func conectar(agente: String, ficha: [String: Any]) {
        guard estado == .conectando else { return }
        do {
            let s = AVAudioSession.sharedInstance()
            guard s.recordPermission == .granted else { fallo("Falta el permiso del micrófono: Ajustes del iPhone → Alma → Micrófono."); return }
            if !engine.isRunning {
                guard UIApplication.shared.applicationState != .background || desdeCalle else {
                    fallo("Abre Alma una vez para dejar el micrófono listo; después funciona bloqueado."); return
                }
                paso("Abriendo el micrófono")
                try s.setCategory(.playAndRecord, mode: .default, options: VozNativa.opciones)
                try s.setActive(true)
                try prepararMotor()
            }
            paso("Micrófono abierto · conectando la voz")
        } catch { fallo("No pude abrir el micrófono (\((error as NSError).code))."); return }
        let firmada = (ficha["signed_url"] as? String).flatMap { URL(string: $0) }
        guard let u = firmada ?? URL(string: "wss://api.elevenlabs.io/v1/convai/conversation?agent_id=\(agente)") else { return }
        var pedido = URLRequest(url: u); pedido.setValue("https://hub.spacioam.com", forHTTPHeaderField: "Origin")
        let sesion = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        sesionURL = sesion
        let t = sesion.webSocketTask(with: pedido); ws = t; t.resume()
        // Si en 12 s Alma no contestó, se avisa (y no queda «Conectando…» para siempre).
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in if self?.estado == .conectando { self?.fallo("Alma no contestó. Revisa tu internet.") } }
        var dv = ficha["dynamic_variables"] as? [String: Any] ?? [:]
        segundosLargo = (ficha["conferencia_tras"] as? NSNumber).map { max(30, $0.doubleValue) } ?? 240
        calleSilencio = (ficha["calle_silencio_s"] as? NSNumber).map { min(30, max(3, $0.doubleValue)) } ?? SuenoCalle.silencioDeFabrica
        calleTope = (ficha["calle_tope_s"] as? NSNumber).map { min(180, max(15, $0.doubleValue)) } ?? SuenoCalle.topeDeFabrica
        // Medidores de la llamada (solo vienen con el administrador principal): el nivel de partida y la adaptación.
        weebo = (ficha["weebo_nivel"] as? NSNumber)?.intValue; weeboCambio = 0
        adaptacion = (ficha["adapt_nivel"] as? NSNumber)?.intValue
        adaptTope = (ficha["adapt_tope"] as? NSNumber)?.intValue ?? 60
        weeboModo = (ficha["weebo_modo"] as? String) ?? "auto"
        // Hay un tema por retomar (lo eligió el Hub, el más importante): Alma empieza por él en lugar de solo escuchar.
        let retomar = (ficha["retomar"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        // La despertaron solo con «Alma» (el anillo, o «Alma» en la conferencia o el Modo Inicio, sin pedido): saluda con el
        // saludo variado. Si ya dijeron el pedido junto con «Alma», no saluda: va directo a eso.
        let sinPedido = (textoInicial ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !desdePantalla {
            let empieza: String = retomar == nil ? "Ya sonó la señal y ya saludaste (o Juan ya empezó a hablar): NO saludes otra vez ni hables más. Escucha." : "Empiezas tú con el tema por retomar (ya está en tu primer mensaje); después escucha."
            dv["quien_llama"] = ((dv["quien_llama"] as? String) ?? "") + "\n\nMODO ANILLO: Juan te habla desde su anillo, casi siempre con el teléfono bloqueado (solo voz, sin pantalla). " + empieza + " Habla en tramos, con pausas, como quien piensa en voz alta: mientras no haya pedido algo concreto o su idea quede a medias, usa skip_turn y sigue escuchando; junta todo lo que dijo como un solo mensaje. Responde solo cuando ya pidió algo claro o terminó de hablar. Respuestas cortas, claras y cálidas."
        }
        if let cf = conferencia {
            dv["quien_llama"] = ((dv["quien_llama"] as? String) ?? "") + "\n\nMODO CONFERENCIA: Juan está en una reunión y tú la escuchas en silencio. Alguien te nombró («Alma, …»): responde solo eso, corto y claro, sin saludar ni presentarte." + (sinPedido ? " Solo dijeron «Alma»: ya contestaste con un saludo corto; escucha lo que te piden." : "") + " Si en LO ÚLTIMO QUE SE DIJO hay una línea «[Alma te avisó] …», le acabas de avisar que algo ya quedó listo y Juan te contestó: dale ese resultado en corto (búscalo con tus herramientas si hace falta), sin volver a preguntar si quiere verlo. Cuando termines y nadie te pida otra cosa, cuelga con end_call: vuelves a escuchar sola. En este modo hay silencios largos y es normal: NUNCA preguntes si siguen ahí ni insistas. Si nadie te habla después de responder, despídete en una frase amable, sin pregunta (por ejemplo: «Sigo aquí; si me necesitas, solo llámame»), y cuelga con end_call. LO ÚLTIMO QUE SE DIJO:\n" + cf
        }
        if desdeCalle {
            dv["quien_llama"] = ((dv["quien_llama"] as? String) ?? "") + "\n\nMODO CALLE: Juan va caminando, con el teléfono bloqueado y audífonos; hay ruido y gente alrededor. Responde en una o dos frases cortas. Si lo que oyes no va dirigido a ti, usa skip_turn y no contestes. Nunca preguntes si sigue ahí ni te despidas: si se queda callado, la app cuelga sola y él te vuelve a llamar con «Alma»."
        }
        // Manos de Alma (navegador): qué tiene abierto el navegador de la app (las reglas están en el Hub, voz.js).
        let manos = ManosAlma.shared.ficha
        if !manos.isEmpty { dv["quien_llama"] = ((dv["quien_llama"] as? String) ?? "") + "\n\n" + manos }
        if let pt = pantalla {
            dv["quien_llama"] = ((dv["quien_llama"] as? String) ?? "") + "\n\nMODO PANTALLA: Juan está en el navegador de la app de Alma viendo " + pt + " y tocó tres veces la roca para hablar contigo de lo que ve. Ya le dijiste «\(VozNativa.saludoPantalla)»: no saludes otra vez; escucha. En unos segundos te llega LO QUE SE VE EN LA PANTALLA (lo que muestra su captura): úsalo como contexto. Si pregunta antes de que llegue, dile que lo estás mirando."
        }
        // Saludo variado (#410): sin tema por retomar, Alma abre con una frase natural y completa que cambia cada vez (antes
        // «Dime, Juan», que sonaba cortado). Tres toques en el navegador (pantalla): «Hola, ahora lo veo».
        // Sin pisar a Juan: el primer mensaje se decide pasada la señal (ventanaSaludo); si para entonces Juan ya está
        // hablando, va vacío y Alma solo escucha (ElevenLabs espera a que hable). Si ya dijeron el pedido con «Alma», tampoco.
        let tema = (ficha["saludo_tema"] as? Bool) == true
        let enPantalla = pantalla != nil, enConferencia = conferencia != nil || alOir
        let fm = ficha["first_message"] as? String ?? "", idioma = ficha["language"] as? String ?? ""
        let deRoca = desdePantalla, llamada = inicioLlamada, dvListas = dv
        let espera = max(0, VozNativa.ventanaSaludo - Date().timeIntervalSince(inicioLlamada))
        escuchar()
        DispatchQueue.main.asyncAfter(deadline: .now() + espera) { [weak self] in
            guard let self, self.inicioLlamada == llamada, self.estado == .conectando || self.estado == .hablando, !self.inicioEnviado, self.ws != nil else { return }
            let primero: String
            if self.vozAlConectar >= 0.25 {   // Juan ya habla: primer mensaje vacío, Alma lo escucha
                self.paso(String(format: "Ya hablabas al conectar (%.1f s): Alma no saluda y te escucha", self.vozAlConectar))
                primero = ""
            }
            else if enPantalla { primero = VozNativa.saludoPantalla }
            else if enConferencia { primero = sinPedido ? VozNativa.saludoVariado(ficha) : "" }
            else if deRoca { primero = retomar ?? (tema && !fm.isEmpty ? fm : VozNativa.saludoVariado(ficha)) }   // un tema por retomar o la llamada reciente siguen primero
            else { primero = retomar ?? VozNativa.saludoVariado(ficha) }
            var agent: [String: Any] = ["first_message": primero]
            if !idioma.isEmpty { agent["language"] = idioma }
            self.mandar(["type": "conversation_initiation_client_data", "dynamic_variables": dvListas, "conversation_config_override": ["agent": agent]])
            self.inicioEnviado = true
            // Lo que esperaba a la ficha (lo que dijo con «Alma» en la conferencia, la captura): sale ahora, detrás de ella.
            let pendiente = self.antesDeFicha; self.antesDeFicha = []; pendiente.forEach { self.mandar($0) }
            // Si ElevenLabs ya contestó (no debería antes de la ficha), lo dicho mientras tanto se manda ahora, detrás de la ficha.
            if self.estado == .hablando { for c in self.colaVoz { self.mandar(["user_audio_chunk": c]) }; self.colaVoz = [] }
        }
    }

    /// Abre el micrófono. Primero con cancelación de eco; si iOS la rechaza (error «what»), sin ella: así Alma igual escucha.
    private func prepararMotor() throws {
        if !motorListo { engine.attach(player); motorListo = true }
        if !sinEco {
            do { try armarMotor(eco: true); return }
            catch {
                paso("La cancelación de eco falló (\((error as NSError).code)); abro el micrófono sin ella")
                engine.inputNode.removeTap(onBus: 0); engine.stop(); engine.reset()
                sinEco = true
            }
        }
        try armarMotor(eco: false)
    }

    private func armarMotor(eco: Bool) throws {
        if engine.inputNode.isVoiceProcessingEnabled != eco { try engine.inputNode.setVoiceProcessingEnabled(eco) }
        // La cancelación de eco baja el volumen de las otras apps; se deja en lo mínimo (iOS 17+, el mínimo de la app).
        if eco { engine.inputNode.voiceProcessingOtherAudioDuckingConfiguration = AVAudioVoiceProcessingOtherAudioDuckingConfiguration(enableAdvancedDucking: false, duckingLevel: .min) }
        engine.connect(player, to: engine.mainMixerNode, format: formatoSalida)
        let fIn = engine.inputNode.outputFormat(forBus: 0)
        guard fIn.sampleRate > 0, fIn.channelCount > 0, let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: fIn.sampleRate, channels: 1, interleaved: false) else {
            throw NSError(domain: "Alma", code: -1, userInfo: [NSLocalizedDescriptionKey: "el micrófono no está disponible"])
        }
        formatoMono = mono
        convertidor = AVAudioConverter(from: mono, to: formatoEntrada)
        engine.inputNode.removeTap(onBus: 0)
        engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: fIn) { [weak self] buf, _ in self?.microfono(buf) }
        if !engine.isRunning { engine.prepare(); try engine.start() }
        player.play()
    }

    private func microfono(_ buf: AVAudioPCMBuffer) {
        if estado == .lista { darAOyente(buf); return }   // sin llamada: lo oye el Modo Inicio o el modo conferencia
        /* En pausa no se manda tu voz; pero si le hablas (más fuerte que el eco y por casi un segundo), Alma vuelve a escuchar
           sola: una pausa que no pediste (un toque de más) ya no la deja muda. */
        if pausada, estado == .hablando, let s = buf.floatChannelData {
            var e: Float = 0; for i in 0..<Int(buf.frameLength) { e += s[0][i] * s[0][i] }
            let rms = sqrt(e / Float(max(1, buf.frameLength))), dur = Double(buf.frameLength) / buf.format.sampleRate
            vozEnPausa = rms > 0.06 && Date() >= finVozAlma ? vozEnPausa + dur : max(0, vozEnPausa - dur)
            if vozEnPausa > 0.8 {
                vozEnPausa = 0
                DispatchQueue.main.async { if self.pausada && self.estado == .hablando { self.paso("Hablaste en pausa: Alma vuelve a escuchar"); self.reanudar() } }
            }
            return
        }
        guard estado == .hablando || estado == .conectando, !pausada, !mudo, let conv = convertidor, let mf = formatoMono, let src = buf.floatChannelData,
              let mono = AVAudioPCMBuffer(pcmFormat: mf, frameCapacity: buf.frameLength), let dst = mono.floatChannelData else { return }
        mono.frameLength = buf.frameLength
        dst[0].update(from: src[0], count: Int(buf.frameLength))   // primer canal
        var e: Float = 0; for i in 0..<Int(buf.frameLength) { e += src[0][i] * src[0][i] }
        let rmsTu = sqrt(e / Float(max(1, buf.frameLength)))
        /* Que Alma no se escuche a sí misma: mientras suena su voz, el parlante entra al micrófono y ella lo toma como si
           Juan la interrumpiera (se corta a media frase y repite «te iba diciendo…»). Mientras suena, solo pasa lo que
           suena más fuerte que su eco (Juan hablándole de verdad); lo demás se manda como silencio. Sin cancelación de
           eco el eco es más fuerte, así que el umbral sube. */
        let suenaAlma = Date() < finVozAlma.addingTimeInterval(0.35)
        /* La señal de la llamada (alma-inicio, ~1 s fuerte) suena por el parlante mientras conecta: si llegaba a ElevenLabs
           como voz, lo tomaba como que Juan interrumpía y cortaba el saludo («Dime, Ju…»). Solo pasa lo que suena más fuerte. */
        let desdeToque = Date().timeIntervalSince(inicioLlamada), suenaSenal = desdeToque >= 0 && desdeToque < VozNativa.finSenal
        if suenaAlma && rmsTu < (sinEco ? 0.12 : 0.045) { for i in 0..<Int(buf.frameLength) { dst[0][i] = 0 } }
        else if suenaSenal && rmsTu < (sinEco ? 0.15 : 0.08) { for i in 0..<Int(buf.frameLength) { dst[0][i] = 0 } }
        let cap = AVAudioFrameCount(Double(buf.frameLength) * 16000 / buf.format.sampleRate) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: formatoEntrada, frameCapacity: cap) else { return }
        var dado = false
        conv.convert(to: out, error: nil) { _, st in
            if dado { st.pointee = .noDataNow; return nil }
            dado = true; st.pointee = .haveData; return mono
        }
        guard out.frameLength > 0, let p = out.int16ChannelData else { return }
        let datos = Data(bytes: p[0], count: Int(out.frameLength) * 2)
        let seg = Double(out.frameLength) / 16000
        DispatchQueue.main.async {
            if self.estado == .conectando || !self.inicioEnviado {   // sin la ficha mandada, nada de audio al socket: se guarda
                if self.colaVoz.count < 80 { self.colaVoz.append(datos.base64EncodedString()) }
                // ¿Juan ya habla? (para no saludarlo encima). Durante la señal solo cuenta una voz claramente más fuerte.
                if self.estado == .conectando && rmsTu > (suenaSenal ? 0.15 : 0.04) { self.vozAlConectar += seg }
                return
            }
            self.vozEnviada += seg; self.ultimaVoz = Date(); self.mandar(["user_audio_chunk": datos.base64EncodedString()])
            if !self.almaHabla { self.nivel = min(1, CGFloat(rmsTu) * 9) }
            if rmsTu > 0.05 && !suenaAlma { self.ultimaActividad = Date(); self.sonidoCalle = Date() }   // Juan hablando también cuenta (no es pausa larga)
        }
    }

    private func escuchar() {
        ws?.receive { [weak self] r in
            guard let self else { return }
            switch r {
            case .success(let m):
                var texto: String?
                if case .string(let s) = m { texto = s } else if case .data(let d) = m { texto = String(data: d, encoding: .utf8) }
                if let t = texto, let d = t.data(using: .utf8), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                    DispatchQueue.main.async { self.mensaje(j) }
                }
                self.escuchar()
            case .failure(let e):
                DispatchQueue.main.async {
                    if self.estado == .conectando || self.estado == .hablando { self.fallo("La voz se cortó: \(e.localizedDescription)") }
                }
            }
        }
    }

    private func mensaje(_ j: [String: Any]) {
        switch j["type"] as? String ?? "" {
        case "conversation_initiation_metadata":
            let ev = j["conversation_initiation_metadata_event"] as? [String: Any] ?? [:]
            if let f = ev["agent_output_audio_format"] as? String, f.hasPrefix("pcm_"), let hz = Double(f.dropFirst(4)), hz != formatoSalida.sampleRate,
               let nuevo = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: hz, channels: 1, interleaved: false) {
                formatoSalida = nuevo; player.stop(); engine.disconnectNodeOutput(player); engine.connect(player, to: engine.mainMixerNode, format: nuevo); player.play()
            }
            estado = .hablando; conectadaDesde = Date(); vozEnPausa = 0
            vigilar()
            aConferencia = false; relojLargo?.invalidate(); relojLargo = nil; vigiaLargo?.invalidate(); vigiaLargo = nil; ultimaActividad = Date(); herramienta = false
            if desdeCalle { vigilarCalle() }
            if conferencia == nil && !desdeCalle {   // en el Modo calle manda el sueño (más corto); pasar a conferencia apagaría el Modo calle
                relojLargo = Timer.scheduledTimer(withTimeInterval: segundosLargo, repeats: false) { [weak self] _ in
                    guard let self, self.estado == .hablando else { return }
                    self.aConferencia = true; self.paso("Llamada larga: en la próxima pausa larga pasa al modo conferencia")
                    let d = self.despedida()
                    // La llamada sigue igual. Solo la próxima pausa larga cambia: en vez de preguntar si sigue ahí, Alma se despide y cuelga.
                    self.mandar(["type": "contextual_update", "text": "LLAMADA LARGA: sigue la conversación con normalidad y no la cortes tú. Pero desde ahora, NUNCA preguntes si Juan sigue ahí. En la próxima pausa larga (cuando antes preguntarías si sigue ahí), di solo esta frase: «\(d)» y cuelga con end_call; la app queda escuchando en modo conferencia."])
                    // Respaldo: si tras la pausa nadie dijo nada en 16 s (7 s de espera + la despedida), la app cuelga y pasa a conferencia.
                    self.vigiaLargo = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                        guard let self, self.estado == .hablando, !self.pausada, !self.herramienta else { return }
                        if Date().timeIntervalSince(max(self.ultimaActividad, self.finVozAlma)) > 16 { self.paso("Pausa larga sin respuesta: pasa al modo conferencia"); self.terminar() }
                    }
                }
            }
            paso("Alma conectada · te escucha" + (colaVoz.isEmpty ? "" : String(format: " (%.1f s dichos mientras conectaba)", Double(colaVoz.count) * 0.128)))
            if inicioEnviado { for c in colaVoz { mandar(["user_audio_chunk": c]) }; colaVoz = [] }   // si no, se mandan tras la ficha
            if let t = textoInicial, !t.isEmpty { mandar(["type": "user_message", "text": t]) }; textoInicial = nil
            if let v = vistaPendiente { vistaPendiente = nil; mandar(["type": "contextual_update", "text": v]) }   // la captura llegó mientras conectaba
            infoBloqueo("Te escucho · dos toques para pausar")
            emitirPersonalidad()   // los chips de la llamada (si es el principal)
            if let id = ev["conversation_id"] as? String { vincular(id) }
        case "audio":
            let ev = j["audio_event"] as? [String: Any] ?? [:]
            ultimaActividad = Date()
            if let b = ev["audio_base_64"] as? String, let d = Data(base64Encoded: b) {
                let primera = !sono
                if primera { sono = true; paso("Alma está hablando") }
                sonar(d, respiro: primera)
            }
        case "agent_tool_request":
            herramienta = true; ultimaActividad = Date()
            let tr = j["agent_tool_request"] as? [String: Any] ?? [:]
            if conferencia != nil, (tr["tool_name"] as? String ?? "secretaria") == "secretaria" { armarEspera() }
            // Alma va a buscar otra cosa: la tarjeta que se ve se encoge a la pestañita
            if (tr["tool_name"] as? String ?? "") == "secretaria" { reglasTarjeta.cambioDeTema(); publicarTarjeta() }
        case "client_tool_call":
            ultimaActividad = Date()
            herramientaCliente(j["client_tool_call"] as? [String: Any] ?? [:])
        case "agent_tool_response":
            herramienta = false; ultimaActividad = Date()
            relojEspera?.invalidate(); relojEspera = nil
            let rt = j["agent_tool_response"] as? [String: Any] ?? [:]
            if (rt["tool_name"] as? String ?? "") == "secretaria" { pedirTarjeta(intento: 0) }
        case "interruption":
            player.stop(); player.play(); finVozAlma = Date(); ventanasAlma = []
        case "ping":
            let ev = j["ping_event"] as? [String: Any] ?? [:]
            mandar(["type": "pong", "event_id": ev["event_id"] ?? 0])
        case "agent_response":
            let ev = j["agent_response_event"] as? [String: Any] ?? [:]
            if let t = ev["agent_response"] as? String { emitir(["tipo": "alma", "texto": t]); linea(true, t) }
        case "user_transcript":
            let ev = j["user_transcription_event"] as? [String: Any] ?? [:]
            if let t = ev["user_transcript"] as? String {
                ultimaActividad = Date(); emitir(["tipo": "yo", "texto": t]); linea(false, t)
                if desdeCalle, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    vozJuanCalle = Date()
                    if SuenoCalle.esCierre(t) { colgarCalle(.cierre) }
                }
            }
        case "vad_score":   // solo llega si el agente lo tiene encendido: «alguien habla» según ElevenLabs (mejor que el volumen)
            let v = ((j["vad_score_event"] as? [String: Any])?["vad_score"] as? NSNumber)?.doubleValue ?? 0
            if v >= 0.6 { sonidoCalle = Date() }
        default: break
        }
    }

    /// Herramientas del lado de la app (client tools de ElevenLabs). mostrar_en_chat: abre el chat con lo que Alma
    /// pone en pantalla y la llamada sigue. Sin pantalla a la vista (teléfono bloqueado, modo anillo) no se muestra y se le
    /// dice a Alma que lo diga por voz. Las Manos de Alma (leer_pagina, senalar, tocar, escribir, bajar, abrir: ManosAlma.swift)
    /// y correr_atajo (AtajosIOS.swift) contestan cuando terminan. Siempre se contesta: así Alma nunca se queda esperando.
    private func herramientaCliente(_ ev: [String: Any]) {
        guard let id = ev["tool_call_id"] as? String else { return }
        let nombre = ev["tool_name"] as? String ?? ""
        let p = ev["parameters"] as? [String: Any] ?? [:]
        if ManosAlma.herramientas.contains(nombre) || nombre == "correr_atajo" {
            herramienta = true; paso("Alma usa " + nombre)
            let llamada = inicioLlamada
            let contestar: (String, Bool) -> Void = { [weak self] res, error in
                guard let self, self.inicioLlamada == llamada else { return }   // la respuesta de una llamada anterior se ignora
                self.herramienta = false; self.ultimaActividad = Date()
                self.mandar(["type": "client_tool_result", "tool_call_id": id, "result": res, "is_error": error])
            }
            if nombre == "correr_atajo" { AtajosPermitidos.correr(ManosAlma.texto(p["nombre"]), contestar) }
            else { ManosAlma.shared.correr(nombre, p, contestar) }
            return
        }
        // Medidor de personalidad (#410): Alma cuenta en silencio su nivel de Modo Weebo. No espera respuesta (expects_response
        // false): no se contesta, así no la hace hablar.
        if nombre == "nivel_weebo" {
            let n: Int? = (p["nivel"] as? NSNumber)?.intValue ?? Int((p["nivel"] as? String) ?? "")
            if let n, (0...3).contains(n) { if n != weebo { paso("Modo Weebo: nivel \(n)") }; ponerWeebo(n); emitirPersonalidad() }
            return
        }
        var res = "Esta herramienta no existe en la app.", error = true
        if nombre == "mostrar_en_chat" {
            let titulo = (p["titulo"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let contenido = (p["contenido"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if contenido.isEmpty { res = "Falta el contenido: no se mostró nada." }
            else if UIApplication.shared.applicationState != .active {
                res = "Juan no tiene la pantalla a la vista (teléfono bloqueado): no se mostró. Díselo por voz, en corto, solo lo más importante."
            } else {
                contador += 1
                mostrado = Mostrado(id: contador, titulo: titulo.isEmpty ? "Alma" : titulo, contenido: contenido)
                paso("Alma lo puso en el chat: " + String(titulo.prefix(40)))
                res = "Listo: ya está en el chat, en la pantalla de Juan. Resúmelo por voz en una sola frase; no lo leas completo."; error = false
            }
        }
        mandar(["type": "client_tool_result", "tool_call_id": id, "result": res, "is_error": error])
    }

    /// La captura de la pantalla, leída por el Hub (almaFoto con captura, la misma lectura del chat; `voz` pide la versión
    /// rápida). Llega a la llamada como contexto; si todavía conecta, espera en vistaPendiente. Una respuesta de una llamada
    /// anterior se ignora.
    private func describir(_ captura: String, aviso: String?) {
        guard let url = Llave.leer("voz_url"), let token = Llave.leer("voz_token"), let sesion = Llave.leer("voz_sesion"), let u = URL(string: url) else { return }
        let llamada = inicioLlamada
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type"); r.timeoutInterval = 40
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["hub": 1, "action": "almaFoto", "foto": captura, "captura": true, "voz": true, "token": token, "session": sesion])
        paso("Leyendo la captura de la pantalla")
        URLSession.shared.dataTask(with: r) { [weak self] data, _, _ in
            let j = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let texto = (j?["ok"] as? Bool) == true ? ((j?["texto"] as? String) ?? "") : ""
            DispatchQueue.main.async {
                guard let self, self.inicioLlamada == llamada, self.estado == .conectando || self.estado == .hablando else { return }
                self.paso(texto.isEmpty ? "No pude leer la captura" : "Captura leída")
                let t = texto.isEmpty ? "LO QUE SE VE EN LA PANTALLA: no se pudo leer la captura. Si Juan pregunta por algo de la pantalla, pídele que te diga qué ve."
                    : (aviso.map { $0 + " " } ?? "") + "LO QUE SE VE EN LA PANTALLA (la captura que te mandó Juan): " + texto
                if self.estado == .hablando { self.mandar(["type": "contextual_update", "text": t]) } else { self.vistaPendiente = t }
            }
        }.resume()
    }

    /// `respiro`: la primera voz de la llamada va después de 0.12 s de silencio. El audio con cancelación de eco recién
    /// abierto puede comerse el arranque de lo primero que suena (la primera sílaba del saludo); el respiro lo protege.
    private func sonar(_ pcm16: Data, respiro: Bool = false) {
        let n = pcm16.count / 2
        guard n > 0, let buf = AVAudioPCMBuffer(pcmFormat: formatoSalida, frameCapacity: AVAudioFrameCount(n)), let ch = buf.floatChannelData else { return }
        buf.frameLength = AVAudioFrameCount(n)
        if respiro, let sil = AVAudioPCMBuffer(pcmFormat: formatoSalida, frameCapacity: AVAudioFrameCount(formatoSalida.sampleRate * 0.12)), let sc = sil.floatChannelData {
            sil.frameLength = sil.frameCapacity
            for i in 0..<Int(sil.frameLength) { sc[0][i] = 0 }
            player.scheduleBuffer(sil, completionHandler: nil)
            finVozAlma = max(finVozAlma, Date()).addingTimeInterval(0.12)
        }
        var e: Float = 0
        pcm16.withUnsafeBytes { (r: UnsafeRawBufferPointer) in
            let s = r.bindMemory(to: Int16.self)
            for i in 0..<n { let v = Float(Int16(littleEndian: s[i])) / 32768; ch[0][i] = v; e += v * v }
        }
        // Alma habla mientras suena este trozo: el círculo late con su voz
        let dur = Double(n) / formatoSalida.sampleRate, nv = min(1, CGFloat(sqrt(e / Float(n))) * 6)
        almaHabla = true; nivel = nv; ultimoAudioAlma = Date()
        let inicio = max(finVozAlma, Date())
        finVozAlma = inicio.addingTimeInterval(dur)   // los trozos llegan más rápido de lo que suenan
        agendarNivelAlma(ch[0], n: n, inicio: inicio)
        finHabla?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.almaHabla = false; self?.nivel = 0; self?.ventanasAlma = [] }
        finHabla = w; DispatchQueue.main.asyncAfter(deadline: .now() + dur + 0.25, execute: w)
        player.scheduleBuffer(buf, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    /// Parte el trozo en ventanas de 50 ms y las pone a la hora en que van a sonar: así el nivel que ve la roca sigue la voz
    /// siempre (antes llegaba un solo valor por trozo y el límite de envío tiraba los demás: la roca a veces no se movía).
    private func agendarNivelAlma(_ x: UnsafePointer<Float>, n: Int, inicio: Date) {
        let paso = max(1, Int(formatoSalida.sampleRate * 0.05))
        var i = 0
        while i < n {
            let fin = min(n, i + paso); var e: Float = 0
            for k in i..<fin { e += x[k] * x[k] }
            ventanasAlma.append((inicio.addingTimeInterval(Double(i) / formatoSalida.sampleRate), min(1, CGFloat(sqrt(e / Float(fin - i))) * 6)))
            i = fin
        }
        if relojAlma == nil {
            relojAlma = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.tickNivelAlma() }
        }
    }
    private func tickNivelAlma() {
        let ahora = Date()
        while ventanasAlma.count > 1, ventanasAlma[1].inicio <= ahora { ventanasAlma.removeFirst() }
        guard almaHabla, let v = ventanasAlma.first, v.inicio <= ahora else {
            if ventanasAlma.isEmpty { relojAlma?.invalidate(); relojAlma = nil }
            return
        }
        nivel = v.nivel
    }

    /// La señal de Alma suena siempre que empieza a escuchar: el anillo, la roca, «Alma» en el inicio, el modo conferencia,
    /// el dictado y la voz de las páginas (que la piden por el puente: suena igual aunque la página esté tomando el micrófono).
    func sonar(_ n: String) { if n == "alma-inicio" || n == "alma-fin" { sonido(n) } }
    func senal() { sonido("alma-inicio") }

    /// Los sonidos de Alma (Recursos/Sonidos): calma primero, tecnología después.
    private func sonido(_ n: String, llamada: Bool = false) {
        // nunca el mismo sonido dos veces seguidas (dos avisos de un mismo gesto), salvo el beep de la llamada tras el del inicio
        if !llamada, let t = ultimoSonido[n], Date().timeIntervalSince(t) < 2.5 { return }
        ultimoSonido[n] = Date()
        if campanas[n] == nil, let u = Bundle.main.url(forResource: n, withExtension: "wav") { campanas[n] = try? AVAudioPlayer(contentsOf: u) }
        campanas[n]?.volume = 0.9; campanas[n]?.currentTime = 0; campanas[n]?.play()
    }

    private func mandar(_ o: [String: Any]) {
        // Nada de la conversación antes de la ficha: si no, ElevenLabs empieza sin quien_llama (InicioVoz, 6-nov-2026).
        if InicioVoz.decidir(tipo: InicioVoz.tipo(o), inicioEnviado: inicioEnviado) == .esperar { antesDeFicha.append(o); return }
        guard let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) else { return }
        ws?.send(.string(s)) { _ in }
    }

    /// La llamada queda ligada a tu chat con Alma en el Hub (como la voz de las web apps).
    /// En modo conferencia también avisa que es conferencia (el Hub espera hasta 45 s) y pide la frase de espera en el formato
    /// de audio de esta llamada.
    private func vincular(_ id: String) {
        guard let url = Llave.leer("voz_url"), let token = Llave.leer("voz_token"), let sesion = Llave.leer("voz_sesion"), let u = URL(string: url) else { return }
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        var b: [String: Any] = ["hub": 1, "action": "vozWebVincular", "app": "alma", "conv_id": id, "token": token, "session": sesion]
        let enConf = conferencia != nil
        if enConf { b["conferencia"] = true; b["hz"] = Int(formatoSalida.sampleRate) }
        idLlamada = id; b["pantalla"] = pantallaVisible   // tarjeta de la llamada: con el teléfono bloqueado no se muestra
        vigilarPantalla()
        r.httpBody = try? JSONSerialization.data(withJSONObject: b)
        let llamada = inicioLlamada
        URLSession.shared.dataTask(with: r) { [weak self] data, _, _ in
            guard enConf, let d = data, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let e = j["espera"] as? [String: Any], let a = e["audio"] as? String, let pcm = Data(base64Encoded: a), !pcm.isEmpty else { return }
            let hz = (e["hz"] as? NSNumber)?.doubleValue ?? 0, tras = (e["tras"] as? NSNumber)?.doubleValue ?? 15
            DispatchQueue.main.async {
                guard let self, self.inicioLlamada == llamada, self.conferencia != nil else { return }   // la de una llamada anterior no sirve
                self.espera = (pcm, hz, max(5, tras))
            }
        }.resume()
    }

    /// La secretaria empezó a trabajar en una llamada del modo conferencia: si pasa de `tras` segundos, «Sigo en eso, ya casi».
    /// Suena por la misma salida que la voz de Alma (sonar), así el micrófono no la toma como si Juan hablara.
    private func armarEspera() {
        relojEspera?.invalidate(); relojEspera = nil
        let tras = espera?.tras ?? 15, llamada = inicioLlamada
        relojEspera = Timer.scheduledTimer(withTimeInterval: tras, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.relojEspera = nil
            guard self.inicioLlamada == llamada, self.estado == .hablando, self.herramienta, !self.almaHabla,
                  let e = self.espera, e.hz == self.formatoSalida.sampleRate else { return }
            self.paso("La secretaria tarda: «Sigo en eso, ya casi»")
            self.sonar(e.pcm)
        }
    }

    /// Mientras hablan: cada 10 s anota cuánta voz llegó; si el micrófono calla más de 3 s, lo vuelve a abrir.
    private func vigilar() {
        vigia?.invalidate(); vozEnviada = 0; ultimaVoz = Date()
        var tramo = 0
        vigia = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self, self.estado == .hablando else { t.invalidate(); return }
            tramo += 1
            if self.cerrarTrasRespuesta {   // pausa sin retomar: cuando Alma terminó de responder (o a los 45 s), se cierra
                let callada = Date().timeIntervalSince(self.ultimoAudioAlma) > 5 && self.ultimoAudioAlma > self.desdeCierre
                if (callada && !self.almaHabla) || Date().timeIntervalSince(self.desdeCierre) > 45 { self.terminar() }
                return
            }
            if self.pausada { self.ultimaVoz = Date(); return }
            if Date().timeIntervalSince(self.ultimaVoz) > 3 {
                self.paso("El micrófono dejó de mandar voz (motor " + (self.engine.isRunning ? "encendido" : "apagado") + ")")
                if self.desdeCalle && !self.mudo { self.colgarCalle(.corte); return }   // Modo calle: sin reintentar; vuelve a esperar «Alma»
                self.ultimaVoz = Date()
                self.revivirMicrofono()
            }
            if tramo % 10 == 0 { self.paso(String(format: "Voz enviada: %.1f s en 10 s", self.vozEnviada)); self.vozEnviada = 0 }
        }
    }

    private func revivirMicrofono() {
        do { try prepararMotor(); paso("Micrófono abierto otra vez") }
        catch {
            paso("No pude volver a abrir el micrófono (\((error as NSError).code))")
            if estado == .hablando { fallo("iOS apagó el micrófono y no dejó volver a abrirlo. Abre Alma y vuelve a intentar.") }
        }
    }

    static let sinPregunta = "En este modo hay silencios largos y es normal: NUNCA preguntes si siguen ahí ni insistas. Si nadie te habla después de responder, despídete en una frase amable, sin pregunta (por ejemplo: «Sigo aquí; si me necesitas, solo llámame»), y cuelga con end_call."
    private func terminar() {
        vigia?.invalidate(); vigia = nil
        vigiaCalle?.invalidate(); vigiaCalle = nil
        if estado == .hablando || estado == .conectando {
            ultimaLlamada = (estado == .hablando ? max(0, Date().timeIntervalSince(conectadaDesde)) : 0, motivoCalle)
        }
        motivoCalle = nil
        relojLargo?.invalidate(); relojLargo = nil; vigiaLargo?.invalidate(); vigiaLargo = nil
        let pasarAConferencia = aConferencia && (estado == .hablando || estado == .conectando); aConferencia = false
        let charla = pasarAConferencia ? charlaReciente : []   // de qué se hablaba: el modo conferencia lo lleva de contexto
        pausaT?.cancel(); pausaT = nil; pausada = false; cerrarTrasRespuesta = false; colaVoz = []; inicioEnviado = false; antesDeFicha = []; mudo = false; enChat = false; player.volume = 1
        let habia = estado == .hablando || estado == .conectando, enConferencia = conferencia != nil
        relojEspera?.invalidate(); relojEspera = nil; espera = nil
        conferencia = nil; textoInicial = nil; alOir = false; pantalla = nil; vistaPendiente = nil
        reglasTarjeta.terminar(); publicarTarjeta(); idLlamada = nil   // lo que hubo queda en el Chat con Alma (lo guarda el Hub)
        avisoPantalla.forEach { NotificationCenter.default.removeObserver($0) }; avisoPantalla = []
        if habia { paso("Pausa") }
        UserDefaults.standard.set(false, forKey: "voz_abierta"); sono = false
        ws?.cancel(with: .normalClosure, reason: nil); ws = nil
        sesionURL?.invalidateAndCancel(); sesionURL = nil
        player.stop()
        if modoAnillo || unRato { player.play() }   // el micrófono sigue listo para el próximo doble toque
        else { engine.inputNode.removeTap(onBus: 0); if engine.isRunning { engine.stop() } }
        if habia { if !enConferencia { sonido("alma-fin") }; fichaLista = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.buscarAvisos() } }
        estado = .apagada
        if modoAnillo || unRato { quedarLista(); DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.fichaLista = nil; self?.precargarSiToca() } }
        else { apagar() }
        // la llamada larga terminó: queda el modo conferencia, escuchando hasta que digan «Alma»
        if pasarAConferencia && !Conferencia.shared.activa {
            paso("La llamada larga pasó al modo conferencia")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { Conferencia.shared.encender(contexto: charla, apagarTras: 7 * 60) }   // si en 7 min nadie dice «Alma», se apaga
        }
    }

    // MARK: - Tarjeta de la llamada (#446 T2)

    /// ¿Juan ve la pantalla? Con el teléfono bloqueado, en el Modo calle o en conferencia, no (la tarjeta queda en el chat).
    private var pantallaVisible: Bool {
        ReglasTarjeta.pantallaVisible(appActiva: UIApplication.shared.applicationState == .active, calle: desdeCalle, conferencia: conferencia != nil)
    }

    /// La secretaria contestó: si el Hub armó una tarjeta, se pide y se pinta. Se reintenta una vez a los 1.5 s.
    private func pedirTarjeta(intento: Int) {
        guard pantallaVisible, let id = idLlamada, let url = Llave.leer("voz_url"), let token = Llave.leer("voz_token"),
              let sesion = Llave.leer("voz_sesion"), let u = URL(string: url) else { return }
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type"); r.timeoutInterval = 12
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["hub": 1, "action": "vozTarjeta", "conv_id": id, "token": token, "session": sesion])
        let llamada = inicioLlamada
        URLSession.shared.dataTask(with: r) { [weak self] data, _, _ in
            let j = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let t = (j?["tarjeta"] as? [String: Any]).flatMap { TarjetaVoz($0) }
            DispatchQueue.main.async {
                guard let self, self.inicioLlamada == llamada, self.estado == .hablando else { return }
                guard let t else {
                    if intento == 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.pedirTarjeta(intento: 1) } }
                    return
                }
                if self.tarjeta?.id == t.id { return }   // la misma que ya llegó
                let d = self.reglasTarjeta.recibir(t, pantalla: self.pantallaVisible, ahora: Date())
                self.paso("Tarjeta de la llamada: " + t.tipo + (d == .mostrar ? "" : d == .repetida ? " (ya se vio)" : " (sin pantalla: queda en el chat)"))
                if d == .mostrar { self.publicarTarjeta(); self.relojDeTarjeta() }
            }
        }.resume()
    }

    /// Lo que Juan toca en la tarjeta (LlamadaVista o la página del inicio): toque · detalle · abrir · plegar · conv · llamar · whatsapp.
    func tarjetaAccion(_ hacer: String) {
        let ahora = Date()
        switch hacer {
        case "toque": reglasTarjeta.toque(ahora: ahora); return   // solo vuelve a contar los 20 s
        case "detalle": reglasTarjeta.detalle(ahora: ahora)
        case "abrir": reglasTarjeta.abrir(ahora: ahora); relojDeTarjeta()
        case "plegar": reglasTarjeta.plegar()
        case "conv":   // abre la conversación en el navegador de la app; la llamada sigue
            guard let c = tarjeta?.conv, !c.isEmpty, let q = c.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let u = URL(string: "https://hub.spacioam.com/index.html?conv=" + q) else { return }
            reglasTarjeta.plegar()
            NotificationCenter.default.post(name: .abrirDesdeTarjeta, object: u)
        case "llamar", "whatsapp":   // ya preguntó «¿Cuelgo a Alma?» y dijo que sí
            guard let t = tarjeta else { return }
            let u = hacer == "llamar" ? URL(string: "tel:" + t.tel.filter { $0.isNumber || $0 == "+" }) : URL(string: "https://wa.me/" + t.wa.filter { $0.isNumber })
            guard let u, !(hacer == "llamar" ? t.tel : t.wa).isEmpty else { return }
            colgar()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { UIApplication.shared.open(u) }
            return
        default: return
        }
        publicarTarjeta()
    }

    /// Cada segundo, mientras se ve abierta: a los 20 s sin tocarla se encoge.
    private func relojDeTarjeta() {
        relojTarjeta?.invalidate()
        relojTarjeta = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self, self.estado == .hablando, self.reglasTarjeta.vista != .nada else { t.invalidate(); return }
            if self.reglasTarjeta.tic(ahora: Date()) { self.publicarTarjeta() }
        }
    }

    /// Solo si algo cambió: LlamadaVista (lo publicado) y la página del inicio (AlmaVoz.evento «tarjeta»).
    private func publicarTarjeta() {
        let t = reglasTarjeta.actual, v = reglasTarjeta.vista
        guard t != tarjeta || v != tarjetaVista else { return }
        tarjeta = t; tarjetaVista = v
        emitir(["tipo": "tarjeta", "vista": v.rawValue, "tarjeta": t.map { $0.crudo as Any } ?? NSNull()])
    }

    /// Juan bloquea el teléfono o vuelve a la app a media llamada: el Hub lo sabe antes de la próxima respuesta (con la
    /// pantalla bloqueada Alma lee los datos en voz alta y la tarjeta queda solo en el chat).
    private func vigilarPantalla() {
        avisoPantalla.forEach { NotificationCenter.default.removeObserver($0) }
        let nc = NotificationCenter.default
        avisoPantalla = [
            nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.avisarPantalla() },
            nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.avisarPantalla() }
        ]
    }
    private func avisarPantalla() {
        guard estado == .hablando, let id = idLlamada, let url = Llave.leer("voz_url"), let token = Llave.leer("voz_token"),
              let sesion = Llave.leer("voz_sesion"), let u = URL(string: url) else { return }
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["hub": 1, "action": "vozPantalla", "conv_id": id, "visible": pantallaVisible, "token": token, "session": sesion])
        URLSession.shared.dataTask(with: r).resume()
    }

    // MARK: - Sueño del Modo calle

    /// Cada medio segundo, en una llamada que abrió el Modo calle: ¿ya hay que colgar? (las reglas, en SuenoCalle).
    private func vigilarCalle() {
        vigiaCalle?.invalidate()
        vozJuanCalle = .distantPast; sonidoCalle = .distantPast
        vigiaCalle = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            guard self.estado == .hablando, self.desdeCalle else { t.invalidate(); if self.vigiaCalle === t { self.vigiaCalle = nil }; return }
            guard !self.enChat, !self.mudo else { return }   // modo chat o mudo con la pantalla a la vista: no se cuelga sola
            let m = SuenoCalle.Momentos(conectada: self.conectadaDesde, finVozAlma: self.finVozAlma, vozJuan: self.vozJuanCalle,
                                        sonido: self.sonidoCalle, herramientaDesde: self.herramientaDesde, finHerramienta: self.finHerramienta)
            if let motivo = SuenoCalle.decidir(m, ahora: Date(), silencio: self.calleSilencio, tope: self.calleTope) { self.colgarCalle(motivo) }
        }
    }

    /// Cuelga la llamada del Modo calle sin despedida (solo el sonido de fin): el Modo calle vuelve a esperar «Alma».
    private func colgarCalle(_ m: SuenoCalle.Motivo) {
        guard estado == .hablando || estado == .conectando else { return }
        paso("Modo calle: cuelga (" + m.rawValue + ") y vuelve a esperar «Alma»")
        motivoCalle = m
        terminar()
    }

    // MARK: - Pausa

    private func pausar() {
        pausada = true; avisar(); paso("Pausa · Alma espera")
        mandar(["type": "contextual_update", "text": "PAUSA: Juan tocó el anillo para pausar (está pensando o lo interrumpieron). No hables ni respondas hasta que retome."])
        sonido("alma-fin"); infoBloqueo("En pausa · dos toques para seguir")
        let w = DispatchWorkItem { [weak self] in self?.pausaVencida() }
        pausaT = w; DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: w)
    }
    private func reanudar() {
        pausaT?.cancel(); pausaT = nil; pausada = false; avisar(); ultimaVoz = Date(); paso("Sigue la conversación")
        mandar(["type": "contextual_update", "text": "SIGUE: Juan retomó; sigue escuchando donde iba."])
        sonido("alma-inicio"); infoBloqueo("Te escucho · dos toques para pausar")
    }
    /// 25 s en pausa: lo dicho se toma como enviado. Alma responde y la conversación se cierra sola al terminar.
    private func pausaVencida() {
        guard estado == .hablando, pausada else { return }
        paso("Pausa larga · Alma responde a lo dicho y cierra")
        cerrarTrasRespuesta = true; desdeCierre = Date()
        mandar(["type": "user_message", "text": "(Terminé de hablar. Responde ahora, breve, a lo que te pedí; si ya no hay nada pendiente, despídete en una frase.)"])
        infoBloqueo("Alma te responde…")
    }

    // MARK: - Más rápido: la ficha pedida de antemano

    /// También mientras escucha el Modo Inicio o la conferencia, y con la app abierta: así, al despertarla, no espera al Hub.
    func precargarSiToca() {
        let escucha = Conferencia.shared.activa || EscuchaInicio.shared.escuchando || UIApplication.shared.applicationState == .active
        guard modoAnillo || unRato || escucha, !pidiendoFicha, estado == .lista || estado == .apagada else { return }
        if let f = fichaLista, Date().timeIntervalSince(f.t) < 480 { return }
        guard let url = Llave.leer("voz_url"), let token = Llave.leer("voz_token"), let sesion = Llave.leer("voz_sesion"), let u = URL(string: url) else { return }
        pidiendoFicha = true
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["hub": 1, "action": "vozWeb", "app": "alma", "token": token, "session": sesion])
        URLSession.shared.dataTask(with: r) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self else { return }; self.pidiendoFicha = false
                guard let d = data, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], (j["ok"] as? Bool) == true, j["agent_id"] is String else { return }
                self.fichaLista = (j, Date())
            }
        }.resume()
    }

    // MARK: - Avisos (notificaciones) y lista «un rato»

    /// El Modo calle, al encenderse: pregunta ya por avisos (no espera la próxima vuelta de 45 s).
    func buscarAvisosAhora() { empezarAvisos(); buscarAvisos() }

    private func empezarAvisos() {
        if avisosT == nil { avisosT = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in self?.buscarAvisos() } }
    }

    private func buscarAvisos() {
        guard estado == .lista || estado == .apagada,
              let url = Llave.leer("voz_url"), let token = Llave.leer("voz_token"), let sesion = Llave.leer("voz_sesion"), let u = URL(string: url) else { return }
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type"); r.timeoutInterval = 40
        // La voz de Alma viene junto con el texto (Juan, 6-nov-2026): el Hub arma el audio de ElevenLabs de lo que se va a
        // decir (hasta el nivel «Habladas»; en conferencia también lo que terminó en segundo plano), solo si ahora se puede
        // decir (Modo calle, conferencia o la app abierta). Así suena sin esperar otra vuelta al Hub.
        let hablado = NivelAvisos.nivel("hablado"), ahora = ModoCalle.shared.puedeHablarAvisos
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["hub": 1, "action": "vozAvisos", "token": token, "session": sesion,
                                                                  "hablado": hablado, "conf": Conferencia.shared.activa, "ahora": ahora && hablado > 0])
        URLSession.shared.dataTask(with: r) { [weak self] data, _, _ in
            guard let d = data, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], (j["ok"] as? Bool) == true else { return }
            DispatchQueue.main.async { self?.novedades(j) }
        }.resume()
    }

    private func novedades(_ j: [String: Any]) {
        trabajando = (j["trabajando"] as? NSNumber)?.intValue ?? 0
        porRetomar = (j["pendientes"] as? NSNumber)?.intValue ?? 0
        let l = j["avisos"] as? [[String: Any]] ?? []
        if !l.isEmpty {
            ultimaNovedad = Date(); fichaLista = nil   // la próxima llamada ya empieza por lo nuevo
            // Cada selector de Ajustes filtra por el nivel del aviso (NivelAvisos, ModoCalle.swift): la notificación del
            // teléfono y lo que Alma dice al oído (con el Modo calle, en conferencia o con la app abierta en el inicio).
            for a in l {
                let id = a["id"] as? String ?? UUID().uuidString, texto = a["texto"] as? String ?? "", n = NivelAvisos.deAviso(a)
                // Con su tarjeta de Pendientes, la notificación lleva la respuesta: el título y hasta 3 líneas del resultado.
                let titulo = a["titulo"] as? String ?? "", lineas = a["lineas"] as? [String] ?? []
                if n <= NivelAvisos.nivel("telefono") { Notificaciones.shared.mostrar(id: id, texto: texto, titulo: titulo, lineas: lineas) }
                // Modo conferencia: lo que terminó en segundo plano (resultado) se dice sea cual sea su nivel (salvo «Silencio»).
                let resultado = (a["resultado"] as? Bool) == true, enConf = resultado && Conferencia.shared.activa
                if n <= NivelAvisos.nivel("hablado") || (enConf && NivelAvisos.nivel("hablado") > 0) {
                    ModoCalle.shared.avisoHablado(id: id, texto: texto, resultado: resultado, hablar: a["hablar"] as? String ?? "",
                                                  audio: a["audio"] as? String, vozMotivo: a["vozMotivo"] as? String)
                }
            }
            paso("Aviso: " + String((l.first?["texto"] as? String ?? "").prefix(60)))
        }
        Notificaciones.shared.globo(porRetomar)
        // Sin el modo anillo: mientras Alma trabaja por detrás (o te avisó hace poco), la app queda lista para que dos toques
        // del anillo te reconecten. Después de 15 min sin nada que esperar, se apaga sola.
        guard !modoAnillo, estado == .lista || estado == .apagada else { return }
        let esperar = trabajando > 0 || Date().timeIntervalSince(ultimaNovedad) < 900
        // Juan (audio libre): con el modo anillo apagado no se toma el audio que no se mezcla (pausaría TikTok o la música
        // hasta 15 min). Por eso «un rato» queda apagado; el código sigue para cuando el anillo pase a su nuevo modo.
        if esperar && !unRato && VozNativa.listaUnRato {
            unRato = true; paso("Alma trabaja en segundo plano · dos toques del anillo: modo conferencia"); quedarLista()
            infoBloqueo(trabajando > 0 ? "Alma está trabajando · dos toques para hablar" : "Alma tiene algo para ti · dos toques para hablar")
        } else if !esperar && unRato { apagar() }
    }

    private func fallo(_ m: String) {
        if desdeCalle && motivoCalle == nil { motivoCalle = .corte }
        paso("Error: " + m)
        UserDefaults.standard.set(m, forKey: "voz_ultimo_error")
        emitir(["tipo": "error", "mensaje": m])
        terminar()
        infoBloqueo(m)   // se ve en la pantalla de bloqueo
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in if self?.estado == .lista { self?.infoBloqueo("Dos toques del anillo: modo conferencia") } }
    }

    func urlSession(_ s: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith code: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let por = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        guard estado == .conectando || estado == .hablando else { return }
        // Cierre normal con la llamada en curso: Alma colgó (end_call), por ejemplo porque sigue el pedido en segundo plano.
        if code == .normalClosure && estado == .hablando { paso("Alma colgó"); terminar(); return }
        // Sin créditos de voz: decirlo claro, no solo colgar.
        if por.range(of: "quota_exceeded|credits|quota", options: [.regularExpression, .caseInsensitive]) != nil {
            fallo("Se acabaron los créditos de voz de Alma en ElevenLabs. Recárgalos y vuelve a llamarla; mientras, escríbele por el chat."); return
        }
        fallo("ElevenLabs cerró la voz (\(code.rawValue)) \(por)")
    }

    private func avisar() { emitir(resumen) }
    private func emitir(_ e: [String: Any]) { alEvento?(e) }

    /// Un segundo de silencio en WAV (PCM 16 bits, 8 kHz) para repetir sin fin.
    static func wavSilencio() -> Data? {
        let hz: UInt32 = 8000, muestras = Int(hz), bytes = UInt32(muestras * 2)
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append("RIFF".data(using: .ascii)!); u32(36 + bytes); d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(1); u32(hz); u32(hz * 2); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(bytes); d.append(Data(count: Int(bytes)))
        return d
    }
}

/// Guardado en el llavero de este equipo (la sesión es una llave: no va en las preferencias).
enum Llave {
    static func guardar(_ k: String, _ v: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.spacioam.alma.voz", kSecAttrAccount as String: k]
        SecItemDelete(base as CFDictionary)
        var q = base; q[kSecValueData as String] = Data(v.utf8); q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
    static func leer(_ k: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.spacioam.alma.voz", kSecAttrAccount as String: k,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var r: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess, let d = r as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}
