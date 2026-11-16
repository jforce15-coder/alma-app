// Pruebas de la lógica pura de la música mientras Alma habla (Alma/AudioCalle.swift).
//   swiftc Alma/AudioCalle.swift Pruebas/AudioCalle/main.swift -o /tmp/audio-calle && /tmp/audio-calle
// Las corre el robot en cada PR (testflight.yml, «Probar la música del Modo calle»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}
typealias A = AudioCalle

// MARK: - El interruptor «Bajar la música cuando Alma hable»

revisa(A.bajaEnCalle(nil), "de fábrica, en el Modo calle la música baja")
revisa(!A.bajaEnConferencia(nil), "de fábrica, en conferencia la música no baja")
revisa(!A.bajaEnCalle(false) && A.bajaEnConferencia(true), "lo que Juan elige se respeta")
revisa(A.baja(.calle, calle: true, conferencia: false) && !A.baja(.conferencia, calle: true, conferencia: false), "cada lugar usa su interruptor")
revisa(A.baja(.aviso, calle: false, conferencia: false), "un aviso con la app abierta baja la música como siempre")
revisa(!A.baja(.nada, calle: true, conferencia: true), "fuera del Modo calle y la conferencia, nada baja")

// MARK: - El momento de cada fase

revisa(A.momento(fase: "esperando") == .espera && A.momento(fase: "verificando") == .espera, "esperando «Alma» o revisándola: la música sigue igual")
revisa(A.momento(fase: "oyendo") == .atiende && A.momento(fase: "pensando") == .atiende && A.momento(fase: "hablando") == .atiende, "oye el pedido, piensa o contesta: Alma atiende")
revisa(A.momento(fase: "llamada") == .llamada, "la llamada de ElevenLabs")
revisa(A.momento(fase: "pausa") == .espera && A.momento(fase: "quieta") == .espera, "en pausa o quieta: nada que bajar")

// MARK: - Las opciones de cada momento

let esperaCalle = A.opciones(.espera, donde: .calle, baja: true, anillo: false)!
revisa(esperaCalle.contains(.mezclar) && !esperaCalle.contains(.bajarOtras), "esperando «Alma»: se mezcla, Spotify a su volumen")
revisa(!esperaCalle.contains(.manosLibres), "esperando: los audífonos siguen en alta calidad (sin manos libres)")
let atiende = A.opciones(.atiende, donde: .calle, baja: true, anillo: false)!
revisa(atiende.contains(.bajarOtras) && atiende.contains(.pausarHablado), "Alma habla o escucha la respuesta: la música baja y un podcast se pausa")
revisa(atiende.contains(.parlante) && atiende.contains(.audifonos), "Alma se oye por los audífonos (o el parlante)")
revisa(A.opciones(.atiende, donde: .calle, baja: false, anillo: false) == A.escucha, "con el interruptor apagado, Alma habla encima de la música (como antes)")
let llamada = A.opciones(.llamada, donde: .calle, baja: true, anillo: false)!
revisa(llamada.contains(.bajarOtras) && llamada.contains(.manosLibres), "la llamada desde el Modo calle: Spotify baja (no se pausa) y oye por el micrófono de los audífonos")
let llamadaSola = A.opciones(.llamada, donde: .nada, baja: false, anillo: false)!
revisa(!llamadaSola.contains(.mezclar) && !llamadaSola.contains(.bajarOtras), "una llamada fuera del Modo calle no se mezcla, como siempre")
revisa(A.opciones(.llamada, donde: .conferencia, baja: true, anillo: false) == A.llamadaBajando, "en conferencia con el interruptor encendido, la llamada también baja la música")
revisa(A.opciones(.espera, donde: .aviso, baja: true, anillo: false) == A.bajando, "un aviso con la app abierta baja mientras tiene el micrófono")
revisa(A.opciones(.atiende, donde: .calle, baja: true, anillo: true) == nil, "con «Alma con el anillo» no se toca el audio")
revisa(A.opciones(.llamada, donde: .calle, baja: true, anillo: true) == nil, "tampoco en la llamada con el anillo")

// MARK: - Volver a mezclar sin dejar sordo al Modo calle

revisa(A.cambio(de: A.bajando, a: A.escucha, appActiva: true) == .soltarYCambiar, "con la app a la vista: se suelta el audio avisando a las otras apps, y la música sube")
revisa(A.cambio(de: A.bajando, a: A.escucha, appActiva: false) == .cambiar, "con el teléfono bloqueado: solo se cambian las opciones, nunca se suelta (el micrófono no volvería)")
revisa(A.cambio(de: A.llamadaSola, a: A.escucha, appActiva: true) == .soltarYCambiar, "tras una llamada que no se mezcla, con la app a la vista, la música vuelve")
revisa(A.cambio(de: A.escucha, a: A.bajando, appActiva: true) == .cambiar, "bajar la música solo cambia las opciones")
revisa(A.cambio(de: A.bajando, a: A.bajando, appActiva: false) == .nada, "sin cambio, nada")
revisa(A.cambio(de: nil, a: A.escucha, appActiva: false) == .cambiar, "sin saber lo de antes, se ponen las opciones")
revisa(A.cambio(de: A.escucha, a: A.escucha, appActiva: true) == .nada, "la escucha de siempre no se toca")

if fallos > 0 { print("\(fallos) fallaron"); exit(1) }
print("Todo bien")
