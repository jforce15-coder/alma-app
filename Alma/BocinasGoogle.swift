import Combine
import Foundation
import Network
import Security

/// Bocinas de Google Home en la llamada (Juan, 19-nov-2026). Las reglas y el formato: BocinasGoogleReglas.swift.
///   · Busca en el Wi-Fi las bocinas y los grupos de Google Home mientras está abierta la hoja «Audio de la llamada» o
///     mientras una llamada espera la bocina elegida. Si no la ve (fuera de casa), la voz sale por el teléfono.
///   · Al empezar la llamada abre Google Cast con la bocina (o el grupo), pone el receptor de audio de fábrica y le pide
///     tocar «http://<este teléfono>:<puerto>/alma.wav»: un audio en vivo que el teléfono sirve por el Wi-Fi con la voz
///     de Alma (o de Claudio) al ritmo del reloj, con silencio entre frases para que la bocina no se corte.
///   · Mientras la bocina suena, la voz no suena en el teléfono (VozNativa la agenda en silencio) y el micrófono la ignora
///     un rato más largo. Al colgar, la bocina se apaga.
final class BocinasGoogle: ObservableObject {
    static let shared = BocinasGoogle()
    typealias Bocina = BocinasGoogleReglas.Bocina
    typealias R = BocinasGoogleReglas

    @Published private(set) var encontradas: [Bocina] = []
    @Published private(set) var estado: R.Estado = .apagada { didSet { AudioLlamada.shared.objectWillChange.send() } }
    /// La voz suena en la bocina ahora (se lee desde el hilo del audio).
    private(set) var sonando = false
    /// Hay una bocina conectándose o sonando (se lee desde el hilo del audio, para no guardar voz de más).
    private var enCurso = false

    private let cola = DispatchQueue(label: "com.spacioam.alma.bocinas")
    private var buscador: NWBrowser?
    private var puntos: [String: NWEndpoint] = [:]
    private var vistaAbierta = false
    private var pendiente: (id: String, nombre: String, hasta: Date)?

    // La conexión con la bocina (en `cola`)
    private var cast: NWConnection?
    private var entrada = Data()
    private var transporte: String?
    private var sesionApp: String?
    private var pedido = 1
    private var latido: DispatchSourceTimer?
    private var nombreActivo = ""
    private var generacion = 0

    // El audio en vivo (en `cola`)
    private var servidor: NWListener?
    private var puerto: UInt16?
    private var oyentes: [NWConnection] = []
    private var porSonar: [Int16] = []
    private var reloj: DispatchSourceTimer?
    private var desde: UInt64 = 0
    private var enviadas = 0

    private init() {}

    // MARK: - La hoja «Audio de la llamada»

    func abrioVista() { DispatchQueue.main.async { self.vistaAbierta = true; self.buscar() } }
    func cerroVista() { DispatchQueue.main.async { self.vistaAbierta = false; self.dejarDeBuscar() } }

    // MARK: - La llamada (AudioLlamada.swift)

    /// Empezó la llamada (o Juan eligió la bocina en plena llamada).
    func empezar(id: String, nombre: String) {
        DispatchQueue.main.async {
            self.pararYa(avisa: false)
            self.pendiente = (id, nombre, Date().addingTimeInterval(R.esperaBuscar))
            self.estado = .buscando(nombre)
            self.buscar()
            self.revisarPendiente()
            DispatchQueue.main.asyncAfter(deadline: .now() + R.esperaBuscar + 0.1) { [weak self] in
                guard let self, let p = self.pendiente, p.id == id, Date() >= p.hasta else { return }
                self.pendiente = nil; self.estado = .noEsta(nombre)
                VozNativa.shared.anotar("Bocina de Google: no está en este Wi-Fi · sale por el teléfono")
                self.dejarDeBuscar()
            }
        }
    }

    /// Colgó o eligió otra salida.
    func parar() { DispatchQueue.main.async { self.pararYa(avisa: true) } }

    /// En el hilo principal.
    private func pararYa(avisa: Bool) {
        let habia = enCurso
        pendiente = nil; generacion += 1
        sonando = false; enCurso = false
        if estado != .apagada { estado = .apagada }
        cola.async { self.cerrar() }
        if avisa, habia { VozNativa.shared.anotar("Bocina de Google: apagada") }
        dejarDeBuscar()
    }

    /// La voz que acaba de agendarse en el teléfono (desde cualquier hilo).
    func audio(_ pcm16: Data, hz: Int) {
        guard enCurso else { return }
        let n = pcm16.count / 2
        guard n > 0 else { return }
        var x = [Int16](repeating: 0, count: n)
        pcm16.withUnsafeBytes { (r: UnsafeRawBufferPointer) in
            let s = r.bindMemory(to: Int16.self)
            for i in 0..<n { x[i] = Int16(littleEndian: s[i]) }
        }
        let y = R.remuestrear(x, de: hz)
        cola.async {
            guard self.cast != nil else { return }
            self.porSonar.append(contentsOf: y)
            let tope = R.hz * 30
            if self.porSonar.count > tope { self.porSonar.removeFirst(self.porSonar.count - tope) }
        }
    }

    /// Juan interrumpió: lo que faltaba mandar se tira (lo que la bocina ya guardó todavía suena un momento).
    func corte() { cola.async { self.porSonar.removeAll() } }

    // MARK: - Buscar en el Wi-Fi

    private func buscar() {
        guard buscador == nil else { return }
        let p = NWParameters(); p.includePeerToPeer = false
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: R.servicio, domain: nil), using: p)
        b.browseResultsChangedHandler = { [weak self] res, _ in
            var lista: [Bocina] = [], pts: [String: NWEndpoint] = [:]
            for r in res {
                guard case let .service(nombre, _, _, _) = r.endpoint else { continue }
                var txt: [String: String] = [:]
                if case let .bonjour(t) = r.metadata { txt = t.dictionary }
                if let bo = R.bocina(servicio: nombre, txt: txt), pts[bo.id] == nil { lista.append(bo); pts[bo.id] = r.endpoint }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.puntos = pts; self.encontradas = R.ordenar(lista); self.revisarPendiente()
            }
        }
        b.stateUpdateHandler = { [weak self] st in
            if case .failed = st { DispatchQueue.main.async { if self?.buscador === b { self?.buscador = nil } } }
        }
        b.start(queue: cola)
        buscador = b
    }

    private func dejarDeBuscar() {
        guard !vistaAbierta, pendiente == nil, let b = buscador else { return }
        b.cancel(); buscador = nil
    }

    private func revisarPendiente() {
        guard let p = pendiente, let punto = puntos[p.id] else { return }
        pendiente = nil
        let nombre = encontradas.first(where: { $0.id == p.id })?.nombre ?? p.nombre
        estado = .conectando(nombre); enCurso = true
        generacion += 1
        let g = generacion
        cola.async { self.conectar(punto, nombre: nombre) }
        DispatchQueue.main.asyncAfter(deadline: .now() + R.esperaSonar) { [weak self] in
            guard let self, self.generacion == g, case .conectando = self.estado else { return }
            self.fallo("no empezó a sonar")
        }
        dejarDeBuscar()
    }

    private func fallo(_ porque: String) {
        DispatchQueue.main.async {
            guard self.enCurso else { return }
            let n = self.nombreActivoMain
            self.sonando = false; self.enCurso = false
            self.estado = .fallo(n, porque)
            self.cola.async { self.cerrar() }
            VozNativa.shared.anotar("Bocina de Google: " + porque + " · sale por el teléfono")
        }
    }
    private var nombreActivoMain: String {
        switch estado {
        case .buscando(let n), .conectando(let n), .sonando(let n), .noEsta(let n), .fallo(let n, _): return n
        case .apagada: return "la bocina"
        }
    }

    // MARK: - Google Cast (en `cola`)

    private func conectar(_ punto: NWEndpoint, nombre: String) {
        cerrar()
        nombreActivo = nombre
        abrirServidor()
        let tls = NWProtocolTLS.Options()
        // Las bocinas usan un certificado propio, sin firma de una autoridad: en la red de la casa se acepta.
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, listo in listo(true) }, cola)
        let tcp = NWProtocolTCP.Options(); tcp.connectionTimeout = 6
        let c = NWConnection(to: punto, using: NWParameters(tls: tls, tcp: tcp))
        c.stateUpdateHandler = { [weak self, weak c] st in
            guard let self, let c, self.cast === c else { return }
            switch st {
            case .ready: self.alAbrir()
            case .failed(let e): self.fallo("no pude conectar: \(e.localizedDescription.prefix(60))")
            case .waiting(let e): self.fallo("la red no deja: \(e.localizedDescription.prefix(60))")
            default: break
            }
        }
        cast = c
        c.start(queue: cola)
        recibir(c)
    }

    private func alAbrir() {
        mandar(R.espacioConexion, a: "receiver-0", ["type": "CONNECT"])
        mandar(R.espacioReceptor, a: "receiver-0", ["type": "LAUNCH", "appId": R.appReceptor, "requestId": siguiente()])
        let t = DispatchSource.makeTimerSource(queue: cola)
        t.schedule(deadline: .now() + 5, repeating: 5)
        t.setEventHandler { [weak self] in self?.mandar(R.espacioLatido, a: "receiver-0", ["type": "PING"]) }
        t.resume(); latido = t
    }

    private func recibir(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] datos, _, fin, error in
            guard let self, self.cast === c else { return }
            if let datos { self.entrada.append(datos); R.desempacar(&self.entrada).forEach(self.atender) }
            if error != nil || fin { if self.sonando || self.transporte != nil { self.fallo("la bocina cortó") } ; return }
            self.recibir(c)
        }
    }

    private func atender(_ m: R.Mensaje) {
        let o = R.objeto(m.texto), tipo = o["type"] as? String ?? ""
        switch m.espacio {
        case R.espacioLatido:
            if tipo == "PING" { mandar(R.espacioLatido, a: m.origen, ["type": "PONG"]) }
        case R.espacioConexion:
            if tipo == "CLOSE", m.origen == transporte || m.origen == "receiver-0" { fallo("la bocina cerró") }
        case R.espacioReceptor:
            if tipo == "LAUNCH_ERROR" { fallo("la bocina no abrió el audio"); return }
            if transporte == nil, let r = R.receptor(o) {
                transporte = r.transporte; sesionApp = r.sesion
                mandar(R.espacioConexion, a: r.transporte, ["type": "CONNECT"])
                cargarAudio()
            }
        case R.espacioMedia:
            if tipo == "LOAD_FAILED" || tipo == "LOAD_CANCELLED" || tipo == "INVALID_REQUEST" { fallo("la bocina no tocó el audio"); return }
            if let r = R.reproductor(o) {
                if r.estado == "PLAYING" || r.estado == "BUFFERING" {
                    let n = nombreActivo
                    DispatchQueue.main.async {
                        guard !self.sonando else { return }
                        self.sonando = true; self.estado = .sonando(n)
                        VozNativa.shared.anotar("Bocina de Google: Alma suena en la bocina elegida")
                    }
                } else if r.estado == "IDLE", r.porque != nil, sonando { fallo("la bocina dejó de tocar (\(r.porque ?? ""))") }
            }
        default: break
        }
    }

    private func cargarAudio(intento: Int = 0) {
        guard let t = transporte else { return }
        guard let p = puerto, let ip = ipLocal() else {
            if intento < 10 { cola.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.cargarAudio(intento: intento + 1) } }
            else { fallo("no tengo dirección en el Wi-Fi") }
            return
        }
        mandar(R.espacioMedia, a: t, R.cargar(url: R.url(host: ip, puerto: p), pedido: siguiente()))
    }

    private func siguiente() -> Int { pedido += 1; return pedido }

    private func mandar(_ espacio: String, a destino: String, _ o: [String: Any]) {
        guard let c = cast else { return }
        c.send(content: R.empacar(R.Mensaje(origen: "sender-0", destino: destino, espacio: espacio, texto: R.json(o))), completion: .contentProcessed { _ in })
    }

    /// Apaga la bocina y suelta todo (en `cola`).
    private func cerrar() {
        if let c = cast {
            if let s = sesionApp { mandar(R.espacioReceptor, a: "receiver-0", ["type": "STOP", "sessionId": s, "requestId": siguiente()]) }
            if let t = transporte { mandar(R.espacioConexion, a: t, ["type": "CLOSE"]) }
            mandar(R.espacioConexion, a: "receiver-0", ["type": "CLOSE"])
            cola.asyncAfter(deadline: .now() + 0.4) { c.cancel() }
        }
        cast = nil; entrada = Data(); transporte = nil; sesionApp = nil
        latido?.cancel(); latido = nil
        reloj?.cancel(); reloj = nil
        oyentes.forEach { $0.cancel() }; oyentes = []
        servidor?.cancel(); servidor = nil; puerto = nil
        porSonar = []; enviadas = 0
    }

    // MARK: - El audio en vivo que toca la bocina (en `cola`)

    private func abrirServidor() {
        guard servidor == nil, let l = try? NWListener(using: .tcp, on: .any) else { return }
        l.stateUpdateHandler = { [weak self, weak l] st in
            guard let self, let l, self.servidor === l else { return }
            if case .ready = st { self.puerto = l.port?.rawValue }
            if case .failed = st { self.fallo("no pude servir el audio") }
        }
        l.newConnectionHandler = { [weak self] c in self?.atenderOyente(c) }
        servidor = l
        l.start(queue: cola)
    }

    private func atenderOyente(_ c: NWConnection) {
        c.start(queue: cola)
        c.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] datos, _, _, error in
            guard let self, self.cast != nil, error == nil else { c.cancel(); return }
            let r = R.respuestaHttp(pedido: String(decoding: datos ?? Data(), as: UTF8.self))
            c.send(content: r.cabecera, completion: .contentProcessed { _ in })
            guard r.sigue else { c.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in c.cancel() }); return }
            self.oyentes.append(c)
            self.arrancarReloj()
        }
    }

    /// Cada 40 ms manda lo que toca para ir al ritmo del reloj: la voz pendiente y, si no hay, silencio.
    private func arrancarReloj() {
        guard reloj == nil else { return }
        desde = DispatchTime.now().uptimeNanoseconds; enviadas = 0
        let t = DispatchSource.makeTimerSource(queue: cola)
        t.schedule(deadline: .now(), repeating: .milliseconds(40), leeway: .milliseconds(5))
        t.setEventHandler { [weak self] in self?.tic() }
        t.resume(); reloj = t
    }

    private func tic() {
        guard !oyentes.isEmpty else { return }
        let seg = Double(DispatchTime.now().uptimeNanoseconds - desde) / 1e9
        let n = R.porMandar(segundos: seg, enviadas: enviadas)
        guard n > 0 else { return }
        var bloque = [Int16](repeating: 0, count: n)
        let k = min(n, porSonar.count)
        if k > 0 { for i in 0..<k { bloque[i] = porSonar[i] }; porSonar.removeFirst(k) }
        enviadas += n
        var d = Data(capacity: n * 2)
        for v in bloque { let u = UInt16(bitPattern: v.littleEndian); d.append(UInt8(u & 0xff)); d.append(UInt8(u >> 8)) }
        for c in oyentes {
            c.send(content: d, completion: .contentProcessed { [weak self, weak c] e in
                guard e != nil, let self, let c else { return }
                self.cola.async { self.oyentes.removeAll { $0 === c }; c.cancel() }
            })
        }
    }

    /// La dirección de este teléfono en el Wi-Fi (IPv4 de preferencia: la bocina la entiende mejor).
    private func ipLocal() -> String? {
        if case let .hostPort(host, _)? = cast?.currentPath?.localEndpoint, case let .ipv4(a) = host { return "\(a)" }
        var lista: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&lista) == 0, let primero = lista else { return nil }
        defer { freeifaddrs(lista) }
        var ip: String?
        for p in sequence(first: primero, next: { $0.pointee.ifa_next }) {
            let i = p.pointee
            guard let a = i.ifa_addr, a.pointee.sa_family == UInt8(AF_INET), String(cString: i.ifa_name) == "en0" else { continue }
            var h = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(a, socklen_t(a.pointee.sa_len), &h, socklen_t(h.count), nil, 0, NI_NUMERICHOST) == 0 { ip = String(cString: h); break }
        }
        return ip
    }
}
