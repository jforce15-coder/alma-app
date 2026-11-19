import AVFoundation
import MultipeerConnectivity
import UIKit

/// Modo compañero con sonido (Hub #727; Juan, 17-nov-2026: «El audio que se reproduce en el teléfono es lo mismo que se
/// debería reproducir en el iPad»). Las reglas y el formato de lo que se manda: RetransmisionReglas.swift.
///   · El dispositivo de la llamada (el iPhone) se anuncia en la red de cerca mientras dura la llamada y le manda al
///     compañero cada trozo de la voz de Alma (o de Claudio) en el momento en que lo pone a sonar, más «corte» cuando
///     Juan la interrumpe y «fin» al colgar. No pasa por internet ni por el Hub, así que llega casi al mismo tiempo.
///   · El compañero (el iPad con «Modo compañero» encendido, que la página avisa con { accion: "companero", on }) busca
///     esa llamada con la app abierta y reproduce lo que llega. El micrófono sigue solo en el teléfono.
///   · Solo se juntan dispositivos de la misma cuenta (la huella de la llave de la app) y el canal va cifrado.
final class Retransmision: NSObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    static let shared = Retransmision()
    static let servicio = "alma-vivo"   // NSBonjourServices: _alma-vivo._tcp y _alma-vivo._udp (project.yml)
    private static let clave = "companero_on"

    private let yo = MCPeerID(displayName: UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")
    private lazy var sesion: MCSession = {
        let s = MCSession(peer: yo, securityIdentity: nil, encryptionPreference: .required); s.delegate = self; return s
    }()
    private var anunciante: MCNearbyServiceAdvertiser?
    private var buscador: MCNearbyServiceBrowser?
    private var reglas = ReglasRetransmision()
    private let envio = DispatchQueue(label: "com.spacioam.alma.retransmision")

    // Lo que suena en el compañero
    private let motor = AVAudioEngine()
    private let reproductor = AVAudioPlayerNode()
    private var hzSonando = 0

    private override init() {
        super.init()
        reglas.companero = UserDefaults.standard.bool(forKey: Retransmision.clave)
        reglas.aLaVista = UIApplication.shared.applicationState != .background
        motor.attach(reproductor)
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.reglas.aLaVista = true; self?.actualizar() }
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.reglas.aLaVista = false; self?.actualizar() }
    }

    /// Para que arranque al abrir la app (si el Modo compañero ya estaba encendido en este dispositivo).
    func arrancar() { DispatchQueue.main.async { self.actualizar() } }

    // MARK: - Lo que dice la página (el interruptor del Modo compañero de este dispositivo)

    func poner(companero on: Bool) {
        DispatchQueue.main.async {
            UserDefaults.standard.set(on, forKey: Retransmision.clave)
            self.reglas.companero = on; self.actualizar()
        }
    }

    // MARK: - El dispositivo de la llamada (Companero.swift y VozNativa.swift)

    func empezo() {
        DispatchQueue.main.async {
            self.reglas.llamadaAqui = true; self.actualizar()
            guard self.anunciante == nil, let p = ReglasRetransmision.pareja(Llave.leer("voz_token")) else { return }
            let a = MCNearbyServiceAdvertiser(peer: self.yo, discoveryInfo: ["p": p], serviceType: Retransmision.servicio)
            a.delegate = self; a.startAdvertisingPeer(); self.anunciante = a
        }
    }

    func termino() {
        DispatchQueue.main.async {
            guard self.reglas.llamadaAqui else { return }
            self.mandar(.fin)
            self.anunciante?.stopAdvertisingPeer(); self.anunciante = nil
            self.reglas.llamadaAqui = false
            self.envio.asyncAfter(deadline: .now() + 1) { [weak self] in self?.sesion.disconnect() }   // que alcance a llegar el «fin»
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.actualizar() }
        }
    }

    /// La voz que acaba de ponerse a sonar aquí (desde cualquier hilo).
    func audio(_ pcm16: Data, hz: Int) { mandar(.audio(hz: hz, pcm: pcm16)) }
    /// Juan interrumpió: lo que quedaba se tira también en el compañero.
    func corte() { mandar(.corte) }
    /// Lo que se ve, al momento (Juan, 19-nov-2026): cada subtítulo y cada cambio de estado (Companero.swift).
    func texto(alma: Bool, _ t: String) {
        let limpio = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        if !limpio.isEmpty { mandar(.texto(alma: alma, t: limpio)) }
    }
    func estado(_ e: String) { mandar(.estado(e)) }

    /// En el compañero: lo que llega por la red de cerca va a la página al momento (AlmaCompanero.cerca en alma/inicio.html):
    /// { tipo: "sub", de, t } · { tipo: "estado", estado } · { tipo: "nivel", v }. Lo pone Puente (accion «companero»).
    var alCerca: (([String: Any]) -> Void)?
    private var ultimoNivel = Date.distantPast

    private func mandar(_ p: PaqueteVivo) {
        envio.async { [weak self] in
            guard let self, !self.sesion.connectedPeers.isEmpty else { return }
            try? self.sesion.send(p.datos(), toPeers: self.sesion.connectedPeers, with: .reliable)
        }
    }

    // MARK: - Buscar y conectar

    private func actualizar() {
        if reglas.busca, buscador == nil {
            let b = MCNearbyServiceBrowser(peer: yo, serviceType: Retransmision.servicio); b.delegate = self; b.startBrowsingForPeers(); buscador = b
        } else if !reglas.busca, let b = buscador {
            b.stopBrowsingForPeers(); buscador = nil
        }
        if !reglas.suena { callar(apagar: true); if !reglas.llamadaAqui { envio.async { [weak self] in self?.sesion.disconnect() } } }
    }

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            guard self.reglas.busca, let p = ReglasRetransmision.pareja(Llave.leer("voz_token")), info?["p"] == p,
                  !self.sesion.connectedPeers.contains(peerID) else { return }
            browser.invitePeer(peerID, to: self.sesion, withContext: Data(p.utf8), timeout: 10)
        }
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async { if self.buscador === browser { self.buscador = nil } }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async {
            let ok = ReglasRetransmision.acepta(contexto: context, pareja: ReglasRetransmision.pareja(Llave.leer("voz_token")), llamadaAqui: self.reglas.llamadaAqui)
            invitationHandler(ok, ok ? self.sesion : nil)
        }
    }
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async { if self.anunciante === advertiser { self.anunciante = nil } }
    }

    // MARK: - Lo que llega al compañero

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let p = PaqueteVivo.leer(data) else { return }
        DispatchQueue.main.async {
            guard self.reglas.suena else { return }
            switch p {
            case let .audio(hz, pcm):
                self.sonar(pcm, hz: hz)
                if Date().timeIntervalSince(self.ultimoNivel) > 0.08 { self.ultimoNivel = Date(); self.alCerca?(["tipo": "nivel", "v": NivelVivo.de(pcm)]) }
            case .corte: self.callar(apagar: false); self.alCerca?(["tipo": "nivel", "v": 0])
            case .fin: self.callar(apagar: true); self.alCerca?(["tipo": "estado", "estado": "fin"])
            case let .texto(alma, t): self.alCerca?(["tipo": "sub", "de": alma ? "alma" : "yo", "t": t])
            case let .estado(e): self.alCerca?(["tipo": "estado", "estado": e])
            }
        }
    }
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        if state == .notConnected { DispatchQueue.main.async { if !self.reglas.llamadaAqui { self.callar(apagar: true) } } }
    }
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    private func sonar(_ pcm16: Data, hz: Int) {
        let n = pcm16.count / 2
        guard n > 0, let f = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(hz), channels: 1, interleaved: false),
              let buf = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: AVAudioFrameCount(n)), let ch = buf.floatChannelData else { return }
        buf.frameLength = AVAudioFrameCount(n)
        pcm16.withUnsafeBytes { (r: UnsafeRawBufferPointer) in
            let s = r.bindMemory(to: Int16.self)
            for i in 0..<n { ch[0][i] = Float(Int16(littleEndian: s[i])) / 32768 }
        }
        if hz != hzSonando || !motor.isRunning {
            let a = AVAudioSession.sharedInstance()
            // Si este dispositivo ya usa el micrófono (escucha del inicio), se respeta su modo; si no, solo reproducir.
            if a.category != .playAndRecord { try? a.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers]) }
            try? a.setActive(true)
            reproductor.stop()
            if hz != hzSonando { motor.disconnectNodeOutput(reproductor); motor.connect(reproductor, to: motor.mainMixerNode, format: f); hzSonando = hz }
            if !motor.isRunning { motor.prepare(); try? motor.start() }
        }
        guard motor.isRunning else { return }
        reproductor.scheduleBuffer(buf, completionHandler: nil)
        if !reproductor.isPlaying { reproductor.play() }
    }

    /// `apagar`: al terminar la llamada se suelta el audio del dispositivo; en un corte solo se tira lo pendiente.
    private func callar(apagar: Bool) {
        reproductor.stop()
        guard apagar, motor.isRunning else { return }
        motor.stop()
    }
}
