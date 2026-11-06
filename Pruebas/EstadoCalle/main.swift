// Pruebas de la lógica pura del encendido del Modo calle y de los avisos hablados fuera de él (Alma/EstadoCalle.swift).
//   swiftc Alma/EstadoCalle.swift Pruebas/EstadoCalle/main.swift -o /tmp/estado-calle && /tmp/estado-calle
// Las corre el robot en cada PR (testflight.yml, «Probar el encendido del Modo calle»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}

// MARK: - Al abrir la app

revisa(!EstadoCalle.alAbrir(guardado: nil), "de fábrica (nada guardado) arranca apagado")
revisa(!EstadoCalle.alAbrir(guardado: false), "si Juan lo apagó, arranca apagado")
revisa(EstadoCalle.alAbrir(guardado: true), "si Juan lo dejó encendido, arranca encendido")

// MARK: - Lo que se guarda

revisa(EstadoCalle.guardar(.ajustes, on: true) == true && EstadoCalle.guardar(.ajustes, on: false) == false, "el interruptor de Ajustes guarda lo que elige Juan")
revisa(EstadoCalle.guardar(.siri, on: false) == false && EstadoCalle.guardar(.enlace, on: true) == true, "Siri y el atajo también guardan")
revisa(EstadoCalle.guardar(.conferencia, on: false) == false, "encender la conferencia lo apaga y queda apagado")
revisa(EstadoCalle.guardar(.prueba, on: true) == nil && EstadoCalle.guardar(.prueba, on: false) == nil, "«Probar el Modo calle» no cambia lo guardado")
revisa(EstadoCalle.guardar(.falla, on: true) == false, "si no pudo encender (permisos), queda apagado: no insiste al abrir")

// MARK: - Lo que ve la página

revisa(EstadoCalle.faseParaPagina("hablando", encendido: false, aviso: true) == "quieta", "un aviso con la app abierta no se ve como Modo calle")
revisa(EstadoCalle.faseParaPagina("oyendo", encendido: false, aviso: true) == "quieta", "escuchar la respuesta a un aviso tampoco")
revisa(EstadoCalle.faseParaPagina("oyendo", encendido: false, aviso: false) == "oyendo", "el botón del caminante sí se ve (te escucho)")
revisa(EstadoCalle.faseParaPagina("hablando", encendido: true, aviso: true) == "hablando", "con el Modo calle encendido, el aviso se ve en su línea")

// MARK: - Apagar apaga de verdad

revisa(EstadoCalle.apagar(encendido: true, temporal: false, aviso: false) == .init(modo: true, temporal: false, aviso: true), "encendido: se apaga el detector, el micrófono y la fila de avisos")
revisa(EstadoCalle.apagar(encendido: false, temporal: true, aviso: true) == .init(modo: false, temporal: true, aviso: true), "apagado pero diciendo un aviso: se calla y suelta el micrófono")
revisa(EstadoCalle.apagar(encendido: false, temporal: false, aviso: true) == .init(modo: false, temporal: false, aviso: true), "aviso en conferencia: se calla (la conferencia sigue)")
revisa(EstadoCalle.apagar(encendido: false, temporal: false, aviso: false) == .init(), "ya apagado y callado: nada que hacer")

// MARK: - La voz del aviso

revisa(EstadoCalle.vozAviso(audio: true, hablar: "¿Lo vemos?", vozMotivo: nil, hubSinAviso: false) == .conElAviso, "con audio en el aviso suena ya la voz de Alma")
revisa(EstadoCalle.vozAviso(audio: false, hablar: "", vozMotivo: nil, hubSinAviso: false) == .pedirAviso, "sin audio ni frase (Hub viejo): se pide avisoHablar")
revisa(EstadoCalle.vozAviso(audio: false, hablar: "Flor pregunta. ¿Lo vemos?", vozMotivo: nil, hubSinAviso: false) == .pedirAviso, "frase sin audio y sin motivo (la app no estaba lista al pedirlo): se pide avisoHablar")
revisa(EstadoCalle.vozAviso(audio: false, hablar: "Flor pregunta. ¿Lo vemos?", vozMotivo: "se acabaron los créditos", hubSinAviso: false) == .soloFrase, "el Hub ya intentó la voz: no se vuelve a pedir el aviso")
revisa(EstadoCalle.vozAviso(audio: false, hablar: "", vozMotivo: nil, hubSinAviso: true) == .soloFrase, "Hub sin avisoHablar: la frase con calleVoz o el iPhone")

if fallos > 0 { print("\(fallos) fallaron"); exit(1) }
print("Todo bien")
