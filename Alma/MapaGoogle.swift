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

    /// Oscuro y sobrio, como la pantalla de un carro: calles grises, nombres claros y los lugares (las referencias de la
    /// guía) en durazno para que se vean.
    static let estiloOscuro = """
    [{"elementType":"geometry","stylers":[{"color":"#1c1d1f"}]},
     {"elementType":"labels.text.stroke","stylers":[{"color":"#1c1d1f"}]},
     {"elementType":"labels.text.fill","stylers":[{"color":"#9aa0a6"}]},
     {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#e9a48f"}]},
     {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#1f2a22"}]},
     {"featureType":"road","elementType":"geometry","stylers":[{"color":"#3a3c40"}]},
     {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#151618"}]},
     {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#c4c7cc"}]},
     {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#4a4d52"}]},
     {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#2a2c30"}]},
     {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0f1724"}]}]
    """

    /// Qué tan cerca y qué tan inclinado va el mapa según el medio (caminando se ve más de cerca).
    static func camara(_ modo: String) -> (zoom: Float, inclinacion: Double) {
        switch modo {
        case "carro": return (17, 55)
        case "bici": return (17.5, 50)
        case "bus": return (16, 40)
        default: return (18, 45)
        }
    }
}

/// La Guía de camino sobre Google Maps, estilo carro: oscuro, en 3D y siguiendo hacia dónde vas (la dirección de tu
/// movimiento arriba). Si mueves el mapa con el dedo deja de seguirte (`siguiendo` = false) hasta que tocas «Centrar».
struct MapaGoogleVista: UIViewRepresentable {
    var puntos: [CLLocationCoordinate2D]
    var fin: CLLocationCoordinate2D?
    var destino: String
    var posicion: CLLocation?
    var modo: String
    @Binding var siguiendo: Bool

    final class Coordinador: NSObject, GMSMapViewDelegate {
        var linea: GMSPolyline?
        var borde: GMSPolyline?
        var meta: GMSMarker?
        var encuadre = ""
        var rumbo: CLLocationDirection = 0
        var soltar: () -> Void = {}
        func mapView(_ mapView: GMSMapView, willMove gesture: Bool) { if gesture { soltar() } }
    }

    func makeCoordinator() -> Coordinador { Coordinador() }

    func makeUIView(context: Context) -> GMSMapView {
        let m = GMSMapView(options: GMSMapViewOptions())
        m.delegate = context.coordinator
        m.isMyLocationEnabled = true
        m.isBuildingsEnabled = true
        m.settings.myLocationButton = false
        m.settings.compassButton = true
        m.settings.tiltGestures = true
        m.mapStyle = try? GMSMapStyle(jsonString: MapaGoogle.estiloOscuro)
        // Arriba va la tarjeta del próximo paso y abajo la barra: la brújula y el logo de Google no quedan debajo.
        m.padding = UIEdgeInsets(top: 170, left: 0, bottom: 8, right: 0)
        return m
    }

    func updateUIView(_ m: GMSMapView, context: Context) {
        let c = context.coordinator, coral = UIColor(Color.almaCoral)
        c.soltar = { DispatchQueue.main.async { if siguiendo { siguiendo = false } } }
        if puntos.count >= 2 {
            let ruta = GMSMutablePath()
            puntos.forEach { ruta.add($0) }
            // La línea con un borde oscuro, para que se lea sobre las calles.
            let b = c.borde ?? GMSPolyline()
            b.path = ruta; b.strokeWidth = 11; b.strokeColor = UIColor(white: 0.05, alpha: 0.9); b.zIndex = 1; b.map = m
            let l = c.linea ?? GMSPolyline()
            l.path = ruta; l.strokeWidth = 7; l.strokeColor = coral; l.zIndex = 2; l.map = m
            c.borde = b; c.linea = l
        } else {
            c.linea?.map = nil; c.borde?.map = nil
            c.linea = nil; c.borde = nil
        }
        if let f = fin {
            let k = c.meta ?? GMSMarker()
            k.position = f; k.title = destino; k.icon = GMSMarker.markerImage(with: coral); k.zIndex = 3; k.map = m
            c.meta = k
        } else {
            c.meta?.map = nil
            c.meta = nil
        }
        // Siguiendo: el mapa va contigo, girado hacia donde te mueves (la brújula del iPhone no: brinca en la mano).
        if siguiendo, let p = posicion {
            if p.course >= 0, p.speed > 0.6 { c.rumbo = p.course }
            let v = MapaGoogle.camara(modo)
            m.animate(to: GMSCameraPosition(target: p.coordinate, zoom: v.zoom, bearing: c.rumbo, viewingAngle: v.inclinacion))
            return
        }
        // Sin tu ubicación todavía: una vez por camino nuevo, que se vea todo.
        var todos = puntos
        if let f = fin { todos.append(f) }
        guard posicion == nil, let a = todos.first, let z = todos.last else { return }
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
