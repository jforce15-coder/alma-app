import Foundation

// Prueba del Modo compañero con sonido (Hub #727): el formato de lo que se manda y cuándo se busca, acepta y suena
// (RetransmisionReglas.swift).
var fallos = 0
func revisa(_ c: Bool, _ m: String) { print((c ? "✓ " : "✗ ") + m); if !c { fallos += 1 } }

let pcm = Data([0x01, 0x00, 0xff, 0x7f, 0x00, 0x80])
revisa(PaqueteVivo.leer(PaqueteVivo.audio(hz: 24000, pcm: pcm).datos()) == .audio(hz: 24000, pcm: pcm), "la voz llega igual que sonó (24 kHz)")
revisa(PaqueteVivo.leer(PaqueteVivo.audio(hz: 16000, pcm: pcm).datos()) == .audio(hz: 16000, pcm: pcm), "y también a 16 kHz")
revisa(PaqueteVivo.leer(PaqueteVivo.corte.datos()) == .corte && PaqueteVivo.leer(PaqueteVivo.fin.datos()) == .fin, "el corte y el fin llegan")
revisa(PaqueteVivo.leer(PaqueteVivo.texto(alma: true, t: "Hoy llegan dos, ¿te los muestro?").datos()) == .texto(alma: true, t: "Hoy llegan dos, ¿te los muestro?"), "un subtítulo de Alma llega igual (con acentos y signos)")
revisa(PaqueteVivo.leer(PaqueteVivo.texto(alma: false, t: "¿Quién llega?").datos()) == .texto(alma: false, t: "¿Quién llega?"), "y uno tuyo también")
revisa(PaqueteVivo.leer(PaqueteVivo.estado("hablando").datos()) == .estado("hablando"), "el estado llega")
revisa(PaqueteVivo.leer(Data([4, 1])) == nil && PaqueteVivo.leer(Data([4, 7, 65])) == nil && PaqueteVivo.leer(Data([5, 65, 66])) == nil, "un subtítulo vacío o raro, o un estado raro, se ignora")
if case let .texto(_, t)? = PaqueteVivo.leer(PaqueteVivo.texto(alma: true, t: String(repeating: "a", count: 900)).datos()) { revisa(t.count == PaqueteVivo.largoTexto, "un subtítulo largo se corta a 280") } else { revisa(false, "un subtítulo largo se corta a 280") }
revisa(NivelVivo.de(Data(count: 200)) == 0 && NivelVivo.de(Data()) == 0, "el silencio no mueve la pantalla")
var fuerte = Data(); for _ in 0..<100 { fuerte.append(contentsOf: [0x00, 0x40]) }
revisa(NivelVivo.de(fuerte) > 0.9 && NivelVivo.de(fuerte) <= 1, "la voz fuerte sí (y nunca pasa de 1)")
revisa(PaqueteVivo.leer(Data()) == nil && PaqueteVivo.leer(Data([9, 1, 2])) == nil, "lo que no es un paquete se ignora")
revisa(PaqueteVivo.leer(PaqueteVivo.audio(hz: 24000, pcm: Data([1, 2, 3])).datos()) == nil, "un trozo de audio partido se ignora")
revisa(PaqueteVivo.leer(PaqueteVivo.audio(hz: 1, pcm: pcm).datos()) == nil, "una frecuencia rara se ignora")

var r = ReglasRetransmision()
revisa(!r.busca && !r.suena, "con el Modo compañero apagado no busca ni suena")
r.companero = true
revisa(r.busca && r.recibe && !r.suena, "encendido (iPad): busca la llamada del otro y la muestra, callado (una sola voz)")
r.sonidoAqui = true
revisa(r.busca && r.suena, "con «Sonido de la llamada aquí», la voz también suena en el iPad")
r.aLaVista = false
revisa(!r.busca && r.suena, "con la app cerrada deja de buscar, pero lo ya conectado sigue sonando")
r.aLaVista = true; r.llamadaAqui = true
revisa(!r.busca && !r.recibe && !r.suena, "si la llamada es en este dispositivo, no busca ni reproduce al otro")
var r2 = ReglasRetransmision(); r2.sonidoAqui = true
revisa(!r2.suena && !r2.recibe, "el sonido solo, sin el Modo compañero, no hace nada")

let p1 = ReglasRetransmision.pareja("llave-de-prueba"), p2 = ReglasRetransmision.pareja("otra-llave")
revisa(p1 != nil && p1 == ReglasRetransmision.pareja("llave-de-prueba") && p1 != p2, "la huella es la misma con la misma llave y distinta con otra")
revisa(!(p1 ?? "").contains("llave") && (p1 ?? "").count == 16, "la huella no deja ver la llave")
revisa(ReglasRetransmision.pareja(nil) == nil && ReglasRetransmision.pareja("  ") == nil, "sin llave no hay huella")
revisa(ReglasRetransmision.acepta(contexto: Data(p1!.utf8), pareja: p1, llamadaAqui: true), "el teléfono acepta al compañero de su misma cuenta durante la llamada")
revisa(!ReglasRetransmision.acepta(contexto: Data(p2!.utf8), pareja: p1, llamadaAqui: true), "a uno de otra cuenta no")
revisa(!ReglasRetransmision.acepta(contexto: Data(p1!.utf8), pareja: p1, llamadaAqui: false), "y sin llamada tampoco")
revisa(!ReglasRetransmision.acepta(contexto: nil, pareja: p1, llamadaAqui: true), "sin huella tampoco")

print(fallos == 0 ? "OK" : "\(fallos) fallos")
exit(fallos == 0 ? 0 : 1)
