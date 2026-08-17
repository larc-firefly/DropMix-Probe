import AppKit
import CoreBluetooth
import SwiftUI

/// A small, deliberately read-only control surface for the DropMix board.
/// It provides connection visibility without pretending that card data has
/// been decoded before protected GATT access is available.
@MainActor
final class DropMixDashboardModel: NSObject, ObservableObject {
    enum ConnectionState: String {
        case bluetoothOff = "Bluetooth is off"
        case waiting = "Waiting for Bluetooth"
        case scanning = "Scanning for DropMix"
        case connecting = "Connecting"
        case discovering = "Discovering board services"
        case authenticationRequired = "Pairing / authentication required"
        case ready = "Connected"
        case disconnected = "Disconnected"
        case failed = "Connection failed"

        var color: Color {
            switch self {
            case .bluetoothOff, .failed: .red
            case .waiting, .disconnected: .secondary
            case .scanning: .blue
            case .connecting, .discovering: .cyan
            case .authenticationRequired: .orange
            case .ready: .green
            }
        }
    }

    struct Candidate: Identifiable, Equatable {
        let id: UUID
        let name: String
        var rssi: Int
    }

    enum SlotState {
        case waiting
        case blocked
        case present

        var color: Color {
            switch self {
            case .waiting: .blue
            case .blocked: .orange
            case .present: .green
            }
        }

        var label: String {
            switch self {
            case .waiting: "Waiting"
            case .blocked: "Pair board"
            case .present: "Card present"
            }
        }
    }

    @Published private(set) var connectionState: ConnectionState = .waiting
    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var eventLog: [String] = []
    @Published private(set) var slots = Array(repeating: SlotState.waiting, count: 5)
    @Published private(set) var connectedBoardName: String?

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var didProbeProtectedAccess = false

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScanning() {
        guard central.state == .poweredOn else {
            connectionState = .bluetoothOff
            addEvent("Bluetooth is not powered on.")
            return
        }
        candidates.removeAll()
        peripherals.removeAll()
        connectionState = .scanning
        addEvent("Scanning — select a discovered DropMix board to connect.")
        central.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ])
    }

    func connect(to candidate: Candidate) {
        guard let peripheral = peripherals[candidate.id] else { return }
        central.stopScan()
        connectedPeripheral = peripheral
        didProbeProtectedAccess = false
        connectedBoardName = candidate.name
        connectionState = .connecting
        slots = Array(repeating: .waiting, count: 5)
        addEvent("Connecting to \(candidate.name)…")
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        guard let connectedPeripheral else { return }
        central.cancelPeripheralConnection(connectedPeripheral)
    }

    private func addEvent(_ text: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        eventLog.insert("\(timestamp)  \(text)", at: 0)
        eventLog = Array(eventLog.prefix(12))
    }

    private func setAuthenticationRequired(_ message: String) {
        connectionState = .authenticationRequired
        slots = Array(repeating: .blocked, count: 5)
        addEvent(message)
    }
}

extension DropMixDashboardModel: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            connectionState = central.state == .poweredOff ? .bluetoothOff : .waiting
            addEvent("Bluetooth central state changed: \(central.state.rawValue).")
            return
        }
        startScanning()
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "Unnamed BLE device"
        // Do not connect automatically. The broad list helps identify boards
        // whose advertisement does not include their product name.
        peripherals[peripheral.identifier] = peripheral
        let candidate = Candidate(id: peripheral.identifier, name: name, rssi: RSSI.intValue)
        if let index = candidates.firstIndex(where: { $0.id == candidate.id }) {
            candidates[index] = candidate
        } else {
            candidates.append(candidate)
            candidates.sort { lhs, rhs in
                let lhsLooksLikeDropMix = lhs.name.localizedCaseInsensitiveContains("dropmix")
                let rhsLooksLikeDropMix = rhs.name.localizedCaseInsensitiveContains("dropmix")
                if lhsLooksLikeDropMix != rhsLooksLikeDropMix { return lhsLooksLikeDropMix }
                return lhs.rssi > rhs.rssi
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionState = .discovering
        addEvent("Connected. Discovering services…")
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionState = .failed
        addEvent("Connection failed: \(error?.localizedDescription ?? "unknown error")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedPeripheral = nil
        connectionState = .disconnected
        slots = Array(repeating: .waiting, count: 5)
        addEvent(error.map { "Disconnected: \($0.localizedDescription)" } ?? "Disconnected.")
    }
}

extension DropMixDashboardModel: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            connectionState = .failed
            addEvent("Service discovery failed: \(error!.localizedDescription)")
            return
        }
        let services = peripheral.services ?? []
        addEvent("Discovered \(services.count) GATT services.")
        services.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard error == nil else {
            addEvent("Characteristic discovery failed: \(error!.localizedDescription)")
            return
        }
        for characteristic in service.characteristics ?? [] {
            // A single safe protected read reports whether the OS already has
            // a usable encrypted/bonded link. No board values are written.
            if characteristic.uuid == ReportedUUIDs.authenticationProbe, !didProbeProtectedAccess {
                didProbeProtectedAccess = true
                addEvent("Checking protected board access…")
                peripheral.readValue(for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            let nsError = error as NSError
            if nsError.domain == CBATTErrorDomain,
               let code = CBATTError.Code(rawValue: nsError.code),
               code == .insufficientAuthentication || code == .insufficientEncryption {
                setAuthenticationRequired("Protected access is blocked. Pair/authenticate the board, then reconnect.")
            } else {
                connectionState = .failed
                addEvent("Protected access check failed: \(error.localizedDescription)")
            }
            return
        }
        if characteristic.uuid == ReportedUUIDs.authenticationProbe {
            connectionState = .ready
            addEvent("Protected GATT access confirmed. Card notifications are ready for decoder support.")
        }
    }
}

private struct DropMixDashboardView: View {
    @ObservedObject var model: DropMixDashboardModel

    var body: some View {
        VStack(spacing: 20) {
            header
            board
            connectionPanel
            eventPanel
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("DropMix Board")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Read-only connection and card-slot monitor")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(model.connectionState.rawValue, systemImage: "circle.fill")
                .foregroundStyle(model.connectionState.color)
                .fontWeight(.semibold)
        }
    }

    private var board: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Five-card board")
                .font(.headline)
            HStack(spacing: 16) {
                ForEach(Array(model.slots.enumerated()), id: \.offset) { index, state in
                    VStack(spacing: 10) {
                        Circle()
                            .fill(state.color.gradient)
                            .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 2))
                            .frame(width: 98, height: 98)
                            .shadow(color: state.color.opacity(0.55), radius: 12)
                            .overlay(Text("\(index + 1)").font(.title.bold()).foregroundStyle(.white))
                        Text(state.label)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(state.color)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text("Blue: waiting for card data  •  Orange: board needs pairing  •  Green: decoded card present")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var connectionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Nearby Bluetooth devices")
                    .font(.headline)
                Spacer()
                Button("Scan again") { model.startScanning() }
                if model.connectionState == .connecting || model.connectionState == .discovering || model.connectionState == .ready || model.connectionState == .authenticationRequired {
                    Button("Disconnect") { model.disconnect() }
                }
            }
            if model.candidates.isEmpty {
                Text("No devices found yet. Make sure the board is on, then scan again.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.candidates) { candidate in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(candidate.name).fontWeight(candidate.name.localizedCaseInsensitiveContains("dropmix") ? .bold : .regular)
                            Text("RSSI \(candidate.rssi) dBm").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Connect") { model.connect(to: candidate) }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var eventPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connection activity").font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(model.eventLog, id: \.self) { event in
                        Text(event).font(.caption.monospaced()).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(height: 120)
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

final class DropMixDashboardAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = DropMixDashboardModel()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DropMix Board Monitor"
        window.center()
        window.contentView = NSHostingView(rootView: DropMixDashboardView(model: model))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

func runDropMixDashboard() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = DropMixDashboardAppDelegate()
    app.delegate = delegate
    app.run()
}
