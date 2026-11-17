import Foundation

// Prueba de la retransmisión del sonido del Modo compañero (RetransmisionReglas.swift).
var fallos = 0
func revisa(_ c: Bool, _ m: String) { print((c ? "✓ " : "✗ ") + m); if !c { fallos += 1 } }
typealias R = RetransmisionReglas

let par = "abcdefghijklmnopqrstuvwxyz012345", otra = "ZYXWVUTSRQPONMLKJIHGFEDCBA987654"
revisa(R.anuncio(par) == R.anuncio(par) && R.anuncio(par) != R.anuncio(otra), "el anuncio es el mismo para la misma par y distinto para otra")
revisa(!R.anuncio(par).contains(par), "el anuncio no deja ver la par")
let ctx = R.contexto(par, "n0nce1234")
revisa(R.revisar(ctx, par: par) == "n0nce1234", "el iPad acepta la invitación de su teléfono")
revisa(R.revisar(ctx, par: otra) == nil, "el iPad de otro no la acepta")
revisa(R.revisar(Data("n0nce1234.\(R.anuncio(par))".utf8), par: par) == nil, "quien solo copió el anuncio no puede invitar")
revisa(R.revisar(nil, par: par) == nil && R.revisar(ctx, par: "") == nil, "sin invitación o sin par, nada")
revisa(R.prueba(par, "n0nce1234") != R.prueba(otra, "n0nce1234") && R.prueba(par, "a1234567") != R.prueba(par, "b1234567"), "la prueba depende de la par y del número al azar")
revisa(!R.parValida(nil) && !R.parValida("corta") && R.parValida(par), "la par tiene que ser de verdad")

let pcm = Data([1, 0, 255, 127, 0, 128])
for (hz, p) in [(16000, pcm), (24000, pcm), (44100, Data())] {
    let d = R.empaquetar(.audio(hz: hz, pcm: p))
    revisa(R.desempaquetar(d) == .audio(hz: hz, pcm: p), "el sonido a \(hz) Hz va y vuelve igual")
}
revisa(R.desempaquetar(R.empaquetar(.corte)) == .corte && R.desempaquetar(R.empaquetar(.fin)) == .fin, "el corte y el fin van y vuelven")
revisa(R.desempaquetar(R.empaquetar(.prueba("xyz"))) == .prueba("xyz"), "la prueba va y vuelve")
revisa(R.desempaquetar(Data()) == nil && R.desempaquetar(Data([9])) == nil && R.desempaquetar(Data([1, 0])) == nil, "lo raro se ignora")
revisa(R.desempaquetar(Data([1, 0, 160, 1])) == nil, "un sonido cortado a la mitad de una muestra se ignora")
revisa(R.desempaquetar(Data([1, 0, 1, 0, 0])) == nil, "una frecuencia imposible se ignora")

if fallos > 0 { print("\(fallos) fallo(s)"); exit(1) }
print("Retransmisión: todo bien")
