import AVFoundation
import Combine
import SwiftUI

/// «Escuchar las voces» (Hub #780; Juan, 18-nov-2026: «no solo para escuchar los audios contigo»): en Ajustes → Voz y modos →
/// Voces locales, cada voz del catálogo (las de Kokoro y las propias) con su botón para oírla aquí mismo, sin llamada y sin
/// elegirla para un personaje. Siempre con Kokoro: una muestra con la voz del iPhone engañaría. Si la voz no está en el
/// teléfono, se baja al tocar y suena al terminar.
struct EscucharVocesSeccion: View {
    @ObservedObject private var v = VocesLocales.shared
    @ObservedObject private var llamada = VozNativa.shared
    @ObservedObject var muestra: MuestraVoces
    /// Lo que se para antes de sonar (el «Probar» de un personaje).
    var antes: () -> Void = {}

    var body: some View {
        Section {
            ForEach(v.voces) { voz in fila(voz) }
            if !muestra.nota.isEmpty { Text(muestra.nota).font(Tipo.sans(12)).foregroundStyle(Tinta.suave) }
        } header: { Text("Escuchar las voces").font(Tipo.sans(12, .medium)) } footer: {
            Text(v.modelo == .listo
                 ? "Cada voz dice una frase corta, aquí mismo y sin llamada. Para usar una, elígela arriba en Claudio local o Maricarmen."
                 : "Para escucharlas, primero baja Kokoro (arriba).")
                .font(Tipo.sans(11))
        }
    }

    private func fila(_ voz: VozKokoroReglas.Voz) -> some View {
        let suena = muestra.sonando == voz.id, espera = muestra.esperando == voz.id
        let enLlamada = llamada.estado == .hablando || llamada.estado == .conectando
        return Button {
            if suena || espera { muestra.parar() } else { antes(); muestra.sonar(voz) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: suena || espera ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28)).foregroundStyle(Tinta.peach)
                VStack(alignment: .leading, spacing: 2) {
                    Text(voz.nombre).font(Tipo.sans(15, .medium)).foregroundStyle(Tinta.tinta)
                    Text(suena ? "Sonando…" : VozKokoroReglas.detalleMuestra(voz, lista: v.vozLista(voz.id), bajando: v.bajandoVoz.contains(voz.id)))
                        .font(Tipo.sans(12)).foregroundStyle(Tinta.suave)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(v.modelo != .listo || enLlamada)
        .accessibilityLabel(suena || espera ? "Parar \(voz.nombre)" : "Escuchar \(voz.nombre)")
    }
}

/// Dice la muestra de una voz con Kokoro y la toca. Una a la vez: tocar otra para la anterior.
final class MuestraVoces: ObservableObject {
    @Published private(set) var sonando: String?
    /// La voz que se está bajando para sonar en cuanto llegue.
    @Published private(set) var esperando: String?
    @Published private(set) var nota = ""
    private var motor: MotorKokoro?
    private var reproductor: AVAudioPlayer?
    private var espera: AnyCancellable?
    private var vuelta = 0
    private let hz = VozKokoroReglas.hzModelo

    func sonar(_ voz: VozKokoroReglas.Voz) {
        parar()
        let v = VocesLocales.shared
        guard v.modeloListo else { nota = "Primero baja Kokoro (arriba)."; return }
        guard v.vozLista(voz.id) else {
            esperando = voz.id
            v.descargarVoz(voz.id, celular: true)
            // Cuando deja de bajarse: si quedó en el teléfono suena; si no, el error ya sale en la pantalla (errorVoz).
            espera = v.$bajandoVoz.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] b in
                guard let self, self.esperando == voz.id, !b.contains(voz.id) else { return }
                self.espera = nil; self.esperando = nil
                if v.vozLista(voz.id) { self.sonar(voz) } else { self.nota = "No se pudo bajar \(voz.nombre)." }
            }
            return
        }
        guard let tabla = v.tabla(voz.id) else { nota = "La voz \(voz.nombre) no se pudo leer."; return }
        vuelta += 1
        let mia = vuelta
        sonando = voz.id
        let m = MotorKokoro(ajustes: VozKokoroReglas.ajustesMuestra(voz), tabla: tabla, excepciones: v.pronunciaciones)
        motor = m
        var pcm = Data()
        var frases = VozKokoroReglas.frases(VozKokoroReglas.muestra(voz))
        func siguiente() {
            guard mia == vuelta else { return }
            guard !frases.isEmpty else { tocar(pcm, mia); return }
            m.sintetizar(frases.removeFirst(), hz: hz, trozo: { pcm.append($0) }, fin: { [weak self] ok in
                guard let self, mia == self.vuelta else { return }
                if ok { siguiente() } else { self.nota = "Kokoro no pudo decir la muestra."; self.sonando = nil }
            })
        }
        siguiente()
    }

    private func tocar(_ pcm: Data, _ mia: Int) {
        guard !pcm.isEmpty else { sonando = nil; return }
        // Como «Probar»: el audio se toma solo si nadie usa el micrófono (Modo calle, conferencia, escucha del inicio).
        let ocupado = ModoCalle.shared.ocupaMicrofono || Conferencia.shared.activa || EscuchaInicio.shared.escuchando
        if !ocupado {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        reproductor = try? AVAudioPlayer(data: VozKokoroReglas.wav(pcm, hz: hz))
        reproductor?.play()
        let dura = reproductor?.duration ?? 0
        DispatchQueue.main.asyncAfter(deadline: .now() + dura + 0.2) { [weak self] in
            if !ocupado { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
            guard let self, mia == self.vuelta else { return }
            self.sonando = nil
        }
    }

    func parar() {
        vuelta += 1
        motor?.cancelar(); motor = nil
        reproductor?.stop(); reproductor = nil
        espera = nil; esperando = nil; sonando = nil; nota = ""
    }
}
