// Pruebas de Apple Pay por voz (Alma/ApplePayReglas.swift, Hub #662).
//   swiftc Alma/ApplePayReglas.swift Pruebas/ApplePay/main.swift -o /tmp/apple-pay && /tmp/apple-pay
// Las corre el robot en cada PR (testflight.yml, «Probar Apple Pay por voz»).
import Foundation

var fallos = 0
func revisa(_ ok: Bool, _ que: String, linea: Int = #line) {
    if ok { print("✓ " + que) } else { fallos += 1; print("✗ " + que + " (línea \(linea))") }
}

revisa(ApplePayReglas.atajo(en: []) == nil, "sin atajos permitidos: se abre Wallet directo")
revisa(ApplePayReglas.atajo(en: ["Modo concentración", "Música"]) == nil, "atajos que no son de pago: Wallet directo")
revisa(ApplePayReglas.atajo(en: ["Música", "Pagar con Apple Pay"]) == "Pagar con Apple Pay", "el atajo con «Apple Pay», con su nombre exacto")
revisa(ApplePayReglas.atajo(en: ["Abrir Wallet", "APPLE  PAY rápido"]) == "APPLE  PAY rápido", "«Apple Pay» gana a «Wallet» (sin mayúsculas ni espacios de más)")
revisa(ApplePayReglas.atajo(en: ["Mi cartera"]) == "Mi cartera", "«Cartera» también vale")
revisa(ApplePayReglas.atajo(en: ["Pagar la luz"]) == nil, "«Pagar» solo no basta: no corre atajos de pagos de otras cosas")
revisa(ApplePayReglas.enlaces.first == "shoebox://", "Wallet se abre primero con shoebox://")

if fallos > 0 { print("\(fallos) fallo(s)"); exit(1) }
print("Todo bien")
