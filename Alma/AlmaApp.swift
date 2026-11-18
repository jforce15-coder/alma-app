import SwiftUI

/// Alma · navegador con Alma integrada.
/// Abre cualquier página (las apps de Spacio AM, GitHub, Google…) y tiene a Alma a un toque, con la página como contexto.
@main
struct AlmaApp: App {
    @StateObject private var navegador = Navegador()

    init() {
        // Con un anillo ya conectado antes, se retoma la conexión desde el arranque (también si iOS despierta la app por él).
        if Anillo.hayGuardado { _ = Anillo.shared; _ = AnilloAlma.shared }   // AnilloAlma: lo que Alma sabe del anillo (batería, pasos, ritmo)
        // Notificaciones push (Ticket #28, PushAlma.swift): si el Hub ya dio con qué registrarse, OneSignal arranca desde el inicio.
        PushAlma.shared.arrancar()
        // «Alma con el anillo»: la app queda lista para que dos toques del anillo enciendan o apaguen el modo conferencia, también con el teléfono bloqueado.
        VozNativa.shared.arrancarSiHaceFalta()
        // Voz de respaldo (Hub #657, Senal.swift): la señal de internet se vigila desde el inicio; lo guardado sin internet se manda.
        Senal.shared.empezar()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(navegador)
                // alma://abrir?u=<enlace> (atajo de Compartir de iOS) o alma://https://… · alma://calle?on=1|0 (Modo calle)
                // Un archivo («Compartir» o «Abrir en Alma» desde Archivos, Mail…): queda cargado en el chat del inicio (ArchivosEntrada.swift)
                .onOpenURL { u in
                    if u.isFileURL { AlmaApp.recibirArchivo(u, navegador) }
                    else if u.host?.lowercased() == "calle" { ModoCalle.shared.abrirEnlace(u) } else { navegador.abrir(desdeEnlace: u) }
                }
        }
    }
}

extension AlmaApp {
    /// Lee el archivo que iOS le pasó a la app (con permiso de acceso si viene de otra app) y lo deja cargado en el chat del
    /// inicio, como soltarlo en la pantalla. Lo que no sirve (tipo, tamaño) se dice en el chat. La copia de iOS se borra.
    static func recibirArchivo(_ u: URL, _ nav: Navegador) {
        let acceso = u.startAccessingSecurityScopedResource()
        defer { if acceso { u.stopAccessingSecurityScopedResource() } }
        let nombre = u.lastPathComponent
        let js: String
        if let d = try? Data(contentsOf: u, options: .mappedIfSafe) {
            switch ArchivosEntrada.js(nombre: nombre, datos: d) {
            case .listo(let j): js = j
            case .noSirve(let t): js = ArchivosEntrada.jsAviso(t)
            }
        } else { js = ArchivosEntrada.jsAviso("No pude leer «\(nombre)».") }
        if u.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: u) }   // la copia que iOS dejó en la app
        NotificationCenter.default.post(name: .manosAlma, object: nil)   // si la pantalla de la llamada estaba encima, se baja
        nav.alInicio(js)
    }
}

extension Color {
    /// Colores de la marca (Spacio AM · design system).
    static let almaCoral = Color(red: 0xE9 / 255, green: 0x82 / 255, blue: 0x6A / 255)
    static let almaTinta = Color(red: 0x3E / 255, green: 0x3F / 255, blue: 0x3F / 255)
    static let almaFondo = Color(red: 0xF5 / 255, green: 0xF3 / 255, blue: 0xF0 / 255)
    static let almaBorde = Color(red: 0xD8 / 255, green: 0xD4 / 255, blue: 0xCE / 255)
}
