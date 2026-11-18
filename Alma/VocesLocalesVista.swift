import AVFoundation
import SwiftUI

extension Notification.Name {
    /// Ajustes → Voz y modos → «Voces locales» (Puente: accion "vocesLocales").
    static let abrirVocesLocales = Notification.Name("alma.voces.abrir")
}

/// Ajustes → Voz y modos → Voces locales (Juan, 17-nov-2026): con qué voz hablan Claudio local y Maricarmen. Por personaje:
/// Kokoro (en el teléfono, más natural) o la voz del iPhone; la voz de Kokoro, el acento y la velocidad. El modelo se baja
/// una vez (~92 MB) y queda guardado. Una voz nueva (de grabaciones propias) se agrega por enlace o llega por el catálogo,
/// sin otra versión de la app. «Escuchar las voces» (Hub #780): cada voz del catálogo se oye aquí mismo, sin llamada.
struct VocesLocalesVista: View {
    @ObservedObject private var v = VocesLocales.shared
    @ObservedObject private var llamada = VozNativa.shared
    @Environment(\.dismiss) private var cerrar
    @StateObject private var prueba = PruebaVoz()
    @StateObject private var muestra = MuestraVoces()
    @State private var enlace = ""
    @State private var nombre = ""
    @State private var avisoEnlace: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Etiqueta("Alma · Ajustes")
                            Spacer()
                            Button { cerrar() } label: {
                                Image(systemName: "xmark").font(.system(size: 15, weight: .medium)).frame(width: 40, height: 40)
                                    .background(Circle().fill(Tinta.tinta.opacity(0.06)))
                            }.buttonStyle(.plain).accessibilityLabel("Cerrar")
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Voces")
                            Text("locales").italic()
                        }.font(Tipo.serif(44)).lineSpacing(-4).accessibilityAddTraits(.isHeader)
                        Text("Con qué voz hablan Claudio local y Maricarmen. Por ahora, la voz gratis (de prueba, mientras se hacen las definitivas); Kokoro queda de respaldo. Las dos trabajan en tu iPhone, sin internet ni créditos. Si un día fallan o tardan, sigue la voz del iPhone sin cortar la conversación.")
                            .font(Tipo.sans(13)).foregroundStyle(Tinta.suave)
                    }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
                }
                gratisSeccion
                modelo
                ForEach(VozKokoroReglas.Personaje.allCases, id: \.self) { p in personaje(p) }
                EscucharVocesSeccion(muestra: muestra, antes: { prueba.parar() })   // cada voz con su botón, sin llamada (Hub #780, EscucharVoces.swift)
                Section {
                    TextField("Enlace https a la voz (.bin o .npy)", text: $enlace)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).font(Tipo.sans(14))
                    TextField("Nombre (por ejemplo «Claudio propio»)", text: $nombre).font(Tipo.sans(14))
                    Button("Agregar la voz") {
                        avisoEnlace = v.agregarVoz(enlace: enlace, nombre: nombre, acento: .latino)
                        if avisoEnlace == nil { enlace = ""; nombre = "" }
                    }.font(Tipo.sans(15, .medium)).foregroundStyle(Tinta.peach).disabled(enlace.isEmpty)
                    if let a = avisoEnlace { Text(a).font(Tipo.sans(12)).foregroundStyle(.red) }
                } header: { Text("Una voz propia").font(Tipo.sans(12, .medium)) } footer: {
                    Text("Para las voces hechas con tus grabaciones: el archivo de estilo de Kokoro (510 × 256). Después aparece en la lista de cada personaje.")
                        .font(Tipo.sans(11))
                }
                if let e = v.errorVoz { Section { Text(e).font(Tipo.sans(12)).foregroundStyle(.red) } }
            }
            .scrollContentBackground(.hidden)
            .background(FondoAtardecer())
            .foregroundStyle(Tinta.tinta)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { v.actualizarCatalogo() }
            .onDisappear { prueba.parar(); muestra.parar() }
        }
        .tint(Tinta.peach)
    }

    /// La voz gratis (Pocket, temporal): se baja una vez, como Kokoro.
    private var gratisSeccion: some View {
        Section {
            switch v.gratis {
            case .listo:
                Label("La voz gratis está en tu iPhone", systemImage: "checkmark.circle.fill").font(Tipo.sans(15, .medium))
                Button("Borrar la voz gratis (libera \(VozPocketReglas.megas) MB)", role: .destructive) { v.borrarGratis() }.font(Tipo.sans(14))
            case .bajando(let f):
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bajando la voz gratis… \(Int(f * 100)) %").font(Tipo.sans(14))
                    ProgressView(value: f).tint(Tinta.peach)
                }
            case .falta, .error:
                Button { v.descargarGratis(celular: true) } label: {
                    Label("Bajar la voz gratis (\(VozPocketReglas.megas) MB)", systemImage: "arrow.down.circle.fill").font(Tipo.sans(15, .medium))
                }.foregroundStyle(Tinta.peach)
                if case .error(let e) = v.gratis { Text("No se pudo: " + e).font(Tipo.sans(12)).foregroundStyle(.red) }
            }
        } header: { Text("Voz gratis (de prueba)").font(Tipo.sans(12, .medium)) } footer: {
            Text("Claudio (gratis) y Maricarmen (gratis). Se baja una sola vez; mientras no esté, habla Kokoro o la voz del iPhone. " + VozPocketReglas.credito)
                .font(Tipo.sans(11))
        }
    }

    private var modelo: some View {
        Section {
            switch v.modelo {
            case .listo:
                Label("Kokoro está en tu iPhone", systemImage: "checkmark.circle.fill").font(Tipo.sans(15, .medium))
                Button("Borrar Kokoro (libera 92 MB)", role: .destructive) { v.borrar() }.font(Tipo.sans(14))
            case .bajando(let f):
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bajando Kokoro… \(Int(f * 100)) %").font(Tipo.sans(14))
                    ProgressView(value: f).tint(Tinta.peach)
                }
            case .falta, .error:
                Button { v.descargarModelo(celular: true) } label: {
                    Label("Bajar Kokoro (92 MB)", systemImage: "arrow.down.circle.fill").font(Tipo.sans(15, .medium))
                }.foregroundStyle(Tinta.peach)
                if case .error(let e) = v.modelo { Text("No se pudo: " + e).font(Tipo.sans(12)).foregroundStyle(.red) }
            }
        } header: { Text("Kokoro").font(Tipo.sans(12, .medium)) } footer: {
            Text("Se baja una sola vez y queda guardado. Mientras no esté, hablan con la voz del iPhone; en una conversación con Wi-Fi se baja solo.")
                .font(Tipo.sans(11))
        }
    }

    private func personaje(_ p: VozKokoroReglas.Personaje) -> some View {
        let a = v.ajustes(p)
        let poner = { (cambio: (inout VozKokoroReglas.Ajustes) -> Void) in var b = a; cambio(&b); v.poner(b, para: p) }
        return Section {
            Picker("Motor", selection: Binding(get: { a.motor }, set: { m in poner { $0.motor = m } })) {
                Text("Gratis").tag(VozKokoroReglas.Motor.pocket)
                Text("Kokoro").tag(VozKokoroReglas.Motor.kokoro)
                Text("iPhone").tag(VozKokoroReglas.Motor.iphone)
            }.pickerStyle(.segmented)
            if a.motor == .pocket {
                Text("Habla con \(VozPocketReglas.voz(p).nombre). Si falla, sigue Kokoro con esta voz:").font(Tipo.sans(13)).foregroundStyle(Tinta.suave)
            }
            if a.motor == .kokoro || a.motor == .pocket {
                Picker("Voz", selection: Binding(get: { a.voz }, set: { id in poner { $0.voz = id } })) {
                    ForEach(v.voces) { voz in
                        Text(voz.nombre + (v.bajandoVoz.contains(voz.id) ? " · bajando" : v.vozLista(voz.id) ? "" : " · sin bajar")).tag(voz.id)
                    }
                }.font(Tipo.sans(14))
                Picker("Acento", selection: Binding(get: { a.acento }, set: { c in poner { $0.acento = c } })) {
                    Text("Latino").tag(FonemasES.Acento.latino)
                    Text("España").tag(FonemasES.Acento.espana)
                }.pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "Velocidad %.2f", a.velocidad)).font(Tipo.sans(13))
                    Slider(value: Binding(get: { Double(a.velocidad) }, set: { x in poner { $0.velocidad = Float((x * 20).rounded() / 20) } }),
                           in: Double(VozKokoroReglas.velocidades.lowerBound)...Double(VozKokoroReglas.velocidades.upperBound))
                }
            }
            Button {
                muestra.parar()
                prueba.probar(p)
            } label: {
                Label(prueba.sonando == p ? "Sonando…" : "Probar", systemImage: "play.circle.fill").font(Tipo.sans(15, .medium))
            }.foregroundStyle(Tinta.peach).disabled(llamada.estado == .hablando || llamada.estado == .conectando)
            if prueba.sonando == p, !prueba.nota.isEmpty { Text(prueba.nota).font(Tipo.sans(11)).foregroundStyle(Tinta.suave) }
        } header: { Text(p == .claudio ? "Claudio local" : "Maricarmen").font(Tipo.sans(12, .medium)) } footer: {
            if p == .claudio && a.motor == .kokoro { Text("Provisional: Alex. Las voces definitivas se harán con grabaciones propias.").font(Tipo.sans(11)) }
        }
    }
}

/// «Probar»: dice una frase del personaje con su voz de ahora (Kokoro si está listo; si no, la del iPhone).
final class PruebaVoz: ObservableObject {
    @Published var sonando: VozKokoroReglas.Personaje?
    @Published var nota = ""
    private var habla: HablaPorFrases?
    private var reproductor: AVAudioPlayer?
    private var pcm = Data()

    func probar(_ p: VozKokoroReglas.Personaje) {
        parar()
        sonando = p; nota = ""; pcm = Data()
        var a = ClaudioLocalReglas.Ajustes()
        if p == .maricarmen { a.hombre = false; a.idiomas = MaricarmenReglas.idiomas; a.tono = MaricarmenReglas.tono; a.velocidad = MaricarmenReglas.velocidad }
        let iphone = MotorIphone(voz: p == .maricarmen ? VozIphone.elegida : AVSpeechSynthesisVoice(language: "es-MX"), ajustes: a)
        let hz = ClaudioLocalReglas.hzIphone
        let h = HablaPorFrases(principal: VocesLocales.shared.motor(para: p), respaldo: iphone, hz: hz)
        h.paso = { [weak self] t in self?.nota = t }
        habla = h
        let frase = p == .claudio ? "Listo, Juan. Ya subí el cambio y las pruebas están en verde. ¿Quieres que lo una?" : MaricarmenReglas.saludo
        h.decir(frase, trozo: { [weak self] d in self?.pcm.append(d) }, fin: { [weak self] in
            guard let self else { return }
            guard !self.pcm.isEmpty else { self.sonando = nil; return }
            // Como la Guía de camino: el audio se toma solo si nadie usa el micrófono (Modo calle, conferencia, escucha).
            let ocupado = ModoCalle.shared.ocupaMicrofono || Conferencia.shared.activa || EscuchaInicio.shared.escuchando
            if !ocupado {
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
                try? AVAudioSession.sharedInstance().setActive(true)
            }
            self.reproductor = try? AVAudioPlayer(data: VozKokoroReglas.wav(self.pcm, hz: hz))
            self.reproductor?.play()
            let dura = self.reproductor?.duration ?? 0
            DispatchQueue.main.asyncAfter(deadline: .now() + dura + 0.2) { [weak self] in
                if !ocupado { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
                if self?.sonando == p { self?.sonando = nil }
            }
        })
    }

    func parar() { habla?.cancelar(); habla = nil; reproductor?.stop(); reproductor = nil; sonando = nil }
}
