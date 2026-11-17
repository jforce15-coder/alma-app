import SwiftUI

/// La conversación del modo anillo, en pantalla: si hablas con Alma con el teléfono bloqueado y abres la app,
/// aquí sigue la misma llamada (no se corta), con la roca latiendo con la voz, lo último que se dijo y «Terminar».
struct LlamadaVista: View {
    @ObservedObject var voz: VozNativa
    let ocultar: () -> Void
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento
    @ObservedObject private var audio = AudioLlamada.shared
    @State private var verAudio = false
    /// Tarjeta de la llamada abierta (#446 T2): la roca se achica a 96 px y la tarjeta sube desde abajo.
    private var conTarjeta: Bool { voz.tarjeta != nil && (voz.tarjetaVista == .abierta || voz.tarjetaVista == .detalle) }
    private var conPestana: Bool { voz.tarjeta != nil && voz.tarjetaVista == .pestana }

    private var estadoTexto: String {
        switch voz.estado {
        case .conectando: return "Conectando…"
        case .hablando: return voz.pausada ? "En pausa" : voz.agente.estadoTexto(habla: voz.almaHabla)
        default: return "En pausa"
        }
    }

    var body: some View {
        ZStack {
            // el mismo atardecer del inicio de Alma
            LinearGradient(stops: [.init(color: Color(red: 0.36, green: 0.42, blue: 0.53), location: 0),
                                   .init(color: Color(red: 0.62, green: 0.57, blue: 0.62), location: 0.32),
                                   .init(color: Color(red: 0.95, green: 0.70, blue: 0.58), location: 0.62),
                                   .init(color: Color(red: 0.98, green: 0.65, blue: 0.50), location: 1)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button(action: ocultar) {
                        Image(systemName: "chevron.down").font(.system(size: 15, weight: .semibold))
                            .frame(width: 40, height: 40).background(Circle().fill(.white.opacity(0.16)))
                    }
                    Spacer()
                    Text(voz.agente == .claudio ? "CLAUDIO" : "ALMA").tracking(3.5).font(.custom("Montserrat", size: 11).weight(.medium))
                    Spacer()
                    // Audio de la llamada (Juan, 17-nov-2026): el micrófono y la salida (AudioLlamada.swift).
                    Button { verAudio = true } label: {
                        Image(systemName: audio.iconoAhora).font(.system(size: 15, weight: .semibold))
                            .frame(width: 40, height: 40).background(Circle().fill(.white.opacity(0.16)))
                    }
                    .accessibilityLabel("Audio de la llamada: micrófono y salida")
                }
                .foregroundStyle(.white)
                if conPestana, let t = voz.tarjeta { pestana(t).padding(.top, 10).transition(.opacity) }
                Spacer(minLength: conTarjeta ? 4 : 8)
                roca
                Text(estadoTexto)
                    .font(.custom("Cormorant Garamond", size: conTarjeta ? 26 : 34).italic())
                    .foregroundStyle(.white)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: estadoTexto)
                    .padding(.top, conTarjeta ? 6 : 44)
                VStack(alignment: .leading, spacing: 10) {
                    // Solo lo último: dos frases, de dos líneas como mucho (la conversación completa queda en el chat).
                    // Con la tarjeta, una sola frase de una línea: lo demás ya se ve en la tarjeta.
                    ForEach(Array(voz.lineas.suffix(conTarjeta ? 1 : 2))) { l in
                        Text(l.texto).lineLimit(conTarjeta ? 1 : 2).truncationMode(.head)
                            .font(l.alma ? .custom("Cormorant Garamond", size: 20) : .custom("Montserrat", size: 14))
                            .foregroundStyle(.white.opacity(l.alma ? 0.95 : 0.7))
                            .frame(maxWidth: .infinity, alignment: l.alma ? .leading : .trailing)
                            .multilineTextAlignment(l.alma ? .leading : .trailing)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .animation(.easeOut(duration: 0.35), value: voz.lineas.count)
                .frame(maxWidth: 420, minHeight: conTarjeta ? 0 : 96, alignment: .bottom)
                .padding(.top, conTarjeta ? 6 : 24)
                Spacer(minLength: conTarjeta ? 10 : 8)
                if conTarjeta, let t = voz.tarjeta {
                    TarjetaVozVista(t: t, detalle: voz.tarjetaVista == .detalle) { voz.tarjetaAccion($0) }
                        .id(t.id)
                        .transition(sinMovimiento ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 14)
                }
                // La Adaptación y el Modo Weebo se ven solo en Ajustes → Personalidad de Alma (Juan, 6-nov-2026), no aquí.
                Button { voz.colgar() } label: {
                    HStack(spacing: 12) {
                        Circle().fill(Color.almaCoral).frame(width: 7, height: 7)
                        Text("TERMINAR").tracking(2.4).font(.custom("Montserrat", size: 12).weight(.semibold))
                    }
                    .padding(.leading, 22).padding(.trailing, 26).frame(height: 54)
                    .background(Capsule().fill(Color(red: 0.18, green: 0.19, blue: 0.19)))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                Text(conTarjeta ? "Toca la tarjeta para ver más · la llamada sigue" : "Dos toques en tu anillo: pausa · otros dos: sigue")
                    .font(.custom("Montserrat", size: 11)).foregroundStyle(.white.opacity(0.7)).padding(.top, conTarjeta ? 8 : 12)
            }
            .padding(.horizontal, conTarjeta ? 12 : 24).padding(.vertical, 18)
            .animation(sinMovimiento ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.86), value: voz.tarjetaVista)
        }
        .sheet(isPresented: $verAudio) { AudioLlamadaVista().presentationDetents([.large]).presentationDragIndicator(.visible).presentationCornerRadius(28) }
    }

    /// La pestañita de la tarjeta: arriba, bajo «ALMA». Tocarla la abre otra vez.
    private func pestana(_ t: TarjetaVoz) -> some View {
        Button { voz.tarjetaAccion("abrir") } label: {
            HStack(spacing: 8) {
                Circle().fill(Color.almaCoral).frame(width: 7, height: 7)
                Text(TarjetaVozVista.nombre(t.tipo) + " · " + t.titulo).lineLimit(1)
                Image(systemName: "chevron.up").font(.system(size: 11, weight: .bold))
            }
            .font(.custom("Montserrat", size: 12.5).weight(.semibold)).foregroundStyle(Color.almaTinta)
            .padding(.horizontal, 16).frame(minHeight: 44)
            .background(Capsule().fill(.white.opacity(0.92)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Abrir la tarjeta de la llamada: " + TarjetaVozVista.nombre(t.tipo) + " " + t.titulo)
    }


    /// La roca de Alma (UNA ROCA, Alma/RocaAlma.swift): la misma de todas las pantallas. Respira siempre y crece con la voz
    /// (la tuya, la de Alma o la de Claudio, con su halo naranja). Con la tarjeta se achica a 96 px con un resorte (el morph).
    private var roca: some View {
        RocaAlma(diametro: 180, nivel: voz.nivel, enLlamada: true, claudio: voz.agente == .claudio)
            .scaleEffect(conTarjeta ? 96.0 / 180.0 : 1)
            .animation(sinMovimiento ? nil : .spring(response: 0.5, dampingFraction: 0.68), value: conTarjeta)
            .frame(height: conTarjeta ? 120 : 260)
            .opacity(voz.estado == .conectando ? 0.7 : 1)
    }
}

extension Notification.Name {
    /// La tarjeta de la llamada: «Abrir conversación» abre el Hub en el navegador de la app y la llamada sigue (ContentView).
    static let abrirDesdeTarjeta = Notification.Name("alma.tarjeta.abrir")
}
