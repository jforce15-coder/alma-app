import Foundation

/// Reglas puras del Navegador de Alma en sus modos (Hub #773).
/// Sin iOS ni WebKit: se prueban solas (Pruebas/Navegador). Las usan Navegador.swift, ManosAlma.swift y GuiaNavegador.swift.
///  · Pausa de privacidad: una contraseña, un código de verificación, un dato de tarjeta o un «no soy un robot» a la vista
///    → Alma no ve (ni texto, ni captura) y avisa «Te toca a ti». Lo escribe Juan solo.
///  · Tarjeta de datos (modo guiado): lo que Juan copia y pega, nunca una contraseña, un código o una tarjeta.
///  · Ritmo humano (modo control): una acción a la vez, una pausa al azar antes de cada una y un tope por sitio.
enum NavegadorReglas {

    // MARK: - Pausa de privacidad

    /// Lo que vio el detector de la página (Navegador.jsPrivada), ya sin ningún valor: solo qué hay a la vista.
    struct Senales: Equatable {
        var clave = false      // input type=password o autocomplete current-password / new-password
        var codigo = false     // autocomplete one-time-code o un campo de código de verificación (OTP, 2FA, SMS)
        var tarjeta = false    // autocomplete cc-* o un campo de tarjeta / CVV
        var captcha = false    // reCAPTCHA, hCaptcha, Turnstile, Arkose o «verifica que eres humano»
        var enfocado = false   // el campo sensible tiene el cursor (Juan está escribiendo ahí)
    }

    enum Motivo: String, Equatable {
        case clave, codigo, tarjeta, captcha

        /// El aviso en la pantalla (arriba del navegador).
        var aviso: String {
            switch self {
            case .clave: return "Te toca a ti: escribe tu contraseña. Alma no mira."
            case .codigo: return "Te toca a ti: escribe el código. Alma no mira."
            case .tarjeta: return "Te toca a ti: escribe los datos de la tarjeta. Alma no mira."
            case .captcha: return "Te toca a ti: esta página quiere saber si eres humano."
            }
        }

        /// Lo que se le dice a Alma (la herramienta y el aviso en la llamada). Nunca lleva lo que hay en la pantalla.
        var paraAlma: String {
            let que: String
            switch self {
            case .clave: que = "una contraseña"
            case .codigo: que = "un código de verificación"
            case .tarjeta: que = "datos de tarjeta"
            case .captcha: que = "una prueba de «no soy un robot»"
            }
            return "PAUSA DE PRIVACIDAD: en la página hay " + que + ". No la ves ni la lees, y no se guarda nada de esta pantalla. "
                + "Dile a Juan en una frase «te toca a ti» (que lo haga él solo) y nunca le pidas que te lo diga en voz alta. "
                + "Espera a que diga «listo»; entonces vuelve a intentar."
        }
    }

    /// ¿Hay que pausar? El captcha manda primero (siempre es de Juan); luego lo que está enfocado; luego lo que está a la vista.
    static func motivo(_ s: Senales) -> Motivo? {
        if s.captcha { return .captcha }
        if s.clave { return .clave }
        if s.codigo { return .codigo }
        if s.tarjeta { return .tarjeta }
        return nil
    }

    /// «Listo» en el aviso: Alma vuelve a ver esa página, aunque el campo siga ahí (ya lleno), hasta que Juan vuelva a poner
    /// el cursor en un campo sensible o la página cambie. Un captcha a la vista no se libera con «Listo».
    static func pausar(_ s: Senales, liberada: Bool) -> Motivo? {
        guard let m = motivo(s) else { return nil }
        if m == .captcha { return m }
        if liberada && !s.enfocado { return nil }
        return m
    }

    // MARK: - Tarjeta de datos (modo guiado)

    /// Un dato para copiar y pegar: «Número de reserva · HM4K2Q».
    struct Dato: Equatable, Identifiable {
        var etiqueta: String
        var valor: String
        var id: String { etiqueta.lowercased() }
    }

    static let maxDatos = 6
    static let maxValor = 300

    /// Lo que nunca va en la tarjeta: contraseñas, códigos y tarjetas. Devuelve el motivo del rechazo, o nil si se puede.
    static func rechazoDato(etiqueta: String, valor: String) -> String? {
        let e = etiqueta.lowercased(), v = valor.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { return "Falta el dato." }
        if v.count > maxValor { return "El dato es muy largo para la tarjeta (máximo \(maxValor) letras)." }
        let sensibles = ["contraseña", "contrasena", "password", "clave", "pin", "cvv", "cvc", "código de seguridad", "codigo de seguridad",
                         "código de verificación", "codigo de verificacion", "verificación", "otp", "2fa", "token", "tarjeta", "card"]
        if sensibles.contains(where: { palabra(e, $0) }) {
            return "Eso es privado (contraseña, código o tarjeta): no va en la tarjeta. Que Juan lo escriba él solo."
        }
        if pareceTarjeta(v) { return "Parece un número de tarjeta: no va en la tarjeta. Que Juan lo escriba él solo." }
        return nil
    }

    /// Agrega o cambia un dato (misma etiqueta = se reemplaza); los más viejos salen si pasa de `maxDatos`.
    static func agregar(_ d: Dato, a lista: [Dato]) -> [Dato] {
        var l = lista.filter { $0.id != d.id }
        l.append(d)
        if l.count > maxDatos { l.removeFirst(l.count - maxDatos) }
        return l
    }

    /// 13 a 19 dígitos que pasan la prueba de Luhn (con o sin espacios y guiones).
    static func pareceTarjeta(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.allSatisfy({ $0.isNumber || $0 == " " || $0 == "-" }) else { return false }
        let d = t.compactMap { $0.wholeNumberValue }
        guard (13...19).contains(d.count) else { return false }
        var suma = 0
        for (i, x) in d.reversed().enumerated() { let y = i % 2 == 1 ? x * 2 : x; suma += y > 9 ? y - 9 : y }
        return suma % 10 == 0
    }

    /// La palabra entera (o la frase) dentro del texto: «pin» sí en «PIN de la tarjeta», no en «pintura».
    private static func palabra(_ texto: String, _ p: String) -> Bool {
        var desde = texto.startIndex
        while let r = texto.range(of: p, range: desde..<texto.endIndex) {
            let antes = r.lowerBound == texto.startIndex ? nil : texto[texto.index(before: r.lowerBound)]
            let despues = r.upperBound == texto.endIndex ? nil : texto[r.upperBound]
            let borde = { (c: Character?) in c.map { !($0.isLetter || $0.isNumber) } ?? true }
            if borde(antes) && borde(despues) { return true }
            desde = r.upperBound
        }
        return false
    }

    // MARK: - Ritmo humano (modo control)

    /// Una pausa al azar antes de actuar, como una persona (azar entre 0 y 1). Leer y señalar no esperan.
    static func pausa(_ herramienta: String, azar: Double) -> TimeInterval {
        let a = min(max(azar, 0), 1)
        switch herramienta {
        case "tocar": return 0.6 + 0.9 * a        // 0,6 a 1,5 s
        case "escribir": return 0.4 + 0.7 * a     // 0,4 a 1,1 s
        case "bajar": return 0.25 + 0.5 * a       // 0,25 a 0,75 s
        default: return 0
        }
    }

    /// Las herramientas que actúan sobre la página (las que cuentan para el tope por sitio y van una a la vez).
    static let actuan: Set<String> = ["tocar", "escribir", "bajar"]

    /// Tope por sitio: como mucho `porMinuto` acciones en 60 s y `porDia` en 24 h en el mismo dominio. Así una página como
    /// PedidosYa no ve una ráfaga de máquina y no bloquea la cuenta de Juan.
    struct Tope: Equatable {
        var porMinuto = 12
        var porDia = 300
        private(set) var marcas: [String: [Date]] = [:]

        init(porMinuto: Int = 12, porDia: Int = 300) { self.porMinuto = porMinuto; self.porDia = porDia }

        /// nil si puede actuar ya (y lo anota); si no, cuántos segundos faltan.
        mutating func pedir(_ dominio: String, ahora: Date) -> TimeInterval? {
            let d = Tope.base(dominio)
            var l = (marcas[d] ?? []).filter { ahora.timeIntervalSince($0) < 86_400 }
            let minuto = l.filter { ahora.timeIntervalSince($0) < 60 }
            if l.count >= porDia, let p = l.first { marcas[d] = l; return 86_400 - ahora.timeIntervalSince(p) }
            if minuto.count >= porMinuto, let p = minuto.first { marcas[d] = l; return max(1, 60 - ahora.timeIntervalSince(p)) }
            l.append(ahora); marcas[d] = l
            return nil
        }

        /// «www.pedidosya.com.gt» y «m.pedidosya.com.gt» cuentan juntos.
        static func base(_ host: String) -> String {
            var h = host.lowercased()
            for p in ["www.", "m.", "mobile."] where h.hasPrefix(p) { h.removeFirst(p.count) }
            return h
        }
    }
}
