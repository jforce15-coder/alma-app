import AVFoundation
import AVKit
import CoreBluetooth
import SwiftUI

/// Los lentes de audio de Juan (iTOUCH AURA, versión sin cámara; Juan, 16-nov-2026). Lo que iOS deja saber:
/// · Si están conectados como audio (AVAudioSession): si son la salida de ahora, o si aparecen como micrófono Bluetooth.
/// · Su batería NO: son audífonos Bluetooth clásicos (A2DP/HFP) y iOS no da esa batería a las apps (solo al sistema:
///   widget de Baterías). Si algún día anuncian un servicio BLE de batería (180F), se lee de ahí; si no, «no disponible».
/// Nada se inventa: sin dato, la pantalla Wearables lo dice así. El nombre de los lentes se reconoce con LentesDatos.
final class Lentes: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = Lentes()

    @Published private(set) var nombre = ""
    @Published private(set) var sonSalida = false        // el audio de ahora sale por los lentes
    @Published private(set) var conectados = false       // aparecen como salida o como micrófono Bluetooth
    @Published private(set) var bateria: Int?            // solo si exponen 180F por BLE
    @Published private(set) var porBLE = false           // se encontraron también por Bluetooth de baja energía
    @Published private(set) var salidaAhora = ""         // nombre de la salida de audio actual (para el detalle)

    private var central: CBCentralManager?
    private var periferico: CBPeripheral?
    private static let bateriaServicio = CBUUID(string: "180F"), nivel = CBUUID(string: "2A19")

    override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.mirarAudio() }
        mirarAudio()
    }

    /// La ruta de audio: salida actual y micrófonos Bluetooth disponibles.
    func mirarAudio() {
        let s = AVAudioSession.sharedInstance()
        let salidas = s.currentRoute.outputs
        salidaAhora = salidas.map { $0.portName }.joined(separator: ", ")
        let bt: Set<AVAudioSession.Port> = [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE]
        let suya = salidas.first { bt.contains($0.portType) && LentesDatos.sonLentes($0.portName) }
        let entrada = (s.availableInputs ?? []).first { $0.portType == .bluetoothHFP && LentesDatos.sonLentes($0.portName) }
        sonSalida = suya != nil
        conectados = suya != nil || entrada != nil || porBLE
        if let n = suya?.portName ?? entrada?.portName { nombre = n; UserDefaults.standard.set(n, forKey: "lentes_nombre") }
        else if nombre.isEmpty { nombre = UserDefaults.standard.string(forKey: "lentes_nombre") ?? "" }
    }

    /// Al abrir Wearables: busca los lentes por Bluetooth de baja energía (conectados al iPhone o anunciándose) por si
    /// exponen su batería. Diez segundos y se detiene.
    func buscarBLE() {
        mirarAudio()
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) } else { centralManagerDidUpdateState(central!) }
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        guard c.state == .poweredOn else { return }
        let ya = c.retrieveConnectedPeripherals(withServices: [Lentes.bateriaServicio, CBUUID(string: "180A"), CBUUID(string: "1812")])
        if let p = ya.first(where: { LentesDatos.sonLentes($0.name ?? "") }) { usar(p); return }
        c.scanForPeripherals(withServices: nil, options: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak c] in c?.stopScan() }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData ad: [String: Any], rssi: NSNumber) {
        let n = p.name ?? (ad[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        guard LentesDatos.sonLentes(n), periferico == nil else { return }
        c.stopScan(); usar(p)
    }

    private func usar(_ p: CBPeripheral) {
        periferico = p; p.delegate = self; porBLE = true
        if nombre.isEmpty, let n = p.name { nombre = n }
        conectados = true
        central?.connect(p, options: nil)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) { p.discoverServices([Lentes.bateriaServicio]) }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        p.services?.filter { $0.uuid == Lentes.bateriaServicio }.forEach { p.discoverCharacteristics([Lentes.nivel], for: $0) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        s.characteristics?.filter { $0.uuid == Lentes.nivel }.forEach { p.readValue(for: $0) }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        if ch.uuid == Lentes.nivel, let b = ch.value?.first, b <= 100 { bateria = Int(b) }
    }
}

/// El botón de iOS para elegir por dónde sale el audio (los lentes, el teléfono, otros audífonos). Las apps no pueden
/// cambiar la salida Bluetooth por su cuenta: Juan la elige aquí.
struct ElegirSalida: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView(); v.tintColor = UIColor(Tinta.tinta); v.activeTintColor = UIColor(Tinta.peach); v.prioritizesVideoDevices = false
        return v
    }
    func updateUIView(_ v: AVRoutePickerView, context: Context) {}
}
