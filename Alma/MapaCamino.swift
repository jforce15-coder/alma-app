import MapKit
import SwiftUI

/// La pantalla de la Guía de camino (GuiaCamino.swift), estilo la navegación de un carro (Juan, 20-nov-2026: «que la
/// interfaz al guiar sea parecida a como lo hace Tesla», para caminar, bici, carro o bus):
///   · El mapa ocupa todo, oscuro y en 3D, y te sigue girado hacia donde vas. Si lo mueves con el dedo, sale «Centrar».
///   · Arriba, la tarjeta del próximo paso: la flecha grande, cuánto falta en grande y el paso (la referencia primero).
///     Debajo, chiquito, el «Luego».
///   · Abajo, la barra del viaje: hora de llegada, minutos, distancia, el medio y «Terminar».
/// El mapa es de Google Maps (MapaGoogle.swift); si la app no trae su llave, sale el de Apple con la misma pantalla.
/// Sube solo cuando la guía empieza con la pantalla a la vista; se baja deslizando (la guía sigue por voz).
struct MapaCaminoVista: View {
    @ObservedObject var guia = GuiaCamino.shared
    @Environment(\.dismiss) private var cerrar
    @State private var camara: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
    @State private var siguiendo = true

    private var puntos: [CLLocationCoordinate2D] { guia.linea.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) } }
    private var fin: CLLocationCoordinate2D? { guia.fin.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) } }

    private static let panel = Color(red: 0.10, green: 0.10, blue: 0.11)

    var body: some View {
        ZStack(alignment: .top) {
            mapa.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 8) {
                tarjetaPaso
                if !guia.luego.isEmpty && !guia.llego { tarjetaLuego }
                if !guia.aviso.isEmpty { avisoChico }
            }
            .padding(.horizontal, 12).padding(.top, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .bottomTrailing) {
            if !siguiendo { botonCentrar.padding(.trailing, 14).padding(.bottom, 12) }
        }
        .safeAreaInset(edge: .bottom) { barra }
        .preferredColorScheme(.dark)
        .onChange(of: guia.activa) { _, a in if !a { cerrar() } }
    }

    // MARK: - El mapa

    @ViewBuilder private var mapa: some View {
        if MapaGoogle.listo {
            MapaGoogleVista(puntos: puntos, fin: fin, destino: guia.destino, posicion: guia.posicion, modo: guia.modo, siguiendo: $siguiendo)
        } else {
            Map(position: $camara) {
                if puntos.count >= 2 {
                    MapPolyline(coordinates: puntos).stroke(Color.black.opacity(0.85), style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: puntos).stroke(Color.almaCoral, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                }
                if let f = fin { Marker(guia.destino, systemImage: "flag.checkered", coordinate: f).tint(Color.almaCoral) }
                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
            .mapControls { MapCompass() }
            .onMapCameraChange { _ in if !camara.followsUserLocation { siguiendo = false } }
        }
    }

    private func centrar() {
        siguiendo = true
        camara = .userLocation(followsHeading: true, fallback: .automatic)
    }

    // MARK: - Arriba: el próximo paso

    private var tarjetaPaso: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: GuiaCaminoReglas.simbolo(guia.giro))
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Color.almaCoral, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                if !guia.faltan.isEmpty && !guia.llego {
                    Text(guia.faltan).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        .monospacedDigit().contentTransition(.numericText())
                }
                Text(guia.proximo).font(.title3.weight(.semibold)).foregroundStyle(.white.opacity(0.92))
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(MapaCaminoVista.panel.opacity(0.94), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
        .animation(.snappy, value: guia.proximo)
    }

    private var tarjetaLuego: some View {
        HStack(spacing: 8) {
            Text("Luego").font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
            Image(systemName: GuiaCaminoReglas.simbolo(guia.luegoGiro)).font(.footnote.weight(.bold)).foregroundStyle(.white)
            Text(guia.luego).font(.footnote).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(MapaCaminoVista.panel.opacity(0.9), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var avisoChico: some View {
        Text(guia.aviso).font(.footnote.weight(.medium)).foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.almaCoral.opacity(0.9), in: Capsule())
    }

    private var botonCentrar: some View {
        Button(action: centrar) {
            Label("Centrar", systemImage: "location.north.line.fill").font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .foregroundStyle(.white)
        .background(MapaCaminoVista.panel.opacity(0.94), in: Capsule())
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
    }

    // MARK: - Abajo: el viaje

    private var icono: String {
        switch guia.modo {
        case "carro": return "car.fill"
        case "bici": return "bicycle"
        case "bus": return "bus.fill"
        default: return "figure.walk"
        }
    }

    private var barra: some View {
        HStack(spacing: 16) {
            Image(systemName: icono).font(.title3.weight(.semibold)).foregroundStyle(Color.almaCoral).frame(width: 28)
            if guia.llego {
                Text(guia.proximo).font(.headline).foregroundStyle(.white).lineLimit(1)
            } else {
                dato(guia.llegada, "llegada")
                dato("\(guia.minutosFaltan) min", "faltan")
                if !guia.restante.isEmpty { dato(guia.restante, guia.destino) }
            }
            Spacer(minLength: 0)
            Button(role: .destructive) { guia.terminar() } label: {
                Text("Terminar").font(.headline).padding(.horizontal, 16).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent).tint(Color(red: 0.86, green: 0.24, blue: 0.22))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(MapaCaminoVista.panel)
    }

    private func dato(_ grande: String, _ chico: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(grande).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(.white).monospacedDigit().lineLimit(1)
            Text(chico).font(.caption2).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
        }
    }
}
