import Foundation

/// El anillo que deja de responder (Juan, 16-nov-2026). Lógica pura, sin iOS: se prueba sola en Pruebas/AnilloVuelve.
/// «Alma con el anillo» funciona porque la app es la que está «Reproduciendo» (audio en silencio en bucle): los toques del
/// anillo llegan como reproducir/pausar. Si otra app de audio o una llamada se lo quita, nada lo recuperaba hasta abrir la app.
///   · Al terminar la interrupción (o si iOS la da por terminada al cambiar la salida de audio), la app vuelve a quedar lista.
///   · Si una interrupción no termina sola en 30 s (Spotify sigue sonando y nunca avisa), se intenta; durante una llamada de
///     teléfono se espera otros 30 s (no se avisa nada a media llamada).
///   · Música de otra app sonando (Juan, 17-nov-2026: «que no haya conflictos en la reproducción»): el anillo no le quita el
///     audio, ni a los 30 s ni al abrir la app; espera a que la música pare y vuelve solo. Mientras suena, el toque del anillo
///     pausa la música (iOS se lo da a la app que suena) y con eso el anillo vuelve a Alma.
///   · Si no se puede (con el teléfono bloqueado iOS no deja abrir el micrófono otra vez, u otra app no suelta el audio), una
///     notificación: «Abre Alma para que el anillo vuelva a funcionar». Una sola vez hasta que vuelva a funcionar.
///   · Los pasos de la voz (voz_pasos) van al Hub con los avisos (vozAvisos), sin datos personales, para el diagnóstico.
enum AnilloVuelve {
    enum Evento: Equatable {
        case interrupcionTermino
        case interrupcionSinFin        // empezó hace 30 s y iOS no avisó que terminó
        case ruta(motivo: UInt)        // AVAudioSession.RouteChangeReason
    }
    enum Que: Equatable { case nada, quedarLista, esperar }

    /// Motivos de cambio de ruta que pueden dejar al anillo sin audio: audífonos nuevos o que se van, otra app que cambia
    /// la categoría del audio, iOS que despierta o reacomoda la salida. (1 nuevo · 2 se fue · 3 categoría · 4 override ·
    /// 6 despertó · 7 sin ruta para la categoría · 8 configuración.) El cambio que hace la propia app no cuenta: se mira si algo se rompió.
    static let motivosRuta: Set<UInt> = [1, 2, 3, 4, 6, 7, 8]
    static let esperaSinFin: TimeInterval = 30
    static let texto = "Abre Alma para que el anillo vuelva a funcionar."

    /// ¿Se vuelve a quedar lista? Solo con el modo anillo, sin llamada de Alma; en una ruta, solo si algo se rompió (el
    /// micrófono o el audio en silencio se detuvieron). `telefono`: hay una llamada de teléfono en curso. `otraSuena`: otra app
    /// está sonando (Spotify): tomar el audio la pausaría, así que se espera.
    static func decidir(_ e: Evento, modoAnillo: Bool, enLlamada: Bool, microfono: Bool, silencio: Bool, telefono: Bool = false, otraSuena: Bool = false) -> Que {
        guard modoAnillo, !enLlamada else { return .nada }
        switch e {
        case .interrupcionTermino: return .quedarLista
        case .interrupcionSinFin: return telefono || otraSuena ? .esperar : .quedarLista
        case .ruta(let m): return motivosRuta.contains(m) && (!microfono || !silencio) && !otraSuena ? .quedarLista : .nada
        }
    }

    /// Después de intentarlo: ¿hay que pedir que abra la app? Si el audio no se pudo tomar, si el audio en silencio no suena
    /// (sin él la app deja de estar «Reproduciendo») o si el micrófono quedó apagado con la app en segundo plano.
    /// Al abrir la app: ¿se vuelve a tomar el audio para el anillo? No si otra app está sonando (la pausaría).
    static func alAbrir(modoAnillo: Bool, otraSuena: Bool) -> Bool { modoAnillo && !otraSuena }

    /// Spotify mientras usas la app (Juan, 17-nov-2026: «la música no suena mientras uso la plataforma»). Cada vez que el
    /// anillo queda listo (al abrir la app, al encenderlo, al colgar, al salir de conferencia) tomaba el audio que no se
    /// mezcla y pausaba la música. Ahora, con música sonando:
    ///   · dejarSonar: Alma suelta su audio (micrófono y silencio) avisando a las otras apps: la música sigue y vuelve a su
    ///     volumen si estaba baja por la llamada. El anillo vuelve solo cuando la música pare (como al abrir la app).
    ///   · esperar: si otro modo usa el micrófono (conferencia, Modo calle, el Modo Inicio), no se le toca; solo se espera.
    /// Sin música, se toma como siempre.
    enum AlQuedar: Equatable { case tomar, dejarSonar, esperar }
    static func alQuedarLista(otraSuena: Bool, microfonoOcupado: Bool) -> AlQuedar {
        guard otraSuena else { return .tomar }
        return microfonoOcupado ? .esperar : .dejarSonar
    }

    static func avisar(activo: Bool, silencio: Bool, microfono: Bool, appActiva: Bool, yaAvisado: Bool) -> Bool {
        guard !appActiva, !yaAvisado else { return false }
        return !activo || !silencio || !microfono
    }
}

/// Los pasos de la voz que van al Hub (diagnóstico del anillo, ALMA_ANILLO con origen «app»): solo lo nuevo desde el último
/// envío y sin datos personales (el texto de un aviso, lo que Alma puso en el chat, lo que va entre «», correos).
enum PasosAnillo {
    static let maximo = 30
    static let largo = 140
    /// Pasos que llevan texto de Juan o de un aviso después de los dos puntos: se queda solo el inicio.
    static let conTexto = ["Aviso: ", "Alma lo puso en el chat: ", "Panel de Claudio: "]

    /// Lo nuevo de `pasos` después del último enviado (si ya no está en la lista, todo). Van por tandas de `maximo`,
    /// empezando por lo más viejo: lo que no cabe en esta vuelta va en la siguiente (antes se mandaban solo los últimos 14 y
    /// el principio de una llamada larga, donde está el porqué de un corte, se perdía).
    static func nuevos(_ pasos: [String], ultimoEnviado: String?) -> [String] {
        guard let u = ultimoEnviado, let i = pasos.lastIndex(of: u) else { return Array(pasos.prefix(maximo)) }
        return Array(pasos[pasos.index(after: i)...].prefix(maximo))
    }

    static func limpiar(_ pasos: [String]) -> [String] {
        pasos.suffix(maximo).map { linea in
            var s = linea
            for p in conTexto { if let r = s.range(of: p) { s = String(s[..<r.upperBound]) + "…"; break } }
            s = s.replacingOccurrences(of: "«[^»]*»", with: "«…»", options: .regularExpression)
            s = s.replacingOccurrences(of: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", with: "(correo)", options: .regularExpression)
            s = s.replacingOccurrences(of: "https?://\\S+", with: "(enlace)", options: .regularExpression)
            return String(s.prefix(largo))
        }.filter { !$0.isEmpty }
    }
}
