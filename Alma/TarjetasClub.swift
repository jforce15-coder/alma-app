import CoreImage
import CoreImage.CIFilterBuiltins
import Security
import SwiftUI
import UIKit
import Vision
import VisionKit

/// Tarjetas de clubes (Juan, 17-nov-2026): las tarjetas del supermercado y de cliente frecuente, guardadas en el perfil, y
/// Alma las pone en pantalla cuando se las pide por voz («Alma, enséñame mi tarjeta de La Torre»).
/// · Se guardan SOLO en este iPhone, en el llavero (no van al Hub ni a ninguna hoja): así funcionan sin internet en la caja
///   y nadie más las ve. Se abren desde Ajustes → «Tarjetas de clubes» (Puente: accion "tarjetas").
/// · Se agregan escaneando el código con la cámara (VisionKit) o tecleando el número.
/// · Alma las pide con la herramienta de cliente mostrar_tarjeta_club (Hub, voz.js): la tarjeta sale en una ventana propia,
///   encima de todo (también de la llamada), en blanco y con el brillo al máximo; al cerrarla, el brillo vuelve.
/// · La lógica pura (códigos de barras, encontrar la que pidió, qué se le contesta a Alma) está en TarjetasClubReglas.swift.
/// · Ajuste (Juan, 17-nov-2026): también boletos de avión, tren, conciertos y eventos, con su fecha y un detalle (asiento,
///   puerta, sección). Se escanean igual (el PDF417 o Aztec del pase de abordar, el QR de la entrada) y Alma los enseña igual.
///   Un día después de su fecha dejan de ofrecerse por voz; se borran a mano.
final class TarjetasClub: ObservableObject {
    static let shared = TarjetasClub()
    @Published private(set) var tarjetas: [TarjetaClub] = []
    /// La que pidió con el teléfono bloqueado: sale al abrir la app (si fue hace menos de 3 min).
    private var pendiente: (id: String, desde: Date)?

    private static let servicio = "com.spacioam.alma.tarjetas", cuenta = "tarjetas"

    init() {
        tarjetas = Self.leer()
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, let p = self.pendiente else { return }
            self.pendiente = nil
            if Date().timeIntervalSince(p.desde) < 180 { VentanaTarjeta.shared.mostrar(p.id) }
        }
    }

    // MARK: Guardar

    func guardar(_ t: TarjetaClub) {
        if let i = tarjetas.firstIndex(where: { $0.id == t.id }) { tarjetas[i] = t } else { tarjetas.append(t) }
        escribir()
    }
    func borrar(_ id: String) { tarjetas.removeAll { $0.id == id }; escribir() }
    func mover(_ desde: IndexSet, _ a: Int) { tarjetas.move(fromOffsets: desde, toOffset: a); escribir() }

    private func escribir() {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.servicio, kSecAttrAccount as String: Self.cuenta]
        SecItemDelete(base as CFDictionary)
        guard !tarjetas.isEmpty, let d = try? JSONEncoder().encode(tarjetas) else { return }
        var q = base; q[kSecValueData as String] = d; q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
    private static func leer() -> [TarjetaClub] {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servicio, kSecAttrAccount as String: cuenta,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var r: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess, let d = r as? Data else { return [] }
        return (try? JSONDecoder().decode([TarjetaClub].self, from: d)) ?? []
    }

    // MARK: Por voz

    /// mostrar_tarjeta_club: busca la que pidió, la pone en pantalla (o la deja para cuando abra la app) y devuelve lo que
    /// Alma tiene que decir. Siempre contesta enseguida.
    func porVoz(_ pedido: String) -> (texto: String, error: Bool) {
        let activa = UIApplication.shared.applicationState == .active
        let r = ReglasTarjetas.respuesta(pedido: pedido, tarjetas: tarjetas, pantalla: activa)
        if let t = r.mostrar {
            if r.pendiente { pendiente = (t.id, Date()) } else { VentanaTarjeta.shared.mostrar(t.id) }
        }
        return (r.texto, r.error)
    }
}

extension Notification.Name {
    /// Ajustes → «Tarjetas de clubes» (Puente: accion "tarjetas").
    static let abrirTarjetasClub = Notification.Name("alma.tarjetas.abrir")
}

// MARK: - La tarjeta en pantalla (para la caja)

/// Una ventana propia por encima de todo: así sale aunque esté abierta la llamada, el chat o Ajustes, sin pelear con las
/// pantallas de SwiftUI. Mientras se ve: brillo al máximo y la pantalla no se apaga; al cerrar, todo vuelve como estaba.
final class VentanaTarjeta {
    static let shared = VentanaTarjeta()
    private var ventana: UIWindow?
    private var brilloAntes: CGFloat?

    func mostrar(_ id: String) {
        DispatchQueue.main.async { self.abrir(id) }
    }

    private func abrir(_ id: String) {
        guard let escena = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let v = ventana ?? UIWindow(windowScene: escena)
        v.windowLevel = .alert + 2
        let raiz = UIHostingController(rootView: TarjetaEnCaja(inicial: id) { [weak self] in self?.cerrar() })
        raiz.view.backgroundColor = .white
        v.rootViewController = raiz
        v.isHidden = false
        ventana = v
        if brilloAntes == nil { brilloAntes = escena.screen.brightness }
        escena.screen.brightness = 1
        UIApplication.shared.isIdleTimerDisabled = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func cerrar() {
        guard let v = ventana else { return }
        if let b = brilloAntes { v.windowScene?.screen.brightness = b }
        brilloAntes = nil
        UIApplication.shared.isIdleTimerDisabled = false
        UIView.animate(withDuration: 0.25, animations: { v.alpha = 0 }) { _ in
            v.isHidden = true; v.alpha = 1; v.rootViewController = nil
        }
    }
}

/// La tarjeta grande, en blanco, para que la lea el lector de la caja. Si hay más, se pasan deslizando.
struct TarjetaEnCaja: View {
    let inicial: String
    let cerrar: () -> Void
    @ObservedObject private var club = TarjetasClub.shared
    @State private var elegida = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: cerrar) {
                    Text("Listo").font(Tipo.sans(15, .semibold)).padding(.horizontal, 18).frame(height: 40)
                        .background(Capsule().fill(Tinta.tinta.opacity(0.07)))
                }.accessibilityLabel("Cerrar la tarjeta")
            }.padding(.horizontal, 20).padding(.top, 10)
            TabView(selection: $elegida) {
                ForEach(club.tarjetas) { t in
                    VStack(spacing: 18) {
                        Spacer(minLength: 0)
                        if t.tipo.boleto { Text(t.tipo.nombre).font(Tipo.sans(11, .semibold)).tracking(2.4).textCase(.uppercase).foregroundStyle(Tinta.suave) }
                        Text(t.nombre).font(Tipo.serif(40)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.6)
                        let sub = [ReglasTarjetas.fechaCorta(t.fecha, hoy: ReglasTarjetas.hoy()), t.detalle].filter { !$0.isEmpty }.joined(separator: " · ")
                        if t.tipo.boleto, !sub.isEmpty { Text(sub).font(Tipo.sans(16, .medium)).foregroundStyle(Tinta.suave).multilineTextAlignment(.center) }
                        CodigoVista(tarjeta: t).padding(.horizontal, 18)
                        Text(t.numero).font(.system(size: 24, weight: .medium, design: .monospaced)).tracking(2)
                            .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.5).textSelection(.enabled)
                        if !t.titular.isEmpty { Text(t.titular).font(Tipo.sans(14)).foregroundStyle(Tinta.suave) }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20).tag(t.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: club.tarjetas.count > 1 ? .always : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            Text("Brillo al máximo · vuelve al cerrar").font(Tipo.sans(11)).foregroundStyle(Tinta.suave).padding(.bottom, 14)
        }
        .foregroundStyle(Tinta.tinta)
        .background(Color.white.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .onAppear { elegida = inicial }
    }
}

/// El código de la tarjeta, nítido (sin suavizar) y con su margen blanco para que el lector lo encuentre.
struct CodigoVista: View {
    let tarjeta: TarjetaClub
    var body: some View {
        if tarjeta.formato == .numero {
            EmptyView()
        } else if let img = Codigos.imagen(tarjeta.numero, tarjeta.formato) {
            Image(decorative: img, scale: 1).interpolation(.none).resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: tarjeta.formato.cuadrado ? 260 : .infinity, maxHeight: tarjeta.formato.cuadrado ? 260 : 170)
                .padding(16).background(Color.white)
                .accessibilityLabel("Código de \(tarjeta.nombre)")
        } else {
            Text("Este número no se puede dibujar como \(tarjeta.formato.nombre). Enséñale el número al cajero o cámbialo en Ajustes.")
                .font(Tipo.sans(13)).foregroundStyle(Tinta.suave).multilineTextAlignment(.center)
        }
    }
}

/// Dibuja el código: EAN y Code 39 con la lógica propia (probada en Pruebas/TarjetasClub); Code 128, QR, PDF417 y Aztec
/// con los generadores de Core Image.
enum Codigos {
    private static let contexto = CIContext()

    static func imagen(_ numero: String, _ f: FormatoCodigo) -> CGImage? {
        let c = ReglasTarjetas.contenido(numero, f)
        switch f {
        case .ean13: return ReglasTarjetas.barrasEAN13(c).flatMap { lineal($0) }
        case .ean8: return ReglasTarjetas.barrasEAN8(c).flatMap { lineal($0) }
        case .code39: return ReglasTarjetas.barrasCode39(c).flatMap { lineal($0) }
        case .code128:
            let g = CIFilter.code128BarcodeGenerator(); g.message = Data(c.utf8); g.quietSpace = 0; g.barcodeHeight = 60
            return ci(g.outputImage)
        case .qr:
            let g = CIFilter.qrCodeGenerator(); g.message = Data(c.utf8); g.correctionLevel = "M"
            return ci(g.outputImage)
        case .pdf417:
            let g = CIFilter.pdf417BarcodeGenerator(); g.message = Data(c.utf8)
            return ci(g.outputImage)
        case .aztec:
            let g = CIFilter.aztecCodeGenerator(); g.message = Data(c.utf8)
            return ci(g.outputImage)
        case .numero: return nil
        }
    }

    private static func ci(_ i: CIImage?) -> CGImage? {
        guard let i else { return nil }
        return contexto.createCGImage(i, from: i.extent)
    }

    /// Un píxel por módulo y 60 de alto: la vista lo agranda sin suavizar.
    private static func lineal(_ barras: [Bool]) -> CGImage? {
        let w = barras.count, h = 60
        var px = [UInt8](repeating: 255, count: w * h)
        for y in 0..<h { for (x, b) in barras.enumerated() where b { px[y * w + x] = 0 } }
        guard let prov = CGDataProvider(data: Data(px) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: prov, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

// MARK: - Ajustes → Tarjetas de clubes

struct TarjetasClubVista: View {
    @ObservedObject private var club = TarjetasClub.shared
    @Environment(\.dismiss) private var cerrar
    @State private var editando: TarjetaClub?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Etiqueta("Alma · Ajustes")
                            Spacer()
                            Button { cerrar() } label: {
                                Image(systemName: "xmark").font(.system(size: 15, weight: .medium)).frame(width: 40, height: 40)
                                    .background(Circle().fill(Tinta.tinta.opacity(0.06)))
                            }.buttonStyle(.plain).accessibilityLabel("Cerrar")
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Tarjetas")
                            Text("y boletos").italic()
                        }.font(Tipo.serif(44)).lineSpacing(-4).accessibilityAddTraits(.isHeader)
                        Text("Las del supermercado y de cliente frecuente, y tus boletos de avión, tren, conciertos y eventos. Se guardan solo en este iPhone. Dile a Alma «enséñame mi tarjeta de…» o «mi boleto del concierto» y lo pone en pantalla.")
                            .font(Tipo.sans(13)).foregroundStyle(Tinta.suave)
                    }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
                }
                Section {
                    ForEach(club.tarjetas) { t in
                        HStack(spacing: 12) {
                            Button { editando = t } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: icono(t))
                                        .font(.system(size: 20)).foregroundStyle(Tinta.peach).frame(width: 30)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t.nombre).font(Tipo.sans(15, .medium))
                                        Text(subtitulo(t)).font(Tipo.sans(12)).foregroundStyle(Tinta.suave)
                                    }
                                    Spacer()
                                }.contentShape(Rectangle())
                                .opacity(ReglasTarjetas.paso(t, hoy: ReglasTarjetas.hoy()) ? 0.5 : 1)
                            }.buttonStyle(.borderless).accessibilityLabel("Cambiar la tarjeta de \(t.nombre)")
                            Button { VentanaTarjeta.shared.mostrar(t.id) } label: {
                                Text("Mostrar").font(Tipo.sans(13, .semibold)).padding(.horizontal, 12).frame(height: 32)
                                    .background(Capsule().fill(Tinta.peach.opacity(0.16)))
                            }.buttonStyle(.borderless).accessibilityLabel("Mostrar la tarjeta de \(t.nombre)")
                        }.foregroundStyle(Tinta.tinta)
                    }
                    .onDelete { i in i.map { club.tarjetas[$0].id }.forEach(club.borrar) }
                    .onMove { club.mover($0, $1) }
                    Button { editando = TarjetaClub(id: UUID().uuidString, nombre: "", numero: "", formato: .code128) } label: {
                        Label("Agregar una tarjeta o un boleto", systemImage: "plus.circle.fill").font(Tipo.sans(15, .medium)).foregroundStyle(Tinta.peach)
                    }
                } footer: {
                    if !club.tarjetas.isEmpty { Text("Desliza a la izquierda para borrar una.").font(Tipo.sans(11)) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(FondoAtardecer())
            .foregroundStyle(Tinta.tinta)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editando) { t in TarjetaClubEditor(tarjeta: t, nueva: !club.tarjetas.contains { $0.id == t.id }) }
        }
        .tint(Tinta.tinta)
    }

    /// En la lista solo se ven los últimos 4 (la tarjeta completa, al mostrarla).
    private func oculto(_ n: String) -> String { n.count <= 4 ? n : "•••• " + String(n.suffix(4)) }
    private func icono(_ t: TarjetaClub) -> String {
        switch t.tipo {
        case .club: return t.formato.cuadrado ? "qrcode" : t.formato == .numero ? "number" : "barcode"
        case .avion: return "airplane"
        case .tren: return "tram.fill"
        case .concierto: return "music.note"
        case .evento: return "ticket"
        }
    }
    /// Una tarjeta: el número tapado. Un boleto: su tipo, la fecha y si ya pasó.
    private func subtitulo(_ t: TarjetaClub) -> String {
        guard t.tipo.boleto else { return oculto(t.numero) }
        let hoy = ReglasTarjetas.hoy()
        return [t.tipo.nombre, ReglasTarjetas.fechaCorta(t.fecha, hoy: hoy), ReglasTarjetas.paso(t, hoy: hoy) ? "ya pasó" : ""]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Agregar o cambiar una tarjeta: el nombre, el número (escaneado o tecleado) y el formato del código.
struct TarjetaClubEditor: View {
    @State var tarjeta: TarjetaClub
    let nueva: Bool
    @Environment(\.dismiss) private var cerrar
    @State private var escanear = false
    /// El formato lo eligió Juan o el escáner: ya no se cambia solo al teclear.
    @State private var formatoFijo = false

    /// La fecha del boleto como yyyy-MM-dd (sin fecha, hoy al abrir el selector).
    private var fechaBinding: Binding<Date> {
        Binding(get: {
            let p = tarjeta.fecha.split(separator: "-").compactMap { Int($0) }
            guard p.count == 3 else { return Date() }
            return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) ?? Date()
        }, set: { tarjeta.fecha = ReglasTarjetas.hoy($0) })
    }

    private var puedeGuardar: Bool {
        !tarjeta.nombre.trimmingCharacters(in: .whitespaces).isEmpty && ReglasTarjetas.sePuede(tarjeta.numero, tarjeta.formato)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Qué es", selection: $tarjeta.tipo) {
                        ForEach(TipoTarjeta.allCases, id: \.self) { Text($0.nombre).tag($0) }
                    }.font(Tipo.sans(15))
                    if Escaner.disponible {
                        Button { escanear = true } label: { Label("Escanear con la cámara", systemImage: "barcode.viewfinder").font(Tipo.sans(15, .medium)) }
                    }
                    TextField(tarjeta.tipo.boleto ? "Nombre (p. ej. Vuelo a Madrid, Coldplay)" : "Nombre del club (p. ej. La Torre)", text: $tarjeta.nombre).font(Tipo.sans(15)).textInputAutocapitalization(.words)
                    TextField(tarjeta.tipo.boleto ? "Número o código del boleto" : "Número de la tarjeta", text: $tarjeta.numero).font(Tipo.sans(15)).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .onChange(of: tarjeta.numero) { _, n in if !formatoFijo { tarjeta.formato = ReglasTarjetas.formatoSugerido(n) } }
                    TextField("A nombre de (opcional)", text: $tarjeta.titular).font(Tipo.sans(15))
                    if tarjeta.tipo.boleto {
                        DatePicker("Fecha", selection: fechaBinding, displayedComponents: .date).font(Tipo.sans(15))
                        TextField("Asiento, puerta o sección (opcional)", text: $tarjeta.detalle).font(Tipo.sans(15))
                    }
                } footer: {
                    Text("Alma la encuentra por el nombre: ponlo como se lo dirías.").font(Tipo.sans(11))
                }
                Section {
                    Picker("Código", selection: Binding(get: { tarjeta.formato }, set: { tarjeta.formato = $0; formatoFijo = true })) {
                        ForEach(FormatoCodigo.allCases, id: \.self) { Text($0.nombre).tag($0) }
                    }.font(Tipo.sans(15))
                    if !tarjeta.numero.isEmpty {
                        if ReglasTarjetas.sePuede(tarjeta.numero, tarjeta.formato) {
                            CodigoVista(tarjeta: tarjeta).frame(maxWidth: .infinity)
                        } else {
                            Text("Ese número no cabe en \(tarjeta.formato.nombre). Prueba otro código o «Solo el número».").font(Tipo.sans(12)).foregroundStyle(Tinta.peach)
                        }
                    }
                } footer: {
                    Text("Al escanear, el código queda igual al de tu tarjeta. Si lo tecleas, Alma elige el más común para ese número.").font(Tipo.sans(11))
                }
                if !nueva {
                    Section {
                        Button(tarjeta.tipo.boleto ? "Borrar este boleto" : "Borrar esta tarjeta", role: .destructive) { TarjetasClub.shared.borrar(tarjeta.id); cerrar() }.font(Tipo.sans(15))
                    }
                }
            }
            .navigationTitle(nueva ? "Nueva" : tarjeta.nombre)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        tarjeta.nombre = tarjeta.nombre.trimmingCharacters(in: .whitespaces)
                        tarjeta.numero = tarjeta.numero.trimmingCharacters(in: .whitespaces)
                        if tarjeta.tipo.boleto { if tarjeta.fecha.isEmpty { tarjeta.fecha = ReglasTarjetas.hoy() } } else { tarjeta.fecha = ""; tarjeta.detalle = "" }
                        TarjetasClub.shared.guardar(tarjeta); cerrar()
                    }.disabled(!puedeGuardar)
                }
            }
            .fullScreenCover(isPresented: $escanear) {
                Escaner { texto, formato in
                    tarjeta.numero = texto; tarjeta.formato = formato; formatoFijo = true; escanear = false
                } cancelar: { escanear = false }
                .ignoresSafeArea()
            }
        }
        .tint(Tinta.tinta)
        .onAppear { formatoFijo = !nueva }
    }
}

/// El escáner de VisionKit: toma el primer código que ve y dice en qué formato venía.
struct Escaner: UIViewControllerRepresentable {
    let listo: (String, FormatoCodigo) -> Void
    let cancelar: () -> Void

    static var disponible: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> UINavigationController {
        let s = DataScannerViewController(recognizedDataTypes: [.barcode()], qualityLevel: .accurate, recognizesMultipleItems: false,
                                          isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        s.delegate = context.coordinator
        s.navigationItem.title = "Apunta al código"
        s.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { _ in cancelar() })
        DispatchQueue.main.async { try? s.startScanning() }
        return UINavigationController(rootViewController: s)
    }
    func updateUIViewController(_ vc: UINavigationController, context: Context) {}
    func makeCoordinator() -> Coordinador { Coordinador(self) }

    @MainActor final class Coordinador: NSObject, DataScannerViewControllerDelegate {
        let padre: Escaner
        private var hecho = false
        init(_ p: Escaner) { padre = p }
        func dataScanner(_ s: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !hecho else { return }
            for i in items {
                if case .barcode(let b) = i, let v = b.payloadStringValue, !v.isEmpty {
                    hecho = true; s.stopScanning()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    padre.listo(v, Self.formato(b.observation.symbology, v))
                    return
                }
            }
        }
        static func formato(_ s: VNBarcodeSymbology, _ v: String) -> FormatoCodigo {
            switch s {
            case .ean13: return ReglasTarjetas.sePuede(v, .ean13) ? .ean13 : .code128
            case .ean8: return .ean8
            case .code39, .code39Checksum, .code39FullASCII, .code39FullASCIIChecksum: return ReglasTarjetas.sePuede(v, .code39) ? .code39 : .code128
            case .qr, .microQR: return .qr
            case .pdf417, .microPDF417: return .pdf417
            case .aztec: return .aztec
            default: return ReglasTarjetas.formatoSugerido(v)
            }
        }
    }
}
