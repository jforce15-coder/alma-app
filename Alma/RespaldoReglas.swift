import Foundation

/// Voz de respaldo de Alma (Hub #657; Juan, 17-nov-2026: «voz local de respaldo para Alma, al igual que Claudio, monitoreando
/// la señal de internet para activarla únicamente en casos de problemas de conexión»). Lógica pura, con sus pruebas en
/// Pruebas/Respaldo. Lo que toca iOS: Senal.swift (vigila la señal y manda lo guardado), ClaudioLocal.swift (la voz) y
/// VozNativa.swift (cuándo entra y cuándo sale).
/// · Entra solo con problemas de conexión, en una llamada normal con Alma (no en el Modo calle ni en conferencia, que
///   tienen su propio camino): sin internet al llamar, si la ficha no llega por la red, si ElevenLabs no conecta, o si la
///   voz se corta sin internet o por segunda vez en 3 minutos (la primera se vuelve a abrir como siempre).
/// · Sale sola: con la señal estable 20 s y en un silencio, Alma vuelve a su voz de ElevenLabs. Si no se pudo, espera 2 min
///   para intentarlo otra vez.
/// · Sin internet, lo que Juan pide se guarda y se manda al volver la señal (máximo 5 pedidos, de los últimos 30 min).
enum RespaldoReglas {

    // MARK: - Cuándo entra

    /// Ventana en la que un segundo corte de la voz ya no es casualidad: la señal está mala.
    static let ventanaCortes: TimeInterval = 180

    /// ¿Se pasa a la voz de respaldo tras un corte de ElevenLabs? Sin internet, siempre; si nunca conectó, también (la señal
    /// no alcanzó); si ya hubo otro corte hace poco, también. Con un solo corte y con internet, se vuelve a abrir como siempre.
    static func trasCorte(hayRed: Bool, conectada: TimeInterval?, cortes: [Date], ahora: Date) -> Bool {
        if !hayRed || conectada == nil { return true }
        return cortes.contains { ahora.timeIntervalSince($0) < ventanaCortes }
    }

    /// Los cortes que todavía cuentan (los de la ventana), con el de ahora.
    static func sumarCorte(_ cortes: [Date], ahora: Date) -> [Date] {
        Array((cortes.filter { ahora.timeIntervalSince($0) < ventanaCortes } + [ahora]).suffix(5))
    }

    /// Errores de la red que dicen «no hay conexión» o «la conexión no alcanza» (no un error del Hub).
    static func esDeRed(_ codigo: Int) -> Bool {
        [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff,
         NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed, NSURLErrorCannotConnectToHost, NSURLErrorTimedOut,
         NSURLErrorSecureConnectionFailed, NSURLErrorCallIsActive].contains(codigo)
    }

    // MARK: - Cuándo sale

    /// Segundos de señal estable para volver a la voz de siempre, y la espera tras un intento que no resultó.
    static let estable: TimeInterval = 20, esperaTrasFallo: TimeInterval = 120

    static func volver(hayRed: Bool, buenaDesde: Date?, quieto: Bool, ultimoIntento: Date?, ahora: Date) -> Bool {
        guard hayRed, quieto, let b = buenaDesde, ahora.timeIntervalSince(b) >= estable else { return false }
        if let u = ultimoIntento, ahora.timeIntervalSince(u) < esperaTrasFallo { return false }
        return true
    }

    // MARK: - Lo que dice

    static let fraseAlEmpezar = "Hay poca señal; te escucho con mi voz del teléfono."
    static let fraseSeFue = "Se fue la señal; sigo con mi voz del teléfono. ¿Qué me decías?"
    static let fraseSigue = "Sigo con mi voz del teléfono."
    static let fraseVuelve = "Ya volvió la señal; sigo con mi voz de siempre."
    static let fraseGuardado = "Estoy sin internet. Lo guardo y lo mando en cuanto vuelva la señal."
    static let fraseLleno = "Estoy sin internet y ya guardé varios pedidos. Mejor dímelo cuando vuelva la señal."
    static let fraseSinRespuesta = "Perdón, no me llegó la respuesta. ¿Me lo repites?"
    static let fraseMandado = "Ya volvió la señal y mandé lo que me pediste."

    // MARK: - Lo que se manda al Hub

    /// La acción calle del Hub (el mismo Chat con Alma del Modo calle), sin el audio de ElevenLabs: la dice el iPhone.
    /// `alter`: «maricarmen» cuando contesta Maricarmen, el alter ego de Alma (MaricarmenReglas.swift: el Hub le pone el Weebo en 3).
    /// `vozMaricarmen`: Maricarmen con su voz de ElevenLabs, a prueba (MaricarmenReglas.vozElevenLabs): el Hub manda la frase
    /// ya dicha en PCM a 24 kHz (audio + hz).
    static func pedido(token: String, sesion: String, texto: String, alter: String? = nil, vozMaricarmen: Bool = false) -> [String: Any] {
        var b: [String: Any] = ["hub": 1, "action": "calle", "app": "alma", "token": token, "session": sesion, "canal": "calle", "sin_audio": true,
                                "texto": String(texto.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1500))]
        if let a = alter, !a.isEmpty { b["alter"] = a; if vozMaricarmen { b["voz_maricarmen"] = true } }
        return b
    }

    struct Respuesta: Equatable { let hablar: String; let claudio: Bool; var audio: Data? = nil }
    static func respuesta(_ j: [String: Any]?) -> Respuesta? {
        guard let j else { return nil }
        let h = (j["hablar"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Respuesta(hablar: h.isEmpty ? fraseSinRespuesta : h, claudio: (j["claudio"] as? Bool) == true, audio: h.isEmpty ? nil : audio(j, hz: 24000))
    }
    /// El audio que mandó el Hub: PCM 16 bits en base64 a `hz` (audio + hz). Otro formato, roto o vacío: nil (habla la voz local).
    static func audio(_ j: [String: Any]?, hz: Int) -> Data? {
        guard let b = j?["audio"] as? String, !b.isEmpty, (j?["hz"] as? NSNumber)?.intValue == hz,
              let a = Data(base64Encoded: b), a.count >= 2 else { return nil }
        return a.count % 2 == 0 ? a : a.dropLast()
    }

    // MARK: - Lo guardado sin internet

    struct Pendiente: Codable, Equatable { let texto: String; let cuando: Date }
    static let maxPendientes = 5, vigencia: TimeInterval = 30 * 60

    /// Los que todavía se mandan (los de los últimos 30 min), en orden.
    static func vigentes(_ l: [Pendiente], ahora: Date) -> [Pendiente] {
        l.filter { ahora.timeIntervalSince($0.cuando) < vigencia && !$0.texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    /// Suma uno si cabe. nil: ya no cabe (se dice fraseLleno).
    static func guardar(_ l: [Pendiente], texto: String, ahora: Date) -> [Pendiente]? {
        let v = vigentes(l, ahora: ahora), t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return v }
        guard v.count < maxPendientes else { return nil }
        return v + [Pendiente(texto: String(t.prefix(1500)), cuando: ahora)]
    }
}
