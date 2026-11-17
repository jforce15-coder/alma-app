import AVFoundation
import MultipeerConnectivity
import UIKit

/// Modo compañero · retransmisión del sonido (Hub #727; Juan, 17-nov-2026: «el audio que se reproduce en el teléfono es lo
/// mismo que se debería reproducir en el iPad»). Directo por la red local (Wi-Fi o la red entre equipos de Apple), sin
/// servidor: el Hub sería lento para la voz. Las reglas de quién puede oír: RetransmisionReglas.swift.
///   · Emisor (el dispositivo de la llamada): VozNativa le pasa cada trozo de voz que suena (`audio`) y los cortes. Busca
///     a su compañero solo mientras hay una llamada y la par del Hub (Companero.swift la recibe en vivoPublicar).
///   · Receptor (el iPad con el Modo compañero y «Con sonido»): la página (alma/inicio.html) lo enciende con
///     { accion: "companero", on, par }; se anuncia y toca lo que llega.
final class Retransmision: NSObject {
    static let shared = Retransmision()
    private typealias R = RetransmisionReglas
    private let yo = MCPeerID(displayName: UIDevice.current.name.isEmpty ? "Alma" : String(UIDevice.current.name.prefix(40)))
    private let q = DispatchQueue(label: "alma.retransmision")

    // Emisor
    private var par = UserDefaults.standard.string(forKey: "comp_par") ?? ""
    private var enLlamada = false
    private var sesionE: MCSession?
    private var buscador: MCNearbyServiceBrowser?
    private var nonces: [MCPeerID: String] = [:]
    private var oyentes: Set<MCPeerID> = []

    // Receptor
    private var parR = ""
    private var sesionR: MCSession?
    private var anunciante: MCNearbyServiceAdvertiser?
    private let motor = AVAudioEngine()
    private let voz = AVAudioPlayerNode()
    private var hzR: Double = 0

    // MARK: emisor

    func ponerPar(_ p: String) { q.async { guard R.parValida(p), p != self.par else { return }; self.par = p; UserDefaults.standard.set(p, forKey: "comp_par"); if self.enLlamada { self.buscar(true) } } }
    func empezo() { q.async { self.enLlamada = true; self.buscar(true) } }
    func fin() { q.async { self.mandar(.fin); self.enLlamada = false; self.buscar(false) } }
    func corte() { q.async { self.mandar(.corte) } }
    /// Un trozo de la voz (PCM de 16 bits, mono) que acaba de agendarse en el teléfono.
    func audio(_ pcm16: Data, hz: Double) { q.async { if !self.oyentes.isEmpty { self.mandar(.audio(hz: Int(hz), pcm: pcm16)) } } }

    private func buscar(_ on: Bool) {
        if on, R.parValida(par) {
            guard buscador == nil else { return }
            let s = MCSession(peer: yo, securityIdentity: nil, encryptionPreference: .required); s.delegate = self; sesionE = s
            let b = MCNearbyServiceBrowser(peer: yo, serviceType: R.servicio); b.delegate = self; b.startBrowsingForPeers(); buscador = b
        } else if !on {
            buscador?.stopBrowsingForPeers(); buscador = nil
            sesionE?.disconnect(); sesionE = nil; nonces = [:]; oyentes = []
        }
    }
    private func mandar(_ p: R.Paquete) {
        guard let s = sesionE, !oyentes.isEmpty else { return }
        let a = Array(oyentes.filter { s.connectedPeers.contains($0) })
        guard !a.isEmpty else { return }
        try? s.send(R.empaquetar(p), toPeers: a, with: .reliable)
    }

    // MARK: receptor

    /// La página encendió o apagó el sonido del compañero en este dispositivo.
    func receptor(on: Bool, par p: String) {
        q.async {
            if on, R.parValida(p) {
                if p == self.parR, self.anunciante != nil { return }
                self.apagarReceptor()
                self.parR = p
                let s = MCSession(peer: self.yo, securityIdentity: nil, encryptionPreference: .required); s.delegate = self; self.sesionR = s
                let a = MCNearbyServiceAdvertiser(peer: self.yo, discoveryInfo: ["a": R.anuncio(p)], serviceType: R.servicio)
                a.delegate = self; a.startAdvertisingPeer(); self.anunciante = a
            } else { self.apagarReceptor() }
        }
    }
    private func apagarReceptor() {
        anunciante?.stopAdvertisingPeer(); anunciante = nil
        sesionR?.disconnect(); sesionR = nil; parR = ""
        DispatchQueue.main.async { self.callar(); if self.motor.isRunning { self.motor.stop() } }
    }
    private func tocar(_ pcm: Data, hz: Double) {
        let n = pcm.count / 2
        guard n > 0, let f = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: hz, channels: 1, interleaved: false),
              let buf = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: AVAudioFrameCount(n)), let ch = buf.floatChannelData else { return }
        buf.frameLength = AVAudioFrameCount(n)
        pcm.withUnsafeBytes { (r: UnsafeRawBufferPointer) in
            let s = r.bindMemory(to: Int16.self)
            for i in 0..<n { ch[0][i] = Float(Int16(littleEndian: s[i])) / 32768 }
        }
        DispatchQueue.main.async {
            // Si este iPad no está en su propia llamada, el sonido sale por su parlante sin cortar lo demás.
            let ses = AVAudioSession.sharedInstance()
            if ses.category != .playAndRecord { try? ses.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers]) }
            try? ses.setActive(true)
            if self.hzR != hz || self.motor.attachedNodes.contains(self.voz) == false {
                if !self.motor.attachedNodes.contains(self.voz) { self.motor.attach(self.voz) } else { self.voz.stop(); self.motor.disconnectNodeOutput(self.voz) }
                self.motor.connect(self.voz, to: self.motor.mainMixerNode, format: f); self.hzR = hz
            }
            if !self.motor.isRunning { do { try self.motor.start() } catch { return } }
            self.voz.scheduleBuffer(buf, completionHandler: nil)
            if !self.voz.isPlaying { self.voz.play() }
        }
    }
    private func callar() { if motor.attachedNodes.contains(voz) { voz.stop() } }
}

extension Retransmision: MCSessionDelegate, MCNearbyServiceBrowserDelegate, MCNearbyServiceAdvertiserDelegate {
    // El teléfono encontró un iPad: solo invita al que se anuncia con la huella de su par.
    func browser(_ b: MCNearbyServiceBrowser, foundPeer p: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        q.async {
            guard let s = self.sesionE, R.parValida(self.par), info?["a"] == R.anuncio(self.par) else { return }
            let n = UUID().uuidString.replacingOccurrences(of: "-", with: ""); self.nonces[p] = n
            b.invitePeer(p, to: s, withContext: R.contexto(self.par, n), timeout: 10)
        }
    }
    func browser(_ b: MCNearbyServiceBrowser, lostPeer p: MCPeerID) { q.async { self.oyentes.remove(p) } }
    // El iPad recibe la invitación: solo acepta la de su par.
    func advertiser(_ a: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer p: MCPeerID, withContext c: Data?, invitationHandler h: @escaping (Bool, MCSession?) -> Void) {
        q.async {
            guard let s = self.sesionR, let n = R.revisar(c, par: self.parR) else { h(false, nil); return }
            self.nonces[p] = n; h(true, s)
        }
    }
    func session(_ s: MCSession, peer p: MCPeerID, didChange e: MCSessionState) {
        q.async {
            if s === self.sesionR, e == .connected, let n = self.nonces[p] { try? s.send(R.empaquetar(.prueba(R.prueba(self.parR, n))), toPeers: [p], with: .reliable) }
            if s === self.sesionE, e == .notConnected { self.oyentes.remove(p) }
        }
    }
    func session(_ s: MCSession, didReceive d: Data, fromPeer p: MCPeerID) {
        guard let paq = R.desempaquetar(d) else { return }
        q.async {
            if s === self.sesionE {   // en el teléfono solo llega la prueba del iPad
                if case .prueba(let x) = paq, let n = self.nonces[p], x == R.prueba(self.par, n) { self.oyentes.insert(p) }
                return
            }
            guard s === self.sesionR else { return }
            switch paq {
            case .audio(let hz, let pcm): self.tocar(pcm, hz: Double(hz))
            case .corte, .fin: DispatchQueue.main.async { self.callar() }
            case .prueba: break
            }
        }
    }
    func session(_ s: MCSession, didReceive st: InputStream, withName n: String, fromPeer p: MCPeerID) {}
    func session(_ s: MCSession, didStartReceivingResourceWithName n: String, fromPeer p: MCPeerID, with pr: Progress) {}
    func session(_ s: MCSession, didFinishReceivingResourceWithName n: String, fromPeer p: MCPeerID, at u: URL?, withError e: Error?) {}
}
