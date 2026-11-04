import SwiftUI

/// La tarjeta de la llamada (#446 T2) en LlamadaVista: blanca, sube desde abajo sobre la roca (diseño A). La misma de la
/// roca del inicio (alma/inicio.html). Tocarla muestra más y la llamada sigue; «Abrir conversación» no cuelga; «Llamar» y
/// «WhatsApp» preguntan antes «¿Cuelgo a Alma?». Lo que se toca va a VozNativa.tarjetaAccion (las reglas: TarjetaLlamada.swift).
struct TarjetaVozVista: View {
    let t: TarjetaVoz
    let detalle: Bool
    let accion: (String) -> Void
    @State private var pregunta: String?
    init(t: TarjetaVoz, detalle: Bool, accion: @escaping (String) -> Void) { self.t = t; self.detalle = detalle; self.accion = accion }

    static func nombre(_ tipo: String) -> String { tipo == "reserva" ? "Reserva" : tipo == "conversacion" ? "Conversación" : "Apartamento" }
    private let tinta = Color.almaTinta, gris = Color(red: 0.435, green: 0.408, blue: 0.404), borde = Color.almaBorde

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // el asa: la baja a la pestañita
            Button { accion("plegar") } label: {
                Capsule().fill(borde).frame(width: 36, height: 4).frame(maxWidth: .infinity, minHeight: 22)
            }
            .buttonStyle(.plain).accessibilityLabel("Encoger la tarjeta")
            ScrollView(showsIndicators: false) { cuerpo }
                .frame(maxHeight: detalle ? 330 : 270)
                .fixedSize(horizontal: false, vertical: !detalle)
                .contentShape(Rectangle())
                .onTapGesture { accion("detalle") }
            if let p = pregunta { confirmar(p) } else { acciones }
        }
        .padding(.horizontal, 18).padding(.bottom, 16)
        .frame(maxWidth: 420)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.white).shadow(color: .black.opacity(0.18), radius: 30, y: 18))
        .simultaneousGesture(TapGesture().onEnded { accion("toque") })
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tarjeta de la llamada: " + TarjetaVozVista.nombre(t.tipo) + " " + t.titulo)
    }

    @ViewBuilder private var cuerpo: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle().fill(Color.almaCoral).frame(width: 6, height: 6)
                Text(t.etiqueta.isEmpty ? TarjetaVozVista.nombre(t.tipo) : t.etiqueta).textCase(.uppercase).tracking(2.6)
                    .font(.custom("Montserrat", size: 10).weight(.semibold)).foregroundStyle(gris).lineLimit(1)
            }
            if t.tipo == "apartamento", let u = URL(string: t.foto), !t.foto.isEmpty {
                AsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: { Color.almaFondo }
                    .frame(height: 92).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel("Foto de " + t.titulo)
            }
            cabecera
            if !t.fechas.isEmpty { fechas }
            ForEach(Array((detalle ? t.mensajes : Array(t.mensajes.suffix(2))).enumerated()), id: \.offset) { _, m in mensaje(m) }
            if !t.semana.isEmpty { semana }
            if !t.datos.isEmpty { datos }
            if let p = t.promesas.first {
                Text("Promesa abierta: " + (detalle ? t.promesas.joined(separator: " · ") : p))
                    .font(.custom("Montserrat", size: 12)).foregroundStyle(Color(red: 0.435, green: 0.322, blue: 0.063))
                    .padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.961, green: 0.902, blue: 0.749)))
            }
            if detalle && !t.detalle.isEmpty {
                Divider()
                ForEach(t.detalle, id: \.self) { Text($0).font(.custom("Montserrat", size: 12)).foregroundStyle(tinta) }
            }
            Text(detalle ? "Toca para ver menos · la llamada sigue" : "Toca para ver más")
                .font(.custom("Montserrat", size: 10.5)).foregroundStyle(gris.opacity(0.85)).frame(maxWidth: .infinity)
        }
    }

    private var cabecera: some View {
        HStack(spacing: 12) {
            if !(t.tipo == "apartamento" && !t.foto.isEmpty) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [Color(red: 0.79, green: 0.72, blue: 0.66), Color(red: 0.56, green: 0.50, blue: 0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(t.iniciales).font(.custom("Montserrat", size: 15).weight(.semibold)).foregroundStyle(.white)
                    if let u = URL(string: t.foto), !t.foto.isEmpty {
                        AsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: { Color.clear }.clipShape(Circle())
                    }
                }
                .frame(width: 46, height: 46).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(t.titulo).font(.custom("Cormorant Garamond", size: 24)).foregroundStyle(tinta).lineLimit(1)
                if !t.sub.isEmpty { Text(t.sub).font(.custom("Montserrat", size: 12)).foregroundStyle(gris).lineLimit(1) }
            }
            Spacer(minLength: 0)
            if !t.chip.isEmpty {
                Text(t.chip).font(.custom("Montserrat", size: 11).weight(.semibold)).lineLimit(1).fixedSize()
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .foregroundStyle(t.tono == "alerta" ? Color(red: 0.62, green: 0.2, blue: 0.15) : t.tono == "aviso" ? Color(red: 0.435, green: 0.322, blue: 0.063) : Color(red: 0.231, green: 0.4, blue: 0.569))
                    .background(Capsule().fill(t.tono == "alerta" ? Color(red: 0.949, green: 0.855, blue: 0.835) : t.tono == "aviso" ? Color(red: 0.961, green: 0.902, blue: 0.749) : Color(red: 0.91, green: 0.929, blue: 0.953)))
            }
        }
    }

    private var fechas: some View {
        HStack(spacing: 0) {
            ForEach(Array(t.fechas.enumerated()), id: \.offset) { i, f in
                if i > 0 { Rectangle().fill(borde).frame(width: 1) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.t).textCase(.uppercase).tracking(1.4).font(.custom("Montserrat", size: 10)).foregroundStyle(gris)
                    Text(f.v.isEmpty ? "–" : f.v).font(.custom("Montserrat", size: 14).weight(.semibold)).foregroundStyle(tinta).lineLimit(1).minimumScaleFactor(0.8)
                    if !f.d.isEmpty { Text(f.d).font(.custom("Montserrat", size: 11)).foregroundStyle(gris) }
                }
                .padding(.horizontal, 11).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(borde, lineWidth: 1))
    }

    private func mensaje(_ m: TarjetaVoz.Mensaje) -> some View {
        let suyo = m.de == "huesped"
        return HStack {
            if !suyo { Spacer(minLength: 30) }
            VStack(alignment: .leading, spacing: 2) {
                Text(m.texto).font(.custom("Montserrat", size: 13)).foregroundStyle(m.de == "auto" ? gris : tinta)
                Text([m.quien, m.hora].filter { !$0.isEmpty }.joined(separator: " · ")).font(.custom("Montserrat", size: 10)).foregroundStyle(gris)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 16).fill(suyo || m.de == "auto" ? Color.almaFondo : Color(red: 0.933, green: 0.945, blue: 0.957)))
            if suyo { Spacer(minLength: 30) }
        }
    }

    /// La semana con los colores del calendario (glosario): azul reservado, amarillo consulta, rojo bloqueado, verde libre.
    private var semana: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Esta semana").textCase(.uppercase).tracking(1.4).font(.custom("Montserrat", size: 9.5)).foregroundStyle(gris)
            HStack(spacing: 4) {
                ForEach(Array(t.semana.enumerated()), id: \.offset) { _, d in
                    let c = TarjetaVozVista.color(d.estado)
                    VStack(spacing: 1) {
                        Text(d.letra).font(.custom("Montserrat", size: 11).weight(.semibold))
                        Text(String(d.n)).font(.custom("Montserrat", size: 9))
                    }
                    .foregroundStyle(c.1).frame(maxWidth: .infinity).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8).fill(c.0))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(tinta, lineWidth: d.hoy ? 1.5 : 0))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel((d.hoy ? "Hoy, " : "") + String(d.n) + ": " + TarjetaVozVista.estadoTexto(d.estado))
                }
            }
            if detalle {
                HStack(spacing: 12) {
                    ForEach(["res", "con", "bloq", "libre"], id: \.self) { e in
                        HStack(spacing: 5) { RoundedRectangle(cornerRadius: 3).fill(TarjetaVozVista.color(e).0).frame(width: 9, height: 9); Text(TarjetaVozVista.estadoTexto(e).capitalized) }
                    }
                }
                .font(.custom("Montserrat", size: 10.5)).foregroundStyle(gris)
            }
        }
    }
    static func color(_ e: String) -> (Color, Color) {
        switch e {
        case "res": return (Color(red: 0.851, green: 0.894, blue: 0.937), Color(red: 0.173, green: 0.318, blue: 0.459))
        case "con": return (Color(red: 0.961, green: 0.902, blue: 0.749), Color(red: 0.435, green: 0.322, blue: 0.063))
        case "bloq": return (Color(red: 0.949, green: 0.855, blue: 0.835), Color(red: 0.62, green: 0.2, blue: 0.149))
        case "pasado": return (Color(red: 0.925, green: 0.918, blue: 0.906), Color(red: 0.435, green: 0.408, blue: 0.404))
        default: return (Color(red: 0.882, green: 0.933, blue: 0.898), Color(red: 0.184, green: 0.357, blue: 0.263))
        }
    }
    static func estadoTexto(_ e: String) -> String { e == "res" ? "reservado" : e == "con" ? "consulta" : e == "bloq" ? "bloqueado" : e == "pasado" ? "pasado" : "libre" }

    private var datos: some View {
        let lista = detalle ? t.datos : Array(t.datos.prefix(3))
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(lista, id: \.self) { x in
                HStack(spacing: 6) { Circle().fill(Color(red: 0.576, green: 0.545, blue: 0.541)).frame(width: 4, height: 4); Text(x).font(.custom("Montserrat", size: 12)).foregroundStyle(tinta) }
            }
        }
    }

    @ViewBuilder private var acciones: some View {
        if !t.conv.isEmpty || !t.tel.isEmpty || !t.wa.isEmpty {
            HStack(spacing: 8) {
                if !t.conv.isEmpty {
                    Button { accion("conv") } label: { etiquetaBoton("text.bubble", "Abrir conversación").frame(maxWidth: .infinity) }
                        .buttonStyle(.plain).foregroundStyle(.white).background(Capsule().fill(tinta))
                }
                if !t.tel.isEmpty {
                    Button { pregunta = "llamar"; accion("toque") } label: { etiquetaBoton("phone", "Llamar") }
                        .buttonStyle(.plain).foregroundStyle(tinta).overlay(Capsule().stroke(borde, lineWidth: 1))
                }
                if !t.wa.isEmpty {
                    Button { pregunta = "whatsapp"; accion("toque") } label: { etiquetaBoton("message", t.conv.isEmpty || t.tel.isEmpty ? "WhatsApp" : "") }
                        .buttonStyle(.plain).foregroundStyle(tinta).overlay(Capsule().stroke(borde, lineWidth: 1))
                        .accessibilityLabel("WhatsApp")
                }
            }
            .padding(.top, 12)
        }
    }
    private func etiquetaBoton(_ icono: String, _ texto: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icono).font(.system(size: 15, weight: .medium))
            if !texto.isEmpty { Text(texto).font(.custom("Montserrat", size: 13).weight(.semibold)).lineLimit(1) }
        }
        .padding(.horizontal, 16).frame(minHeight: 44)
    }
    /// «¿Cuelgo a Alma?»: con el sí cuelga y llama (o abre WhatsApp); con el no, la llamada sigue.
    private func confirmar(_ que: String) -> some View {
        VStack(spacing: 8) {
            Text("¿Cuelgo a Alma?").font(.custom("Montserrat", size: 14).weight(.semibold)).foregroundStyle(tinta)
            HStack(spacing: 8) {
                Button { pregunta = nil; accion("toque") } label: { Text("No, sigue").font(.custom("Montserrat", size: 13).weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.plain).foregroundStyle(tinta).overlay(Capsule().stroke(borde, lineWidth: 1))
                Button { pregunta = nil; accion(que) } label: {
                    Text(que == "llamar" ? "Sí, cuelga y llama" : "Sí, abre WhatsApp").font(.custom("Montserrat", size: 13).weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain).foregroundStyle(.white).background(Capsule().fill(tinta))
            }
        }
        .padding(.top, 12)
    }
}

