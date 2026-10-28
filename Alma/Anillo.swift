import CoreBluetooth
import Foundation

/// El anillo QRing (Colmi / Yawell) conectado directo a la app, sin la app del anillo.
/// · Se conecta por Bluetooth y sigue conectado con el teléfono bloqueado (modo de fondo bluetooth-central).
/// · Comandos de 16 bytes: [comando, 14 bytes de datos, suma de los 15 anteriores]. Lo conocido del protocolo viene de
///   la prueba del Hub (hub.spacioam.com/anillo/) y de los proyectos abiertos que lo documentan (Gadgetbridge, colmi_r02_client).
/// · Todo lo que manda el anillo se registra crudo (diagnóstico): así se ve qué avisa al tocarlo, también bloqueado.
/// La página Health (hub.spacioam.com) lo usa por el puente: Puente.swift → accion "anillo".
final class Anillo: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = Anillo()
    /// Si ya hay un anillo guardado, al abrir la app se reconecta (y iOS puede despertarla por él en segundo plano).
    static var hayGuardado: Bool { UserDefaults.standard.string(forKey: "anillo_uuid") != nil }

    static let servicio = CBUUID(string: "6E40FFF0-B5A3-F393-E0A9-E50E24DCCA9E")
    static let escribir = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    static let avisa = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    static let servicio2 = CBUUID(string: "DE5BF728-D711-4E47-AF26-65E3012A5DC7")
    static let escribir2 = CBUUID(string: "DE5BF72A-D711-4E47-AF26-65E3012A5DC7")
    static let avisa2 = CBUUID(string: "DE5BF729-D711-4E47-AF26-65E3012A5DC7")

    /// Quien escucha (la página Health): recibe cada evento como diccionario listo para JSON.
    var alEvento: (([String: Any]) -> Void)?

    private var central: CBCentralManager!
    private var anillo: CBPeripheral?
    private var canal: CBCharacteristic?
    private var buscando = false
    private var vistos: [UUID: CBPeripheral] = [:]
    private var registro: [[String: Any]] = []
    private var ultimoComando = Date.distantPast
    private let claveGuardado = "anillo_uuid"

    override init() {
        super.init()
        // Identificador de restauración: si iOS cierra la app en segundo plano, la vuelve a despertar con el anillo.
        central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionRestoreIdentifierKey: "alma.anillo"])
    }

    // MARK: - Lo que pide la página

    var estado: [String: Any] {
        ["bluetooth": central.state == .poweredOn, "conectado": anillo?.state == .connected,
         "nombre": anillo?.name ?? UserDefaults.standard.string(forKey: "anillo_nombre") ?? "",
         "guardado": UserDefaults.standard.string(forKey: claveGuardado) != nil, "buscando": buscando]
    }

    /// Busca anillos cercanos (o se reconecta al guardado).
    func buscar() {
        guard central.state == .poweredOn else { emitirEstado(); return }
        if reconectarGuardado() { return }
        buscando = true; vistos = [:]
        // Un anillo que ya está conectado al iPhone (la app QRing, o Ajustes → Bluetooth) no se anuncia: se pide al sistema
        // la lista de los que ya están conectados y Alma se une a esa misma conexión.
        let yaConectados = central.retrieveConnectedPeripherals(withServices: [Anillo.servicio, Anillo.servicio2, CBUUID(string: "180F"), CBUUID(string: "1812"), CBUUID(string: "180A")])
        for p in yaConectados where Anillo.pareceAnillo(p.name ?? "", []) && vistos[p.identifier] == nil {
            vistos[p.identifier] = p
            emitir(["tipo": "encontrado", "id": p.identifier.uuidString, "nombre": p.name ?? "Anillo", "senal": 0, "yaConectado": true])
        }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        emitir(["tipo": "buscando"])
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, self.buscando else { return }
            self.central.stopScan(); self.buscando = false; self.emitir(["tipo": "busqueda_fin"])
        }
    }

    func elegir(_ id: String) {
        guard let u = UUID(uuidString: id), let p = vistos[u] ?? central.retrievePeripherals(withIdentifiers: [u]).first else { return }
        central.stopScan(); buscando = false
        conectar(p)
    }

    func olvidar() {
        if let a = anillo { central.cancelPeripheralConnection(a) }
        anillo = nil; canal = nil
        UserDefaults.standard.removeObject(forKey: claveGuardado); UserDefaults.standard.removeObject(forKey: "anillo_nombre")
        emitirEstado()
    }

    /// Comandos con nombre (la página no arma bytes).
    func comando(_ nombre: String, _ d: [String: Any]) {
        switch nombre {
        case "hora": mandar(Anillo.paqueteHora())
        case "bateria": mandar([0x03])
        case "buscarAnillo": mandar([0x10])                                   // el anillo parpadea
        case "ritmoAhora": mandar([0x69, 0x01, 0x01])                        // ritmo cardíaco en vivo
        case "oxigenoAhora": mandar([0x69, 0x03, 0x01])                      // oxígeno en sangre en vivo
        case "pararMedicion": mandar([0x6A, (d["tipo"] as? Int).map { UInt8(truncatingIfNeeded: $0) } ?? 0x01, 0x00, 0x00])
        case "ritmoAjustes": mandar([0x16, 0x01])                            // leer: activo y cada cuántos minutos
        case "ritmoGuardar":
            let on = (d["activo"] as? Bool) ?? true, minutos = UInt8(Swift.max(5, Swift.min(60, (d["minutos"] as? Int) ?? 30)))
            mandar([0x16, 0x02, on ? 0x01 : 0x02, minutos])
        case "pasos": mandar([0x43, UInt8(Swift.max(0, Swift.min(6, (d["dia"] as? Int) ?? 0))), 0x0F, 0x00, 0x5F, 0x01])
        case "ritmoHistorial":
            var t = UInt32(Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(-86400 * ((d["dia"] as? Int) ?? 0))).timeIntervalSince1970)
            let b = withUnsafeBytes(of: &t) { Array($0) }
            mandar([0x15] + b)
        case "crudo":
            if let h = d["hex"] as? String { mandar(Anillo.bytes(h)) }
        default: break
        }
    }

    /// Lo que llegó desde que se abrió (para subirlo al Hub y leerlo).
    func tomarRegistro() -> [[String: Any]] { defer { registro = [] }; return registro }

    // MARK: - Bluetooth

    @discardableResult
    private func reconectarGuardado() -> Bool {
        guard let s = UserDefaults.standard.string(forKey: claveGuardado), let u = UUID(uuidString: s),
              let p = central.retrievePeripherals(withIdentifiers: [u]).first else { return false }
        conectar(p); return true
    }

    private func conectar(_ p: CBPeripheral) {
        anillo = p; p.delegate = self
        // Conexión «pendiente»: iOS la mantiene y la retoma sola cuando el anillo vuelve a estar cerca, aun bloqueado.
        central.connect(p, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: false])
        emitir(["tipo": "conectando", "nombre": p.name ?? ""])
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        emitirEstado()
        if c.state == .poweredOn, anillo == nil { reconectarGuardado() }
    }

    func centralManager(_ c: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let ps = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral], let p = ps.first { anillo = p; p.delegate = self }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData ad: [String: Any], rssi: NSNumber) {
        let nombre = p.name ?? (ad[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        let servicios = (ad[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        guard !nombre.isEmpty, Anillo.pareceAnillo(nombre, servicios), vistos[p.identifier] == nil else { return }
        vistos[p.identifier] = p
        emitir(["tipo": "encontrado", "id": p.identifier.uuidString, "nombre": nombre, "senal": rssi.intValue])
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        UserDefaults.standard.set(p.identifier.uuidString, forKey: claveGuardado)
        UserDefaults.standard.set(p.name ?? "", forKey: "anillo_nombre")
        p.discoverServices([Anillo.servicio, Anillo.servicio2])
        emitir(["tipo": "conectado", "nombre": p.name ?? ""])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        emitir(["tipo": "error", "mensaje": error?.localizedDescription ?? "No se pudo conectar"])
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        canal = nil
        emitir(["tipo": "desconectado"])
        // Se queda esperando: en cuanto vuelva a estar cerca, se reconecta solo.
        if UserDefaults.standard.string(forKey: claveGuardado) == p.identifier.uuidString { central.connect(p, options: nil) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        p.services?.forEach { p.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            if ch.uuid == Anillo.escribir { canal = ch }
            if ch.properties.contains(.notify) || ch.properties.contains(.indicate) { p.setNotifyValue(true, for: ch) }
        }
        if s.uuid == Anillo.servicio, canal != nil {
            // Al conectar: la hora del teléfono, la batería y los ajustes del ritmo cardíaco.
            mandar(Anillo.paqueteHora())
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.mandar([0x03]) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.mandar([0x16, 0x01]) }
            emitir(["tipo": "listo", "nombre": p.name ?? ""])
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let v = ch.value, !v.isEmpty else { return }
        let b = [UInt8](v), hex = b.map { String(format: "%02x", $0) }.joined()
        // ¿Lo mandó el anillo por su cuenta (sin que le pidiéramos nada)? Es lo que interesa para los toques.
        let solo = Date().timeIntervalSince(ultimoComando) > 1.5
        let ev: [String: Any] = ["t": Date().timeIntervalSince1970, "canal": String(ch.uuid.uuidString.prefix(8)), "hex": hex, "solo": solo]
        registro.append(ev); if registro.count > 500 { registro.removeFirst(registro.count - 500) }
        var e = interpretar(b); e["hex"] = hex; e["solo"] = solo
        emitir(e)
    }

    // MARK: - Paquetes

    private func mandar(_ datos: [UInt8]) {
        guard let p = anillo, p.state == .connected, let ch = canal else { emitir(["tipo": "sin_conexion"]); return }
        var b = Array(datos.prefix(15)); while b.count < 15 { b.append(0) }
        b.append(UInt8(b.reduce(0) { ($0 + Int($1)) } & 0xFF))
        ultimoComando = Date()
        p.writeValue(Data(b), for: ch, type: ch.properties.contains(.write) ? .withResponse : .withoutResponse)
    }

    static func pareceAnillo(_ nombre: String, _ servicios: [CBUUID]) -> Bool {
        servicios.contains(Anillo.servicio) || ["R0", "R1", "R2", "COLMI", "QRING", "RING", "YAWELL"].contains { nombre.uppercased().contains($0) }
    }

    static func bytes(_ h: String) -> [UInt8] {
        var out: [UInt8] = [], s = Substring(h.filter { $0.isHexDigit })
        while s.count >= 2 { out.append(UInt8(s.prefix(2), radix: 16) ?? 0); s = s.dropFirst(2) }
        return out
    }

    private static func bcd(_ n: Int) -> UInt8 { UInt8(((n / 10) << 4) | (n % 10)) }

    static func paqueteHora() -> [UInt8] {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
        return [0x01, bcd((c.year ?? 2026) % 100), bcd(c.month ?? 1), bcd(c.day ?? 1), bcd(c.hour ?? 0), bcd(c.minute ?? 0), bcd(c.second ?? 0), 0x01]
    }

    /// Lo que se sabe leer; lo demás llega como «paquete» con sus bytes.
    private var pasosDia: (calorias: Int, pasos: Int, metros: Int) = (0, 0, 0)
    private func interpretar(_ b: [UInt8]) -> [String: Any] {
        let u16 = { (i: Int) -> Int in b.count > i + 1 ? Int(b[i]) | Int(b[i + 1]) << 8 : 0 }
        switch b[0] {
        case 0x03 where b.count > 2: return ["tipo": "bateria", "nivel": Int(b[1]), "cargando": b[2] != 0]
        case 0x16 where b.count > 3: return ["tipo": "ritmoAjustes", "activo": b[2] == 0x01, "minutos": Int(b[3])]
        case 0x69 where b.count > 3:
            if b[2] != 0 { return ["tipo": "medicion_error", "medida": Int(b[1]), "codigo": Int(b[2])] }
            return ["tipo": b[1] == 0x03 ? "oxigeno" : "ritmo", "valor": Int(b[3])]
        case 0x43 where b.count > 12:
            if b[1] == 0xF0 { pasosDia = (0, 0, 0); return ["tipo": "pasos_inicio"] }
            if b[1] == 0xFF { return ["tipo": "pasos", "pasos": 0, "calorias": 0, "metros": 0, "fin": true] }
            pasosDia.calorias += u16(7); pasosDia.pasos += u16(9); pasosDia.metros += u16(11)
            let fin = Int(b[5]) + 1 >= Int(b[6])
            return ["tipo": "pasos", "pasos": pasosDia.pasos, "calorias": pasosDia.calorias, "metros": pasosDia.metros, "fin": fin]
        case 0x01: return ["tipo": "hora_ok"]
        default: return ["tipo": "paquete", "comando": Int(b[0])]
        }
    }

    private func emitir(_ e: [String: Any]) { alEvento?(e) }
    private func emitirEstado() { var e = estado; e["tipo"] = "estado"; emitir(e) }
}
