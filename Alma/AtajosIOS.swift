import UIKit

/// Atajos de iOS (#396 T4): Alma corre por voz los atajos de la app Atajos de Juan (herramienta de cliente correr_atajo,
/// VozNativa.herramientaCliente). Solo los **atajos permitidos**: la lista que Juan maneja en Ajustes → «Atajos permitidos»
/// (alma/inicio.html, por el puente: { accion: "atajos" }), guardada en este teléfono. «Permitir todos» viene apagado.
/// Un atajo que no está en la lista no corre: Alma le dice a Juan que lo agregue.
enum AtajosPermitidos {
    private static let claveLista = "atajos_permitidos"
    private static let claveTodos = "atajos_todos"

    static var lista: [String] { UserDefaults.standard.stringArray(forKey: claveLista) ?? [] }
    static var todos: Bool { UserDefaults.standard.bool(forKey: claveTodos) }
    static var resumen: [String: Any] { ["lista": lista, "todos": todos] }

    /// «Pon mi Lista de Concentración» = «pon mi lista de concentracion»: sin mayúsculas, tildes ni espacios de más.
    static func normal(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func agregar(_ nombre: String) {
        let n = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !lista.contains(where: { normal($0) == normal(n) }) else { return }
        UserDefaults.standard.set(lista + [String(n.prefix(80))], forKey: claveLista)
    }
    static func quitar(_ nombre: String) {
        UserDefaults.standard.set(lista.filter { normal($0) != normal(nombre) }, forKey: claveLista)
    }
    static func ponerTodos(_ on: Bool) { UserDefaults.standard.set(on, forKey: claveTodos) }

    /// El nombre tal como está en la lista (así se abre el atajo con su nombre exacto), o nil si no está permitido.
    static func permitido(_ nombre: String) -> String? {
        let n = normal(nombre)
        guard !n.isEmpty else { return nil }
        if let x = lista.first(where: { normal($0) == n }) { return x }
        return todos ? nombre.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }

    /// correr_atajo { nombre }: abre shortcuts://run-shortcut?name=… si está permitido. Siempre contesta (JSON, ¿es error?).
    static func correr(_ nombre: String, _ fin: @escaping (String, Bool) -> Void) {
        let pedido = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pedido.isEmpty else { fin(ManosAlma.json(["error": "Falta el nombre del atajo."]), true); return }
        guard let exacto = permitido(pedido) else {
            fin(ManosAlma.json(["permitido": false, "nombre": pedido, "permitidos": lista,
                                "instruccion": "No lo corrí: no está en sus atajos permitidos. Dile a Juan que lo agregue en Ajustes → Atajos permitidos (con el nombre exacto que tiene en la app Atajos). Si se parece a uno de la lista, pregúntale si era ese."]), false)
            return
        }
        guard UIApplication.shared.applicationState == .active else {
            fin(ManosAlma.json(["permitido": true, "abierto": false, "motivo": "El teléfono está bloqueado: iOS no deja abrir Atajos así. Dile a Juan que desbloquee y te lo vuelva a pedir."]), false)
            return
        }
        // Solo letras y números sin codificar: los espacios, tildes, «&» y «+» del nombre van codificados.
        let seguros = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        guard let q = exacto.addingPercentEncoding(withAllowedCharacters: seguros), let u = URL(string: "shortcuts://run-shortcut?name=" + q) else {
            fin(ManosAlma.json(["error": "No pude armar el enlace del atajo."]), true); return
        }
        UIApplication.shared.open(u, options: [:]) { ok in
            let o: [String: Any] = ok
                ? ["permitido": true, "abierto": true, "que": "Abrí el atajo «" + exacto + "» en la app Atajos. Si no existe con ese nombre, Atajos lo dice en pantalla."]
                : ["permitido": true, "abierto": false, "motivo": "iOS no abrió la app Atajos."]
            fin(ManosAlma.json(o), !ok)
        }
    }
}

/// abrir_apple_pay (Hub #662): abre la vista de pago de Apple Pay. Primero el atajo permitido de Juan para eso (si tiene uno
/// con «Apple Pay», «Wallet» o «Cartera» en el nombre); si no, la app Wallet. Reglas puras en ApplePayReglas.swift.
/// No paga ni lee tarjetas: Juan confirma con Face ID. Siempre contesta (JSON, ¿es error?).
enum ApplePay {
    static func abrir(_ fin: @escaping (String, Bool) -> Void) {
        guard UIApplication.shared.applicationState == .active else {
            fin(ManosAlma.json(["abierto": false, "motivo": "El teléfono está bloqueado: iOS no deja abrir Wallet así. Dile a Juan que desbloquee y te lo vuelva a pedir, o que dé doble clic al botón lateral."]), false)
            return
        }
        if let nombre = ApplePayReglas.atajo(en: AtajosPermitidos.lista) {
            AtajosPermitidos.correr(nombre, fin)
            return
        }
        probar(ApplePayReglas.enlaces, fin)
    }

    private static func probar(_ enlaces: [String], _ fin: @escaping (String, Bool) -> Void) {
        guard let primero = enlaces.first, let u = URL(string: primero) else {
            fin(ManosAlma.json(["abierto": false, "motivo": "iOS no abrió Wallet. Dile a Juan que dé doble clic al botón lateral para pagar con Apple Pay."]), true)
            return
        }
        UIApplication.shared.open(u, options: [:]) { ok in
            if ok {
                fin(ManosAlma.json(["abierto": true, "como": "wallet",
                                    "que": "Abrí Wallet con sus tarjetas. Para pagar: elige la tarjeta, Face ID y acerca el teléfono a la terminal. Tú no ves las tarjetas ni pagas nada."]), false)
            } else { probar(Array(enlaces.dropFirst()), fin) }
        }
    }
}
