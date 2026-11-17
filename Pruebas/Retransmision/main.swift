import Foundation

// Prueba del Modo compañero con sonido (Hub #727): el formato de lo que se manda y cuándo se busca, acepta y suena
// (RetransmisionReglas.swift).
var fallos = 0
func revisa(_ c: Bool, _ m: String) { print((c ? "✓ " : "✗ ") + m); if !c { fallos += 1 } }

let pcm = Data([0x01, 0x00, 0xff, 0x7f, 0x00, 0x80])
revisa(PaqueteVivo.leer(PaqueteVivo.audio(hz: 24000, pcm: pcm).datos()) == .audio(hz: 24000, pcm: pcm), "la voz llega igual que sonó (24 kHz)")
revisa(PaqueteVivo.leer(PaqueteVivo.audio(hz: 16000, pcm: pcm).datos()) == .audio(hz: 16000, pcm: pcm), "y también a 16 kHz")
revisa(PaqueteVivo.leer(PaqueteVivo.corte.datos()) == .corte && PaqueteVivo.leer(PaqueteVivo.fin.datos()) == .fin, "el corte y el fin llegan")
revisa(PaqueteVivo.leer(Data()) == nil && PaqueteVivo.leer(Data([9, 1, 2])) == nil, "lo que no es un paquete se ignora")
revisa(PaqueteVivo.leer(PaqueteVivo.audio(hz: 24000, pcm: Data([1, 2, 3])).datos()) == nil, "un trozo de audio partido se ignora")
revisa(PaqueteVivo.leer(PaqueteVivo.audio(hz: 1, pcm: pcm).datos()) == nil, "una frecuencia rara se ignora")

var r = ReglasRetransmision()
revisa(!r.busca && !r.suena, "con el Modo compañero apagado no busca ni suena")
r.companero = true
revisa(r.busca && r.suena, "encendido (iPad): busca la llamada del otro y la voz suena")
r.aLaVista = false
revisa(!r.busca && r.suena, "con la app cerrada deja de buscar, pero lo ya conectado sigue sonando")
r.aLaVista = true; r.llamadaAqui = true
revisa(!r.busca && !r.suena, "si la llamada es en este dispositivo, no busca ni reproduce al otro")

let p1 = ReglasRetransmision.pareja("llave-de-prueba"), p2 = ReglasRetransmision.pareja("otra-llave")
revisa(p1 != nil && p1 == ReglasRetransmision.pareja("llave-de-prueba") && p1 != p2, "la huella es la misma con la misma llave y distinta con otra")
revisa(!(p1 ?? "").contains("llave") && (p1 ?? "").count == 16, "la huella no deja ver la llave")
revisa(ReglasRetransmision.pareja(nil) == nil && ReglasRetransmision.pareja("  ") == nil, "sin llave no hay huella")
revisa(ReglasRetransmision.acepta(contexto: Data(p1!.utf8), pareja: p1, llamadaAqui: true), "el teléfono acepta al compañero de su misma cuenta durante la llamada")
revisa(!ReglasRetransmision.acepta(contexto: Data(p2!.utf8), pareja: p1, llamadaAqui: true), "a uno de otra cuenta no")
revisa(!ReglasRetransmision.acepta(contexto: Data(p1!.utf8), pareja: p1, llamadaAqui: false), "y sin llamada tampoco")
revisa(!ReglasRetransmision.acepta(contexto: nil, pareja: p1, llamadaAqui: true), "sin huella tampoco")

// Una sola llamada (Juan, 17-nov-2026: «Importante que en modo Companion sólo haya una llamada»)
let t0 = Date()
var u = ReglasRetransmision(); u.companero = true
revisa(!u.llamadaEnOtro(t0), "sin noticias de otra llamada, aquí se puede llamar")
u.otraVista = t0; u.otroDispositivo = "iPhone"
revisa(u.llamadaEnOtro(t0.addingTimeInterval(5)), "con la llamada viva en el iPhone, el iPad no abre otra")
revisa(!u.llamadaEnOtro(t0.addingTimeInterval(25)), "si dejó de verse hace más de 20 s, ya se puede llamar")
u.companero = false
revisa(!u.llamadaEnOtro(t0.addingTimeInterval(5)), "con el Modo compañero apagado, cada dispositivo llama libre")
u.companero = true; u.llamadaAqui = true
revisa(!u.llamadaEnOtro(t0.addingTimeInterval(5)), "la llamada de este mismo dispositivo no se bloquea a sí misma")
revisa(ReglasRetransmision.avisoUnaLlamada("iPhone").contains("desde tu iPhone") && ReglasRetransmision.avisoUnaLlamada("").contains("tu otro dispositivo"), "el aviso dice dónde está la llamada")

print(fallos == 0 ? "OK" : "\(fallos) fallos")
exit(fallos == 0 ? 0 : 1)
