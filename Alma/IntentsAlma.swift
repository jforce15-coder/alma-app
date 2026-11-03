import AppIntents
import UIKit

/// App Intents de Alma (#396 T4): así Siri, el botón de acción y la app Atajos le hablan a Alma.
/// · «Pregúntale a Alma»: abre la app y empieza la voz (con texto, ese es el primer mensaje y Alma responde a eso).
/// · «Modo calle»: enciende o apaga el Modo calle (ModoCalle.swift). Sin decir cuál, lo cambia.
/// · «Mándale a Alma»: le escribe a Alma en tu chat, como el cuadro de texto de la app (opEnviar, canal «app»), y te dice
///   en corto lo que contestó.
/// Con el Modo calle encendido Siri no lee nada en voz alta (su voz es otra, de hombre en el teléfono de Juan): el diálogo
/// queda vacío y, si hay respuesta, la dice el Modo calle con la voz de Alma.
struct PreguntarleAAlma: AppIntent {
    static var title: LocalizedStringResource = "Pregúntale a Alma"
    static var description = IntentDescription("Abre Alma y empieza a hablar con ella por voz. Si escribes la pregunta, Alma responde a eso de una vez.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Pregunta")
    var texto: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        // La app recién se abre: un momento para que quede activa (el micrófono solo se abre con la app a la vista).
        if UIApplication.shared.applicationState != .active { try? await Task.sleep(nanoseconds: 800_000_000) }
        let v = VozNativa.shared
        // Sin sesión guardada, la app queda abierta en el inicio (ahí se entra) y no se llama.
        guard v.puedeHablar else { return .result() }
        let t = (texto ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { v.hablarDesdePantalla() } else { v.hablarAlOir(t) }
        return .result()
    }
}

struct ModoCalleAlma: AppIntent {
    static var title: LocalizedStringResource = "Modo calle"
    static var description = IntentDescription("Enciende o apaga el Modo calle de Alma: con audífonos y el teléfono bloqueado, dices «Alma» y una frase.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Encender")
    var encender: Bool?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if UIApplication.shared.applicationState != .active { try? await Task.sleep(nanoseconds: 800_000_000) }
        let m = ModoCalle.shared
        let on = encender ?? !m.encendido
        m.poner(on)
        // Encender pide permisos y carga el detector: se espera un poco para decir lo que de verdad pasó.
        if on { try? await Task.sleep(nanoseconds: 1_500_000_000) }
        let frase: String
        // Ya escucha «Alma»: lo confirma Alma con su voz (cuando Siri suelta el audio); Siri no dice nada con la suya.
        if on, m.encendido { _ = m.decirDeFuera("Modo calle encendido."); return .result(dialog: "") }
        if m.encendido == on { frase = "Modo calle apagado." }
        else { frase = on ? "Estoy encendiendo el Modo calle; si no queda, ábrelo en Alma." : "No pude apagar el Modo calle; ábrelo en Alma." }
        return .result(dialog: "\(frase)")
    }
}

struct MandaleAAlma: AppIntent {
    static var title: LocalizedStringResource = "Mándale a Alma"
    static var description = IntentDescription("Le escribe a Alma en tu chat, como si lo escribieras en la app, y te dice lo que contestó.")

    @Parameter(title: "Mensaje", requestValueDialog: "¿Qué le mando a Alma?")
    var texto: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let r = await ChatAlma.enviar(texto)
        // Con el Modo calle encendido, la respuesta la dice Alma con su voz (al soltar Siri el audio), no Siri.
        if await MainActor.run(body: { ModoCalle.shared.decirDeFuera(r) }) { return .result(dialog: "") }
        return .result(dialog: "\(r)")
    }
}

/// Las frases de Siri (llevan el nombre de la app). Salen solas en Atajos y en el botón de acción.
struct AtajosDeAlma: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PreguntarleAAlma(),
                    phrases: ["Pregúntale a \(.applicationName)", "Pregunta a \(.applicationName)", "Habla con \(.applicationName)"],
                    shortTitle: "Pregúntale a Alma", systemImageName: "waveform")
        AppShortcut(intent: ModoCalleAlma(),
                    phrases: ["Modo calle de \(.applicationName)", "Activa el modo calle de \(.applicationName)", "\(.applicationName) modo calle"],
                    shortTitle: "Modo calle", systemImageName: "figure.walk")
        AppShortcut(intent: MandaleAAlma(),
                    phrases: ["Mándale a \(.applicationName)", "Escríbele a \(.applicationName)", "Manda un mensaje a \(.applicationName)"],
                    shortTitle: "Mándale a Alma", systemImageName: "paperplane")
    }
}

/// El chat con Alma desde fuera de la pantalla (Mándale a Alma): la misma acción del cuadro de texto de la app.
enum ChatAlma {
    static func enviar(_ texto: String) async -> String {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "No me dijiste qué mandarle a Alma." }
        guard let url = Llave.leer("voz_url"), let token = Llave.leer("voz_token"), let sesion = Llave.leer("voz_sesion"), let u = URL(string: url) else {
            return "Abre Alma una vez con tu sesión para que pueda mandarle mensajes."
        }
        var b: [String: Any] = ["hub": 1, "action": "opEnviar", "texto": t, "canal": "app", "token": token, "session": sesion, "app": "alma"]
        if let email = correo(sesion) { b["email"] = email }
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.timeoutInterval = 25
        r.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: b)
        do {
            let (d, _) = try await URLSession.shared.data(for: r)
            let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
            guard (j?["ok"] as? Bool) == true else { return "No pude mandárselo a Alma ahora. Intenta otra vez." }
            let alma = (j?["alma"] as? [String: Any])?["texto"] as? String ?? ""
            return alma.isEmpty ? "Listo, se lo mandé a Alma." : ModoCalle.corto(alma, palabras: 60)
        } catch let e as URLError where e.code == .timedOut {
            // Se cortó la espera, no el pedido: el Hub lo sigue y la respuesta queda en el chat.
            return "Se lo mandé a Alma; te contesta en el chat."
        } catch {
            return "No pude conectar con Alma. Revisa tu internet."
        }
    }

    /// El correo de la sesión firmada (va dentro, en base64), como lo manda el Modo calle.
    private static func correo(_ s: String) -> String? {
        guard let i = s.lastIndex(of: ".") else { return nil }
        var b = String(s[..<i]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        guard let d = Data(base64Encoded: b), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        if let p = j["p"] as? [String: Any], let e = p["email"] as? String, !e.isEmpty { return e }
        return j["e"] as? String
    }
}
