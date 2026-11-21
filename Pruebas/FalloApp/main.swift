// Pruebas del porqué de un cierre de la app (Alma/FalloAppReglas.swift).
//   swiftc Alma/FalloAppReglas.swift Pruebas/FalloApp/main.swift -o /tmp/fallo-app && /tmp/fallo-app
// Las corre el robot en cada PR (testflight.yml, «Probar el informe de fallo»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}
typealias R = FalloAppReglas

// MARK: - La pila del informe de iOS (MXCallStackTree)

let json = """
{"callStackPerThread":true,"callStacks":[
 {"threadAttributed":false,"callStackRootFrames":[{"binaryName":"libsystem_kernel.dylib","offsetIntoBinaryTextSegment":10}]},
 {"threadAttributed":true,"callStackRootFrames":[{"binaryName":"libsystem_kernel.dylib","offsetIntoBinaryTextSegment":4660,
   "subFrames":[{"binaryName":"AVFAudio","offsetIntoBinaryTextSegment":255,
     "subFrames":[{"binaryName":"Alma","offsetIntoBinaryTextSegment":4096}]}]}]}]}
""".data(using: .utf8)!
let pila = R.pila(json: json)
revisa(pila == ["libsystem_kernel.dylib +0x1234", "AVFAudio +0xff", "Alma +0x1000"], "la pila sale del hilo que falló, de arriba hacia abajo")
revisa(R.pila(json: Data("no".utf8)).isEmpty, "un JSON roto no tumba nada: pila vacía")

// MARK: - Los pasos

var f = R.Fallo(); f.build = "412"; f.tipo = 10; f.senal = 6; f.excepcion = "com.apple.coreaudio.avfaudio"
f.motivo = "required condition is false: _engine != nil"; f.pila = pila
let p = R.pasos(f, de: "informe de iOS")
revisa(p.first == "Fallo de la app (informe de iOS, build 412): EXC_CRASH · SIGABRT · com.apple.coreaudio.avfaudio", "el primer paso dice qué fue")
revisa(p.contains("Motivo del fallo: required condition is false: _engine != nil"), "el motivo de la excepción va en su paso")
revisa(p.contains { $0.hasPrefix("Pila del fallo 1: libsystem_kernel.dylib +0x1234 < AVFAudio") }, "la pila va en su paso")
revisa(p.allSatisfy { $0.count <= R.largo }, "cada paso cabe en el registro del Hub")

var largo = R.Fallo(); largo.tipo = 1; largo.pila = (0..<20).map { "BibliotecaMuyLargaNumero\($0) +0xabcdef" }
let pl = R.pasos(largo, de: "informe de iOS")
revisa(pl.filter { $0.hasPrefix("Pila del fallo") }.count >= 2, "una pila larga se parte en tramos")
revisa(pl.allSatisfy { $0.count <= R.largo }, "los tramos también caben")
revisa(pl.joined().components(separatedBy: "BibliotecaMuyLarga").count - 1 == R.marcos, "solo los primeros \(R.marcos) marcos")
revisa(R.recortar("dijo «hola»") == "dijo 'hola'", "sin «»: PasosAnillo.limpiar las borraría")
revisa(R.pasos(R.Fallo(), de: "x") == ["Fallo de la app (x): sin tipo"], "sin datos, igual queda la marca")

// MARK: - La excepción de Objective-C guardada antes de morir

let archivo = """
com.apple.coreaudio.avfaudio
player started when engine not running
413
0   CoreFoundation                      0x0000000180123456 __exceptionPreprocess + 164
1   libobjc.A.dylib                     0x0000000180654321 objc_exception_throw + 60
2   AVFAudio                            0x00000001a0000001 -[AVAudioPlayerNode play] + 120
3   Alma                                0x0000000100abcdef 0x100000000 + 11259375
"""
let e = R.desdeArchivo(archivo)
revisa(e?.excepcion == "com.apple.coreaudio.avfaudio" && e?.motivo == "player started when engine not running" && e?.build == "413", "nombre, motivo y build")
revisa(e?.pila == ["AVFAudio -[AVAudioPlayerNode play]", "Alma"], "la pila sin los marcos de la excepción y con la función del sistema")
revisa(R.desdeArchivo("") == nil, "un archivo vacío no es un fallo")

// MARK: - Las salidas raras del día

revisa(R.salidas(fondo: ["memoria": 0], frente: ["vigilante": 0]) == nil, "sin salidas raras, nada")
revisa(R.salidas(fondo: ["memoria": 2, "vigilante": 0], frente: [:]) == "Salidas raras de ayer (iOS) · en segundo plano: memoria 2", "memoria en segundo plano")

print(fallos == 0 ? "Todo bien" : "\(fallos) fallo(s)")
exit(fallos == 0 ? 0 : 1)
