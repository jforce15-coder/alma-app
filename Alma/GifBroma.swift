import Foundation

// GIF de la broma (Hub, Juan 16-nov-2026): «cuando Alma bromee, su interfaz puede desplegar GIFs… la broma pasa y el GIF se
// quita». Alma llama en silencio a la herramienta de cliente mostrar_gif con una idea corta («slow clap», «mind blown»).
// Aquí, la lógica pura (sin pantalla, sin iOS; se prueba sola en Pruebas/GifBroma): decide si se muestra.
//   · Solo con el administrador principal (la ficha trae sus medidores) y con la pantalla a la vista (la app activa, fuera
//     del Modo calle): con el teléfono bloqueado no hay nada que ver.
//   · Con Alma, no con Claudio.
//   · Como mucho uno cada 60 s y 4 por llamada: el GIF acompaña una broma, no la llamada.
//   · La idea se limpia: letras, números, espacios y apóstrofos; de 2 a 40 letras.
// Si se muestra, VozNativa la pasa a la página del inicio (AlmaVoz.evento «gif»), que pide el GIF al Hub (acción gif) y lo
// pone unos segundos en UN cuadro del tablero o en el chat (js/alma-gif.js del Hub).
struct ReglasGif {
    static let espera: TimeInterval = 60
    static let tope = 4
    private(set) var ultimo: Date?
    private(set) var cuantos = 0

    /// La idea limpia, o nil si no sirve.
    static func idea(_ crudo: Any?) -> String? {
        let permitidos = CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: "' "))
        let t = String((crudo as? String ?? "").unicodeScalars.map { permitidos.contains($0) ? Character($0) : " " })
            .split(separator: " ").joined(separator: " ")
        let corta = String(t.prefix(40)).trimmingCharacters(in: .whitespaces)
        return corta.count >= 2 ? corta : nil
    }

    /// ¿Se muestra? Si sí, cuenta. Devuelve la idea limpia o nil.
    mutating func pedir(_ crudo: Any?, principal: Bool, pantalla: Bool, conAlma: Bool, ahora: Date = Date()) -> String? {
        guard principal, pantalla, conAlma, cuantos < ReglasGif.tope, let i = ReglasGif.idea(crudo) else { return nil }
        if let u = ultimo, ahora.timeIntervalSince(u) < ReglasGif.espera { return nil }
        ultimo = ahora; cuantos += 1
        return i
    }

    /// Llamada nueva: se empieza de cero.
    mutating func reiniciar() { ultimo = nil; cuantos = 0 }
}
