import Charts
import SwiftUI
import UIKit

/// Health, nativo: el cuerpo contado como la Colección 2026 de Alma. Siete capítulos a pantalla completa
/// (foto editorial, titular en Cormorant con la segunda línea en itálica, «ALMA» a la izquierda y el capítulo a la derecha)
/// con tarjetas de vidrio que muestran Apple Salud y el anillo.
struct SaludVista: View {
    @StateObject private var m = SaludModelo()
    @Environment(\.dismiss) private var cerrar
    @State private var capitulo = "Tu cuerpo hoy"
    @State private var oscuro = false
    @State private var detalle: Medida?
    @State private var conexion = false
    @State private var ajustes = false
    @State private var respira = false

    var body: some View {
        GeometryReader { g in
            let ancho = g.size.width, arriba = g.safeAreaInsets.top
            ZStack(alignment: .top) {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        portada(ancho, arriba)
                        descanso(ancho, arriba)
                        pulso(ancho, arriba)
                        movimiento(ancho, arriba)
                        deporte(ancho, arriba)
                        respirar(ancho, arriba)
                        elAnillo(ancho, arriba)
                    }
                }
                .scrollIndicators(.hidden)
                .coordinateSpace(name: "salud")
                .onPreferenceChange(PosCapitulo.self) { pos in
                    // el capítulo que cruza el 42 % de la pantalla da nombre a la firma de arriba
                    let actual = pos.filter { $0.value <= g.size.height * 0.42 }.max { $0.value < $1.value }?.key ?? "Tu cuerpo hoy"
                    if actual != capitulo { withAnimation(.easeInOut(duration: 0.35)) { capitulo = actual; oscuro = actual == "Descanso" } }
                }
                firma(arriba)
            }
            .ignoresSafeArea()
        }
        .background(Color(hex: 0xE8DCCD))
        .statusBarHidden(false)
        .preferredColorScheme(.light)
        .onAppear { m.cargar() }
        .sheet(item: $detalle) { k in DetalleVista(m: m, medida: k, conectar: { detalle = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { abrirConexion() } }) }
        .sheet(isPresented: $ajustes) { AjustesAnillo(m: m) }
        .fullScreenCover(isPresented: $conexion) { ConexionVista(m: m) }
        .fullScreenCover(isPresented: $respira) { RespiraVista() }
    }

    private func abrirConexion() { m.reiniciarConexion(); conexion = true }

    // MARK: - La firma del deck

    private func firma(_ arriba: CGFloat) -> some View {
        HStack {
            Button { cerrar() } label: {
                HStack(spacing: 8) { Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)); Text("ALMA").tracking(3.5) }
            }
            Spacer()
            Text(capitulo.uppercased()).tracking(3.5).id(capitulo).transition(.opacity)
        }
        .font(Tipo.sans(11, .medium))
        .foregroundStyle(oscuro ? Color(hex: 0xF5EFE8) : Tinta.tinta)
        .padding(.horizontal, 24)
        .padding(.top, max(arriba, 16) + 4)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Capítulos

    private func portada(_ w: CGFloat, _ a: CGFloat) -> some View {
        let s = m.sueno, e = m.ultimo("hrv")
        let l1 = s.map { $0.minutos >= 420 ? "Dormiste bien." : $0.minutos >= 360 ? "Dormiste lo justo." : "Dormiste poco." } ?? (m.pasos != nil || e != nil ? "Buenos días." : "Tu cuerpo, hoy.")
        let l2 = s == nil && e == nil && m.pasos == nil ? "Alma lo escucha." : ((e ?? 60) >= 45 ? "Hoy vas en calma." : "Hoy, con pausas.")
        return Capitulo(nombre: "Tu cuerpo hoy", foto: "cap-cuerpo", pie: Color(hex: 0x9A7757), ancho: w, arriba: a) {
            Titulo(l1, l2).aparece(0)
            Text(m.permiso == true ? "Alma revisó tu noche y tu pulso." : "Conecta tu anillo o Apple Salud para ver tu día.").font(Tipo.sans(15)).padding(.top, 14).aparece(1)
        } tarjetas: {
            Rejilla(columnas: 3) {
                TarjetaCifra("Sueño", s.map { Formato.hm($0.minutos) } ?? "—").boton { detalle = .sueno }.aparece(2)
                TarjetaCifra("Pulso", Formato.n(m.ultimo("ritmo")), "lpm", punto: true).boton { detalle = .ritmo }.aparece(3)
                TarjetaCifra("Oxígeno", Formato.n(m.ultimo("oxigeno")), "%").boton { detalle = .oxigeno }.aparece(4)
                TarjetaCifra("HRV", Formato.n(m.ultimo("hrv")), "ms").boton { detalle = .hrv }.aparece(5)
                TarjetaCifra("Temp.", Formato.n(m.ultimo("temp"), 1), "°").boton { detalle = .temperatura }.aparece(6)
                TarjetaCifra("Pasos", Formato.miles(m.pasos)).boton { detalle = .pasos }.aparece(7)
            }
        }
    }

    private func descanso(_ w: CGFloat, _ a: CGFloat) -> some View {
        let s = m.sueno
        let noches = m.dias.compactMap { $0.valores["sueno"] }
        return Capitulo(nombre: "Descanso", foto: "cap-noche", pie: Color(hex: 0x4E525C), ancho: w, arriba: a, oscuro: true) {
            Titulo("Descansa.", s == nil ? "Alma cuida la noche." : "Alma cuidó tu noche.").aparece(0)
        } tarjetas: {
            Vidrio(oscuro: true) {
                Etiqueta("Tu noche", color: Color(hex: 0xF2B39E))
                Text(s.map { Formato.hm($0.minutos) } ?? "—").font(Tipo.serif(58, .medium)).padding(.top, 2)
                if let s { Hipnograma(fases: s.fases).frame(height: 70).padding(.top, 12) }
                Text(s == nil ? "Duerme con tu anillo y aquí verás tu noche." : "Profundo \(Formato.hm(m.suma("p"))) · REM \(Formato.hm(m.suma("r")))")
                    .font(Tipo.sans(12)).opacity(0.75).padding(.top, 10)
                if noches.count >= 3 {
                    Text("Promedio de \(noches.count) noches: \(Formato.hm(noches.reduce(0, +) / Double(noches.count)))").font(Tipo.sans(12)).opacity(0.75)
                }
            }.boton { detalle = .sueno }.aparece(1)
            Rejilla(columnas: 2) {
                TarjetaCifra("Te dormiste", s?.inicio ?? "—", oscuro: true).aparece(2)
                TarjetaCifra("Despertaste", s?.fin ?? "—", oscuro: true).aparece(3)
            }
        }
    }

    private func pulso(_ w: CGFloat, _ a: CGFloat) -> some View {
        let r = m.estadisticas("ritmo")
        return Capitulo(nombre: "Pulso", foto: "cap-pulso", pie: Color(hex: 0xAC9D8A), ancho: w, arriba: a) {
            Titulo("Tu pulso,", (m.ultimo("ritmo") ?? 60) < 80 ? "en calma." : "despierto.").aparece(0)
            Text("El anillo lo mide solo. Si quieres, mídelo ahora.").font(Tipo.sans(15)).padding(.top, 14).aparece(1)
        } tarjetas: {
            Vidrio {
                Etiqueta("Ritmo cardíaco", punto: true)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Formato.n(m.ultimo("ritmo"))).font(Tipo.serif(58, .medium)).contentTransition(.numericText())
                    Text("lpm").font(Tipo.sans(14)).foregroundStyle(Tinta.suave)
                    Image(systemName: "heart.fill").font(.system(size: 13)).foregroundStyle(Tinta.peach)
                        .symbolEffect(.pulse, isActive: m.midiendo == "ritmo")
                }
                LineaDia(puntos: m.serie("ritmo"), color: Tinta.peach).frame(height: 58).padding(.top, 8)
                Text(r.map { "\(Int($0.min))–\(Int($0.max)) lpm hoy · en reposo \(Int($0.min))" } ?? "Toca para ver tu día").font(Tipo.sans(12)).foregroundStyle(Tinta.suave)
            }.boton { detalle = .ritmo }.aparece(2)
            Rejilla(columnas: 2) {
                TarjetaCifra("Variabilidad", Formato.n(m.ultimo("hrv")), "ms", pie: Formato.hrv(m.ultimo("hrv"))).boton { detalle = .hrv }.aparece(3)
                TarjetaCifra("Oxígeno", Formato.n(m.ultimo("oxigeno")), "%", pie: "En sangre").boton { detalle = .oxigeno }.aparece(4)
            }
        }
    }

    private func movimiento(_ w: CGFloat, _ a: CGFloat) -> some View {
        let meta = m.pasos.map { min(100, $0 / 100) }
        return Capitulo(nombre: "Movimiento", foto: "cap-movimiento", pie: Color(hex: 0xCDB9A8), ancho: w, arriba: a) {
            Titulo("Muévete.", "Alma lleva\nla cuenta.").aparece(0)
        } tarjetas: {
            Vidrio {
                Etiqueta("Pasos")
                Text(Formato.miles(m.pasos)).font(Tipo.serif(58, .medium)).contentTransition(.numericText())
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Tinta.tinta.opacity(0.12))
                        Capsule().fill(Tinta.peach).frame(width: g.size.width * CGFloat((meta ?? 0) / 100))
                    }
                }.frame(height: 3).padding(.top, 8)
                Text(meta.map { $0 >= 100 ? "Meta cumplida" : "Te faltan \(Formato.miles(10000 - (m.pasos ?? 0))) para tu meta" } ?? "Meta 10 000")
                    .font(Tipo.sans(12)).foregroundStyle(Tinta.suave).padding(.top, 6)
            }.boton { detalle = .pasos }.aparece(1)
            Rejilla(columnas: 3) {
                TarjetaCifra("km", Formato.n(m.km, 1)).aparece(2)
                TarjetaCifra("kcal", Formato.n(m.kcal)).aparece(3)
                TarjetaCifra("Meta", Formato.n(meta), "%").aparece(4)
            }
            Vidrio {
                Etiqueta("Hoy, hora por hora")
                BarrasHora(valores: m.pasosHora).frame(height: 54).padding(.top, 10)
                HStack { Text("0 h"); Spacer(); Text("6"); Spacer(); Text("12"); Spacer(); Text("18"); Spacer(); Text("24") }.font(Tipo.sans(10)).foregroundStyle(Tinta.suave).padding(.top, 4)
            }.boton { detalle = .pasos }.aparece(5)
        }
    }

    private func deporte(_ w: CGFloat, _ a: CGFloat) -> some View {
        let ej = m.ejercicios, tot = ej.reduce(0) { $0 + $1.min }, kc = ej.reduce(0) { $0 + $1.kcal }
        return Capitulo(nombre: "Deporte", foto: "cap-deporte", pie: Color(hex: 0xBCB1A7), ancho: w, arriba: a) {
            Titulo("Entrena.", tot >= 150 ? "Semana completa." : "Alma va contigo.").aparece(0)
        } tarjetas: {
            Rejilla(columnas: 3) {
                TarjetaCifra("Minutos", ej.isEmpty ? "—" : Formato.n(tot)).aparece(1)
                TarjetaCifra("Sesiones", ej.isEmpty ? "—" : "\(ej.count)").aparece(2)
                TarjetaCifra("kcal", ej.isEmpty ? "—" : Formato.miles(kc)).aparece(3)
            }
            Vidrio {
                Etiqueta("Esta semana")
                SemanaDeporte(ejercicios: ej).frame(height: 80).padding(.top, 10)
                if ej.isEmpty {
                    Text("Entrena con tu reloj o tu anillo y aquí verás tu semana.").font(Tipo.sans(12)).foregroundStyle(Tinta.suave).padding(.top, 6)
                } else {
                    ForEach(ej.suffix(3).reversed()) { x in FilaSesion(x: x) }
                }
            }.boton { detalle = .deporte }.aparece(4)
        }
    }

    private func respirar(_ w: CGFloat, _ a: CGFloat) -> some View {
        Capitulo(nombre: "Respira", foto: "cap-respira", pie: Color(hex: 0x82654F), ancho: w, arriba: a) {
            Titulo("Respira.", "Un minuto con Alma.").aparece(0)
            Text("Inhala cuando la roca crezca. Exhala cuando se encoja.").font(Tipo.sans(15)).padding(.top, 14).aparece(1)
        } tarjetas: {
            Pildora("Empezar") { respira = true }.aparece(2)
            Text("Inhala 4 · sostén 4 · exhala 6").font(Tipo.sans(12)).foregroundStyle(.white.opacity(0.85)).aparece(3)
        }
    }

    private func elAnillo(_ w: CGFloat, _ a: CGFloat) -> some View {
        Capitulo(nombre: "El anillo", foto: "cap-anillo", pie: Color(hex: 0xCBB396), ancho: w, arriba: a) {
            Titulo("Un toque.", "Alma está ahí.").aparece(0)
        } tarjetas: {
            Vidrio {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Etiqueta("Tu anillo")
                        Text(m.conectado || m.guardado ? (m.nombreAnillo.isEmpty ? "Tu anillo" : m.nombreAnillo) : "Sin anillo").font(Tipo.serif(24, .medium))
                        Text(m.conectado ? "Conectado" + (m.bateria.map { " · batería \($0) %" + (m.cargando ? ", cargando" : "") } ?? "") : m.guardado ? "Esperando al anillo…" : "Toca para conectarlo")
                            .font(Tipo.sans(12)).foregroundStyle(Tinta.suave)
                    }
                    Spacer()
                    Chip(m.conectado ? "Ajustes" : "Conectar", claro: m.conectado)
                }
            }.boton { if m.conectado { ajustes = true } else { abrirConexion() } }.aparece(1)
            Vidrio {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Etiqueta("Apple Salud")
                        Text("Tu reloj y tu iPhone").font(Tipo.serif(24, .medium))
                        Text(m.permiso == true ? "Leyendo tu último año" : "Pasos, pulso, sueño y ejercicios").font(Tipo.sans(12)).foregroundStyle(Tinta.suave)
                    }
                    Spacer()
                    Chip(m.permiso == true ? "Conectado" : "Conectar", claro: m.permiso == true)
                }
            }.boton { if m.permiso != true { m.pedirPermiso() } }.aparece(2)
        }
    }
}

// MARK: - Piezas

enum Tinta {
    static let tinta = Color(hex: 0x2F3030)
    static let suave = Color(hex: 0x6F6867)
    static let peach = Color(hex: 0xE9826A)
    static let papel = Color(hex: 0xF7F2EC)
}

enum Tipo {
    static func serif(_ t: CGFloat, _ w: Font.Weight = .regular) -> Font { .custom("Cormorant Garamond", size: t).weight(w) }
    static func sans(_ t: CGFloat, _ w: Font.Weight = .regular) -> Font { .custom("Montserrat", size: t).weight(w) }
}

enum Formato {
    static func n(_ v: Double?, _ dec: Int = 0) -> String {
        guard let v else { return "—" }
        return dec > 0 ? String(format: "%.\(dec)f", v) : "\(Int(v.rounded()))"
    }
    static func miles(_ v: Double?) -> String {
        guard let v else { return "—" }
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = " "; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v.rounded())) ?? "\(Int(v))"
    }
    static func hm(_ min: Double) -> String { let n = Int(min.rounded()); return "\(n / 60) h " + String(format: "%02d", n % 60) }
    static func hrv(_ v: Double?) -> String { guard let v else { return "HRV" }; return v < 30 ? "Baja" : v <= 60 ? "Normal" : v <= 101 ? "Buena" : "Excelente" }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

/// Las fotos de los capítulos viven en la app (Recursos/Salud, en WebP).
enum Foto {
    static func imagen(_ nombre: String) -> UIImage? {
        guard let p = Bundle.main.path(forResource: nombre, ofType: "webp") else { return nil }
        return UIImage(contentsOfFile: p)
    }
}

struct PosCapitulo: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) { value.merge(nextValue()) { $1 } }
}

private struct VistoClave: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues { var visto: Bool { get { self[VistoClave.self] } set { self[VistoClave.self] = newValue } } }

/// Aparecer en orden: titular, bajada, tarjetas (sube 22 pt y aparece, 85 ms entre uno y otro).
struct Aparece: ViewModifier {
    let i: Int
    @Environment(\.visto) private var visto
    @Environment(\.accessibilityReduceMotion) private var quieto
    func body(content: Content) -> some View {
        content.opacity(visto ? 1 : 0).offset(y: visto || quieto ? 0 : 22)
            .animation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.9).delay(Double(i) * 0.085 + 0.12), value: visto)
    }
}
extension View {
    func aparece(_ i: Int) -> some View { modifier(Aparece(i: i)) }
    func boton(_ accion: @escaping () -> Void) -> some View {
        Button(action: { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); accion() }) { self }.buttonStyle(Presion())
    }
}
struct Presion: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label.scaleEffect(c.isPressed ? 0.97 : 1).animation(.spring(response: 0.25, dampingFraction: 1), value: c.isPressed)
    }
}

/// Un capítulo: foto 9:16 arriba (se acerca despacio al llegar), texto encima y tarjetas al pie.
struct Capitulo<Arriba: View, Abajo: View>: View {
    let nombre: String, foto: String, pie: Color, ancho: CGFloat, arriba: CGFloat
    var oscuro = false
    @ViewBuilder let texto: () -> Arriba
    @ViewBuilder let tarjetas: () -> Abajo
    @State private var visto = false
    @Environment(\.accessibilityReduceMotion) private var quieto

    init(nombre: String, foto: String, pie: Color, ancho: CGFloat, arriba: CGFloat, oscuro: Bool = false,
         @ViewBuilder _ texto: @escaping () -> Arriba, @ViewBuilder tarjetas: @escaping () -> Abajo) {
        self.nombre = nombre; self.foto = foto; self.pie = pie; self.ancho = ancho; self.arriba = arriba; self.oscuro = oscuro
        self.texto = texto; self.tarjetas = tarjetas
    }

    var body: some View {
        let altoFoto = ancho * 16 / 9
        VStack(alignment: .leading, spacing: 0) {
            texto()
            Spacer(minLength: 22)
            VStack(alignment: .leading, spacing: 10) { tarjetas() }
        }
        .foregroundStyle(oscuro ? Color(hex: 0xF7F1EA) : Tinta.tinta)
        .padding(.horizontal, 24)
        .padding(.top, max(arriba, 16) + 86)
        .padding(.bottom, 36)
        .frame(width: ancho, alignment: .leading)
        .frame(minHeight: altoFoto + max(arriba, 16) + 86, alignment: .top)
        .background(alignment: .top) {
            ZStack(alignment: .bottom) {
                if let img = Foto.imagen(foto) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: ancho, height: altoFoto).clipped()
                        .scaleEffect(visto || quieto ? 1 : 1.07)
                        .animation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 2.6), value: visto)
                }
                LinearGradient(colors: [pie.opacity(0), pie], startPoint: .top, endPoint: .bottom).frame(height: altoFoto * 0.22)
            }
            .frame(width: ancho, height: altoFoto).clipped()
            .accessibilityHidden(true)
        }
        .background(pie)
        .environment(\.visto, visto)
        .background(GeometryReader { g in Color.clear.preference(key: PosCapitulo.self, value: [nombre: g.frame(in: .named("salud")).minY]) })
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { visto = true } }
    }
}

struct Titulo: View {
    let a: String, b: String
    init(_ a: String, _ b: String) { self.a = a; self.b = b }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(a)
            Text(b).italic()
        }
        .font(Tipo.serif(min(58, max(42, UIScreen.main.bounds.width * 0.116))))
        .lineSpacing(-4)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct Etiqueta: View {
    let t: String; var color: Color? = nil; var punto = false
    init(_ t: String, color: Color? = nil, punto: Bool = false) { self.t = t; self.color = color; self.punto = punto }
    @Environment(\.colorScheme) private var esquema
    var body: some View {
        HStack(spacing: 7) {
            if punto { Circle().fill(Tinta.peach).frame(width: 6, height: 6) }
            Text(t.uppercased()).tracking(1.7)
        }
        .font(Tipo.sans(10.5, .medium))
        .foregroundStyle(color ?? (esquema == .dark ? Color.white.opacity(0.72) : Tinta.suave))
    }
}

/// Vidrio: material translúcido con borde de luz (como las tarjetas del deck).
struct Vidrio<C: View>: View {
    var oscuro = false
    @ViewBuilder let contenido: () -> C
    init(oscuro: Bool = false, @ViewBuilder _ c: @escaping () -> C) { self.oscuro = oscuro; contenido = c }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { contenido() }
            .padding(.horizontal, 14).padding(.top, 13).padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(oscuro ? 0.03 : 0.3)))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(oscuro ? 0.2 : 0.7), lineWidth: 1))
            }
            .foregroundStyle(oscuro ? Color(hex: 0xF7F1EA) : Tinta.tinta)
            .environment(\.colorScheme, oscuro ? .dark : .light)
    }
}

struct TarjetaCifra: View {
    let et: String, valor: String; var unidad: String? = nil; var punto = false; var pie: String? = nil; var oscuro = false
    init(_ et: String, _ valor: String, _ unidad: String? = nil, punto: Bool = false, pie: String? = nil, oscuro: Bool = false) {
        self.et = et; self.valor = valor; self.unidad = unidad; self.punto = punto; self.pie = pie; self.oscuro = oscuro
    }
    var body: some View {
        Vidrio(oscuro: oscuro) {
            Etiqueta(et, punto: punto)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(valor).font(Tipo.serif(30, .medium)).contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.6)
                if let unidad, valor != "—" { Text(unidad).font(Tipo.sans(12)).opacity(0.7) }
            }.padding(.top, 4)
            if let pie { Text(pie).font(Tipo.sans(12)).opacity(0.7).padding(.top, 2) }
        }
    }
}

struct Rejilla<C: View>: View {
    let columnas: Int
    @ViewBuilder let c: () -> C
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columnas), spacing: 10) { c() }
    }
}

struct Chip: View {
    let t: String; let claro: Bool
    init(_ t: String, claro: Bool) { self.t = t; self.claro = claro }
    var body: some View {
        Text(t.uppercased()).tracking(1.5).font(Tipo.sans(11, .semibold))
            .padding(.horizontal, 16).frame(height: 38)
            .background(Capsule().fill(claro ? Tinta.tinta.opacity(0.08) : Tinta.tinta))
            .foregroundStyle(claro ? Tinta.suave : Color(hex: 0xF7F1EA))
    }
}

/// El botón del deck: píldora tinta con el punto peach.
struct Pildora: View {
    let t: String; let accion: () -> Void
    init(_ t: String, _ accion: @escaping () -> Void) { self.t = t; self.accion = accion }
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Tinta.peach).frame(width: 7, height: 7)
            Text(t.uppercased()).tracking(2.4).font(Tipo.sans(12, .semibold))
        }
        .padding(.leading, 22).padding(.trailing, 26).frame(height: 54)
        .background(Capsule().fill(Tinta.tinta)).foregroundStyle(Color(hex: 0xF7F1EA))
        .boton(accion)
    }
}

struct Hipnograma: View {
    let fases: [SaludModelo.Fase]
    @Environment(\.visto) private var visto
    static let color: [String: Color] = ["p": Color(hex: 0x3F5677), "l": Color(hex: 0x7F93B0), "r": Color(hex: 0xB9C5D6), "d": Color(hex: 0xE9A58E)]
    static let alto: [String: CGFloat] = ["d": 1, "r": 0.72, "l": 0.5, "p": 0.28]
    var body: some View {
        GeometryReader { g in
            let tot = max(1, fases.reduce(0) { $0 + $1.min }), hueco = CGFloat(max(0, fases.count - 1)) * 2
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(fases) { f in
                    RoundedRectangle(cornerRadius: 2).fill(Hipnograma.color[f.c] ?? .gray)
                        .frame(width: max(1, (g.size.width - hueco) * CGFloat(f.min / tot)), height: g.size.height * (Hipnograma.alto[f.c] ?? 0.5))
                        .scaleEffect(y: visto ? 1 : 0, anchor: .bottom)
                        .animation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.9).delay(Double(f.id) * 0.035), value: visto)
                }
            }.frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

struct BarrasHora: View {
    let valores: [Double]
    @Environment(\.visto) private var visto
    var body: some View {
        let v = valores.isEmpty ? Array(repeating: 0.0, count: 24) : valores
        let mx = max(1, v.max() ?? 1), pico = v.firstIndex(of: v.max() ?? 0), hora = Calendar.current.component(.hour, from: Date())
        GeometryReader { g in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(v.enumerated()), id: \.offset) { i, n in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(n == 0 ? Tinta.tinta.opacity(0.16) : i == pico ? Tinta.peach : Tinta.tinta.opacity(0.82))
                        .frame(height: max(3, g.size.height * CGFloat(n / mx)))
                        .opacity(i > hora ? 0.35 : 1)
                        .scaleEffect(y: visto ? 1 : 0, anchor: .bottom)
                        .animation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 1).delay(Double(i) * 0.022), value: visto)
                }
            }.frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

/// Una línea del día (sin ejes), la del capítulo de Pulso.
struct LineaDia: View {
    let puntos: [SaludModelo.Punto]; let color: Color
    var body: some View {
        if puntos.count < 2 { Color.clear } else {
            Chart(puntos) { p in
                LineMark(x: .value("t", p.t), y: .value("v", p.v)).interpolationMethod(.catmullRom).foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 1.6))
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .chartYScale(domain: (puntos.map(\.v).min() ?? 0) - 3 ... (puntos.map(\.v).max() ?? 1) + 3)
        }
    }
}

struct SemanaDeporte: View {
    let ejercicios: [SaludModelo.Ejercicio]
    static let dias = ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"]
    var body: some View {
        let hoy = Calendar.current.component(.weekday, from: Date()) - 1
        var mins = Array(repeating: 0.0, count: 7)
        for e in ejercicios { mins[min(6, max(0, e.dia))] += e.min }
        let mx = max(1, mins.max() ?? 1), top = mins.firstIndex(of: mins.max() ?? 0)
        return VStack(spacing: 6) {
            GeometryReader { g in
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(0..<7, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2).fill(mins[i] == 0 ? Tinta.tinta.opacity(0.16) : i == top ? Tinta.peach : Tinta.tinta.opacity(0.82))
                            .frame(height: max(4, g.size.height * CGFloat(mins[i] / mx)))
                    }
                }.frame(maxHeight: .infinity, alignment: .bottom)
            }
            HStack { ForEach(0..<7, id: \.self) { i in Text(SemanaDeporte.dias[(hoy - 6 + i + 7) % 7]).frame(maxWidth: .infinity) } }
                .font(Tipo.sans(10)).foregroundStyle(Tinta.suave)
        }
    }
}

struct FilaSesion: View {
    let x: SaludModelo.Ejercicio
    var body: some View {
        let hoy = Calendar.current.component(.weekday, from: Date()) - 1
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(x.tipo).font(Tipo.serif(21, .medium))
                Text("\(SemanaDeporte.dias[(hoy - 6 + x.dia + 7) % 7]) · \(Int(x.min)) min").font(Tipo.sans(12)).foregroundStyle(Tinta.suave)
            }
            Spacer()
            Text("\(Int(x.kcal))").font(Tipo.serif(21, .medium)) + Text(" kcal").font(Tipo.sans(11)).foregroundColor(Tinta.suave)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(Tinta.tinta.opacity(0.08)).frame(height: 1) }
    }
}

// MARK: - Detalle de cada medida

enum Medida: String, Identifiable {
    case sueno, ritmo, oxigeno, hrv, temperatura, pasos, deporte
    var id: String { rawValue }
}

struct DetalleVista: View {
    @ObservedObject var m: SaludModelo
    let medida: Medida
    let conectar: () -> Void
    @State private var anio = false

    private var info: (t1: String, t2: String, unidad: String, serie: String?, hist: String?, foto: String, dec: Int) {
        switch medida {
        case .ritmo: return ("Ritmo", " cardíaco", "lpm", "ritmo", "ritmo", "cap-pulso", 0)
        case .oxigeno: return ("Oxígeno", " en sangre", "%", "oxigeno", "oxigeno", "cap-cuerpo", 0)
        case .hrv: return ("Variabilidad", " del pulso", "ms", "hrv", "hrv", "cap-pulso", 0)
        case .temperatura: return ("Temperatura", "", "°C", "temp", nil, "cap-cuerpo", 1)
        case .sueno: return ("Tu", " noche", "", nil, "sueno", "cap-noche", 0)
        case .pasos: return ("Movi", "miento", "pasos", nil, "pasos", "cap-movimiento", 0)
        case .deporte: return ("Deporte", "", "", nil, nil, "cap-deporte", 0)
        }
    }

    var body: some View {
        let i = info
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let img = Foto.imagen(i.foto) {
                    Image(uiImage: img).resizable().scaledToFill().frame(height: 210).frame(maxWidth: .infinity).clipped()
                }
                VStack(alignment: .leading, spacing: 0) {
                    Etiqueta(Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es"))))
                    (Text(i.t1) + Text(i.t2).italic()).font(Tipo.serif(40)).padding(.top, 6)
                    contenido(i)
                }
                .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 30)
            }
        }
        .foregroundStyle(Tinta.tinta)
        .background(Tinta.papel)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    @ViewBuilder private func contenido(_ i: (t1: String, t2: String, unidad: String, serie: String?, hist: String?, foto: String, dec: Int)) -> some View {
        switch medida {
        case .sueno: sueno
        case .pasos: pasos
        case .deporte: deporte
        default:
            if let k = i.serie {
                let st = m.estadisticas(k)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Formato.n(m.ultimo(k), i.dec)).font(Tipo.serif(64, .medium)).contentTransition(.numericText())
                    Text(i.unidad).font(Tipo.sans(15)).foregroundStyle(Tinta.suave)
                }.padding(.top, 14)
                GraficaDia(puntos: m.serie(k), color: medida == .ritmo ? Tinta.peach : Tinta.tinta, dec: i.dec)
                Tres([(Formato.n(st?.prom, i.dec), "Promedio"), (Formato.n(st?.min, i.dec), "Mínimo"), (Formato.n(st?.max, i.dec), "Máximo")])
                if let z = zonas(k), !z.isEmpty { Zonas(filas: z) }
            }
            if let h = i.hist { historial(h, unidad: i.unidad, dec: i.dec) }
            if medida == .ritmo || medida == .oxigeno {
                Button {
                    if m.conectado { m.medir(medida == .ritmo ? "ritmo" : "oxigeno") } else { conectar() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "heart.fill").foregroundStyle(Tinta.peach).symbolEffect(.pulse, isActive: m.midiendo != nil)
                        Text(m.midiendo != nil ? "Midiendo…" : m.conectado ? "Medir ahora" : "Conecta tu anillo").tracking(1.9)
                    }
                    .font(Tipo.sans(12, .semibold)).frame(maxWidth: .infinity).frame(height: 52)
                    .background(Capsule().fill(Tinta.tinta)).foregroundStyle(Color(hex: 0xF7F1EA))
                }
                .disabled(m.midiendo != nil).padding(.top, 18)
            }
        }
    }

    private func zonas(_ k: String) -> [(String, String, Double, Color)]? {
        let s = m.serie(k).map(\.v); guard !s.isEmpty else { return nil }
        let def: [(String, Double, Double)]
        switch k {
        case "ritmo": def = [("Calentamiento", 0, 109), ("Quema de grasa", 110, 129), ("Aeróbico", 130, 149), ("Anaeróbico", 150, 169), ("Límite", 170, 250)]
        case "oxigeno": def = [("Menos de 95 %", 0, 94), ("95–97 %", 95, 97), ("98 % o más", 98, 100)]
        case "hrv": def = [("Baja · menos de 30", 0, 29), ("Normal · 30–60", 30, 60), ("Buena · 61–101", 61, 101), ("Excelente · más de 101", 102, 400)]
        default: return nil
        }
        let tonos = [0xD9CFC3, 0xBCAE9F, 0x8F8175, 0xE9A58E, 0xE9826A].map { Color(hex: UInt32($0)) }
        return def.enumerated().map { (j: Int, z: (String, Double, Double)) -> (String, String, Double, Color) in
            let p = Double(s.filter { $0 >= z.1 && $0 <= z.2 }.count) / Double(s.count) * 100
            return (z.0, "\(Int(p.rounded())) %", p, tonos[min(tonos.count - 1, j + (def.count < 5 ? 1 : 0))])
        }
    }

    private var sueno: some View {
        Group {
            if let s = m.sueno {
                Etiqueta("Anoche · \(s.inicio) – \(s.fin)").padding(.top, 10)
                Text(Formato.hm(s.minutos)).font(Tipo.serif(64, .medium)).padding(.top, 6)
                let tot = max(1, s.fases.reduce(0) { $0 + $1.min })
                Zonas(filas: [("p", "Profundo"), ("l", "Ligero"), ("r", "REM"), ("d", "Despierto")].map { (c: String, n: String) -> (String, String, Double, Color) in
                    let v = m.suma(c), p = v / tot * 100
                    return (n, "\(Formato.hm(v)) · \(Int(p.rounded())) %", p, Hipnograma.color[c] ?? .gray)
                })
                Tres([("\(Int(((tot - m.suma("d")) / tot * 100).rounded())) %", "Eficiencia"), ("\(Int((m.suma("p") / tot * 100).rounded())) %", "Profundo"), ("\(Int((m.suma("r") / tot * 100).rounded())) %", "REM")])
            } else {
                Text("Duerme con tu anillo o tu reloj y aquí verás tus fases y cómo descansaste.").font(Tipo.sans(15)).foregroundStyle(Tinta.suave).padding(.top, 12)
            }
            historial("sueno", unidad: "", dec: 0, horas: true)
        }
    }

    private var pasos: some View {
        Group {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Formato.miles(m.pasos)).font(Tipo.serif(64, .medium))
                Text("pasos").font(Tipo.sans(15)).foregroundStyle(Tinta.suave)
            }.padding(.top, 14)
            BarrasHora(valores: m.pasosHora).frame(height: 150).padding(14).background(RoundedRectangle(cornerRadius: 20).fill(.white)).padding(.top, 14)
            Tres([(Formato.n(m.km, 1), "km"), (Formato.n(m.kcal), "kcal"), (m.pasos.map { "\(Int(min(100, $0 / 100))) %" } ?? "—", "de la meta")])
            historial("pasos", unidad: "pasos", dec: 0)
        }
    }

    private var deporte: some View {
        Group {
            Etiqueta("Últimos 7 días").padding(.top, 10)
            if m.ejercicios.isEmpty {
                Text("Aún no hay entrenamientos esta semana. Entrena con tu reloj o tu anillo y Alma los guarda aquí.").font(Tipo.sans(15)).foregroundStyle(Tinta.suave).padding(.top, 12)
            } else {
                VStack(spacing: 0) { ForEach(m.ejercicios.reversed()) { x in FilaSesion(x: x) } }
                    .padding(.horizontal, 16).padding(.vertical, 4).background(RoundedRectangle(cornerRadius: 20).fill(.white)).padding(.top, 12)
            }
        }
    }

    /// 30 días o el año (un promedio por mes).
    @ViewBuilder private func historial(_ campo: String, unidad: String, dec: Int, horas: Bool = false) -> some View {
        let h = m.historia(campo, anio: anio), con = h.compactMap { $0.valor }
        if con.count >= 2 {
            let f: (Double) -> String = { horas ? Formato.hm($0) : campo == "pasos" ? Formato.miles($0) : Formato.n($0, dec) }
            HStack {
                Etiqueta(anio ? "Tu año, mes a mes" : "Últimos 30 días")
                Spacer()
                Picker("", selection: $anio.animation(.easeInOut(duration: 0.3))) { Text("30 días").tag(false); Text("Año").tag(true) }
                    .pickerStyle(.segmented).frame(width: 150)
            }.padding(.top, 24)
            Chart(Array(h.enumerated()), id: \.offset) { i, x in
                if let v = x.valor {
                    BarMark(x: .value("fecha", x.fecha, unit: anio ? .month : .day), y: .value("v", v))
                        .foregroundStyle(i == h.count - 1 ? Tinta.peach : Tinta.tinta.opacity(0.82))
                        .cornerRadius(2)
                }
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: anio ? .month : .day, count: anio ? 3 : 10)) { _ in
                    AxisValueLabel(format: anio ? .dateTime.month(.abbreviated) : .dateTime.day().month(.abbreviated)).font(Tipo.sans(10))
                }
            }
            .environment(\.locale, Locale(identifier: "es"))
            .frame(height: 130).padding(14).background(RoundedRectangle(cornerRadius: 20).fill(.white)).padding(.top, 10)
            Tres([(f(con.reduce(0, +) / Double(con.count)), "Promedio"), (f(con.min() ?? 0), "Mínimo"), (f(con.max() ?? 0), "Máximo")])
        }
    }
}

struct GraficaDia: View {
    let puntos: [SaludModelo.Punto]; let color: Color; let dec: Int
    var body: some View {
        Group {
            if puntos.count < 2 {
                Text("Todavía no hay datos de hoy").font(Tipo.sans(14)).foregroundStyle(Tinta.suave).frame(maxWidth: .infinity).frame(height: 170)
            } else {
                Chart(puntos) { p in
                    AreaMark(x: .value("t", p.t), y: .value("v", p.v)).interpolationMethod(.catmullRom).foregroundStyle(color.opacity(0.07))
                    LineMark(x: .value("t", p.t), y: .value("v", p.v)).interpolationMethod(.catmullRom).foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 1.6))
                    if p.t == puntos.last?.t {
                        PointMark(x: .value("t", p.t), y: .value("v", p.v)).foregroundStyle(Tinta.peach).symbolSize(60)
                    }
                }
                .chartXScale(domain: 0...1440)
                .chartYScale(domain: (puntos.map(\.v).min() ?? 0) - 4 ... (puntos.map(\.v).max() ?? 1) + 4)
                .chartXAxis {
                    AxisMarks(values: [0.0, 360, 720, 1080, 1440]) { v in
                        AxisValueLabel { Text("\(Int(v.as(Double.self) ?? 0) / 60) h").font(Tipo.sans(10)) }
                    }
                }
                .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in AxisValueLabel().font(Tipo.sans(10)) } }
                .frame(height: 170)
            }
        }
        .padding(14).background(RoundedRectangle(cornerRadius: 20).fill(.white)).padding(.top, 14)
    }
}

struct Tres: View {
    let v: [(String, String)]
    init(_ v: [(String, String)]) { self.v = v }
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(v.enumerated()), id: \.offset) { i, x in
                VStack(spacing: 2) { Text(x.0).font(Tipo.serif(28, .medium)); Text(x.1).font(Tipo.sans(11)).foregroundStyle(Tinta.suave) }
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                if i < v.count - 1 { Rectangle().fill(Tinta.tinta.opacity(0.07)).frame(width: 1) }
            }
        }
        .background(RoundedRectangle(cornerRadius: 20).fill(.white)).padding(.top, 12)
    }
}

struct Zonas: View {
    let filas: [(String, String, Double, Color)]
    @State private var lleno = false
    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(filas.enumerated()), id: \.offset) { _, z in
                VStack(spacing: 5) {
                    HStack { Text(z.0); Spacer(); Text(z.1).fontWeight(.semibold) }.font(Tipo.sans(13))
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Tinta.tinta.opacity(0.08))
                            Capsule().fill(z.3).frame(width: lleno ? g.size.width * CGFloat(z.2 / 100) : 0)
                        }
                    }.frame(height: 4)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 20).fill(.white)).padding(.top, 12)
        .onAppear { withAnimation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 1.2).delay(0.25)) { lleno = true } }
    }
}

// MARK: - Anillo: ajustes y conexión

struct AjustesAnillo: View {
    @ObservedObject var m: SaludModelo
    @Environment(\.dismiss) private var cerrar
    @State private var nota = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let img = Foto.imagen("cap-anillo") { Image(uiImage: img).resizable().scaledToFill().frame(height: 200).frame(maxWidth: .infinity).clipped().padding(.horizontal, -24) }
                Etiqueta("Tu anillo").padding(.top, 8)
                Text(m.nombreAnillo.isEmpty ? "Anillo" : m.nombreAnillo).font(Tipo.serif(40))
                Fila("Batería", m.cargando ? "Cargando" : "Conectado") { Text(m.bateria.map { "\($0) %" } ?? "—").font(Tipo.serif(24, .medium)) }
                Fila("Medir el ritmo solo", "Lo guarda el anillo: es el mismo ajuste que en QRing") {
                    Toggle("", isOn: $m.auto).labelsHidden().tint(Tinta.tinta).onChange(of: m.auto) { _, _ in m.guardarRitmo() }
                }
                Fila("Cada", nil) {
                    Picker("", selection: $m.minutos) { ForEach([5, 10, 15, 30, 60], id: \.self) { Text("\($0) min").tag($0) } }
                        .tint(Tinta.tinta).onChange(of: m.minutos) { _, _ in m.guardarRitmo() }
                }
                HStack(spacing: 10) {
                    BotonClaro("Encontrar") { m.encontrarAnillo(); nota = "Tu anillo está parpadeando." }
                    BotonClaro("Igualar hora") { m.igualarHora(); nota = "Listo: el anillo tiene la hora del teléfono." }
                }.padding(.top, 6)
                BotonClaro("Olvidar este anillo", rojo: true) { m.olvidar(); cerrar() }
                if !nota.isEmpty { Text(nota).font(Tipo.sans(12)).foregroundStyle(Tinta.suave).frame(maxWidth: .infinity).padding(.top, 6) }
            }
            .padding(.horizontal, 24).padding(.bottom, 30)
        }
        .foregroundStyle(Tinta.tinta).background(Tinta.papel)
        .presentationDragIndicator(.visible).presentationCornerRadius(28)
    }
}

struct Fila<D: View>: View {
    let t: String; let sub: String?; @ViewBuilder let d: () -> D
    init(_ t: String, _ sub: String?, @ViewBuilder _ d: @escaping () -> D) { self.t = t; self.sub = sub; self.d = d }
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(t).font(Tipo.sans(14.5))
                if let sub { Text(sub).font(Tipo.sans(11.5)).foregroundStyle(Tinta.suave) }
            }
            Spacer(); d()
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 18).fill(.white))
    }
}

struct BotonClaro: View {
    let t: String; var rojo = false; let accion: () -> Void
    init(_ t: String, rojo: Bool = false, _ accion: @escaping () -> Void) { self.t = t; self.rojo = rojo; self.accion = accion }
    var body: some View {
        Text(t.uppercased()).tracking(1.9).font(Tipo.sans(12, .semibold))
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(Capsule().fill(.white)).foregroundStyle(rojo ? Color(hex: 0xB5624E) : Tinta.tinta)
            .boton(accion)
    }
}

/// Conectar el anillo: los dibujos de línea, uno tras otro (mano → anillo con ondas → toque → Alma).
struct ConexionVista: View {
    @ObservedObject var m: SaludModelo
    @Environment(\.dismiss) private var cerrar
    @State private var onda = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { cerrar() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .medium)).frame(width: 40, height: 40).background(Circle().fill(Tinta.tinta.opacity(0.06))) }
                Spacer()
            }
            ZStack {
                if m.pasoConexion == 1 {
                    ForEach(0..<3, id: \.self) { i in
                        Circle().stroke(Color(hex: 0xF2B39E), lineWidth: 1).frame(width: 230, height: 230)
                            .scaleEffect(onda ? 1.55 : 0.6).opacity(onda ? 0 : 0.9)
                            .animation(.easeOut(duration: 2.6).repeatForever(autoreverses: false).delay(Double(i) * 0.85), value: onda)
                    }
                }
                lamina("linea-mano", visible: m.pasoConexion == 0)
                lamina("linea-anillo", visible: m.pasoConexion == 1 || m.pasoConexion == 2)
                lamina("linea-toque", visible: m.pasoConexion == 3)
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0xFFFBF8), Color(hex: 0xFCE6DC), Color(hex: 0xF6C7B5), Color(hex: 0xEFAE97)], center: UnitPoint(x: 0.36, y: 0.3), startRadius: 2, endRadius: 90))
                    .frame(width: 150, height: 150).shadow(color: Tinta.peach.opacity(0.5), radius: 30, y: 20)
                    .scaleEffect(m.pasoConexion == 4 ? 1 : 0.5).opacity(m.pasoConexion == 4 ? 1 : 0)
                    .animation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 1.2).delay(0.3), value: m.pasoConexion)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 8) {
                Text(m.textoConexion.0).font(Tipo.serif(36))
                Text(m.textoConexion.1).font(Tipo.sans(14)).foregroundStyle(Tinta.suave).multilineTextAlignment(.center)
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { i in Capsule().fill(i == min(3, m.pasoConexion) ? Tinta.peach : Tinta.tinta.opacity(0.14)).frame(width: i == min(3, m.pasoConexion) ? 20 : 6, height: 6) }
                }.padding(.top, 10).animation(.easeInOut(duration: 0.4), value: m.pasoConexion)
            }
            .frame(maxWidth: 340, minHeight: 130, alignment: .top)
            VStack(spacing: 8) {
                ForEach(m.encontrados) { e in
                    HStack { Text(e.nombre).font(Tipo.serif(20, .medium)); Spacer(); Text(e.detalle).font(Tipo.sans(12)).foregroundStyle(Tinta.suave) }
                        .padding(.horizontal, 18).padding(.vertical, 15).background(RoundedRectangle(cornerRadius: 18).fill(.white))
                        .boton { m.elegir(e) }
                }
            }.frame(maxWidth: 380).padding(.top, 10)
            if m.pasoConexion == 0 || m.pasoConexion == 4 {
                Text(m.pasoConexion == 4 ? "LISTO" : "BUSCAR MI ANILLO").tracking(1.9).font(Tipo.sans(12, .semibold))
                    .frame(maxWidth: 380).frame(height: 54).background(Capsule().fill(Tinta.tinta)).foregroundStyle(Color(hex: 0xF7F1EA))
                    .boton { if m.pasoConexion == 4 { cerrar() } else { m.buscar() } }
                    .padding(.top, 14)
            }
        }
        .foregroundStyle(Tinta.tinta)
        .padding(.horizontal, 24).padding(.vertical, 18)
        .background(Color(hex: 0xFBF9F6).ignoresSafeArea())
        .onAppear { onda = true }
        .onChange(of: m.pasoConexion) { _, p in if p == 4 { UINotificationFeedbackGenerator().notificationOccurred(.success) } }
    }

    private func lamina(_ n: String, visible: Bool) -> some View {
        Group { if let img = Foto.imagen(n) { Image(uiImage: img).resizable().scaledToFit() } }
            .frame(width: min(UIScreen.main.bounds.width * 0.82, 340), height: min(UIScreen.main.bounds.width * 0.82, 340))
            .blendMode(.multiply)
            .opacity(visible ? 1 : 0).scaleEffect(visible ? 1 : 0.96)
            .animation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.8), value: visible)
    }
}

/// Respira con Alma (4 · 4 · 6), cuatro vueltas sobre la roca encendida.
struct RespiraVista: View {
    @Environment(\.dismiss) private var cerrar
    @State private var fase = ("Inhala", "4 segundos")
    @State private var escala: CGFloat = 1
    @State private var tarea: Task<Void, Never>?
    var body: some View {
        ZStack {
            if let img = Foto.imagen("cap-respira") { Image(uiImage: img).resizable().scaledToFill().ignoresSafeArea() }
            Color(hex: 0x3C2C22, opacity: 0.28).ignoresSafeArea()
            VStack(spacing: 0) {
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0xFFFBF8), Color(hex: 0xFCE6DC), Color(hex: 0xF6C7B5), Color(hex: 0xEFAE97)], center: UnitPoint(x: 0.36, y: 0.3), startRadius: 2, endRadius: 90))
                    .frame(width: 150, height: 150).shadow(color: Color(hex: 0xF2B39E, opacity: 0.9), radius: 40, y: 20)
                    .scaleEffect(escala).padding(.bottom, 36)
                Text(fase.0).font(Tipo.serif(44)).contentTransition(.opacity)
                Text(fase.1.uppercased()).tracking(2.6).font(Tipo.sans(13)).opacity(0.85).padding(.top, 10)
            }.foregroundStyle(Color(hex: 0xFBF6F0))
            VStack {
                HStack {
                    Button { tarea?.cancel(); cerrar() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .medium)).frame(width: 40, height: 40).background(Circle().fill(.white.opacity(0.16))).foregroundStyle(.white) }
                    Spacer()
                }
                Spacer()
            }.padding(18)
        }
        .onAppear { tarea = Task { await respirar() } }
        .onDisappear { tarea?.cancel() }
    }

    @MainActor private func respirar() async {
        let fases: [(String, String, CGFloat, Double)] = [("Inhala", "4 segundos", 1.45, 4), ("Sostén", "4 segundos", 1.45, 4), ("Exhala", "6 segundos", 1, 6)]
        for _ in 0..<4 {
            for f in fases {
                if Task.isCancelled { return }
                fase = (f.0, f.1)
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                withAnimation(.timingCurve(0.45, 0, 0.55, 1, duration: f.3)) { escala = f.2 }
                try? await Task.sleep(nanoseconds: UInt64(f.3 * 1_000_000_000))
            }
        }
        fase = ("Bien hecho", "Un minuto para ti")
        withAnimation(.easeInOut(duration: 1)) { escala = 1 }
    }
}
