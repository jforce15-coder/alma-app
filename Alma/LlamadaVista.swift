import SwiftUI

/// La conversación del modo anillo, en pantalla: si hablas con Alma con el teléfono bloqueado y abres la app,
/// aquí sigue la misma llamada (no se corta), con la roca latiendo con la voz, lo último que se dijo y «Terminar».
struct LlamadaVista: View {
    @ObservedObject var voz: VozNativa
    let ocultar: () -> Void
    @State private var respira = false

    private var estadoTexto: String {
        switch voz.estado {
        case .conectando: return "Conectando…"
        case .hablando: return voz.almaHabla ? "Alma te responde" : "Te escucho"
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
                    Text("ALMA").tracking(3.5).font(.custom("Montserrat", size: 11).weight(.medium))
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                .foregroundStyle(.white)
                Spacer()
                roca
                Text(estadoTexto)
                    .font(.custom("Cormorant Garamond", size: 34).italic())
                    .foregroundStyle(.white)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: estadoTexto)
                    .padding(.top, 44)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(voz.lineas.suffix(3))) { l in
                        Text(l.texto)
                            .font(l.alma ? .custom("Cormorant Garamond", size: 20) : .custom("Montserrat", size: 14))
                            .foregroundStyle(.white.opacity(l.alma ? 0.95 : 0.7))
                            .frame(maxWidth: .infinity, alignment: l.alma ? .leading : .trailing)
                            .multilineTextAlignment(l.alma ? .leading : .trailing)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .animation(.easeOut(duration: 0.35), value: voz.lineas.count)
                .frame(maxWidth: 420, minHeight: 120, alignment: .bottom)
                .padding(.top, 24)
                Spacer()
                Button { voz.alternar() } label: {
                    HStack(spacing: 12) {
                        Circle().fill(Color.almaCoral).frame(width: 7, height: 7)
                        Text("TERMINAR").tracking(2.4).font(.custom("Montserrat", size: 12).weight(.semibold))
                    }
                    .padding(.leading, 22).padding(.trailing, 26).frame(height: 54)
                    .background(Capsule().fill(Color(red: 0.18, green: 0.19, blue: 0.19)))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                Text("También puedes tocar dos veces tu anillo").font(.custom("Montserrat", size: 11)).foregroundStyle(.white.opacity(0.7)).padding(.top, 12)
            }
            .padding(.horizontal, 24).padding(.vertical, 18)
        }
        .onAppear { respira = true }
    }

    /// La roca de Alma: respira sola y crece con la voz (la tuya o la de ella).
    private var roca: some View {
        let s = 1 + voz.nivel * 0.28
        return ZStack {
            Circle().fill(Color.almaCoral.opacity(0.35)).frame(width: 260, height: 260).blur(radius: 40)
                .scaleEffect(respira ? 1.08 : 0.92)
                .animation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true), value: respira)
            Circle()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.985, blue: 0.97), Color(red: 0.99, green: 0.9, blue: 0.86),
                                              Color(red: 0.96, green: 0.78, blue: 0.71), Color(red: 0.94, green: 0.68, blue: 0.59)],
                                     center: UnitPoint(x: 0.36, y: 0.3), startRadius: 4, endRadius: 120))
                .frame(width: 180, height: 180)
                .shadow(color: Color.almaCoral.opacity(0.5), radius: 30, y: 18)
                .scaleEffect(s)
                .animation(.spring(response: 0.22, dampingFraction: 0.8), value: voz.nivel)
            Image(systemName: "sparkle").font(.system(size: 28)).foregroundStyle(Color(red: 0.71, green: 0.38, blue: 0.31).opacity(0.45))
        }
        .frame(height: 260)
        .opacity(voz.estado == .conectando ? 0.7 : 1)
    }
}
