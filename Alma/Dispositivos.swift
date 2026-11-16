import PhotosUI
import SwiftUI

/// Dispositivos (Juan, 16-nov-2026): «una foto del anillo, una foto de los lentes, muy al estilo de Alma, cada uno con su
/// porcentaje de batería y algunos datos importantes; al tocar cada uno, sus configuraciones e información».
/// · Se abre desde Ajustes → «Dispositivos» (Puente: accion "dispositivos") o cuando Alma usa anillo_estado con mostrar.
/// · Sin roca: es una pantalla de ajustes (una roca por pantalla, y aquí no hace falta).
/// · Las fotos son un dibujo propio; Juan toca la foto en el detalle para poner la suya (se guarda solo en el teléfono).
/// · Nada se inventa: la batería de los lentes dice «no disponible» porque iOS no la da a las apps (Lentes.swift).
struct DispositivosVista: View {
    @ObservedObject private var anillo = AnilloAlma.shared
    @ObservedObject private var lentes = Lentes.shared
    @Environment(\.dismiss) private var cerrar

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Etiqueta("Alma · Ajustes")
                        Spacer()
                        Button { cerrar() } label: {
                            Image(systemName: "xmark").font(.system(size: 15, weight: .medium)).frame(width: 40, height: 40)
                                .background(Circle().fill(Tinta.tinta.opacity(0.06)))
                        }.accessibilityLabel("Cerrar")
                    }.padding(.top, 14)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Tus")
                        Text("dispositivos").italic()
                    }.font(Tipo.serif(44)).lineSpacing(-4).accessibilityAddTraits(.isHeader)
                    Text("Lo que Alma lee de tu anillo y tus lentes. Toca uno para ver sus ajustes.")
                        .font(Tipo.sans(13)).foregroundStyle(Tinta.suave).padding(.bottom, 6)

                    NavigationLink { AnilloDetalle() } label: {
                        TarjetaDispositivo(id: "anillo", titulo: Anillo.hayGuardado ? nombreAnillo : "Anillo QRing",
                                           estado: estadoAnillo, conectado: anillo.conectado, bateria: anillo.memoria.bateria?.v,
                                           cargando: anillo.memoria.cargando == true, sinBateria: "Sin lectura",
                                           datos: datosAnillo) { DibujoAnillo() }
                    }.buttonStyle(Presion())
                    NavigationLink { LentesDetalle() } label: {
                        TarjetaDispositivo(id: "lentes", titulo: lentes.nombre.isEmpty ? "Lentes AURA" : lentes.nombre,
                                           estado: lentes.sonSalida ? "Conectados · el audio sale por aquí" : lentes.conectados ? "Conectados" : "No conectados",
                                           conectado: lentes.conectados, bateria: lentes.bateria, cargando: false, sinBateria: "Batería no disponible",
                                           datos: datosLentes) { DibujoLentes() }
                    }.buttonStyle(Presion())
                }
                .padding(.horizontal, 22).padding(.bottom, 30)
            }
            .foregroundStyle(Tinta.tinta)
            .background(FondoAtardecer())
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(Tinta.tinta)
        .onAppear { lentes.buscarBLE(); anillo.sincronizar() }
    }

    private var nombreAnillo: String { UserDefaults.standard.string(forKey: "anillo_nombre").flatMap { $0.isEmpty ? nil : $0 } ?? "Anillo QRing" }
    private var estadoAnillo: String {
        if !Anillo.hayGuardado { return "Sin conectar a Alma" }
        if anillo.conectado { return "Conectado" }
        return "No conectado" + (AnilloDatos.hace(AnilloDatos.ultimoDato(anillo.memoria), ahora: Date().timeIntervalSince1970).map { " · visto \($0)" } ?? "")
    }
    private var datosAnillo: [(String, String)] {
        let m = anillo.memoria
        return [("Pasos hoy", m.pasos.map { Formato.miles(Double($0.v)) } ?? "—"),
                ("Último ritmo", m.ritmo.map { "\($0.v) lpm" } ?? "—"),
                ("Firmware", firmwareAnillo(m) ?? "—")]
    }
    private var datosLentes: [(String, String)] {
        [("Audio de Alma", lentes.sonSalida ? "Por los lentes" : "Por otro lado"),
         ("Música", lentes.bateria == nil ? "4–6 h llenos" : LentesDatos.horasMusica(bateria: lentes.bateria)),
         ("Llamadas", "3–4 h")]
    }
}

// MARK: - Piezas

/// El firmware del anillo: el que guardó la memoria o el que leyó Anillo.swift (sin despertar el Bluetooth).
func firmwareAnillo(_ m: AnilloDatos.Memoria) -> String? {
    let f = m.firmware ?? UserDefaults.standard.string(forKey: "anillo_firmware") ?? ""
    return f.isEmpty ? nil : f
}

/// El fondo: papel con un velo de atardecer arriba (los colores de la roca).
struct FondoAtardecer: View {
    var body: some View {
        ZStack(alignment: .top) {
            Tinta.papel
            LinearGradient(colors: [Color(hex: 0xE3A47F, opacity: 0.32), Color(hex: 0xB8B6C8, opacity: 0.18), Tinta.papel.opacity(0)],
                           startPoint: .top, endPoint: .bottom).frame(height: 420)
        }.ignoresSafeArea()
    }
}

/// Una tarjeta grande: foto a la derecha, nombre, estado, la batería en grande y tres datos.
struct TarjetaDispositivo<Dibujo: View>: View {
    let id: String, titulo: String, estado: String, conectado: Bool, bateria: Int?, cargando: Bool, sinBateria: String
    let datos: [(String, String)]
    @ViewBuilder let dibujo: () -> Dibujo

    var body: some View {
        Vidrio {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(titulo).font(Tipo.sans(15, .semibold)).lineLimit(1)
                    HStack(spacing: 6) {
                        Circle().fill(conectado ? Color(hex: 0x7FA88A) : Tinta.suave.opacity(0.5)).frame(width: 7, height: 7)
                        Text(estado).font(Tipo.sans(11.5)).foregroundStyle(Tinta.suave).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    if let b = bateria {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(b)").font(Tipo.serif(52, .medium))
                            Text("%").font(Tipo.serif(24))
                            if cargando { Image(systemName: "bolt.fill").font(.system(size: 13)).foregroundStyle(Tinta.peach) }
                        }
                        BarraBateria(nivel: b)
                    } else {
                        Text(sinBateria).font(Tipo.serif(22)).foregroundStyle(Tinta.suave)
                    }
                }
                Spacer(minLength: 0)
                FotoDispositivo(id: id, lado: 118, dibujo: dibujo)
            }
            Divider().overlay(Color.white.opacity(0.7)).padding(.vertical, 12)
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(datos.enumerated()), id: \.offset) { _, d in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(d.0.uppercased()).tracking(1.2).font(Tipo.sans(9, .medium)).foregroundStyle(Tinta.suave)
                        Text(d.1).font(Tipo.sans(13, .medium)).lineLimit(1).minimumScaleFactor(0.7)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre sus ajustes")
    }
}

struct BarraBateria: View {
    let nivel: Int
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Tinta.tinta.opacity(0.08))
                Capsule().fill(LinearGradient(colors: nivel <= 20 ? [Color(hex: 0xB5624E), Tinta.peach] : [Color(hex: 0xE3A47F), Tinta.peach],
                                              startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, g.size.width * CGFloat(nivel) / 100))
            }
        }.frame(width: 120, height: 6)
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

/// El encabezado de un detalle: la foto grande (tocarla deja poner la de Juan), nombre, estado y batería.
struct CabezaDetalle<Dibujo: View>: View {
    let id: String, titulo: String, estado: String, bateria: String
    @ViewBuilder let dibujo: () -> Dibujo
    @State private var elegida: PhotosPickerItem?
    @State private var hayFoto = false
    init(id: String, titulo: String, estado: String, bateria: String, @ViewBuilder _ dibujo: @escaping () -> Dibujo) {
        self.id = id; self.titulo = titulo; self.estado = estado; self.bateria = bateria; self.dibujo = dibujo
    }
    var body: some View {
        VStack(spacing: 10) {
            PhotosPicker(selection: $elegida, matching: .images) { FotoDispositivo(id: id, lado: 190, dibujo: dibujo) }
                .accessibilityLabel("Cambiar la foto")
            Text(hayFoto ? "Toca la foto para cambiarla" : "Toca el dibujo para poner tu foto").font(Tipo.sans(10.5)).foregroundStyle(Tinta.suave)
            if hayFoto { Button("Quitar mi foto") { FotosDispositivo.quitar(id); hayFoto = false }.font(Tipo.sans(11, .medium)) }
            Text(titulo).font(Tipo.serif(34)).multilineTextAlignment(.center).padding(.top, 4)
            Text(estado).font(Tipo.sans(12.5)).foregroundStyle(Tinta.suave)
            Text(bateria).font(Tipo.serif(26, .medium))
        }
        .frame(maxWidth: .infinity).padding(.top, 8)
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

// MARK: - Detalle del anillo

struct AnilloDetalle: View {
    @ObservedObject private var a = AnilloAlma.shared
    @State private var modoAnillo = UserDefaults.standard.bool(forKey: "voz_modo_anillo")
    @State private var monitoreo = true
    @State private var cada = 30
    private let opciones = [5, 10, 15, 30, 60]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                CabezaDetalle(id: "anillo", titulo: UserDefaults.standard.string(forKey: "anillo_nombre").flatMap { $0.isEmpty ? nil : $0 } ?? "Anillo QRing",
                              estado: a.conectado ? "Conectado" : Anillo.hayGuardado ? "No conectado" : "Sin conectar a Alma",
                              bateria: a.memoria.bateria.map { "\($0.v) %" + (a.memoria.cargando == true ? " · cargando" : "") } ?? "Batería sin lectura") { DibujoAnillo() }
                if !a.aviso.isEmpty {
                    Text(a.aviso).font(Tipo.sans(13.5, .medium)).frame(maxWidth: .infinity).padding(14)
                        .background(RoundedRectangle(cornerRadius: 18).fill(.white))
                }
                if !Anillo.hayGuardado {
                    Text("Conecta tu anillo desde Health (en el inicio) → Anillo. Después aparece aquí con su batería y sus ajustes.")
                        .font(Tipo.sans(13.5)).fixedSize(horizontal: false, vertical: true).padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 18).fill(.white))
                }

                Etiqueta("Alma con el anillo").padding(.top, 10)
                Fila("Modo anillo", "Dos toques encienden o apagan el modo conferencia, aun bloqueado") {
                    Toggle("", isOn: $modoAnillo).labelsHidden().tint(Tinta.peach)
                }
                .onChange(of: modoAnillo) { _, on in VozNativa.shared.ponerModoAnillo(on) }

                Etiqueta("Acciones").padding(.top, 10)
                HStack(spacing: 8) {
                    BotonClaro("Buscar") { a.buscar() }
                    BotonClaro(a.midiendo == .ritmo ? "Midiendo…" : "Ritmo") { if a.midiendo == nil { a.medir(.ritmo) { _, _ in } } }
                    BotonClaro(a.midiendo == .oxigeno ? "Midiendo…" : "Oxígeno") { if a.midiendo == nil { a.medir(.oxigeno) { _, _ in } } }
                }.disabled(!a.conectado).opacity(a.conectado ? 1 : 0.5)

                Etiqueta("Monitoreo del ritmo").padding(.top, 10)
                Fila("Medir solo", "El anillo mide tu ritmo durante el día") {
                    Toggle("", isOn: $monitoreo).labelsHidden().tint(Tinta.peach)
                }
                .onChange(of: monitoreo) { _, on in if on != (a.memoria.ritmoActivo ?? true) { a.ajustar(activo: on, minutos: cada) } }
                Fila("Cada", nil) {
                    Picker("Cada", selection: $cada) { ForEach(opciones, id: \.self) { Text("\($0) min").tag($0) } }.tint(Tinta.tinta)
                }
                .onChange(of: cada) { _, m in if m != a.memoria.ritmoMinutos { a.ajustar(activo: monitoreo, minutos: m) } }
                .disabled(!monitoreo)

                Etiqueta("Hoy").padding(.top, 10)
                dato("Pasos", a.memoria.pasos.map { Formato.miles(Double($0.v)) + " · " + (a.memoria.kcal.map { "\($0.v) kcal" } ?? "") + (a.memoria.metros.map { String(format: " · %.1f km", Double($0.v) / 1000) } ?? "") }, a.memoria.pasos?.t)
                dato("Ritmo del día", a.memoria.ritmoMin.map { "mín \($0) · máx \(a.memoria.ritmoMax ?? 0) · prom. \(a.memoria.ritmoProm ?? 0)" }, a.memoria.ritmoDiaT)
                dato("Último ritmo", a.memoria.ritmo.map { "\($0.v) lpm" }, a.memoria.ritmo?.t)
                dato("Oxígeno", a.memoria.oxigeno.map { "\($0.v) %" }, a.memoria.oxigeno?.t)

                Etiqueta("Información").padding(.top, 10)
                dato("Firmware", firmwareAnillo(a.memoria), nil)
                dato("Sincronizado", a.memoria.sync.map { _ in "" }, a.memoria.sync)
                BotonClaro("Sincronizar ahora") { a.sincronizar() }.disabled(!a.conectado).opacity(a.conectado ? 1 : 0.5).padding(.top, 4)
                NavigationLink { DiagnosticoAnilloVista() } label: {
                    Fila("Diagnóstico del anillo (Bluetooth)", "Qué manda el anillo al tocarlo") { Text("›").font(Tipo.sans(18)).foregroundStyle(Tinta.suave) }
                }.buttonStyle(Presion())
            }
            .padding(.horizontal, 22).padding(.bottom, 30)
        }
        .foregroundStyle(Tinta.tinta).background(FondoAtardecer())
        .onAppear {
            monitoreo = a.memoria.ritmoActivo ?? true
            cada = a.memoria.ritmoMinutos.map { m in opciones.min { abs($0 - m) < abs($1 - m) } ?? 30 } ?? 30
        }
    }

    private func dato(_ t: String, _ v: String?, _ cuando: Double?) -> some View {
        Fila(t, cuando.flatMap { AnilloDatos.hace($0, ahora: Date().timeIntervalSince1970) }) {
            Text(v.flatMap { $0.isEmpty ? nil : $0 } ?? (cuando == nil ? "—" : "")).font(Tipo.sans(13.5, .medium)).multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Detalle de los lentes

struct LentesDetalle: View {
    @ObservedObject private var l = Lentes.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                CabezaDetalle(id: "lentes", titulo: l.nombre.isEmpty ? "Lentes AURA" : l.nombre,
                              estado: l.sonSalida ? "Conectados · el audio sale por aquí" : l.conectados ? "Conectados" : "No conectados",
                              bateria: l.bateria.map { "\($0) %" } ?? "Batería no disponible") { DibujoLentes() }
                if l.bateria == nil {
                    Text("iOS no comparte la batería de unos lentes de audio con las apps. La ves en el widget de Baterías del iPhone.")
                        .font(Tipo.sans(12.5)).foregroundStyle(Tinta.suave).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }

                Etiqueta("Audio").padding(.top, 10)
                Fila("Salida de audio ahora", l.salidaAhora.isEmpty ? "—" : l.salidaAhora) { Image(systemName: l.sonSalida ? "checkmark.circle.fill" : "circle").foregroundStyle(l.sonSalida ? Tinta.peach : Tinta.suave) }
                Fila("Usarlos para Alma", "Elige los lentes como salida de audio") { ElegirSalida().frame(width: 36, height: 36) }

                Etiqueta("Según el fabricante").padding(.top, 10)
                Fila("Música", LentesDatos.horasMusica(bateria: l.bateria)) { EmptyView() }
                Fila("Llamadas", "3–4 h con la carga llena") { EmptyView() }
                Fila("Baterías", "Dos de 110 mAh, una en cada patilla · carga magnética") { EmptyView() }
                Fila("Bluetooth", "6.0 · solo audio, sin cámara") { EmptyView() }

                Etiqueta("Lo que ve Alma").padding(.top, 10)
                Fila("Por Bluetooth de baja energía", l.porBLE ? "Encontrados" + (l.bateria == nil ? " · sin servicio de batería" : " · con batería") : "No se anuncian: solo audio") { EmptyView() }
                Button("Buscar otra vez") { l.buscarBLE() }.font(Tipo.sans(12, .semibold)).frame(maxWidth: .infinity).padding(.top, 4)
            }
            .padding(.horizontal, 22).padding(.bottom, 30)
        }
        .foregroundStyle(Tinta.tinta).background(FondoAtardecer())
        .onAppear { l.buscarBLE() }
    }
}
