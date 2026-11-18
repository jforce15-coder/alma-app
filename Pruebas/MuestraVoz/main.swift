import Foundation

// Pruebas de MuestraVoz (Hub #781): voice_id, nombre, duración y qué se le contesta a Claudio. Lógica pura.
var fallos = 0
func ok(_ c: Bool, _ m: String) { if c { print("✓ " + m) } else { print("::error::" + m); fallos += 1 } }

ok(MuestraVoz.herramienta == "reproducir_voz", "la herramienta se llama como en el Hub (claudio.js)")
ok(MuestraVoz.idValido("21m00Tcm4TlvDq8ikWAM"), "un voice_id de ElevenLabs sirve")
ok(!MuestraVoz.idValido("") && !MuestraVoz.idValido("corto") && !MuestraVoz.idValido("../../../etc/passwd00") && !MuestraVoz.idValido("ñandú0000000000000"), "vacío, corto, con símbolos o letras raras: no")
ok(MuestraVoz.nombre("  Rachel \n calm ") == "Rachel calm" && MuestraVoz.nombre(nil) == "esa voz", "el nombre, limpio (y «esa voz» si no vino)")
ok(abs(MuestraVoz.duracion(bytes: 64000, hz: 16000) - 2) < 0.001 && MuestraVoz.duracion(bytes: 10, hz: 0) == 0, "la duración del PCM de 16 bits")
let pcm = Data(repeating: 1, count: 3200).base64EncodedString()
ok(MuestraVoz.audio(["ok": true, "hz": 16000, "audio": pcm], hz: 16000).pcm?.count == 3200, "llega al hz de la llamada: suena")
ok(MuestraVoz.audio(["ok": true, "hz": 24000, "audio": pcm], hz: 16000).pcm == nil, "otro hz: no suena (se oiría rara)")
ok(MuestraVoz.audio(["ok": false, "error": "Esa voz es de la biblioteca"], hz: 16000).error == "Esa voz es de la biblioteca", "el error del Hub pasa tal cual")
ok(MuestraVoz.audio(nil, hz: 16000).error == "el Hub no respondió" && MuestraVoz.audio(["ok": true, "hz": 16000, "audio": ""], hz: 16000).pcm == nil, "sin respuesta o vacía: no suena")
ok(MuestraVoz.sono("Rachel", segundos: 3.6).contains("Rachel (4 s)") && MuestraVoz.sono("x", segundos: 0.2).contains("(1 s)"), "lo que se contesta al sonar")
ok(MuestraVoz.noSono("llegó vacía").contains("hilo de Claudio"), "si no sonó, Claudio sabe que está en el hilo")
if fallos > 0 { exit(1) }
print("Todo bien: las muestras de voz suenan en la llamada solo si llegan bien.")
