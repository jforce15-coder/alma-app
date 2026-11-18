import SwiftUI
import UniformTypeIdentifiers

/// Modo guiado del Navegador de Alma: la tarjeta de datos (lo que Juan copia y pega) y el aviso «Te toca a ti» de la pausa
/// de privacidad. Las reglas están en NavegadorReglas.swift (se prueban solas); aquí solo se dibujan.

/// La tarjeta de datos: Alma pone ahí (mostrar_dato) lo que Juan tiene que escribir en la página, y con un toque se copia.
/// No depende de la llamada: si Alma cuelga, la tarjeta sigue igual hasta que Juan la cierra.
final class TarjetaDatos: ObservableObject {
    static let shared = TarjetaDatos()
    @Published private(set) var datos: [NavegadorReglas.Dato] = []
    @Published var plegada = false

    /// Pone un dato (o lo cambia si ya hay uno con esa etiqueta). Devuelve por qué no, si es privado.
    func mostrar(etiqueta: String, valor: String) -> String? {
        if let no = NavegadorReglas.rechazoDato(etiqueta: etiqueta, valor: valor) { return no }
        let d = NavegadorReglas.Dato(etiqueta: String(etiqueta.prefix(60)), valor: valor.trimmingCharacters(in: .whitespacesAndNewlines))
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                self.datos = NavegadorReglas.agregar(d, a: self.datos); self.plegada = false
            }
        }
        return nil
    }

    func cerrar() { withAnimation(.easeOut(duration: 0.2)) { datos = [] } }

    /// Se copia solo en este teléfono (no pasa a la Mac ni al iPad) y se borra del portapapeles en 10 minutos.
    static func copiar(_ valor: String) {
        UIPasteboard.general.setItems([[UTType.plainText.identifier: valor]],
                                      options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(600)])
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

struct TarjetaDatosVista: View {
    @ObservedObject var tarjeta = TarjetaDatos.shared
    @State private var copiado: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.on.doc").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.almaCoral)
                Text(tarjeta.plegada ? "Para copiar · \(tarjeta.datos.count)" : "Para copiar")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.almaTinta)
                Spacer(minLength: 8)
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { tarjeta.plegada.toggle() } } label: {
                    Image(systemName: tarjeta.plegada ? "chevron.down" : "chevron.up").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.almaTinta.opacity(0.6)).frame(width: 30, height: 30).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(tarjeta.plegada ? "Abrir la tarjeta" : "Plegar la tarjeta")
                Button { tarjeta.cerrar() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.almaTinta.opacity(0.6)).frame(width: 30, height: 30).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Cerrar la tarjeta para copiar")
            }
            .padding(.leading, 14).padding(.trailing, 4).padding(.vertical, 4)
            if !tarjeta.plegada {
                ForEach(tarjeta.datos) { d in
                    Divider().overlay(Color.almaBorde)
                    Button {
                        TarjetaDatos.copiar(d.valor)
                        withAnimation(.easeOut(duration: 0.15)) { copiado = d.id }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { if copiado == d.id { withAnimation { copiado = nil } } }
                    } label: {
                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.etiqueta).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.almaTinta.opacity(0.6))
                                Text(d.valor).font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.almaTinta)
                                    .lineLimit(3).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 6)
                            Text(copiado == d.id ? "Copiado" : "Copiar")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(copiado == d.id ? Color.white : Color.almaCoral)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Capsule().fill(copiado == d.id ? Color.almaCoral : Color.almaCoral.opacity(0.12)))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(d.etiqueta): \(d.valor). Toca para copiar")
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.almaBorde, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .frame(maxWidth: 360)
        .padding(.horizontal, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Pausa de privacidad: arriba del navegador, «Te toca a ti» con un candado y «Listo». Mientras se ve, Alma no ve la página.
struct AvisoTeToca: View {
    let motivo: NavegadorReglas.Motivo
    let listo: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: motivo == .captcha ? "hand.raised.fill" : "lock.fill")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.white)
                .frame(width: 30, height: 30).background(Circle().fill(Color.white.opacity(0.22)))
            Text(motivo.aviso).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.white)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if motivo != .captcha {
                Button(action: listo) {
                    Text("Listo").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.almaCoral)
                        .padding(.horizontal, 12).padding(.vertical, 7).background(Capsule().fill(Color.white))
                }
                .buttonStyle(.plain).accessibilityLabel("Listo: Alma puede volver a ver la página")
            }
        }
        .padding(.leading, 10).padding(.trailing, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.almaCoral))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 5)
        .frame(maxWidth: 380)
        .padding(.horizontal, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }
}
