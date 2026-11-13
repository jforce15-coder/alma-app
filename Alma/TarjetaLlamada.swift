import Foundation

// Tarjeta de la llamada (#446 T2): la lógica pura (sin pantalla, sin iOS), para poder probarla sola (Pruebas/TarjetaLlamada).
// El Hub arma la tarjeta (apps-script/tarjeta.js) cuando la secretaria trajo UNA reserva, conversación, consulta o apartamento; la
// app la pide (vozTarjeta) y la pinta en LlamadaVista o en la llamada de la roca del inicio (alma/inicio.html).
// Decisiones de Juan (4-nov-2026):
//   · Sube desde abajo sobre la roca (la roca se achica a 96 px y «Terminar» sigue a la vista, también en un iPhone SE).
//   · Con el teléfono bloqueado o en el Modo calle no sale nada en la llamada: al colgar queda en el Chat con Alma junto a
//     esa llamada (lo guarda el Hub en la columna tarjeta), sin notificación.
// Tablero bento (Hub #508, Juan 13-nov-2026): se maneja por ESTADO, no por segundos.
//   · Se queda en pantalla mientras dure la llamada: no se encoge solo (antes, a los 20 s o al cambiar de tema).
//   · Una tarjeta nueva de otra cosa lo reemplaza; volver a algo que ya se vio en la llamada también lo muestra otra vez
//     (el Hub lo sabe porque la app avisa «tablero: estado» al vincular).
//   · Al colgar (o cuando el modo conferencia vuelve a esperar «Alma») se quita; la página del inicio espera ~3 s y
//     vuelve a la pantalla de siempre.
//   · También en el modo conferencia, con la pantalla encendida. Con el teléfono bloqueado, solo el chat (como siempre).
//   · Juan lo puede guardar en la pestañita (el asa, o tocar a Alma en la esquina) y abrirlo otra vez.

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
        guard !clave.isEmpty, TarjetaVoz.tipos.contains(tipo) else { return nil }
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
    /// Lo que la app sabe pintar. «consulta» (Hub #470): quien escribió por Airbnb sin reservar (persona, propiedad,
    /// fechas, noches, su mensaje, el precio si lo hay y el borrador que saldría); se pinta como una reserva. «edificio»
    /// (Hub #508 T2): el edificio completo (foto, apartamentos, llegadas y salidas de hoy); se pinta como un apartamento.
    static let tipos = ["reserva", "conversacion", "apartamento", "consulta", "edificio"]
    /// El nombre del tipo (la etiqueta de la tarjeta y la pestañita).
    static func nombre(_ tipo: String) -> String {
        switch tipo {
        case "reserva": return "Reserva"
        case "conversacion": return "Conversación"
        case "consulta": return "Consulta"
        case "edificio": return "Edificio"
        default: return "Apartamento"
        }
    }
}

/// Qué se ve de la tarjeta y cuándo. La usan LlamadaVista y la página del inicio (por AlmaVoz.evento).
struct ReglasTarjeta {
    enum Vista: String { case nada, abierta, detalle, pestana }
    /// mostrar: cambia lo que se ve · igual: ya es la que se ve · soloChat: sin pantalla (el Hub ya la dejó en el chat).
    enum Decision: Equatable { case mostrar, igual, soloChat }

    private(set) var actual: TarjetaVoz?
    private(set) var vista: Vista = .nada

    /// ¿Juan ve la pantalla? Con el teléfono bloqueado o en el Modo calle, no. En el modo conferencia, sí si la app está a
    /// la vista (Juan, 13-nov-2026).
    static func pantallaVisible(appActiva: Bool, calle: Bool) -> Bool { appActiva && !calle }

    /// Llegó una tarjeta del Hub. Sin pantalla no se muestra. Una a la vez: la nueva reemplaza a la anterior y se queda
    /// hasta que llegue otra o se cuelgue. La misma (mismo id) no cambia nada; si estaba en la pestañita, se abre.
    mutating func recibir(_ t: TarjetaVoz, pantalla: Bool) -> Decision {
        guard pantalla else { return .soloChat }
        if let a = actual, a.id == t.id {
            if vista == .pestana || vista == .nada { vista = .abierta; return .mostrar }
            return .igual
        }
        actual = t; vista = .abierta
        return .mostrar
    }
    /// Tocar la tarjeta: muestra más (o menos); la llamada sigue.
    mutating func detalle() {
        guard actual != nil else { return }
        if vista == .abierta { vista = .detalle } else if vista == .detalle { vista = .abierta }
    }
    /// Tocar la pestañita: la abre otra vez.
    mutating func abrir() { guard actual != nil, vista == .pestana else { return }; vista = .abierta }
    /// Bajarla con el asa o tocar a Alma en la esquina: se guarda en la pestañita (no se va).
    mutating func plegar() { if actual != nil, vista == .abierta || vista == .detalle { vista = .pestana } }
    /// Colgó, o el modo conferencia volvió a esperar «Alma»: no queda nada en la llamada (lo que hubo vive en el Chat con Alma).
    mutating func terminar() { actual = nil; vista = .nada }
}
