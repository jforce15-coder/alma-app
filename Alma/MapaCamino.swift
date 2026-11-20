import MapKit
import SwiftUI

/// El mapa de la Guía de camino (GuiaCamino.swift): la línea del camino en durazno, el punto de Juan, el destino, arriba
/// el próximo paso con cuánto falta y abajo el destino, el medio, los minutos y «Terminar». Sube solo cuando la guía
/// empieza con la pantalla a la vista; se baja deslizando (la guía sigue por voz) y «Terminar» la apaga.
/// El mapa es de Google Maps (MapaGoogle.swift, Juan 20-nov-2026); si la app no trae su llave, sale el de Apple.
struct MapaCaminoVista: View {
    @ObservedObject var guia = GuiaCamino.shared
    @Environment(\.dismiss) private var cerrar
    @State private var camara: MapCameraPosition = .userLocation(followsHeading: false, fallback: .automatic)

    private var puntos: [CLLocationCoordinate2D] { guia.linea.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) } }

    var body: some View {
        ZStack(alignment: .top) {
            mapa.ignoresSafeArea(edges: .bottom)

            tarjetaPaso.padding(.horizontal, 16).padding(.top, 12)
        }
        .safeAreaInset(edge: .bottom) { barra }
        .onChange(of: guia.activa) { _, a in if !a { cerrar() } }
    }

    private var fin: CLLocationCoordinate2D? { guia.fin.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) } }

    @ViewBuilder private var mapa: some View {
        if MapaGoogle.listo {
            MapaGoogleVista(puntos: puntos, fin: fin, destino: guia.destino)
        } else {
            Map(position: $camara) {
                if puntos.count >= 2 { MapPolyline(coordinates: puntos).stroke(Color.almaCoral, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)) }
                if let f = fin { Marker(guia.destino, systemImage: "flag.fill", coordinate: f).tint(Color.almaCoral) }
                UserAnnotation()
            }
            .mapControls { MapUserLocationButton(); MapCompass() }
        }
    }

    private var tarjetaPaso: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: guia.llego ? "checkmark.circle.fill" : "arrow.turn.up.right")
                .font(.title2.weight(.semibold)).foregroundStyle(Color.almaCoral)
            VStack(alignment: .leading, spacing: 4) {
                if !guia.faltan.isEmpty { Text("En " + guia.faltan).font(.title3.weight(.bold)).foregroundStyle(Color.almaTinta) }
                Text(guia.proximo).font(.body).foregroundStyle(Color.almaTinta).fixedSize(horizontal: false, vertical: true)
                if !guia.aviso.isEmpty { Text(guia.aviso).font(.footnote).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var barra: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(guia.destino).font(.headline).foregroundStyle(Color.almaTinta).lineLimit(1)
                Text(resumen).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(role: .destructive) { guia.terminar() } label: {
                Text("Terminar").font(.headline).padding(.horizontal, 18).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent).tint(Color.almaCoral)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private var resumen: String {
        var p: [String] = []
        if !guia.modoTexto.isEmpty { p.append(guia.modoTexto.prefix(1).uppercased() + guia.modoTexto.dropFirst()) }
        if guia.minutos > 0 { p.append("\(guia.minutos) min") }
        return p.joined(separator: " · ")
    }
}
