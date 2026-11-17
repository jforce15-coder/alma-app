// Pruebas de «¿le contestó el aviso?» (Alma/RespuestaAviso.swift; Juan, 17-nov-2026).
//   swiftc Alma/RespuestaAviso.swift Pruebas/RespuestaAviso/main.swift -o /tmp/respuesta-aviso && /tmp/respuesta-aviso
// Las corre el robot en cada PR (testflight.yml, «Probar la respuesta al aviso»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}

// «no» o «luego» solo cierran la espera
revisa(RespuestaAviso.esNoOLuego("No") && RespuestaAviso.esNoOLuego("luego") && RespuestaAviso.esNoOLuego("Después, porfa") && RespuestaAviso.esNoOLuego("ahorita no"), "«no», «luego», «después» y «ahorita no» dejan el aviso para después")
revisa(!RespuestaAviso.esNoOLuego("sí, dime") && !RespuestaAviso.esNoOLuego("nosotros llegamos tarde"), "«sí, dime» o «nosotros…» no")

// La conferencia: el juez del Hub
revisa(RespuestaAviso.callar(avisoRespuesta: ["ok": true, "es": false, "por": "ia_no"]), "el juez dice que no le responden: Alma calla y no abre la llamada")
revisa(!RespuestaAviso.callar(avisoRespuesta: ["ok": true, "es": true, "por": "corta"]), "el juez dice que sí: abre la llamada")
revisa(!RespuestaAviso.callar(avisoRespuesta: nil), "sin respuesta del Hub a tiempo: abre como antes")
revisa(!RespuestaAviso.callar(avisoRespuesta: ["ok": false, "error": "accion"]), "un Hub de antes (sin la acción): abre como antes")
revisa(!RespuestaAviso.callar(avisoRespuesta: ["ok": true]), "sin «es»: abre como antes")

// El Modo calle: «calle» con puede_callar
revisa(RespuestaAviso.callar(calle: ["ok": true, "hablar": "", "silencio": true]), "«calle» dice silencio: no dice nada (ni «Listo.»)")
revisa(!RespuestaAviso.callar(calle: ["ok": true, "hablar": "Claro, te lo leo."]), "una respuesta normal se dice")
revisa(!RespuestaAviso.callar(calle: nil) && !RespuestaAviso.callar(calle: ["ok": false, "silencio": true]), "sin respuesta o con error no calla (va el mensaje de error de siempre)")

// La ficha y el diagnóstico
revisa(RespuestaAviso.regla.contains("skip_turn") && RespuestaAviso.regla.contains("no digas nada") && !RespuestaAviso.regla.contains("end_call"), "la regla de la ficha: skip_turn y nada, sin colgar")
revisa(RespuestaAviso.motivo(["por": "ia_no"]).contains("otra plática") && !RespuestaAviso.motivo(nil).isEmpty, "el motivo para «Lo que pasó», sin lo que se dijo")
revisa(RespuestaAviso.espera > 0 && RespuestaAviso.espera <= 6, "no se espera al juez más de unos segundos")

print(fallos == 0 ? "Todo bien: tras un aviso, Alma solo contesta si le responden." : "\(fallos) fallo(s)")
exit(fallos == 0 ? 0 : 1)
