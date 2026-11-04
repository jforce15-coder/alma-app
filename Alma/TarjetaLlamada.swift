import Foundation

// Tarjeta de la llamada (#446 T2): la lógica pura (sin pantalla, sin iOS), para poder probarla sola (Pruebas/TarjetaLlamada).
// El Hub arma la tarjeta (apps-script/tarjeta.js) cuando la secretaria trajo UNA reserva, conversación o apartamento; la
// app la pide (vozTarjeta) y la pinta en LlamadaVista o en la llamada de la roca del inicio (alma/inicio.html).
// Decisiones de Juan (4-nov-2026):
//   · Sube desde abajo sobre la roca (la roca se achica a 96 px y «Terminar» sigue a la vista, también en un iPhone SE).
//   · Al cambiar de tema, o a los 20 s sin tocarla, se encoge a una pestañita; tocar la pestañita la abre otra vez.
//   · Con el teléfono bloqueado (Modo calle, anillo, conferencia) no sale nada en la llamada: al colgar queda en el Chat
//     con Alma junto a esa llamada (lo guarda el Hub en la columna tarjeta), sin notificación.
// Reglas: una a la vez (la nueva reemplaza a la anterior) y nunca la misma cosa dos veces en la llamada.

/// La tarjeta como la manda el Hub. `crudo` va tal cual a la página del inicio.
struct TarjetaVoz: Equatable {
    struct Fecha: Equatable { let t: String; let v: String; let d: String }
    struct Mensaje: Equatable { let de: String; let quien: String; let texto: String; let hora: String }
    struct Dia: Equatable { let letra: String; let n: Int; let estado: String; let hoy: Bool }

    let id: String, clave: String, tipo: String, etiqueta: String, titulo: String, sub: String
    let chip: String, tono: String, foto: String, iniciales: String
    let fechas: [Fecha], datos: [String], mensajes: [Mensaje], promesas: [String], semana: [Dia], detalle: [String]
    let conv: String, tel: String, wa: String
    let crudo: [String: Any]

    init?(_ j: [String: Any]) {
        func s(_ k: String, _ o: [String: Any] = j) -> String { (o[k] as? String) ?? ((o[k] as? NSNumber)?.stringValue ?? "") }
        func lista(_ k: String) -> [[String: Any]] { (j[k] as? [Any] ?? []).compactMap { $0 as? [String: Any] } }
        let clave = s("clave"), tipo = s("tipo")
        guard !clave.isEmpty, ["reserva", "conversacion", "apartamento"].contains(tipo) else { return nil }
        id = s("id").isEmpty ? clave : s("id"); self.clave = clave; self.tipo = tipo
        etiqueta = s("etiqueta"); titulo = s("titulo"); sub = s("sub"); chip = s("chip"); tono = s("tono"); foto = s("foto"); iniciales = s("iniciales")
        fechas = lista("fechas").map { Fecha(t: s("t", $0), v: s("v", $0), d: s("d", $0)) }
        datos = (j["datos"] as? [Any] ?? []).compactMap { $0 as? String }
        mensajes = lista("mensajes").map { Mensaje(de: s("de", $0), quien: s("quien", $0), texto: s("texto", $0), hora: s("hora", $0)) }
        promesas = (j["promesas"] as? [Any] ?? []).compactMap { $0 as? String }
        semana = lista("semana").map { Dia(letra: s("letra", $0), n: ($0["n"] as? NSNumber)?.intValue ?? 0, estado: s("e", $0), hoy: ($0["hoy"] as? Bool) ?? false) }
        detalle = (j["detalle"] as? [Any] ?? []).compactMap { $0 as? String }
        conv = s("conv"); tel = s("tel"); wa = s("wa")
        crudo = j
    }
    static func == (a: TarjetaVoz, b: TarjetaVoz) -> Bool { a.id == b.id && a.clave == b.clave }
}

/// Qué se ve de la tarjeta y cuándo. La usan LlamadaVista y la página del inicio (por AlmaVoz.evento).
struct ReglasTarjeta {
    enum Vista: String { case nada, abierta, detalle, pestana }
    enum Decision: Equatable { case mostrar, repetida, soloChat }

    /// Sin tocarla, a los 20 s se encoge a la pestañita.
    static let encogerTras: TimeInterval = 20

    private(set) var actual: TarjetaVoz?
    private(set) var vista: Vista = .nada
    private(set) var vistas: Set<String> = []
    private var desde = Date.distantPast

    /// ¿Juan ve la pantalla? Con el teléfono bloqueado, en el Modo calle o en el modo conferencia, no.
    static func pantallaVisible(appActiva: Bool, calle: Bool, conferencia: Bool) -> Bool { appActiva && !calle && !conferencia }

    /// Llegó una tarjeta del Hub. Sin pantalla no se muestra (el Hub ya la dejó en el chat); la misma cosa no sale dos veces.
    mutating func recibir(_ t: TarjetaVoz, pantalla: Bool, ahora: Date) -> Decision {
        guard pantalla else { return .soloChat }
        if vistas.contains(t.clave) { return .repetida }
        vistas.insert(t.clave)
        actual = t; vista = .abierta; desde = ahora   // una a la vez: la nueva reemplaza a la anterior
        return .mostrar
    }
    /// Cualquier toque en la tarjeta: vuelve a contar los 20 s.
    mutating func toque(ahora: Date) { if vista == .abierta || vista == .detalle { desde = ahora } }
    /// Tocar la tarjeta: muestra más (o menos); la llamada sigue.
    mutating func detalle(ahora: Date) {
        guard actual != nil else { return }
        if vista == .abierta { vista = .detalle } else if vista == .detalle { vista = .abierta } else { return }
        desde = ahora
    }
    /// Tocar la pestañita: la abre otra vez.
    mutating func abrir(ahora: Date) { guard actual != nil, vista == .pestana else { return }; vista = .abierta; desde = ahora }
    /// Bajarla con el asa.
    mutating func plegar() { if actual != nil, vista == .abierta || vista == .detalle { vista = .pestana } }
    /// Cambió el tema (Alma va a buscar otra cosa): se encoge.
    mutating func cambioDeTema() { plegar() }
    /// Cada segundo: ¿ya pasaron 20 s sin tocarla? Devuelve true si cambió.
    mutating func tic(ahora: Date) -> Bool {
        guard vista == .abierta || vista == .detalle, ahora.timeIntervalSince(desde) >= ReglasTarjeta.encogerTras else { return false }
        vista = .pestana; return true
    }
    /// Colgó: no queda nada en la llamada (lo que hubo vive en el Chat con Alma).
    mutating func terminar() { actual = nil; vista = .nada; vistas = []; desde = .distantPast }
}
