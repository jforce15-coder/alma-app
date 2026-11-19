import Foundation

// Prueba de las bocinas de Google Home en la llamada (Juan, 19-nov-2026): el anuncio de cada bocina en el Wi-Fi, la salida
// que se recuerda, los mensajes de Google Cast y el audio en vivo (BocinasGoogleReglas.swift).
var fallos = 0
func revisa(_ c: Bool, _ m: String) { print((c ? "✓ " : "✗ ") + m); if !c { fallos += 1 } }
typealias R = BocinasGoogleReglas

// El anuncio
let sala = R.bocina(servicio: "Google-Home-Mini-abc", txt: ["id": "abc123", "fn": "Sala", "md": "Google Home Mini"])
let casa = R.bocina(servicio: "Google-Cast-Group-xyz", txt: ["id": "xyz9", "fn": "Toda la casa", "md": "Google Cast Group"])
revisa(sala?.nombre == "Sala" && sala?.id == "abc123" && sala?.grupo == false, "una bocina se lee con su nombre de Google Home")
revisa(casa?.grupo == true, "un grupo de bocinas se reconoce")
revisa(R.bocina(servicio: "Cocina-1", txt: [:])?.nombre == "Cocina-1", "sin anuncio completo, el nombre del servicio")
let cuarto = R.bocina(servicio: "c", txt: ["id": "c1", "fn": "cuarto", "md": "Google Nest Mini"])!
revisa(R.ordenar([sala!, cuarto, casa!]).map(\.nombre) == ["Toda la casa", "cuarto", "Sala"], "primero los grupos, luego por nombre")
revisa(R.explica(casa!) == "Grupo de bocinas" && R.explica(sala!) == "Google Home Mini", "la línea de cada una")

// La salida que se recuerda
let g = R.guardar(casa!)
revisa(R.elegida(g)?.id == "xyz9" && R.elegida(g)?.nombre == "Toda la casa", "el grupo elegido se recuerda con su nombre")
revisa(R.elegida("auto") == nil && R.elegida("telefono") == nil && R.elegida(nil) == nil, "lo demás no es una bocina de Google")
revisa(R.elegida(R.prefijo + "id|Sala | arriba")?.nombre == "Sala | arriba", "un nombre con barra no se rompe")

// Google Cast
let m = R.Mensaje(origen: "sender-0", destino: "receiver-0", espacio: R.espacioReceptor, texto: R.json(["type": "LAUNCH", "appId": R.appReceptor]))
var d = R.empacar(m)
let n = Int(d[0]) << 24 | Int(d[1]) << 16 | Int(d[2]) << 8 | Int(d[3])
revisa(n == d.count - 4, "cada mensaje lleva su largo adelante")
let dos = d + R.empacar(R.Mensaje(origen: "a", destino: "b", espacio: R.espacioLatido, texto: "{\"type\":\"PING\"}"))
let medio = dos.count - 3
let parte = dos.prefix(medio)
var parteData = Data(parte)
let primeros = R.desempacar(&parteData)
revisa(primeros == [m] && parteData.count == medio - d.count, "lo que llega a medias espera la siguiente vuelta")
parteData.append(dos.suffix(3))
revisa(R.desempacar(&parteData).first?.espacio == R.espacioLatido && parteData.isEmpty, "y luego sale completo")
revisa(R.desempacar(&d) == [m], "ida y vuelta igual")
let largo = String(repeating: "x", count: 300)   // largo de dos bytes (varint)
var dl = R.empacar(R.Mensaje(origen: "s", destino: "r", espacio: R.espacioMedia, texto: largo))
revisa(R.desempacar(&dl).first?.texto == largo, "un texto largo se lee entero")

let st = R.objeto("{\"type\":\"RECEIVER_STATUS\",\"status\":{\"applications\":[{\"appId\":\"CC1AD845\",\"sessionId\":\"s1\",\"transportId\":\"t1\"}]}}")
revisa(R.receptor(st)?.transporte == "t1" && R.receptor(st)?.sesion == "s1", "del estado de la bocina sale el receptor de audio")
revisa(R.receptor(R.objeto("{\"type\":\"RECEIVER_STATUS\",\"status\":{\"applications\":[{\"appId\":\"OTRA\",\"sessionId\":\"s\",\"transportId\":\"t\"}]}}")) == nil, "otra app abierta (Spotify) no cuenta")
let ms = R.objeto("{\"type\":\"MEDIA_STATUS\",\"status\":[{\"playerState\":\"PLAYING\"}]}")
revisa(R.reproductor(ms)?.estado == "PLAYING", "se sabe cuándo la bocina ya suena")
let carga = R.cargar(url: "http://192.168.1.5:5000/alma.wav", pedido: 3)
let media = carga["media"] as? [String: Any]
revisa(carga["type"] as? String == "LOAD" && media?["streamType"] as? String == "LIVE" && media?["contentType"] as? String == "audio/wav", "el pedido para tocar es en vivo y WAV")

revisa(R.url(host: "192.168.1.5%en0", puerto: 5000) == "http://192.168.1.5:5000/alma.wav", "la dirección sin la zona")
revisa(R.url(host: "fe80::1%en0", puerto: 80) == "http://[fe80::1]:80/alma.wav", "IPv6 entre corchetes")

// El audio en vivo
let wav = R.cabeceraWav()
revisa(wav.count == 44 && String(decoding: wav.prefix(4), as: UTF8.self) == "RIFF", "la cabecera WAV mide 44 bytes")
revisa(wav[24] == 0xC0 && wav[25] == 0x5D, "a 24 kHz")
let get = R.respuestaHttp(pedido: "GET /alma.wav HTTP/1.1\r\n\r\n"), head = R.respuestaHttp(pedido: "HEAD /alma.wav HTTP/1.1\r\n\r\n")
revisa(get.sigue && !head.sigue && get.cabecera.count == head.cabecera.count + 44, "GET recibe el audio; HEAD solo la cabecera")
revisa(String(decoding: get.cabecera, as: UTF8.self).contains("Content-Type: audio/wav"), "se anuncia como WAV")
revisa(R.remuestrear([0, 100, 200, 300], de: 16000).count == 6, "de 16 kHz a 24 kHz salen 1,5 veces las muestras")
revisa(R.remuestrear([5, 6, 7], de: 24000) == [5, 6, 7], "a 24 kHz queda igual")
revisa(R.remuestrear([], de: 16000).isEmpty && R.remuestrear([1], de: 0).isEmpty, "sin voz no hay nada")
revisa(R.remuestrear([32767, -32768], de: 48000).count == 1, "de 48 kHz a la mitad")
revisa(R.porMandar(segundos: 0, enviadas: 0) == 7200, "al empezar va un colchón de 0,3 s")
revisa(R.porMandar(segundos: 1, enviadas: 7200) == 24000, "y luego al ritmo del reloj")
revisa(R.porMandar(segundos: 1, enviadas: 40000) == 0, "nunca de más")
revisa(R.colitaEco(enBocina: true) > R.retraso && R.colitaEco(enBocina: false) == 0, "el micrófono ignora a Alma más rato solo con la bocina")

// Lo que se ve
revisa(R.Estado.noEsta("Sala").linea?.contains("sale por el teléfono") == true, "fuera de casa se dice que sale por el teléfono")
revisa(R.Estado.apagada.linea == nil, "apagada no dice nada")

print(fallos == 0 ? "Todo bien" : "\(fallos) fallos")
exit(fallos == 0 ? 0 : 1)
