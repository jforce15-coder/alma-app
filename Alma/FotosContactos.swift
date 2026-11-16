import Foundation

/// La foto del contacto desde los Contactos del iPhone (Hub #567 T4, Juan 16-nov-2026). La bandeja del Hub pone la foto de
/// cada persona; quien escribe por WhatsApp sin reserva ni cuenta (familia, amigos, proveedores) se quedaba con sus
/// iniciales. Ahora, en este orden: los Contactos del iPhone, los Contactos de Google y la que Juan sube a mano.
///   · El Hub le pasa a la app SOLO los números de la bandeja que no tienen foto (a lo mucho `maxNumeros`). Nunca se lee
///     ni se sube la agenda entera: la app mira los teléfonos en el iPhone y devuelve solo la foto de los que coinciden.
///   · Coincide por los últimos 8 dígitos (como el Hub) y gana el contacto que comparte más dígitos del final; si dos
///     contactos distintos empatan, ninguno (mejor iniciales que la foto de otra persona).
///   · La foto sale cuadrada (el centro), de `lado` px o menos (nunca se agranda) y en JPEG.
///   · El permiso de Contactos lo pide iOS una sola vez; si Juan dice que no, la app no insiste (el Hub espera una semana).
/// Lógica pura, sin iOS: se prueba sola en Pruebas/FotosContactos. Lo que toca Contactos y UIKit está en FotosContactosIOS.swift.
enum FotosContactos {
    static let maxNumeros = 40
    static let lado = 256
    static let calidad = 0.8

    /// Qué hacer con el permiso de Contactos, por el valor de CNAuthorizationStatus (0 sin decidir, 1 restringido,
    /// 2 negado, 3 autorizado, 4 limitado en iOS 18: se leen los contactos que Juan eligió).
    enum Permiso: Equatable { case pedir, leer, negado }
    static func permiso(estado: Int) -> Permiso {
        switch estado {
        case 0: return .pedir
        case 3, 4: return .leer
        default: return .negado
        }
    }

    /// Solo los dígitos (0–9) de un teléfono.
    static func digitos(_ s: String) -> String { String(s.filter { $0.isASCII && $0.isNumber }) }

    /// La clave de un teléfono: sus últimos 8 dígitos (nil si tiene menos).
    static func clave(_ s: String) -> String? {
        let d = digitos(s)
        return d.count >= 8 ? String(d.suffix(8)) : nil
    }

    /// Lo que pidió el Hub → los números válidos, sin repetir (por su clave) y a lo mucho `maxNumeros`.
    static func pedidos(_ numeros: [Any]) -> [String] {
        var vistos = Set<String>(), out: [String] = []
        for n in numeros {
            let s = (n as? String) ?? (n as? NSNumber)?.stringValue ?? ""
            let d = digitos(s)
            guard let k = clave(d), !vistos.contains(k) else { continue }
            vistos.insert(k); out.append(d)
            if out.count >= maxNumeros { break }
        }
        return out
    }

    /// Cuántos dígitos del final comparten dos números (solo dígitos).
    static func finalComun(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        var n = 0
        while n < x.count && n < y.count && x[x.count - 1 - n] == y[y.count - 1 - n] { n += 1 }
        return n
    }

    /// Para cada número pedido, el contacto (su posición en `contactos`, la lista de teléfonos de cada contacto con foto)
    /// que tiene su foto: el que comparte más dígitos del final, al menos 8. Empate entre contactos distintos: ninguno.
    static func coincidencias(pedidos: [String], contactos: [[String]]) -> [String: Int] {
        let tels = contactos.map { $0.map(digitos).filter { $0.count >= 8 } }
        var porClave: [String: [Int]] = [:]
        for (i, ts) in tels.enumerated() {
            for t in ts { let k = String(t.suffix(8)); if porClave[k]?.last != i { porClave[k, default: []].append(i) } }
        }
        var out: [String: Int] = [:]
        for p in pedidos {
            let d = digitos(p)
            guard d.count >= 8, let candidatos = porClave[String(d.suffix(8))] else { continue }
            var mejor = 0, elegidos: [Int] = []
            for i in candidatos {
                let s = tels[i].map { finalComun(d, $0) }.max() ?? 0
                if s > mejor { mejor = s; elegidos = [i] } else if s == mejor && !elegidos.contains(i) { elegidos.append(i) }
            }
            if mejor >= 8 && elegidos.count == 1 { out[p] = elegidos[0] }
        }
        return out
    }

    /// El cuadrado del centro de una foto de ancho×alto (x, y, lado del recorte) y el lado final: `lado` o menos, nunca más
    /// grande que la foto. final 0 = foto vacía.
    static func recorte(ancho: Double, alto: Double) -> (x: Double, y: Double, lado: Double, final: Int) {
        let l = min(ancho, alto)
        guard l >= 1 else { return (0, 0, 0, 0) }
        return ((ancho - l) / 2, (alto - l) / 2, l, Int(min(Double(lado), l.rounded(.down))))
    }

    /// Lo que la app le contesta al Hub (AlmaFotosCt.evento).
    static func respuesta(permiso: Permiso, fotos: [(tel: String, jpeg: String)]) -> [String: Any] {
        let lista: [[String: String]] = permiso == .negado ? [] : fotos.map { ["tel": $0.tel, "jpeg": $0.jpeg] }
        return ["permiso": permiso == .negado ? "negado" : "si", "fotos": lista]
    }
}
