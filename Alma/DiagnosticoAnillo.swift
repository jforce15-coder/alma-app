import CoreBluetooth
import SwiftUI
import UIKit

/// Diagnóstico del anillo (Bluetooth) (Juan, 16-nov-2026, ticket #29 paso 1). Ajustes → Alma con el anillo →
/// «Diagnóstico del anillo (Bluetooth)» abre esta pantalla (Puente: accion "anilloBle").
/// Hoy el anillo llega como control de música y otra app de audio (Spotify) se lo quita. Juan aprobó leerlo directo por
/// Bluetooth; antes hay que saber qué manda. Esto NO cambia cómo funciona el anillo hoy: solo mira y anota.
///   1. Busca lo que está conectado al iPhone (HID 0x1812, batería 0x180F, información 0x180A y los del QRing) y lo que se
///      anuncia cerca, con nombre y fuerza de señal. Juan toca el suyo.
///   2. Se conecta con su propio gestor de Bluetooth (no toca el de Anillo.swift), descubre todos los servicios y
///      características, se suscribe a las que avisan y lee las que se pueden leer. El registro en vivo: hora, servicio,
///      característica y bytes en hex, con las marcas de Juan («1 toque», «2 toques», «largo»).
///   3. «Mandar al Hub»: el registro sin datos personales (DiagnosticoAnilloPuro.swift) va al Hub (action anilloBle), que
///      lo guarda en ANILLO_BLE_<clave> y Claude lo lee con «anillo» (campo ble) para mapear los toques (paso 2).
/// iOS no deja leer el servicio HID desde una app: si el anillo solo es eso, la pantalla lo dice claro.
final class DiagnosticoAnillo: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    struct Visto: Identifiable {
        let id: UUID
        var nombre: String
        var senal: Int
        var porHID: Bool
        let p: CBPeripheral
    }
    enum Fase: Equatable { case inicio, buscando, elegir, conectando, leyendo, escuchando, desconectado, error(String) }

    @Published var fase: Fase = .inicio
    @Published var vistos: [Visto] = []
    @Published var lineas: [String] = []
    @Published var veredicto: DiagAnillo.Veredicto?
    @Published var textoVeredicto = ""
    @Published var envio = ""
    @Published var enviando = false
    @Published var nombre = ""
    @Published var cuantos = 0   // datos que mandó el anillo solo

    private var central: CBCentralManager?
    private var elegido: CBPeripheral?
    private var inicio = Date()
    private var disp = DiagAnillo.Dispositivo()
    private var servicios: [DiagAnillo.Servicio] = []
    private var eventos: [DiagAnillo.Evento] = []
    private var marcas: [DiagAnillo.Marca] = []
    private var porLeer = Set<String>()
    private var serviciosPendientes = 0
    private var finBusqueda: DispatchWorkItem?

    static let hid = CBUUID(string: "1812")
    static let conocidos = [CBUUID(string: "180F"), CBUUID(string: "180A"), Anillo.servicio, Anillo.servicio2]

    // MARK: - Lo que pide la pantalla

    func empezar() {
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }   // sin restauración: no es el del anillo
        else { buscar() }
    }

    func buscar() {
        guard let c = central, c.state == .poweredOn else { return }
        if elegido != nil { soltar() }
        vistos = []; fase = .buscando
        // Lo que ya está conectado al iPhone no se anuncia: se pide al sistema. Primero por HID, para saber si es teclado.
        for p in c.retrieveConnectedPeripherals(withServices: [DiagnosticoAnillo.hid]) { agregar(p, nombre: p.name ?? "", senal: 0, porHID: true) }
        for p in c.retrieveConnectedPeripherals(withServices: DiagnosticoAnillo.conocidos) { agregar(p, nombre: p.name ?? "", senal: 0, porHID: false) }
        c.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        finBusqueda?.cancel()
        let fin = DispatchWorkItem { [weak self] in
            guard let self, self.fase == .buscando else { return }
            self.central?.stopScan(); self.fase = .elegir
        }
        finBusqueda = fin
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: fin)
    }

    func elegir(_ v: Visto) {
        guard let c = central else { return }
        finBusqueda?.cancel(); c.stopScan()
        elegido = v.p; v.p.delegate = self
        disp = DiagAnillo.Dispositivo(); disp.nombre = v.nombre; disp.senal = v.senal; disp.porHID = v.porHID
        servicios = []; eventos = []; marcas = []; porLeer = []; lineas = []; cuantos = 0
        veredicto = nil; textoVeredicto = ""; envio = ""
        nombre = v.nombre.isEmpty ? "Sin nombre" : v.nombre
        inicio = Date(); fase = .conectando
        anotar("Conectando con " + nombre + "…")
        c.connect(v.p, options: nil)
    }

    func marcar(_ gesto: String) {
        guard elegido != nil else { return }
        let t = Date().timeIntervalSince(inicio)
        marcas.append(DiagAnillo.Marca(t: t, gesto: gesto))
        anotar("— Marca: " + gesto + " —")
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Al cerrar la pantalla: deja de buscar y suelta solo su propia conexión (la del anillo de Health sigue igual).
    func soltar() {
        finBusqueda?.cancel()
        central?.stopScan()
        if let p = elegido, let c = central { c.cancelPeripheralConnection(p) }
        elegido = nil
    }

    var registro: [String: Any] {
        let v = Bundle.main.infoDictionary
        let app = (v?["CFBundleShortVersionString"] as? String ?? "") + " (" + (v?["CFBundleVersion"] as? String ?? "") + ")"
        return DiagAnillo.recortar(DiagAnillo.registro(disp, servicios: servicios, eventos: eventos, marcas: marcas, fecha: Date(), app: app))
    }

    /// «Mandar al Hub»: por el mismo canal que los avisos de la voz (la sesión que la app guardó en su llavero).
    func mandar() {
        guard let url = Llave.leer("voz_url"), let token = Llave.leer("voz_token"), let sesion = Llave.leer("voz_sesion"), let u = URL(string: url) else {
            envio = "Abre el inicio de Alma con tu sesión y vuelve a intentar."; return
        }
        enviando = true; envio = "Mandando…"
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type"); r.timeoutInterval = 30
        let cuerpo: [String: Any] = ["hub": 1, "action": "anilloBle", "token": token, "session": sesion, "diagnostico": registro]
        r.httpBody = try? JSONSerialization.data(withJSONObject: cuerpo)
        URLSession.shared.dataTask(with: r) { [weak self] data, _, error in
            let j = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async {
                guard let self else { return }
                self.enviando = false
                if (j?["ok"] as? Bool) == true { self.envio = "Listo: el Hub lo guardó. Claude ya lo puede leer." }
                else { self.envio = "No se pudo mandar: " + ((j?["error"] as? String) ?? error?.localizedDescription ?? "sin respuesta") }
            }
        }.resume()
    }

    // MARK: - Bluetooth

    private func agregar(_ p: CBPeripheral, nombre: String, senal: Int, porHID: Bool) {
        if let i = vistos.firstIndex(where: { $0.id == p.identifier }) {
            if porHID { vistos[i].porHID = true }
            if senal != 0 { vistos[i].senal = senal }
            return
        }
        vistos.append(Visto(id: p.identifier, nombre: nombre, senal: senal, porHID: porHID, p: p))
        // Lo conectado al iPhone primero; luego lo más cerca.
        vistos.sort { a, b in (a.senal == 0) != (b.senal == 0) ? a.senal == 0 : a.senal > b.senal }
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn: if fase == .inicio || fase == .buscando { buscar() }
        case .unauthorized: fase = .error("Alma no tiene permiso de Bluetooth. Ábrelo en Ajustes del iPhone → Alma → Bluetooth.")
        case .poweredOff: fase = .error("El Bluetooth está apagado. Enciéndelo y vuelve a intentar.")
        case .unsupported: fase = .error("Este teléfono no tiene Bluetooth para esto.")
        default: break
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData ad: [String: Any], rssi: NSNumber) {
        let nombre = p.name ?? (ad[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        guard !nombre.isEmpty else { return }   // sin nombre son decenas (audífonos, relojes de otros): no se listan
        let servs = (ad[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let r = rssi.intValue
        agregar(p, nombre: nombre, senal: r == 127 ? 0 : r, porHID: servs.contains(DiagnosticoAnillo.hid))
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        guard p == elegido else { return }
        fase = .leyendo
        anotar("Conectado. Buscando sus servicios…")
        p.readRSSI()
        p.discoverServices(nil)
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        guard p == elegido else { return }
        fase = .error("No se pudo conectar: " + (error?.localizedDescription ?? "sin motivo"))
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        guard p == elegido else { return }
        anotar("Se desconectó" + (error.map { ": " + $0.localizedDescription } ?? "."))
        fase = .desconectado
    }

    func peripheral(_ p: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if error == nil { disp.senal = RSSI.intValue }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        let ss = p.services ?? []
        anotar("Servicios: " + (ss.isEmpty ? "ninguno a la vista" : ss.map { DiagAnillo.corto($0.uuid.uuidString) }.joined(separator: ", ")))
        serviciosPendientes = ss.count
        if ss.isEmpty { decidir(); return }
        for s in ss {
            servicios.append(DiagAnillo.Servicio(uuid: s.uuid.uuidString))
            p.discoverCharacteristics(nil, for: s)
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        let su = s.uuid.uuidString
        var cars: [DiagAnillo.Caracteristica] = []
        for ch in s.characteristics ?? [] {
            let props = DiagnosticoAnillo.props(ch.properties)
            cars.append(DiagAnillo.Caracteristica(uuid: ch.uuid.uuidString, props: props))
            if props.contains("notify") || props.contains("indicate") { p.setNotifyValue(true, for: ch) }
            // Se lee todo lo legible, menos el nombre del aparato (2A00, puede llevar el de una persona) y el número de serie (2A25).
            let cu = DiagAnillo.corto(ch.uuid.uuidString)
            if props.contains("read"), cu != "2A00", cu != "2A25" { porLeer.insert(su + "|" + ch.uuid.uuidString); p.readValue(for: ch) }
        }
        if let i = servicios.firstIndex(where: { $0.uuid == su }) { servicios[i].caracteristicas = cars }
        anotar(DiagAnillo.corto(su) + " (" + DiagAnillo.nombreServicio(su) + "): " + (cars.isEmpty ? "sin características" : cars.map { DiagAnillo.corto($0.uuid) + " " + $0.props.joined(separator: "/") }.joined(separator: ", ")))
        serviciosPendientes -= 1
        if serviciosPendientes <= 0 { decidir() }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        if let e = error { anotar("No avisa " + DiagAnillo.corto(ch.uuid.uuidString) + ": " + e.localizedDescription) }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let su = ch.service?.uuid.uuidString, let v = ch.value else { return }
        let b = [UInt8](v), h = DiagAnillo.hex(b), clave = su + "|" + ch.uuid.uuidString
        if porLeer.remove(clave) != nil {
            // Lo leído (una vez): va a su característica, y la información del dispositivo, en texto.
            if let i = servicios.firstIndex(where: { $0.uuid == su }), let k = servicios[i].caracteristicas.firstIndex(where: { $0.uuid == ch.uuid.uuidString }) {
                servicios[i].caracteristicas[k].valor = h
            }
            switch DiagAnillo.corto(ch.uuid.uuidString) {
            case "2A29": disp.fabricante = DiagAnillo.texto(b) ?? ""
            case "2A24": disp.modelo = DiagAnillo.texto(b) ?? ""
            case "2A26", "2A28": if disp.firmware.isEmpty { disp.firmware = DiagAnillo.texto(b) ?? "" }
            default: break
            }
            anotar("Leído " + DiagAnillo.corto(ch.uuid.uuidString) + ": " + (DiagAnillo.texto(b) ?? DiagAnillo.hexEspaciado(h)))
            return
        }
        // Lo que el anillo mandó solo: es lo que interesa para los toques.
        let t = Date().timeIntervalSince(inicio)
        eventos.append(DiagAnillo.Evento(t: t, servicio: su, caracteristica: ch.uuid.uuidString, hex: h))
        if eventos.count > DiagAnillo.maxEventos { eventos.removeFirst(eventos.count - DiagAnillo.maxEventos) }
        cuantos += 1
        anotar(DiagAnillo.linea(hora: Date(), servicio: su, caracteristica: ch.uuid.uuidString, hex: h), hora: false)
    }

    private func decidir() {
        let v = DiagAnillo.veredicto(servicios, porHID: disp.porHID)
        veredicto = v; textoVeredicto = DiagAnillo.textoVeredicto(v, servicios, porHID: disp.porHID)
        anotar("Veredicto: " + textoVeredicto)
        fase = .escuchando
    }

    static func props(_ p: CBCharacteristicProperties) -> [String] {
        var r: [String] = []
        if p.contains(.read) { r.append("read") }
        if p.contains(.write) { r.append("write") }
        if p.contains(.writeWithoutResponse) { r.append("writeNR") }
        if p.contains(.notify) { r.append("notify") }
        if p.contains(.indicate) { r.append("indicate") }
        return r
    }

    private func anotar(_ s: String, hora: Bool = true) {
        lineas.insert(hora ? DiagAnillo.reloj.string(from: Date()) + " · " + s : s, at: 0)
        if lineas.count > 150 { lineas.removeLast(lineas.count - 150) }
    }
}

extension Notification.Name {
    /// Ajustes → Alma con el anillo → «Diagnóstico del anillo (Bluetooth)» (Puente: accion "anilloBle").
    static let abrirDiagnosticoAnillo = Notification.Name("alma.anillo.diagnostico")
}

// MARK: - Pantalla (el estilo de Ajustes del anillo: Health/SaludVista.swift)

struct DiagnosticoAnilloVista: View {
    @StateObject private var d = DiagnosticoAnillo()
    @Environment(\.dismiss) private var cerrar

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Etiqueta("Alma con el anillo")
                    Spacer()
                    Button { d.soltar(); cerrar() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .medium)).frame(width: 40, height: 40)
                            .background(Circle().fill(Tinta.tinta.opacity(0.06)))
                    }.accessibilityLabel("Cerrar")
                }.padding(.top, 14)
                Text("Diagnóstico del anillo").font(Tipo.serif(36))
                Text("Mira qué manda tu anillo por Bluetooth. No cambia cómo funciona hoy.").font(Tipo.sans(13)).foregroundStyle(Tinta.suave)
                switch d.fase {
                case .inicio, .buscando, .elegir: lista
                case .error(let m):
                    aviso(m)
                    BotonClaro("Buscar otra vez") { d.buscar() }
                default: conectado
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 30)
        }
        .foregroundStyle(Tinta.tinta).background(Tinta.papel.ignoresSafeArea())
        .onAppear { d.empezar() }
        .onDisappear { d.soltar() }
    }

    @ViewBuilder private var lista: some View {
        Etiqueta(d.fase == .elegir ? "Toca el tuyo" : "Buscando…", punto: d.fase != .elegir).padding(.top, 10)
        if d.vistos.isEmpty && d.fase == .elegir {
            aviso("No apareció nada. Acerca el anillo al teléfono y vuelve a buscar.")
        }
        ForEach(d.vistos) { v in
            Fila(v.nombre.isEmpty ? "Sin nombre" : v.nombre, DiagAnillo.senal(v.senal) + (v.porHID ? " · teclado o control" : "")) {
                Text("›").font(Tipo.sans(18)).foregroundStyle(Tinta.suave)
            }.boton { d.elegir(v) }
        }
        if d.fase == .elegir { BotonClaro("Buscar otra vez") { d.buscar() }.padding(.top, 6) }
    }

    @ViewBuilder private var conectado: some View {
        Fila(d.nombre, estado) { Text("\(d.cuantos)").font(Tipo.serif(24, .medium)).accessibilityLabel("\(d.cuantos) datos") }
        if !d.textoVeredicto.isEmpty { aviso(d.textoVeredicto, fuerte: d.veredicto == .soloHID) }
        Etiqueta("Haz esto").padding(.top, 8)
        Text("Toca el anillo una vez, espera, dos veces, espera, mantén presionado. Después de cada gesto, márcalo aquí.")
            .font(Tipo.sans(13.5)).fixedSize(horizontal: false, vertical: true)
        Etiqueta("Marcar").padding(.top, 4)
        HStack(spacing: 8) {
            ForEach(DiagAnillo.gestos, id: \.self) { g in BotonClaro(g == "largo" ? "Largo" : g) { d.marcar(g) } }
        }
        Etiqueta("Registro en vivo").padding(.top, 8)
        VStack(alignment: .leading, spacing: 4) {
            if d.lineas.isEmpty { Text("Todavía nada.").foregroundStyle(Tinta.suave) }
            ForEach(Array(d.lineas.prefix(80).enumerated()), id: \.offset) { _, l in Text(l).fixedSize(horizontal: false, vertical: true) }
        }
        .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(.white))
        BotonClaro(d.enviando ? "Mandando…" : "Mandar al Hub") { if !d.enviando { d.mandar() } }.padding(.top, 6)
        if !d.envio.isEmpty { Text(d.envio).font(Tipo.sans(12)).foregroundStyle(Tinta.suave).frame(maxWidth: .infinity) }
        BotonClaro("Elegir otro") { d.buscar() }
    }

    private var estado: String {
        switch d.fase {
        case .conectando: return "Conectando…"
        case .leyendo: return "Leyendo sus servicios…"
        case .escuchando: return "Escuchando · datos que mandó solo"
        case .desconectado: return "Se desconectó"
        default: return ""
        }
    }

    private func aviso(_ t: String, fuerte: Bool = false) -> some View {
        Text(t).font(Tipo.sans(13.5, fuerte ? .semibold : .regular))
            .foregroundStyle(fuerte ? Color(hex: 0xB5624E) : Tinta.tinta)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(RoundedRectangle(cornerRadius: 18).fill(.white))
    }
}
