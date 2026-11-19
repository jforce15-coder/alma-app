// Pruebas de Wearables (Alma/WearablesReglas.swift): agregar audífonos sin repetir ni confundirlos con los lentes, la
// batería sin inventar y lo que va a Ajustes.
//   swiftc Alma/WearablesReglas.swift Pruebas/Wearables/main.swift -o /tmp/wearables && /tmp/wearables
// Las corre el robot en cada PR (testflight.yml, «Probar Wearables»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}
typealias W = WearablesReglas
let lentes: (String) -> Bool = { $0.uppercased().contains("AURA") }

// MARK: - Bluetooth

revisa(W.esBluetooth("BluetoothA2DPOutput") && W.esBluetooth("BluetoothHFP") && W.esBluetooth("BluetoothLE"), "los tres puertos Bluetooth cuentan")
revisa(!W.esBluetooth("Speaker") && !W.esBluetooth("Headphones") && !W.esBluetooth("CarAudio"), "la bocina del teléfono, el cable y el carro no")

// MARK: - Agregar

revisa(W.idAudio("AirPods Pro de Juan") == "audio-airpods-pro-de-juan", "el id va sin espacios")
revisa(W.idAudio("Audífonos Sony WH-1000XM5") == "audio-audifonos-sony-wh-1000xm5", "el id va sin acentos ni signos")
revisa(W.idAudio("  ") == "audio-bt", "un nombre vacío no rompe el id")
let vistos = ["AirPods Pro", "iTOUCH AURA", "airpods pro", "Bose QC", ""]
revisa(W.paraAgregar(vistos: vistos, guardados: [], sonLentes: lentes) == ["AirPods Pro", "Bose QC"], "se ofrecen los que se ven, sin repetir y sin los lentes")
revisa(W.paraAgregar(vistos: vistos, guardados: ["Bose QC"], sonLentes: lentes) == ["AirPods Pro"], "los ya agregados no se vuelven a ofrecer")
var lista = W.agregar("AirPods Pro", a: [])
lista = W.agregar("AirPods Pro", a: lista)
revisa(lista == ["AirPods Pro"], "agregar dos veces el mismo deja uno")
lista = W.agregar("Bose QC", a: lista)
revisa(W.quitar(id: W.idAudio("AirPods Pro"), de: lista) == ["Bose QC"], "quitar por id quita solo ese")

// MARK: - Estado y batería (nada se inventa)

revisa(W.estadoAudio(salida: true, conectado: true) == "El audio sale por aquí", "la salida de ahora se dice")
revisa(W.estadoAudio(salida: false, conectado: true) == "Conectados" && W.estadoAudio(salida: false, conectado: false) == "Sin conectar", "conectados o no")
revisa(W.bateria(82) == "82 %" && W.bateria(100, cargando: true) == "100 % · cargando", "la batería con su porcentaje")
revisa(W.bateria(nil) == "Batería no disponible" && W.bateria(nil, sin: "Sin lectura") == "Sin lectura", "sin dato, lo dice")
revisa(W.bateria(140) == "100 %" && W.bateria(-3) == "0 %", "fuera de rango se acota")
revisa(W.bajo(20) && W.bajo(5) && !W.bajo(21) && !W.bajo(nil), "batería baja de 20 % para abajo; sin dato no es baja")

// MARK: - Lo que va a Ajustes

let ws = [W.Wearable(id: "anillo", tipo: .anillo, nombre: "Anillo QRing", corto: "Anillo", conectado: true, bateria: 82, cargando: false, estado: "Conectado"),
          W.Wearable(id: "lentes", tipo: .lentes, nombre: "Lentes AURA", corto: "Lentes", conectado: false, bateria: nil, estado: "Sin conectar")]
let r = W.resumenWeb(ws)
revisa(r.count == 2 && r[0]["id"] as? String == "anillo" && r[0]["tipo"] as? String == "anillo" && r[0]["bateria"] as? Int == 82, "el anillo va con su batería")
revisa(r[1]["bateria"] == nil && r[1]["conectado"] as? Bool == false && r[1]["estado"] as? String == "Sin conectar", "los lentes sin batería inventada")
revisa(JSONSerialization.isValidJSONObject(r), "se puede mandar a la página como JSON")

print(fallos == 0 ? "OK" : "\(fallos) fallos")
exit(fallos == 0 ? 0 : 1)
