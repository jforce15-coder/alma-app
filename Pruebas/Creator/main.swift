// Pruebas del Modo Creator (Alma/CreatorReglas.swift, Hub #770): cuándo la app lo abre y cuál es su página.
//   swiftc Alma/CreatorReglas.swift Pruebas/Creator/main.swift -o /tmp/creator && /tmp/creator
// Las corre el robot en cada PR (testflight.yml, «Probar el Modo Creator»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}
typealias L = CreatorReglas

revisa(L.abre(herramienta: "claudio_creator", conClaudio: true, error: false), "Claudio cambió el diseño: se abre el Modo Creator")
revisa(!L.abre(herramienta: "claudio_creator", conClaudio: true, error: true), "si el Hub contestó con error, no se abre")
revisa(!L.abre(herramienta: "claudio_creator", conClaudio: false, error: false), "con Alma no hay Modo Creator")
revisa(!L.abre(herramienta: "claudio_pedido", conClaudio: true, error: false) && !L.abre(herramienta: "claudio_estado", conClaudio: true, error: false), "las otras herramientas de Claudio no lo abren")
revisa(L.direccion.absoluteString == "https://hub.spacioam.com/alma/creator.html?app=1", "la página del Hub, con app=1 (sin su botón de volver)")
revisa(L.esCreator(URL(string: "https://hub.spacioam.com/alma/creator.html?app=1")) && L.esCreator(URL(string: "https://hub.spacioam.com/alma/creator.html")), "reconoce el Modo Creator con o sin app=1")
revisa(!L.esCreator(URL(string: "https://hub.spacioam.com/alma/claudio.html")) && !L.esCreator(URL(string: "https://otro.com/alma/creator.html")) && !L.esCreator(nil), "otras páginas u otro sitio no son el Modo Creator")

if fallos > 0 { print("\(fallos) fallo(s)"); exit(1) }
print("Todo bien: el Modo Creator se abre solo cuando Claudio cambió el diseño.")
