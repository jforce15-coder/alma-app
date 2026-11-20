import CoreLocation
import GoogleMaps
import SwiftUI

/// El mapa de Google Maps (Juan, 20-nov-2026: «cada vez que mostremos un mapa, que sea de Google Maps»).
/// La llave del SDK entra al Info.plist al compilar (secreto GOOGLE_MAPS_IOS_KEY, testflight.yml). Sin llave, `MapaGoogle.listo`
/// es falso y la Guía de camino sigue con Apple Maps: nunca un mapa en blanco.
enum MapaGoogle {
    static let llave: String = {
        let k = (Bundle.main.object(forInfoDictionaryKey: "GoogleMapsKey") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return k.isEmpty || k.hasPrefix("$(") ? "" : k
    }()
    /// Se pide una sola vez, en el hilo principal, antes de crear el primer mapa.
    static let listo: Bool = !llave.isEmpty && GMSServices.provideAPIKey(llave)
}

/// La línea del camino en durazno, el destino con su banderita y el punto azul de Juan, sobre Google Maps.
/// La primera vez encuadra todo el camino; después Juan mueve el mapa como quiera (el botón de ubicación lo regresa).
struct MapaGoogleVista: UIViewRepresentable {
    var puntos: [CLLocationCoordinate2D]
    var fin: CLLocationCoordinate2D?
    var destino: String

    final class Coordinador {
        var linea: GMSPolyline?
        var meta: GMSMarker?
        var encuadre = ""
    }

    func makeCoordinator() -> Coordinador { Coordinador() }

    func makeUIView(context: Context) -> GMSMapView {
        let m = GMSMapView(options: GMSMapViewOptions())
        m.isMyLocationEnabled = true
        m.settings.myLocationButton = true
        m.settings.compassButton = true
        // Arriba va la tarjeta del próximo paso y abajo la barra: los botones y el logo de Google no quedan debajo.
        m.padding = UIEdgeInsets(top: 130, left: 0, bottom: 12, right: 0)
        return m
    }

    func updateUIView(_ m: GMSMapView, context: Context) {
        let c = context.coordinator, coral = UIColor(Color.almaCoral)
        if puntos.count >= 2 {
            let ruta = GMSMutablePath()
            puntos.forEach { ruta.add($0) }
            let l = c.linea ?? GMSPolyline()
            l.path = ruta
            l.strokeWidth = 7
            l.strokeColor = coral
            l.map = m
            c.linea = l
        } else {
            c.linea?.map = nil
            c.linea = nil
        }
        if let f = fin {
            let k = c.meta ?? GMSMarker()
            k.position = f
            k.title = destino
            k.icon = GMSMarker.markerImage(with: coral)
            k.map = m
            c.meta = k
        } else {
            c.meta?.map = nil
            c.meta = nil
        }
        // Encuadre: una vez por camino nuevo (primer punto + último + destino), no en cada paso.
        var todos = puntos
        if let f = fin { todos.append(f) }
        guard let a = todos.first, let z = todos.last else { return }
        let firma = "\(a.latitude),\(a.longitude)|\(z.latitude),\(z.longitude)"
        guard firma != c.encuadre else { return }
        c.encuadre = firma
        let caja = todos.dropFirst().reduce(GMSCoordinateBounds(coordinate: a, coordinate: a)) { $0.includingCoordinate($1) }
        DispatchQueue.main.async {
            if todos.count == 1 { m.moveCamera(GMSCameraUpdate.setTarget(a, zoom: 16)) }
            else { m.moveCamera(GMSCameraUpdate.fit(caja, withPadding: 48)) }
        }
    }
}
