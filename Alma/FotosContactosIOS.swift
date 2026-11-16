import Contacts
import UIKit

/// Lee en el iPhone la foto de los contactos que pide el Hub (Hub #567 T4; las reglas están en FotosContactos.swift).
/// El Hub (index.html, fotosIphone) manda { accion: "fotosContactos", numeros } por el puente y recibe
/// AlmaFotosCt.evento({ permiso: "si" | "negado", fotos: [{ tel, jpeg }] }).
///   1. Permiso de Contactos: iOS lo pide una sola vez (NSContactsUsageDescription); si Juan dice que no, se contesta «negado».
///   2. Primera pasada: solo teléfonos de los contactos que tienen foto, en memoria, para encontrar los números pedidos.
///   3. Segunda pasada: la foto pequeña (thumbnailImageData) solo de los contactos que coincidieron, recortada al centro,
///      256 px o menos y en JPEG. Nada más sale del teléfono: ni nombres, ni otros números, ni la agenda.
final class FotosContactosLector {
    static let shared = FotosContactosLector()
    private let store = CNContactStore()
    private let cola = DispatchQueue(label: "com.spacioam.alma.fotos-contactos", qos: .utility)

    func buscar(_ numeros: [Any], fin: @escaping ([String: Any]) -> Void) {
        let pedidos = FotosContactos.pedidos(numeros)
        let responder: (FotosContactos.Permiso, [(tel: String, jpeg: String)]) -> Void = { p, f in
            DispatchQueue.main.async { fin(FotosContactos.respuesta(permiso: p, fotos: f)) }
        }
        switch FotosContactos.permiso(estado: CNContactStore.authorizationStatus(for: .contacts).rawValue) {
        case .negado:
            responder(.negado, [])
        case .pedir:
            store.requestAccess(for: .contacts) { [weak self] ok, _ in
                guard let self, ok else { responder(.negado, []); return }
                self.cola.async { responder(.leer, self.leer(pedidos)) }
            }
        case .leer:
            cola.async { [weak self] in responder(.leer, self?.leer(pedidos) ?? []) }
        }
    }

    /// Las fotos de los números pedidos que están en Contactos (como data: URL JPEG).
    private func leer(_ pedidos: [String]) -> [(tel: String, jpeg: String)] {
        guard !pedidos.isEmpty else { return [] }
        // 1. Teléfonos de los contactos con foto (sin la foto todavía).
        var ids: [String] = [], tels: [[String]] = []
        let r1 = CNContactFetchRequest(keysToFetch: [CNContactPhoneNumbersKey as CNKeyDescriptor, CNContactImageDataAvailableKey as CNKeyDescriptor])
        try? store.enumerateContacts(with: r1) { c, _ in
            guard c.imageDataAvailable, !c.phoneNumbers.isEmpty else { return }
            ids.append(c.identifier); tels.append(c.phoneNumbers.map { $0.value.stringValue })
        }
        let par = FotosContactos.coincidencias(pedidos: pedidos, contactos: tels)
        guard !par.isEmpty else { return [] }
        // 2. La foto pequeña solo de los que coincidieron.
        let quiero = Array(Set(par.values.map { ids[$0] }))
        var fotoDe: [String: Data] = [:]
        let pred = CNContact.predicateForContacts(withIdentifiers: quiero)
        if let cs = try? store.unifiedContacts(matching: pred, keysToFetch: [CNContactThumbnailImageDataKey as CNKeyDescriptor]) {
            for c in cs { if let d = c.thumbnailImageData { fotoDe[c.identifier] = d } }
        }
        var out: [(tel: String, jpeg: String)] = []
        for p in pedidos {
            guard let i = par[p], let d = fotoDe[ids[i]], let j = FotosContactosLector.jpeg(d) else { continue }
            out.append((tel: p, jpeg: "data:image/jpeg;base64," + j.base64EncodedString()))
        }
        return out
    }

    /// Cuadrada (el centro), 256 px o menos y JPEG.
    static func jpeg(_ datos: Data) -> Data? {
        guard let img = UIImage(data: datos), let cg = img.cgImage else { return nil }
        let r = FotosContactos.recorte(ancho: Double(cg.width), alto: Double(cg.height))
        guard r.final > 0, let centro = cg.cropping(to: CGRect(x: r.x, y: r.y, width: r.lado, height: r.lado)) else { return nil }
        let formato = UIGraphicsImageRendererFormat()
        formato.scale = 1
        formato.opaque = true
        let L = CGFloat(r.final)
        let foto = UIGraphicsImageRenderer(size: CGSize(width: L, height: L), format: formato).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: L, height: L))
            UIImage(cgImage: centro).draw(in: CGRect(x: 0, y: 0, width: L, height: L))
        }
        return foto.jpegData(compressionQuality: CGFloat(FotosContactos.calidad))
    }
}
