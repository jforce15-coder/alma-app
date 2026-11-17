import AVFoundation
import PhotosUI
import SwiftUI

/// Wearables (Juan, 17-nov-2026; antes «Dispositivos»): «una sección solo para dispositivos: ahí va a estar todo lo del
/// anillo, de lentes o auriculares o lo que sea; ahí se va a ver y ahí se va a configurar […] muy aesthetic, muy
/// minimalista, muy moderna». La lógica pura vive en WearablesReglas.swift.
/// · Se abre desde Ajustes → Wearables (Puente: accion "dispositivos", con `id` para abrir uno), o cuando Alma usa
///   anillo_estado con mostrar. A pantalla completa: en el iPhone, NavigationStack (las tarjetas y, al tocar una, su
///   detalle); en el iPad, NavigationSplitView (la lista a la izquierda y el detalle a la derecha).
/// · Claro y oscuro (WColor), Dynamic Type (WTipo) y con «reducir movimiento» el anillo de la batería no se anima.
/// · Sin roca: es una pantalla de ajustes (una roca por pantalla, y aquí no hace falta).
/// · Las fotos son un dibujo propio; Juan toca la foto en el detalle para poner la suya (se guarda solo en el teléfono).
/// · Nada se inventa: la batería de lentes y audífonos dice «no disponible» porque iOS no la da a las apps (Lentes.swift).
struct WearablesVista: View {
    var inicial: String? = nil
    @Environment(\.horizontalSizeClass) private var ancho
    @Environment(\.dismiss) private var cerrar
    @ObservedObject private var anillo = AnilloAlma.shared
    @ObservedObject private var lentes = Lentes.shared
    @ObservedObject private var m = WearablesModelo.shared
    @State private var sel: String?
    @State private var ruta: [String] = []

    var body: some View {
        Group {
            if ancho == .regular {
                NavigationSplitView {
                    lista(dividida: true)
                        .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 440)
                } detail: {
                    NavigationStack { detalle(sel ?? "anillo") }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationStack(path: $ruta) {
                    lista(dividida: false)
                        .navigationDestination(for: String.self) { detalle($0) }
                }
            }
        }
        .tint(WColor.accion)
        .onAppear {
            lentes.buscarBLE(); anillo.sincronizar(); m.mirar()
            let i = (inicial ?? "").isEmpty ? nil : inicial
            if ancho == .regular { sel = i ?? "anillo" } else if let i { ruta = [i] }
        }
    }

    // MARK: Lista

    private func lista(dividida: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Wearables").font(WTipo.serif(44)).accessibilityAddTraits(.isHeader).padding(.top, 4)
                Text("Lo que llevas puesto y Alma ve: su batería, si está conectado y sus ajustes.")
                    .font(WTipo.sans(13.5)).foregroundStyle(WColor.suave).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2).padding(.bottom, 20)
                LazyVGrid(columns: dividida ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(m.lista, id: \.id) { w in tarjeta(w, dividida: dividida) }
                    agregar(dividida: dividida)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 32)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .foregroundStyle(WColor.tinta)
        .background(WColor.fondo.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Listo") { cerrar() }.font(WTipo.sans(16, .semibold)) }
        }
    }

    @ViewBuilder private func tarjeta(_ w: WearablesReglas.Wearable, dividida: Bool) -> some View {
        if dividida {
            Button { sel = w.id } label: { TarjetaWearable(w: w, elegida: sel == w.id, fila: true) }.buttonStyle(Presion())
        } else {
            NavigationLink(value: w.id) { TarjetaWearable(w: w) }.buttonStyle(Presion())
        }
    }

    @ViewBuilder private func agregar(dividida: Bool) -> some View {
        let t = AgregarTarjeta(fila: dividida, elegida: dividida && sel == "agregar")
        if dividida { Button { sel = "agregar" } label: { t }.buttonStyle(Presion()) }
        else { NavigationLink(value: "agregar") { t }.buttonStyle(Presion()) }
    }

    @ViewBuilder private func detalle(_ id: String) -> some View {
        switch id {
        case "anillo": AnilloDetalle()
        case "lentes": LentesDetalle()
        case "agregar": AgregarWearable()
        default: AudioDetalle(id: id)
        }
    }
}

// MARK: - Modelo

/// Los wearables que ve la app: el anillo, los lentes y los audífonos que Juan agregó (por nombre, solo en este iPhone).
final class WearablesModelo: ObservableObject {
    static let shared = WearablesModelo()
    static let clave = "wearables_audio"
    @Published private(set) var guardados: [String] = UserDefaults.standard.stringArray(forKey: WearablesModelo.clave) ?? []
    @Published private(set) var vistos: [String] = []   // los Bluetooth que el iPhone ve ahora (salida o micrófono)
    @Published private(set) var salida = ""             // la salida Bluetooth de ahora

    private init() {
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.mirar() }
        mirar()
    }

    func mirar() {
        let s = AVAudioSession.sharedInstance()
        let sal = s.currentRoute.outputs.filter { WearablesReglas.esBluetooth($0.portType.rawValue) }.map { $0.portName }
        let ent = (s.availableInputs ?? []).filter { WearablesReglas.esBluetooth($0.portType.rawValue) }.map { $0.portName }
        salida = sal.first ?? ""
        vistos = sal + ent
    }

    var paraAgregar: [String] { WearablesReglas.paraAgregar(vistos: vistos, guardados: guardados, sonLentes: { LentesDatos.sonLentes($0) }) }
    func agregar(_ nombre: String) { guardados = WearablesReglas.agregar(nombre, a: guardados); UserDefaults.standard.set(guardados, forKey: Self.clave) }
    func quitar(_ id: String) { guardados = WearablesReglas.quitar(id: id, de: guardados); UserDefaults.standard.set(guardados, forKey: Self.clave) }

    static var nombreAnillo: String { UserDefaults.standard.string(forKey: "anillo_nombre").flatMap { $0.isEmpty ? nil : $0 } ?? "Anillo QRing" }
    static var estadoAnillo: String {
        let a = AnilloAlma.shared
        if !Anillo.hayGuardado { return "Sin conectar a Alma" }
        if a.conectado { return "Conectado" }
        return "No conectado" + (AnilloDatos.hace(AnilloDatos.ultimoDato(a.memoria), ahora: Date().timeIntervalSince1970).map { " · visto \($0)" } ?? "")
    }
    static var estadoLentes: String {
        let l = Lentes.shared
        return l.sonSalida ? "El audio sale por aquí" : l.conectados ? "Conectados" : "Sin conectar"
    }

    /// Todos, con lo que se sabe de cada uno (la pantalla y Ajustes, en el estado de la voz: VozNativa.resumen).
    var lista: [WearablesReglas.Wearable] {
        let a = AnilloAlma.shared, l = Lentes.shared
        var r = [WearablesReglas.Wearable(id: "anillo", tipo: .anillo, nombre: Self.nombreAnillo, corto: "Anillo", conectado: a.conectado,
                                          bateria: a.memoria.bateria?.v, cargando: a.memoria.cargando == true, estado: Self.estadoAnillo),
                 WearablesReglas.Wearable(id: "lentes", tipo: .lentes, nombre: l.nombre.isEmpty ? "Lentes AURA" : l.nombre, corto: "Lentes",
                                          conectado: l.conectados, bateria: l.bateria, estado: Self.estadoLentes)]
        for n in guardados {
            let en = vistos.contains(n)
            r.append(WearablesReglas.Wearable(id: WearablesReglas.idAudio(n), tipo: .audio, nombre: n, corto: n, conectado: en, bateria: nil,
                                              estado: WearablesReglas.estadoAudio(salida: salida == n, conectado: en)))
        }
        return r
    }
}

// MARK: - Colores y letra (claro y oscuro, Dynamic Type)

enum WColor {
    static func din(_ claro: UInt32, _ oscuro: UInt32, _ a: CGFloat = 1) -> Color {
        Color(UIColor { t in
            let h = t.userInterfaceStyle == .dark ? oscuro : claro
            return UIColor(red: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255, blue: CGFloat(h & 0xFF) / 255, alpha: a)
        })
    }
    static let fondo = din(0xF2EFEC, 0x121111)
    static let tarjeta = din(0xFFFFFF, 0x1F1D1C)
    static let tinta = din(0x2F3030, 0xF3EEE9)
    static let suave = din(0x857F7A, 0x9E9690)
    static let linea = din(0x3E3F3F, 0xFFFFFF, 0.13)
    static let pista = din(0xEDE8E3, 0x2E2B2A)
    static let accion = din(0xC25F45, 0xF0957D)
    static let verde = Color(hex: 0x7FA88A)
    static let rojo = Color(hex: 0xD9583A)
}

enum WTipo {
    static func serif(_ t: CGFloat, _ w: Font.Weight = .regular) -> Font { .custom("Cormorant Garamond", size: t, relativeTo: .largeTitle).weight(w) }
    static func sans(_ t: CGFloat, _ w: Font.Weight = .regular) -> Font { .custom("Montserrat", size: t, relativeTo: .body).weight(w) }
}

// MARK: - Piezas

/// Una tarjeta: el anillo de la batería con su dibujo, el nombre, la batería y el estado. En el iPad, una fila.
struct TarjetaWearable: View {
    let w: WearablesReglas.Wearable
    var elegida = false
    var fila = false

    var body: some View {
        Group {
            if fila {
                HStack(spacing: 14) {
                    AroBateria(nivel: w.bateria, tipo: w.tipo, lado: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(w.nombre).font(WTipo.sans(15, .semibold)).lineLimit(1)
                        estado
                    }
                    Spacer(minLength: 6)
                    if let b = w.bateria { Text("\(b) %").font(WTipo.serif(24, .medium)).monospacedDigit() }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    AroBateria(nivel: w.bateria, tipo: w.tipo, lado: 66)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(w.nombre).font(WTipo.sans(14.5, .semibold)).lineLimit(1)
                        if let b = w.bateria {
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text("\(b)").font(WTipo.serif(36, .medium)).monospacedDigit()
                                Text("%").font(WTipo.serif(18))
                                if w.cargando { Image(systemName: "bolt.fill").font(.system(size: 11)).foregroundStyle(Tinta.peach) }
                            }
                        } else {
                            Text("Batería no disponible").font(WTipo.sans(12.5)).foregroundStyle(WColor.suave).padding(.vertical, 8)
                        }
                    }
                    Spacer(minLength: 0)
                    estado
                }
                .frame(maxWidth: .infinity, minHeight: 186, alignment: .topLeading)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(elegida ? Tinta.peach.opacity(0.16) : WColor.tarjeta))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .foregroundStyle(WColor.tinta)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(w.nombre), \(WearablesReglas.bateria(w.bateria, cargando: w.cargando)), \(w.estado)")
        .accessibilityHint("Abre sus ajustes")
        .accessibilityAddTraits(elegida ? .isSelected : [])
    }

    private var estado: some View {
        HStack(spacing: 6) {
            Circle().fill(w.conectado ? WColor.verde : WColor.suave.opacity(0.5)).frame(width: 7, height: 7)
            Text(w.estado).font(WTipo.sans(12)).foregroundStyle(WColor.suave).lineLimit(1)
        }
    }
}

/// «Agregar»: la tarjeta punteada para sumar audífonos u otro wearable.
struct AgregarTarjeta: View {
    var fila = false
    var elegida = false
    var body: some View {
        Group {
            if fila {
                HStack(spacing: 14) {
                    Image(systemName: "plus").font(.system(size: 18, weight: .light)).frame(width: 52, height: 52)
                        .background(Circle().strokeBorder(WColor.linea, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])))
                    Text("Agregar un wearable").font(WTipo.sans(15, .medium))
                    Spacer()
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 26, weight: .light))
                    Text("Agregar").font(WTipo.sans(14, .medium))
                }
                .frame(maxWidth: .infinity, minHeight: 186)
            }
        }
        .padding(16)
        .foregroundStyle(WColor.suave)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(elegida ? Tinta.peach.opacity(0.16) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(WColor.linea, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5])))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Agregar un wearable")
    }
}

/// La batería en un anillo (como el widget de Baterías), con el dibujo del wearable adentro. Se llena al aparecer.
struct AroBateria: View {
    let nivel: Int?
    let tipo: WearablesReglas.Tipo
    let lado: CGFloat
    @State private var lleno = false
    @Environment(\.accessibilityReduceMotion) private var quieto

    var body: some View {
        ZStack {
            Circle().stroke(WColor.pista, lineWidth: lado * 0.08)
            if let n = nivel {
                Circle().trim(from: 0, to: lleno ? CGFloat(max(0, min(100, n))) / 100 : 0)
                    .stroke(WearablesReglas.bajo(n) ? WColor.rojo : WColor.verde, style: StrokeStyle(lineWidth: lado * 0.08, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            dibujo.frame(width: lado * 0.5, height: lado * 0.5)
        }
        .frame(width: lado, height: lado)
        .onAppear {
            if quieto { lleno = true } else { withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.9)) { lleno = true } }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private var dibujo: some View {
        switch tipo {
        case .anillo: DibujoAnillo()
        case .lentes: Image(systemName: "eyeglasses").resizable().scaledToFit().fontWeight(.light).foregroundStyle(WColor.tinta)
        case .audio: Image(systemName: "headphones").resizable().scaledToFit().fontWeight(.light).foregroundStyle(WColor.tinta)
        }
    }
}

/// Un grupo de filas, como en Ajustes de iOS: título arriba, las filas en una tarjeta y una nota abajo.
struct WGrupo<C: View>: View {
    var titulo: String? = nil
    var pie: String? = nil
    @ViewBuilder let contenido: () -> C
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let titulo { Text(titulo.uppercased()).tracking(1.4).font(WTipo.sans(11, .semibold)).foregroundStyle(WColor.suave).padding(.horizontal, 16) }
            VStack(spacing: 0) { contenido() }
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(WColor.tarjeta))
            if let pie { Text(pie).font(WTipo.sans(12)).foregroundStyle(WColor.suave).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 16) }
        }
        .padding(.top, 18)
    }
}

/// Una fila: ícono de color, título, subtítulo corto y lo de la derecha (un interruptor, un valor, una flecha).
struct WFila<D: View>: View {
    var ico: String? = nil
    var color: Color = Color(hex: 0x8E8A86)
    let t: String
    var sub: String? = nil
    @ViewBuilder let d: () -> D
    var body: some View {
        HStack(spacing: 12) {
            if let ico {
                Image(systemName: ico).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(t).font(WTipo.sans(15))
                if let sub, !sub.isEmpty { Text(sub).font(WTipo.sans(12)).foregroundStyle(WColor.suave).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            d()
        }
        .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}
extension WFila where D == EmptyView {
    init(ico: String? = nil, color: Color = Color(hex: 0x8E8A86), t: String, sub: String? = nil) {
        self.ico = ico; self.color = color; self.t = t; self.sub = sub; self.d = { EmptyView() }
    }
}

struct WLinea: View {
    var sangria: CGFloat = 56
    var body: some View { Rectangle().fill(WColor.linea).frame(height: 0.5).padding(.leading, sangria) }
}

/// Una fila que es un botón (acción): texto en el color de acción, con su ícono.
struct WAccion: View {
    let ico: String
    var color: Color = Tinta.peach
    let t: String
    var valor: String? = nil
    let accion: () -> Void
    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(); accion()
        } label: {
            WFila(ico: ico, color: color, t: t) {
                if let valor { Text(valor).font(WTipo.sans(13)).foregroundStyle(WColor.suave) }
            }
        }
        .buttonStyle(FilaPresion())
    }
}

/// Al tocar una fila: se oscurece un poco al instante (como en iOS).
struct FilaPresion: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label.background(WColor.linea.opacity(c.isPressed ? 0.6 : 0))
    }
}

/// El firmware del anillo: el que guardó la memoria o el que leyó Anillo.swift (sin despertar el Bluetooth).
func firmwareAnillo(_ m: AnilloDatos.Memoria) -> String? {
    let f = m.firmware ?? UserDefaults.standard.string(forKey: "anillo_firmware") ?? ""
    return f.isEmpty ? nil : f
}

/// El fondo: papel con un velo de atardecer arriba (los colores de la roca). Lo usan otras pantallas (Tarjetas, Audio).
struct FondoAtardecer: View {
    var body: some View {
        ZStack(alignment: .top) {
            Tinta.papel
            LinearGradient(colors: [Color(hex: 0xE3A47F, opacity: 0.32), Color(hex: 0xB8B6C8, opacity: 0.18), Tinta.papel.opacity(0)],
                           startPoint: .top, endPoint: .bottom).frame(height: 420)
        }.ignoresSafeArea()
    }
}

/// La foto del dispositivo: la de Juan si la puso, si no el dibujo sobre una piedra de alabastro.
struct FotoDispositivo<Dibujo: View>: View {
    let id: String, lado: CGFloat
    @ViewBuilder let dibujo: () -> Dibujo
    @State private var foto: UIImage?
    init(id: String, lado: CGFloat, @ViewBuilder dibujo: @escaping () -> Dibujo) { self.id = id; self.lado = lado; self.dibujo = dibujo }
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: RocaAlma.alabastro, startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 1))
                .shadow(color: Color(hex: 0xA98C93, opacity: 0.25), radius: 14, y: 8)
            if let f = foto { Image(uiImage: f).resizable().scaledToFill().clipShape(Circle()) } else { dibujo().padding(lado * 0.2) }
        }
        .frame(width: lado, height: lado)
        .onAppear { foto = FotosDispositivo.leer(id) }
        .onReceive(NotificationCenter.default.publisher(for: FotosDispositivo.cambio)) { _ in foto = FotosDispositivo.leer(id) }
        .accessibilityHidden(true)
    }
}

/// Las fotos que pone Juan: en la carpeta de la app, nunca en el Hub ni en GitHub.
enum FotosDispositivo {
    static let cambio = Notification.Name("alma.dispositivos.foto")
    static func url(_ id: String) -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("dispositivo_\(id).jpg")
    }
    static func leer(_ id: String) -> UIImage? { url(id).flatMap { UIImage(contentsOfFile: $0.path) } }
    static func guardar(_ id: String, _ img: UIImage) {
        let lado: CGFloat = 600, e = lado / max(img.size.width, img.size.height, 1)
        let tam = CGSize(width: img.size.width * min(1, e), height: img.size.height * min(1, e))
        let chica = UIGraphicsImageRenderer(size: tam).image { _ in img.draw(in: CGRect(origin: .zero, size: tam)) }
        if let u = url(id), let d = chica.jpegData(compressionQuality: 0.85) { try? d.write(to: u, options: .atomic) }
        NotificationCenter.default.post(name: cambio, object: nil)
    }
    static func quitar(_ id: String) {
        if let u = url(id) { try? FileManager.default.removeItem(at: u) }
        NotificationCenter.default.post(name: cambio, object: nil)
    }
}

/// El anillo dibujado: un aro con el atardecer de Alma.
struct DibujoAnillo: View {
    var body: some View {
        ZStack {
            Ellipse().strokeBorder(LinearGradient(colors: [Color(hex: 0x2F3030), Color(hex: 0x6F6867), Color(hex: 0x2F3030)], startPoint: .leading, endPoint: .trailing), lineWidth: 9)
            Ellipse().strokeBorder(LinearGradient(colors: RocaAlma.atardecer, startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2.5).padding(3)
        }
        .aspectRatio(1.15, contentMode: .fit)
        .rotation3DEffect(.degrees(58), axis: (x: 1, y: 0.15, z: 0))
    }
}

/// Los lentes dibujados (SF Symbols) en tinta, con el brillo del atardecer.
struct DibujoLentes: View {
    var body: some View {
        Image(systemName: "eyeglasses").resizable().scaledToFit()
            .foregroundStyle(LinearGradient(colors: [Tinta.tinta, Color(hex: 0x8FA5C8)], startPoint: .top, endPoint: .bottom))
            .fontWeight(.light)
    }
}

/// El encabezado de un detalle: la foto grande (tocarla deja poner la de Juan), nombre, estado y la batería en su anillo.
struct CabezaDetalle<Dibujo: View>: View {
    let id: String, titulo: String, estado: String, conectado: Bool, bateria: Int?, cargando: Bool
    @ViewBuilder let dibujo: () -> Dibujo
    @State private var elegida: PhotosPickerItem?
    @State private var hayFoto = false
    init(id: String, titulo: String, estado: String, conectado: Bool, bateria: Int?, cargando: Bool = false, @ViewBuilder _ dibujo: @escaping () -> Dibujo) {
        self.id = id; self.titulo = titulo; self.estado = estado; self.conectado = conectado; self.bateria = bateria; self.cargando = cargando; self.dibujo = dibujo
    }
    var body: some View {
        VStack(spacing: 8) {
            PhotosPicker(selection: $elegida, matching: .images) { FotoDispositivo(id: id, lado: 168, dibujo: dibujo) }
                .accessibilityLabel(hayFoto ? "Cambiar la foto" : "Poner tu foto")
            if hayFoto { Button("Quitar mi foto") { FotosDispositivo.quitar(id); hayFoto = false }.font(WTipo.sans(11.5, .medium)) }
            Text(titulo).font(WTipo.serif(34)).multilineTextAlignment(.center).padding(.top, 6)
            HStack(spacing: 6) {
                Circle().fill(conectado ? WColor.verde : WColor.suave.opacity(0.5)).frame(width: 7, height: 7)
                Text(estado).font(WTipo.sans(12.5)).foregroundStyle(WColor.suave)
            }
            Text(WearablesReglas.bateria(bateria, cargando: cargando)).font(bateria == nil ? WTipo.sans(13) : WTipo.serif(28, .medium))
                .foregroundStyle(bateria == nil ? WColor.suave : (WearablesReglas.bajo(bateria) ? WColor.rojo : WColor.tinta))
        }
        .frame(maxWidth: .infinity).padding(.top, 10)
        .onAppear { hayFoto = FotosDispositivo.leer(id) != nil }
        .onChange(of: elegida) { _, it in
            guard let it else { return }
            Task {
                if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                    await MainActor.run { FotosDispositivo.guardar(id, img); hayFoto = true }
                }
            }
        }
    }
}

/// El marco de cada detalle: el fondo, el ancho máximo y el título chico en la barra.
struct DetalleMarco<C: View>: View {
    let titulo: String
    @ViewBuilder let contenido: () -> C
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { contenido() }
                .padding(.horizontal, 20).padding(.bottom, 36)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .foregroundStyle(WColor.tinta)
        .background(WColor.fondo.ignoresSafeArea())
        .navigationTitle(titulo)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Detalle del anillo

struct AnilloDetalle: View {
    @ObservedObject private var a = AnilloAlma.shared
    @State private var modoAnillo = UserDefaults.standard.bool(forKey: "voz_modo_anillo")
    @State private var monitoreo = true
    @State private var cada = 30
    private let opciones = [5, 10, 15, 30, 60]

    var body: some View {
        DetalleMarco(titulo: "Anillo") {
            CabezaDetalle(id: "anillo", titulo: WearablesModelo.nombreAnillo, estado: WearablesModelo.estadoAnillo, conectado: a.conectado,
                          bateria: a.memoria.bateria?.v, cargando: a.memoria.cargando == true) { DibujoAnillo() }
            if !a.aviso.isEmpty {
                Text(a.aviso).font(WTipo.sans(13.5, .medium)).frame(maxWidth: .infinity).padding(14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Tinta.peach.opacity(0.16))).padding(.top, 16)
                    .transition(.opacity)
            }
            if !Anillo.hayGuardado {
                WGrupo(pie: "Conéctalo desde Health (en el inicio) → Anillo. Después aparece aquí con su batería y sus ajustes.") {
                    WFila(ico: "link", color: Tinta.peach, t: "Tu anillo aún no está conectado a Alma")
                }
            }

            WGrupo(titulo: "Alma con el anillo", pie: "Dos toques encienden o apagan el modo conferencia, aunque el teléfono esté bloqueado. El anillo va en modo Music.") {
                WFila(ico: "hand.tap.fill", color: Tinta.peach, t: "Modo anillo") {
                    Toggle("Modo anillo", isOn: $modoAnillo).labelsHidden().tint(Tinta.peach)
                }
            }
            .onChange(of: modoAnillo) { _, on in VozNativa.shared.ponerModoAnillo(on) }

            WGrupo(titulo: "Acciones", pie: a.conectado ? nil : "Se activan cuando el anillo está conectado.") {
                WAccion(ico: "dot.radiowaves.left.and.right", color: Color(hex: 0x7F98C2), t: "Buscar mi anillo", valor: nil) { a.buscar() }
                WLinea()
                WAccion(ico: "heart.fill", color: WColor.rojo, t: "Medir el ritmo", valor: a.midiendo == .ritmo ? "Midiendo…" : nil) {
                    if a.midiendo == nil { a.medir(.ritmo) { _, _ in } }
                }
                WLinea()
                WAccion(ico: "drop.fill", color: Color(hex: 0x5F7BA8), t: "Medir el oxígeno", valor: a.midiendo == .oxigeno ? "Midiendo…" : nil) {
                    if a.midiendo == nil { a.medir(.oxigeno) { _, _ in } }
                }
            }
            .disabled(!a.conectado).opacity(a.conectado ? 1 : 0.55)

            WGrupo(titulo: "Monitoreo del ritmo") {
                WFila(ico: "waveform.path.ecg", color: WColor.verde, t: "Medir solo", sub: "El anillo mide tu ritmo durante el día") {
                    Toggle("Medir solo", isOn: $monitoreo).labelsHidden().tint(Tinta.peach)
                }
                WLinea()
                WFila(ico: "clock", color: Color(hex: 0x8E8A86), t: "Cada") {
                    Picker("Cada", selection: $cada) { ForEach(opciones, id: \.self) { Text("\($0) min").tag($0) } }.tint(WColor.suave)
                }
                .disabled(!monitoreo).opacity(monitoreo ? 1 : 0.55)
            }
            .onChange(of: monitoreo) { _, on in if on != (a.memoria.ritmoActivo ?? true) { a.ajustar(activo: on, minutos: cada) } }
            .onChange(of: cada) { _, mm in if mm != a.memoria.ritmoMinutos { a.ajustar(activo: monitoreo, minutos: mm) } }

            WGrupo(titulo: "Hoy") {
                dato("figure.walk", WColor.verde, "Pasos", a.memoria.pasos.map { Formato.miles(Double($0.v)) + (a.memoria.kcal.map { " · \($0.v) kcal" } ?? "") + (a.memoria.metros.map { String(format: " · %.1f km", Double($0.v) / 1000) } ?? "") }, a.memoria.pasos?.t)
                WLinea()
                dato("heart.text.square", WColor.rojo, "Ritmo del día", a.memoria.ritmoMin.map { "mín \($0) · máx \(a.memoria.ritmoMax ?? 0) · prom. \(a.memoria.ritmoProm ?? 0)" }, a.memoria.ritmoDiaT)
                WLinea()
                dato("heart", WColor.rojo, "Último ritmo", a.memoria.ritmo.map { "\($0.v) lpm" }, a.memoria.ritmo?.t)
                WLinea()
                dato("lungs", Color(hex: 0x5F7BA8), "Oxígeno", a.memoria.oxigeno.map { "\($0.v) %" }, a.memoria.oxigeno?.t)
            }

            WGrupo(titulo: "Información") {
                dato("cpu", Color(hex: 0x8E8A86), "Firmware", firmwareAnillo(a.memoria), nil)
                WLinea()
                dato("arrow.triangle.2.circlepath", Color(hex: 0x8E8A86), "Sincronizado", a.memoria.sync.map { _ in "" }, a.memoria.sync)
                WLinea()
                WAccion(ico: "arrow.clockwise", color: Tinta.peach, t: "Sincronizar ahora") { a.sincronizar() }
                    .disabled(!a.conectado).opacity(a.conectado ? 1 : 0.55)
                WLinea()
                NavigationLink { DiagnosticoAnilloVista() } label: {
                    WFila(ico: "stethoscope", color: Color(hex: 0x8E8A86), t: "Diagnóstico del anillo", sub: "Qué manda por Bluetooth al tocarlo") {
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(WColor.suave.opacity(0.7))
                    }
                }
                .buttonStyle(FilaPresion())
            }
        }
        .animation(.easeOut(duration: 0.2), value: a.aviso)
        .onAppear {
            monitoreo = a.memoria.ritmoActivo ?? true
            cada = a.memoria.ritmoMinutos.map { mm in opciones.min { abs($0 - mm) < abs($1 - mm) } ?? 30 } ?? 30
        }
    }

    private func dato(_ ico: String, _ color: Color, _ t: String, _ v: String?, _ cuando: Double?) -> some View {
        WFila(ico: ico, color: color, t: t, sub: cuando.flatMap { AnilloDatos.hace($0, ahora: Date().timeIntervalSince1970) }) {
            Text(v.flatMap { $0.isEmpty ? nil : $0 } ?? (cuando == nil ? "—" : "")).font(WTipo.sans(13.5, .medium)).multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Detalle de los lentes

struct LentesDetalle: View {
    @ObservedObject private var l = Lentes.shared
    var body: some View {
        DetalleMarco(titulo: "Lentes") {
            CabezaDetalle(id: "lentes", titulo: l.nombre.isEmpty ? "Lentes AURA" : l.nombre, estado: WearablesModelo.estadoLentes,
                          conectado: l.conectados, bateria: l.bateria) { DibujoLentes() }
            if l.bateria == nil {
                Text("iOS no comparte la batería de unos lentes de audio con las apps. La ves en el widget de Baterías del iPhone.")
                    .font(WTipo.sans(12.5)).foregroundStyle(WColor.suave).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity).padding(.top, 8)
            }
            WGrupo(titulo: "Audio", pie: "Las apps no pueden cambiar la salida Bluetooth solas: elígela aquí.") {
                WFila(ico: "speaker.wave.2.fill", color: Tinta.peach, t: "Salida de audio ahora", sub: l.salidaAhora.isEmpty ? "—" : l.salidaAhora) {
                    Image(systemName: l.sonSalida ? "checkmark.circle.fill" : "circle").foregroundStyle(l.sonSalida ? Tinta.peach : WColor.suave)
                }
                WLinea()
                WFila(ico: "airplayaudio", color: Color(hex: 0x7F98C2), t: "Usarlos para Alma", sub: "Elige los lentes como salida") { ElegirSalida().frame(width: 36, height: 36) }
            }
            WGrupo(titulo: "Según el fabricante") {
                WFila(ico: "music.note", color: Color(hex: 0x9C96C8), t: "Música", sub: LentesDatos.horasMusica(bateria: l.bateria))
                WLinea()
                WFila(ico: "phone.fill", color: WColor.verde, t: "Llamadas", sub: "3–4 h con la carga llena")
                WLinea()
                WFila(ico: "battery.100", color: Color(hex: 0x8E8A86), t: "Baterías", sub: "Dos de 110 mAh, una en cada patilla · carga magnética")
                WLinea()
                WFila(ico: "wave.3.right", color: Color(hex: 0x5F7BA8), t: "Bluetooth", sub: "6.0 · solo audio, sin cámara")
            }
            WGrupo(titulo: "Lo que ve Alma") {
                WFila(ico: "antenna.radiowaves.left.and.right", color: Color(hex: 0x8E8A86), t: "Bluetooth de baja energía",
                      sub: l.porBLE ? "Encontrados" + (l.bateria == nil ? " · sin servicio de batería" : " · con batería") : "No se anuncian: solo audio")
                WLinea()
                WAccion(ico: "magnifyingglass", color: Tinta.peach, t: "Buscar otra vez") { l.buscarBLE() }
            }
        }
        .onAppear { l.buscarBLE() }
    }
}

// MARK: - Detalle de unos audífonos agregados

struct AudioDetalle: View {
    let id: String
    @ObservedObject private var m = WearablesModelo.shared
    @Environment(\.dismiss) private var cerrar
    var body: some View {
        let w = m.lista.first { $0.id == id }
        DetalleMarco(titulo: w?.nombre ?? "Audífonos") {
            if let w {
                CabezaDetalle(id: id, titulo: w.nombre, estado: w.estado, conectado: w.conectado, bateria: nil) {
                    Image(systemName: "headphones").resizable().scaledToFit().fontWeight(.light).foregroundStyle(Tinta.tinta)
                }
                Text("iOS no comparte la batería de unos audífonos Bluetooth con las apps. La ves en el widget de Baterías del iPhone.")
                    .font(WTipo.sans(12.5)).foregroundStyle(WColor.suave).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity).padding(.top, 8)
                WGrupo(titulo: "Audio") {
                    WFila(ico: "speaker.wave.2.fill", color: Tinta.peach, t: "Salida de audio ahora", sub: m.salida.isEmpty ? "—" : m.salida) {
                        Image(systemName: m.salida == w.nombre ? "checkmark.circle.fill" : "circle").foregroundStyle(m.salida == w.nombre ? Tinta.peach : WColor.suave)
                    }
                    WLinea()
                    WFila(ico: "airplayaudio", color: Color(hex: 0x7F98C2), t: "Usarlos para Alma", sub: "Elige por dónde sale el audio") { ElegirSalida().frame(width: 36, height: 36) }
                }
                WGrupo {
                    Button(role: .destructive) { m.quitar(id); cerrar() } label: {
                        Text("Quitar de Wearables").font(WTipo.sans(15, .medium)).foregroundStyle(WColor.rojo).frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(FilaPresion())
                }
            } else {
                Text("Este wearable ya no está en la lista.").font(WTipo.sans(14)).foregroundStyle(WColor.suave).frame(maxWidth: .infinity).padding(.top, 40)
            }
        }
        .onAppear { m.mirar() }
    }
}

// MARK: - Agregar un wearable

struct AgregarWearable: View {
    @ObservedObject private var m = WearablesModelo.shared
    var body: some View {
        DetalleMarco(titulo: "Agregar") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Agregar un wearable").font(WTipo.serif(34))
                Text("Por ahora Alma ve tus audífonos y bocinas por su audio Bluetooth. Conéctalos al iPhone y aparecen aquí.")
                    .font(WTipo.sans(13.5)).foregroundStyle(WColor.suave).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 10)
            WGrupo(titulo: "Lo que tu iPhone ve ahora", pie: m.paraAgregar.isEmpty ? "No veo audífonos Bluetooth nuevos. Conéctalos en Ajustes de iOS → Bluetooth (o elige la salida abajo) y vuelve aquí." : nil) {
                if m.paraAgregar.isEmpty {
                    WFila(ico: "headphones", color: Color(hex: 0x8E8A86), t: "Nada nuevo por ahora")
                } else {
                    ForEach(Array(m.paraAgregar.enumerated()), id: \.element) { i, n in
                        if i > 0 { WLinea() }
                        WFila(ico: "headphones", color: Color(hex: 0x7F98C2), t: n, sub: "Bluetooth · audio") {
                            Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); withAnimation(.easeOut(duration: 0.2)) { m.agregar(n) } } label: {
                                Text("Agregar").font(WTipo.sans(13, .semibold)).foregroundStyle(.white).padding(.horizontal, 14).frame(minHeight: 34)
                                    .background(Capsule().fill(Tinta.peach))
                            }
                            .buttonStyle(Presion())
                            .accessibilityLabel("Agregar \(n)")
                        }
                    }
                }
            }
            WGrupo(titulo: "Conectar otro") {
                WFila(ico: "airplayaudio", color: Tinta.peach, t: "Elegir salida de audio", sub: "Los que ya emparejaste en el iPhone") { ElegirSalida().frame(width: 36, height: 36) }
                WLinea()
                WAccion(ico: "arrow.clockwise", color: Color(hex: 0x8E8A86), t: "Buscar otra vez") { m.mirar() }
            }
        }
        .onAppear { m.mirar() }
    }
}
