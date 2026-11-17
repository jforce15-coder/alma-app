import AVFoundation
import AVKit
import SwiftUI

/// Audio de la llamada (Juan, 17-nov-2026): elegir el micrófono y la salida de la llamada; con el Modo compañero, el
/// micrófono del teléfono de fábrica. Las reglas: AudioLlamadaReglas.swift. Se abre con el botón de audio de la llamada
/// (arriba a la derecha en LlamadaVista). La voz lo aplica al abrir el micrófono, si cambia la ruta y si el Hub avisa que
/// el compañero empezó o dejó de mirar (Companero.swift).
final class AudioLlamada: ObservableObject {
    static let shared = AudioLlamada()
    typealias Puerto = AudioLlamadaReglas.Puerto

    @Published private(set) var entradas: [Puerto] = []
    @Published private(set) var entradaAhora: Puerto?
    @Published private(set) var salidaAhora = ""
    @Published private(set) var salidaTipo = ""
    @Published private(set) var companero = false
    @Published private(set) var prefEntrada: String
    @Published private(set) var prefSalida: String

    let dispositivo = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    private var mirandoAhora: Bool?          // lo que dijo el Hub en esta llamada (nil: todavía nada)
    private var puseEntrada = false, puseBocina = false
    private var enLlamada = false

    private init() {
        prefEntrada = UserDefaults.standard.string(forKey: AudioLlamadaReglas.claveEntrada) ?? AudioLlamadaReglas.automatico
        prefSalida = UserDefaults.standard.string(forKey: AudioLlamadaReglas.claveSalida) ?? AudioLlamadaReglas.automatico
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.mirar() }
        mirar()
    }

    // MARK: - Lo que llama la voz

    /// Al abrir el micrófono de una llamada (antes de encender el motor).
    func empezo() {
        enLlamada = true; mirandoAhora = nil
        aplicar("al abrir el micrófono")
    }
    /// Al colgar: se suelta lo que se pidió (el Modo Inicio, la conferencia y el anillo siguen como siempre).
    func termino() {
        enLlamada = false; mirandoAhora = nil
        let s = AVAudioSession.sharedInstance()
        if puseEntrada { try? s.setPreferredInput(nil); puseEntrada = false }
        if puseBocina { try? s.overrideOutputAudioPort(.none); puseBocina = false }
        mirar()
    }
    /// El Hub contestó si el compañero mira esta llamada.
    func companeroMira(_ m: Bool) {
        if m { UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: AudioLlamadaReglas.claveCompanero) }
        guard enLlamada, m != mirandoAhora else { return }
        mirandoAhora = m
        aplicar(m ? "el Modo compañero está mirando" : "el Modo compañero dejó de mirar")
    }
    /// Cambió la ruta en plena llamada (se conectaron o se quitaron unos audífonos): se vuelve a pedir lo elegido.
    func rutaCambio() { if enLlamada { aplicar(nil) } }

    // MARK: - Lo que elige Juan

    func elegirEntrada(_ p: Puerto?) {
        prefEntrada = p.map(AudioLlamadaReglas.guardar) ?? AudioLlamadaReglas.automatico
        UserDefaults.standard.set(prefEntrada, forKey: AudioLlamadaReglas.claveEntrada)
        aplicar("elegiste el micrófono")
    }
    func elegirSalida(bocina: Bool) {
        prefSalida = bocina ? AudioLlamadaReglas.esteDispositivo : AudioLlamadaReglas.automatico
        UserDefaults.standard.set(prefSalida, forKey: AudioLlamadaReglas.claveSalida)
        if !bocina, puseBocina { try? AVAudioSession.sharedInstance().overrideOutputAudioPort(.none); puseBocina = false }
        aplicar("elegiste la salida")
    }

    // MARK: - Aplicar

    private func aplicar(_ porque: String?) {
        let s = AVAudioSession.sharedInstance()
        let ultimo = UserDefaults.standard.object(forKey: AudioLlamadaReglas.claveCompanero) as? Double
        companero = AudioLlamadaReglas.companeroActivo(ahora: mirandoAhora, ultimoVisto: ultimo.map { Date(timeIntervalSince1970: $0) }, hoy: Date())
        let disponibles = s.availableInputs ?? []
        let quiero = AudioLlamadaReglas.entrada(preferencia: prefEntrada, companero: companero, disponibles: disponibles.map(puerto))
        var hecho: [String] = []
        if let q = quiero, let p = disponibles.first(where: { puerto($0) == q }) {
            // Solo si todavía no se pidió: pedirlo otra vez en cada cambio de ruta sería una vuelta sin fin.
            if s.preferredInput.map(puerto) != q || !puseEntrada {
                do { try s.setPreferredInput(p); puseEntrada = true; hecho.append("micrófono → " + (q.tipo == AudioLlamadaReglas.microfonoPropio ? "el del \(dispositivo)" : q.tipo)) }
                catch { hecho.append("no pude poner el micrófono (\((error as NSError).code))") }
            }
        } else if quiero == nil, puseEntrada {
            try? s.setPreferredInput(nil); puseEntrada = false; hecho.append("micrófono → lo elige iOS")
        }
        if AudioLlamadaReglas.bocinaFija(prefSalida), enLlamada {
            if s.currentRoute.outputs.first?.portType != .builtInSpeaker {
                do { try s.overrideOutputAudioPort(.speaker); puseBocina = true; hecho.append("salida → la bocina del \(dispositivo)") }
                catch { hecho.append("no pude pasar a la bocina (\((error as NSError).code))") }
            }
        }
        mirar()
        // El tipo (no el nombre: «AirPods de …» lleva un nombre y estos pasos van al Hub).
        if let porque, !hecho.isEmpty { VozNativa.shared.anotar("Audio de la llamada (" + porque + "): " + hecho.joined(separator: " · ")) }
    }

    private func puerto(_ d: AVAudioSessionPortDescription) -> Puerto { Puerto(tipo: d.portType.rawValue, nombre: d.portName) }

    /// Lo que se ve en la pantalla: los micrófonos que hay y por dónde va el audio ahora.
    func mirar() {
        let s = AVAudioSession.sharedInstance()
        let lista = (s.availableInputs ?? []).map(puerto)
        // El del teléfono primero; los demás, como los da iOS.
        entradas = lista.filter { $0.tipo == AudioLlamadaReglas.microfonoPropio } + lista.filter { $0.tipo != AudioLlamadaReglas.microfonoPropio }
        entradaAhora = s.currentRoute.inputs.first.map(puerto)
        let o = s.currentRoute.outputs.first
        salidaTipo = o?.portType.rawValue ?? ""
        salidaAhora = o.map { $0.portType == .builtInSpeaker ? "Bocina del \(dispositivo)" : $0.portType == .builtInReceiver ? "Auricular del \(dispositivo)" : $0.portName } ?? ""
    }

    // MARK: - Para la pantalla

    func nombre(_ p: Puerto) -> String { p.tipo == AudioLlamadaReglas.microfonoPropio ? "Este \(dispositivo)" : p.nombre }
    func clase(_ p: Puerto) -> AudioLlamadaReglas.Clase { AudioLlamadaReglas.clase(p, lentes: LentesDatos.sonLentes(p.nombre)) }
    func icono(_ c: AudioLlamadaReglas.Clase) -> String {
        switch c {
        case .dispositivo: return dispositivo == "iPad" ? "ipad" : "iphone"
        case .audifonos: return "headphones"
        case .lentes: return "eyeglasses"
        case .bocina: return "hifispeaker"
        case .carro: return "car"
        case .cable: return "cable.connector"
        case .otro: return "waveform"
        }
    }
    /// El ícono del botón de la llamada: por dónde sale el audio ahora.
    var iconoAhora: String {
        let s = AVAudioSession.sharedInstance()
        guard let o = s.currentRoute.outputs.first else { return "speaker.wave.2" }
        let c = clase(Puerto(tipo: o.portType.rawValue, nombre: o.portName))
        return c == .dispositivo ? "speaker.wave.2" : icono(c)
    }
}

/// La hoja «Audio de la llamada»: micrófono (entrada) y salida.
struct AudioLlamadaVista: View {
    @ObservedObject private var a = AudioLlamada.shared
    @Environment(\.dismiss) private var cerrar

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Etiqueta("Alma · Llamada")
                    Spacer()
                    Button { cerrar() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .medium)).frame(width: 40, height: 40)
                            .background(Circle().fill(Tinta.tinta.opacity(0.06)))
                    }.accessibilityLabel("Cerrar")
                }.padding(.top, 14)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Audio de")
                    Text("la llamada").italic()
                }.font(Tipo.serif(40)).lineSpacing(-4).accessibilityAddTraits(.isHeader)
                Text("Elige por dónde te oye Alma y por dónde la oyes tú. Se recuerda para las próximas llamadas.")
                    .font(Tipo.sans(13)).foregroundStyle(Tinta.suave).fixedSize(horizontal: false, vertical: true).padding(.bottom, 6)

                Etiqueta("Micrófono · te oye por aquí").padding(.top, 6)
                opcion("Automático", AudioLlamadaReglas.explicaAutomatico(companero: a.companero, dispositivo: a.dispositivo),
                       icono: "sparkles", elegida: AudioLlamadaReglas.elegida(nil, preferencia: a.prefEntrada), enUso: false) { a.elegirEntrada(nil) }
                ForEach(Array(a.entradas.enumerated()), id: \.offset) { _, p in
                    opcion(a.nombre(p), p == a.entradaAhora ? "En uso ahora" : nil, icono: a.icono(a.clase(p)),
                           elegida: AudioLlamadaReglas.elegida(p, preferencia: a.prefEntrada), enUso: p == a.entradaAhora) { a.elegirEntrada(p) }
                }

                Etiqueta("Salida · oyes a Alma por aquí").padding(.top, 12)
                opcion("Automático", a.salidaAhora.isEmpty ? "Lo que elija iOS" : "Ahora: " + a.salidaAhora, icono: "sparkles",
                       elegida: !AudioLlamadaReglas.bocinaFija(a.prefSalida), enUso: false) { a.elegirSalida(bocina: false) }
                opcion("Bocina de este \(a.dispositivo)", a.salidaTipo == AudioLlamadaReglas.bocinaPropia ? "En uso ahora" : nil, icono: "speaker.wave.2",
                       elegida: AudioLlamadaReglas.bocinaFija(a.prefSalida), enUso: a.salidaTipo == AudioLlamadaReglas.bocinaPropia) { a.elegirSalida(bocina: true) }
                Fila("Audífonos, lentes o bocinas", "Abre la lista de iOS (Bluetooth y AirPlay)") {
                    ElegirSalidaLlamada { a.elegirSalida(bocina: false) }.frame(width: 40, height: 40)
                }

                Text("El micrófono y el sonido van en el dispositivo donde está la llamada; el Modo compañero la muestra y repite la voz de Alma (una sola llamada). Para hablar por el iPad, llama desde el iPad.")
                    .font(Tipo.sans(11.5)).foregroundStyle(Tinta.suave).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            }
            .padding(.horizontal, 22).padding(.bottom, 30)
        }
        .foregroundStyle(Tinta.tinta)
        .background(FondoAtardecer())
        .onAppear { a.mirar() }
    }

    private func opcion(_ t: String, _ sub: String?, icono: String, elegida: Bool, enUso: Bool, _ accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            HStack(spacing: 12) {
                Image(systemName: icono).font(.system(size: 17)).frame(width: 26).foregroundStyle(enUso ? Tinta.peach : Tinta.tinta)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t).font(Tipo.sans(14.5)).lineLimit(1)
                    if let sub { Text(sub).font(Tipo.sans(11.5)).foregroundStyle(Tinta.suave).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer()
                Image(systemName: elegida ? "checkmark.circle.fill" : "circle").font(.system(size: 20))
                    .foregroundStyle(elegida ? Tinta.peach : Tinta.suave.opacity(0.5))
            }
            .padding(.horizontal, 16).padding(.vertical, 14).frame(minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 18).fill(.white))
            .contentShape(Rectangle())
        }
        .buttonStyle(Presion())
        .accessibilityAddTraits(elegida ? .isSelected : [])
    }
}

/// El botón de iOS para elegir la salida (audífonos, lentes, bocinas Bluetooth, AirPlay). Al abrirlo, la salida vuelve a
/// «Automático»: lo que Juan elija ahí manda (la bocina fija lo taparía).
struct ElegirSalidaLlamada: UIViewRepresentable {
    let alAbrir: () -> Void
    func makeCoordinator() -> Delegado { Delegado(alAbrir) }
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView(); v.tintColor = UIColor(Tinta.tinta); v.activeTintColor = UIColor(Tinta.peach); v.prioritizesVideoDevices = false
        v.delegate = context.coordinator
        return v
    }
    func updateUIView(_ v: AVRoutePickerView, context: Context) {}
    final class Delegado: NSObject, AVRoutePickerViewDelegate {
        let alAbrir: () -> Void
        init(_ f: @escaping () -> Void) { alAbrir = f }
        func routePickerViewWillBeginPresentingRoutes(_ v: AVRoutePickerView) { alAbrir() }
    }
}
