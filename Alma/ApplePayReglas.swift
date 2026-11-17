import Foundation

/// Apple Pay por voz (Hub #662): Alma no lee las tarjetas de Wallet (iOS no deja); abre la vista de pago para que Juan pague
/// con Face ID. Herramienta de cliente abrir_apple_pay (VozNativa.herramientaCliente → ApplePay.abrir en AtajosIOS.swift).
/// Lógica pura (sin UIKit), se prueba sola: Pruebas/ApplePay.
///   1. Si Juan tiene un atajo permitido con «Apple Pay», «Wallet» o «Cartera» en el nombre, se corre ese (él decide qué hace).
///   2. Si no, se abre Wallet directo (shoebox://, y si no abre, wallet://).
/// Alma nunca paga: abrir la vista no cobra nada; Juan confirma con Face ID y acerca el teléfono a la terminal.
enum ApplePayReglas {
    /// En orden de preferencia: un atajo con «Apple Pay» gana a uno con «Wallet», y ese a uno con «Cartera».
    static let palabras = ["apple pay", "applepay", "wallet", "cartera"]
    /// Los enlaces que abren la app Wallet, en orden.
    static let enlaces = ["shoebox://", "wallet://"]

    static func normal(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// El atajo permitido que abre Apple Pay (con su nombre exacto), o nil para abrir Wallet directo.
    static func atajo(en lista: [String]) -> String? {
        for p in palabras {
            if let x = lista.first(where: { normal($0).contains(p) }) { return x }
        }
        return nil
    }
}
