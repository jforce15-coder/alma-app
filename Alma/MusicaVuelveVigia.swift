import AVFoundation
import UIKit

/// El vigía de «La música vuelve» (Hub #822): mira cada segundo si la música de otra app paró por Alma y, cuando Alma
/// termina, le pide al Hub que Spotify siga (reglas en MusicaVuelve.swift). Todo en el hilo principal.
final class VigiaMusica {
    static let shared = VigiaMusica()
    private var reglas = MusicaVuelve()
    private var reloj: Timer?
    private var pidiendo = false

    func empezar() {
        guard reloj == nil else { return }
        reloj = Timer.scheduledTimer(withTimeInterval: MusicaVuelve.cada, repeats: true) { [weak self] _ in self?.mirar() }
    }

    /// Alma tomó, cambió o soltó su audio: si la música para en los próximos segundos, la paró Alma.
    static func tomo(_ motivo: String) {
        if Thread.isMainThread { shared.reglas.tomo(motivo, ahora: Date()) }
        else { DispatchQueue.main.async { shared.reglas.tomo(motivo, ahora: Date()) } }
    }

    private func mirar() {
        let v = VozNativa.shared
        let ocupada = v.estado == .hablando || v.estado == .conectando || ModoCalle.shared.atendiendo
        switch reglas.mirar(suena: AVAudioSession.sharedInstance().isOtherAudioPlaying, almaOcupada: ocupada, ahora: Date()) {
        case .nada: return
        case .paro(let m): v.anotar("La música de otra app paró (" + m + "): vuelve cuando Alma termine")
        case .pedir: pedir()
        }
    }

    private func pedir() {
        guard !pidiendo else { return }
        pidiendo = true
        VozNativa.shared.anotar("Alma terminó: le pido a Spotify que siga")
        ModoCalle.shared.llamarHub([:], accion: "musicaVuelve", timeout: 12) { [weak self] j in
            self?.pidiendo = false
            VozNativa.shared.anotar(MusicaVuelve.texto(j))
        }
    }
}
