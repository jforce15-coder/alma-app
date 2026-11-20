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

    /// Claro y sobrio, como el prototipo que eligió Juan (20-nov-2026): manzanas de piedra clara, calles blancas, parques
    /// verde suave y los lugares (las referencias de la guía) a la vista.
    static let estiloClaro = """
    [{"elementType":"geometry","stylers":[{"color":"#ecebe6"}]},
     {"elementType":"labels.text.stroke","stylers":[{"color":"#f4f2ef"}]},
     {"elementType":"labels.text.fill","stylers":[{"color":"#8f867e"}]},
     {"featureType":"landscape.man_made","elementType":"geometry","stylers":[{"color":"#e4e0db"}]},
     {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#6f6862"}]},
     {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#dde7d6"}]},
     {"featureType":"road","elementType":"geometry","stylers":[{"color":"#ffffff"}]},
     {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#e3ded8"}]},
     {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#9c928a"}]},
     {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#fbfaf8"}]},
     {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#e6e2dd"}]},
     {"featureType":"water","elementType":"geometry","stylers":[{"color":"#cfdce8"}]}]
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

/// La Guía de camino sobre Google Maps: claro, en 3D y siguiendo hacia dónde vas (la dirección de tu movimiento arriba).
/// Si mueves el mapa con el dedo deja de seguirte (`siguiendo` = false) hasta que tocas «Centrar». Tu punto no es el
/// punto azul de Google: es la roca de Alma con su luz de rumbo, que MapaCaminoVista dibuja encima en el lugar que este
/// mapa le dice (RumboGuia.roca) junto con cuánto va girado (RumboGuia.mapa).
struct MapaGoogleVista: UIViewRepresentable {
    var puntos: [CLLocationCoordinate2D]
    var fin: CLLocationCoordinate2D?
    var destino: String
    var posicion: CLLocation?
    var modo: String
    /// Lo que tapan las tarjetas (arriba el giro, abajo la llegada): la cámara centra en lo que queda libre.
    var margen: UIEdgeInsets
    @Binding var siguiendo: Bool

    final class Coordinador: NSObject, GMSMapViewDelegate {
        var linea: GMSPolyline?
        var borde: GMSPolyline?
        var meta: GMSMarker?
        var encuadre = ""
        var rumbo: CLLocationDirection = 0
        var tu: CLLocationCoordinate2D?
        var soltar: () -> Void = {}
        func mapView(_ mapView: GMSMapView, willMove gesture: Bool) { if gesture { soltar() } }
        func mapView(_ mapView: GMSMapView, didChange position: GMSCameraPosition) { avisar(mapView) }
        func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) { avisar(mapView) }
        /// Dónde queda tu punto en la pantalla y cuánto va girado el mapa: ahí va la roca con su luz.
        func avisar(_ m: GMSMapView) {
            let p = tu.map { m.projection.point(for: $0) }, g = m.camera.bearing
            DispatchQueue.main.async { RumboGuia.shared.roca(p); RumboGuia.shared.mapa(giro: g) }
        }
    }

    func makeCoordinator() -> Coordinador { Coordinador() }

    func makeUIView(context: Context) -> GMSMapView {
        let m = GMSMapView(options: GMSMapViewOptions())
        m.delegate = context.coordinator
        m.isMyLocationEnabled = false   // tu punto es la roca de Alma (encima, en SwiftUI)
        m.isBuildingsEnabled = true
        m.settings.myLocationButton = false
        m.settings.compassButton = false   // la brújula es la píldora de la pantalla (BrujulaGuia)
        m.settings.tiltGestures = true
        m.mapStyle = try? GMSMapStyle(jsonString: MapaGoogle.estiloClaro)
        m.padding = margen
        return m
    }

    func updateUIView(_ m: GMSMapView, context: Context) {
        let c = context.coordinator, azul = UIColor(GuiaColor.azul), tinta = UIColor(GuiaColor.tinta)
        if m.padding != margen { m.padding = margen }
        c.tu = posicion?.coordinate
        c.soltar = { DispatchQueue.main.async { if siguiendo { siguiendo = false } } }
        if puntos.count >= 2 {
            let ruta = GMSMutablePath()
            puntos.forEach { ruta.add($0) }
            // La ruta azul gruesa con un borde blanco, para que se lea sobre las calles claras.
            let b = c.borde ?? GMSPolyline()
            b.path = ruta; b.strokeWidth = 13; b.strokeColor = UIColor(white: 1, alpha: 0.9); b.zIndex = 1; b.map = m
            let l = c.linea ?? GMSPolyline()
            l.path = ruta; l.strokeWidth = 9; l.strokeColor = azul; l.zIndex = 2; l.map = m
            c.borde = b; c.linea = l
        } else {
            c.linea?.map = nil; c.borde?.map = nil
            c.linea = nil; c.borde = nil
        }
        if let f = fin {
            let k = c.meta ?? GMSMarker()
            k.position = f; k.title = destino; k.icon = GMSMarker.markerImage(with: tinta); k.zIndex = 3; k.map = m
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
            c.avisar(m)
            return
        }
        // Sin tu ubicación todavía: una vez por camino nuevo, que se vea todo.
        var todos = puntos
        if let f = fin { todos.append(f) }
        c.avisar(m)
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
