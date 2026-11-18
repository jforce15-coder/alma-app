// Pruebas de los archivos como entrada (Alma/ArchivosEntrada.swift; Hub, Juan 18-nov-2026).
//   swiftc Alma/ArchivosEntrada.swift Pruebas/ArchivosEntrada/main.swift -o /tmp/archivos-entrada && /tmp/archivos-entrada
// Las corre el robot en cada PR (testflight.yml, «Probar los archivos para Alma»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}

revisa(ArchivosEntrada.mime(nombre: "Factura.PDF") == "application/pdf", "el tipo sale de la extensión, sin importar mayúsculas")
revisa(ArchivosEntrada.mime(nombre: "nota.m4a") == "audio/mp4" && ArchivosEntrada.mime(nombre: "foto.HEIC") == "image/heic", "audio del iPhone y fotos")
revisa(ArchivosEntrada.mime(nombre: "programa.exe") == nil && ArchivosEntrada.mime(nombre: "sin-extension") == nil, "lo que el Hub no sabe leer no entra")

let pdf = Data([37, 80, 68, 70, 45, 49])
if case .listo(let js) = ArchivosEntrada.js(nombre: "factura «luz».pdf", datos: pdf) {
    revisa(js.hasPrefix("window.AlmaArchivos && AlmaArchivos.recibir({"), "va al chat del inicio (AlmaArchivos.recibir)")
    revisa(js.contains(pdf.base64EncodedString()) && (js.contains("application\\/pdf") || js.contains("application/pdf")), "con su tipo y su contenido en base64")
    revisa(!js.contains("\n") && js.contains("factura «luz».pdf"), "el nombre va como texto JSON (comillas y acentos seguros)")
} else { revisa(false, "un PDF chico se acepta") }
revisa(ArchivosEntrada.js(nombre: "virus.exe", datos: pdf) != .listo(""), "un tipo que no sirve no arma nada")
if case .noSirve(let t) = ArchivosEntrada.js(nombre: "virus.exe", datos: pdf) { revisa(t.contains("no lo puedo abrir"), "y dice por qué") } else { revisa(false, "un .exe no se acepta") }
if case .noSirve(let t) = ArchivosEntrada.js(nombre: "grande.pdf", datos: Data(count: 8_000_001)) { revisa(t.contains("8 MB"), "más de 8 MB no entra (el tope del Hub)") } else { revisa(false, "más de 8 MB no entra") }
if case .noSirve = ArchivosEntrada.js(nombre: "vacio.pdf", datos: Data()) { revisa(true, "un archivo vacío no entra") } else { revisa(false, "un archivo vacío no entra") }
if case .listo(let js) = ArchivosEntrada.js(nombre: "   ", datos: pdf) { revisa(false, "sin nombre ni extensión no hay tipo: " + js) } else { revisa(true, "sin nombre ni extensión no se adivina el tipo") }
revisa(ArchivosEntrada.jsAviso("«x» pasa de 8 MB.").contains("pasa de 8 MB") && ArchivosEntrada.jsAviso("x").hasPrefix("window.AlmaArchivos && AlmaArchivos.recibir({"), "el aviso de lo que no sirve se dice en el chat")

print(fallos == 0 ? "Todo bien" : "\(fallos) fallos")
exit(fallos == 0 ? 0 : 1)
