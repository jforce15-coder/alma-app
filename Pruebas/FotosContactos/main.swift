// Pruebas de la foto del contacto desde los Contactos del iPhone (Alma/FotosContactos.swift, Hub #567 T4).
//   swiftc Alma/FotosContactos.swift Pruebas/FotosContactos/main.swift -o /tmp/fotos-contactos && /tmp/fotos-contactos
// Las corre el robot en cada PR (testflight.yml, «Probar la foto del contacto»). Números de prueba, de nadie.
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}

// MARK: - Lo que pide el Hub

revisa(FotosContactos.digitos("+502 5555-0101") == "50255550101", "solo los dígitos del teléfono")
revisa(FotosContactos.clave("+502 5555-0101") == "55550101" && FotosContactos.clave("1234567") == nil, "la clave son los últimos 8 dígitos (con menos, ninguna)")
let p1 = FotosContactos.pedidos(["50255550101", "+502 5555 0101", "123", NSNumber(value: 50255550102), 7, "50255550103"])
revisa(p1 == ["50255550101", "50255550102", "50255550103"], "sin repetir (por los últimos 8), sin los cortos ni lo que no es número: \(p1)")
let muchos = (0..<60).map { "5025555" + String(format: "%04d", $0) }
revisa(FotosContactos.pedidos(muchos).count == FotosContactos.maxNumeros && FotosContactos.maxNumeros == 40, "a lo mucho 40 números por vuelta")

// MARK: - Coincidencias

let contactos: [[String]] = [
    ["+502 5555 0101"],                      // 0 · el mismo número con espacios
    ["5555-0102", "+1 (305) 555-0000"],     // 1 · sin código de país
    ["+502 5555 0103"],                      // 2 · empatan dos contactos distintos con el mismo número
    ["(502) 5555-0103"],                     // 3
    ["+502 5555 0104"],                      // 4 · el que comparte más dígitos gana
    ["+1 787 5555 0104"],                    // 5
    ["0101"]                                 // 6 · muy corto: nunca coincide
]
let par = FotosContactos.coincidencias(pedidos: ["50255550101", "50255550102", "50255550103", "50255550104", "50255550199"], contactos: contactos)
revisa(par["50255550101"] == 0, "coincide el mismo número escrito distinto")
revisa(par["50255550102"] == 1, "coincide por los últimos 8 aunque el contacto no tenga el código de país")
revisa(par["50255550103"] == nil, "si dos contactos distintos empatan, ninguno (mejor iniciales que la foto de otra persona)")
revisa(par["50255550104"] == 4, "gana el contacto que comparte más dígitos del final")
revisa(par["50255550199"] == nil && par.count == 3, "un número que no está en Contactos no trae nada")
let mismo = FotosContactos.coincidencias(pedidos: ["50255550101"], contactos: [["+502 5555 0101", "50255550101"]])
revisa(mismo["50255550101"] == 0, "un contacto con el mismo número dos veces sigue siendo uno")
revisa(FotosContactos.coincidencias(pedidos: [], contactos: contactos).isEmpty && FotosContactos.coincidencias(pedidos: ["50255550101"], contactos: []).isEmpty, "sin pedidos o sin contactos con foto, nada")

// MARK: - Recorte

let r1 = FotosContactos.recorte(ancho: 640, alto: 480)
revisa(r1.x == 80 && r1.y == 0 && r1.lado == 480 && r1.final == 256, "foto ancha: el cuadrado del centro, a 256 px")
let r2 = FotosContactos.recorte(ancho: 120, alto: 200)
revisa(r2.x == 0 && r2.y == 40 && r2.lado == 120 && r2.final == 120, "foto chica: no se agranda (120 px)")
revisa(FotosContactos.recorte(ancho: 0, alto: 300).final == 0, "foto vacía: nada")
revisa(FotosContactos.lado == 256 && FotosContactos.calidad > 0.5 && FotosContactos.calidad <= 0.9, "256 px y JPEG con calidad media (para no pasar de 64 KB)")

// MARK: - Permiso y respuesta

revisa(FotosContactos.permiso(estado: 0) == .pedir, "sin decidir: iOS pide el permiso (una vez)")
revisa(FotosContactos.permiso(estado: 3) == .leer && FotosContactos.permiso(estado: 4) == .leer, "autorizado o limitado (iOS 18): se leen")
revisa(FotosContactos.permiso(estado: 1) == .negado && FotosContactos.permiso(estado: 2) == .negado && FotosContactos.permiso(estado: 9) == .negado, "negado, restringido o desconocido: no se insiste")
let no = FotosContactos.respuesta(permiso: .negado, fotos: [(tel: "50255550101", jpeg: "data:image/jpeg;base64,AA==")])
revisa(no["permiso"] as? String == "negado" && (no["fotos"] as? [[String: String]])?.isEmpty == true, "con el permiso negado no sale ninguna foto")
let si = FotosContactos.respuesta(permiso: .leer, fotos: [(tel: "50255550101", jpeg: "data:image/jpeg;base64,AA==")])
let f0 = (si["fotos"] as? [[String: String]])?.first
revisa(si["permiso"] as? String == "si" && f0?["tel"] == "50255550101" && f0?["jpeg"]?.hasPrefix("data:image/jpeg;base64,") == true && f0?.count == 2, "con permiso: solo el número y su foto (nada de nombres)")

print(fallos == 0 ? "Todo bien." : "\(fallos) fallos.")
exit(fallos == 0 ? 0 : 1)
