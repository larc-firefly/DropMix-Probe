import AppKit
import CoreBluetooth
import IOBluetooth
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
        case pairing = "Pairing with macOS"
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
            case .pairing: .purple
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
    @Published var pairingAddress = ""

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var pairingAttempt: IOBluetoothDevicePair?
    private var pendingSubscriptions = Set<CBUUID>()

    private static let subscriptionOrder = [
        CBUUID(string: "0003CFD4-2730-4BB8-B160-502596E4C2FE"),
        CBUUID(string: "0005CFD4-2730-4BB8-B160-502596E4C2FE"),
        CBUUID(string: "0004CFD4-2730-4BB8-B160-502596E4C2FE")
    ]

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
        pendingSubscriptions.removeAll()
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

    /// CoreBluetooth cannot create a BLE bond. This public macOS API is an
    /// explicit, one-shot bridge that requires a freshly observed Bluetooth
    /// address rather than a CoreBluetooth peripheral identifier.
    func pairUsingAddress() {
        let address = pairingAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidBluetoothAddress(address) else {
            connectionState = .failed
            addEvent("Enter a Bluetooth address in the form AA:BB:CC:DD:EE:FF. This is not the CoreBluetooth UUID.")
            return
        }
        guard let device = IOBluetoothDevice(addressString: address),
              let attempt = IOBluetoothDevicePair(device: device) else {
            connectionState = .failed
            addEvent("macOS could not create a pairing target for \(address).")
            return
        }
        attempt.delegate = self
        pairingAttempt = attempt
        let result = attempt.start()
        guard result == kIOReturnSuccess else {
            pairingAttempt = nil
            connectionState = .failed
            addEvent("macOS could not start pairing (IOReturn \(result)).")
            return
        }
        connectionState = .pairing
        addEvent("Requested macOS pairing with \(address). Respond to any system prompt, then reconnect the selected board.")
    }

    func shutdown() {
        central.stopScan()
        disconnect()
        addEvent("Stopping Bluetooth activity.")
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

    private static func isValidBluetoothAddress(_ address: String) -> Bool {
        address.range(of: "^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$", options: .regularExpression) != nil
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
        // The dashboard is intentionally focused on the board, not every BLE
        // device nearby. DropMix boards observed so far advertise this name.
        guard name.localizedCaseInsensitiveContains("dropmix") else { return }
        // Do not connect automatically; the user still explicitly selects a
        // discovered board before any connection is made.
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
        guard service.uuid == ReportedUUIDs.boardService else { return }
        let characteristics = service.characteristics ?? []
        let byUUID = Dictionary(uniqueKeysWithValues: characteristics.map { ($0.uuid, $0) })
        let subscriptionTargets = Self.subscriptionOrder.compactMap { byUUID[$0] }
        guard subscriptionTargets.count == Self.subscriptionOrder.count else {
            connectionState = .failed
            addEvent("The board is missing one or more expected notification characteristics.")
            return
        }
        pendingSubscriptions = Set(subscriptionTargets.map(\.uuid))
        addEvent("Subscribing to board indications (0003, 0005, 0004)…")
        for characteristic in subscriptionTargets {
            peripheral.setNotifyValue(true, for: characteristic)
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
        if Self.subscriptionOrder.contains(characteristic.uuid) {
            let hex = (characteristic.value ?? Data()).map { String(format: "%02X", $0) }.joined(separator: " ")
            addEvent("Received board data from \(characteristic.uuid.uuidString.prefix(4)): \(hex.isEmpty ? "empty" : hex)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard Self.subscriptionOrder.contains(characteristic.uuid) else { return }
        if let error {
            let nsError = error as NSError
            if nsError.domain == CBATTErrorDomain,
               let code = CBATTError.Code(rawValue: nsError.code),
               code == .insufficientAuthentication || code == .insufficientEncryption {
                setAuthenticationRequired("Board indications are protected. Pair the board with macOS, then reconnect.")
            } else {
                connectionState = .failed
                addEvent("Subscription failed for \(characteristic.uuid.uuidString): \(error.localizedDescription)")
            }
            return
        }
        pendingSubscriptions.remove(characteristic.uuid)
        addEvent("Subscribed to \(characteristic.uuid.uuidString.prefix(4)) indications.")
        if pendingSubscriptions.isEmpty {
            connectionState = .ready
            addEvent("Board connection ready. Waiting for validated card data.")
        }
    }
}

extension DropMixDashboardModel: @preconcurrency IOBluetoothDevicePairDelegate {
    func devicePairingStarted(_ sender: Any!) {
        addEvent("macOS pairing started.")
    }

    func devicePairingConnecting(_ sender: Any!) {
        addEvent("macOS pairing is connecting.")
    }

    func devicePairingConnected(_ sender: Any!) {
        addEvent("macOS pairing connected.")
    }

    func devicePairingPINCodeRequest(_ sender: Any!) {
        addEvent("macOS requested a PIN. The app will not guess or submit one.")
    }

    func devicePairingUserConfirmationRequest(_ sender: Any!, numericValue: BluetoothNumericValue) {
        addEvent("Confirm the macOS pairing number \(numericValue) if it is shown.")
    }

    func devicePairingFinished(_ sender: Any!, error: IOReturn) {
        if error == kIOReturnSuccess {
            connectionState = .disconnected
            addEvent("Pairing completed. Click Connect for the selected DropMix board.")
        } else {
            connectionState = .failed
            addEvent("Pairing finished with IOReturn \(error). The board address may have rotated or be unreachable.")
        }
        pairingAttempt = nil
    }
}

private struct DropMixDashboardView: View {
    @ObservedObject var model: DropMixDashboardModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                board
                connectionPanel
                eventPanel
            }
            .padding(24)
            .frame(minWidth: 760, alignment: .top)
        }
        .frame(minWidth: 760, minHeight: 680, alignment: .top)
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
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Pair board with macOS")
                    .font(.headline)
                Text("Enter a freshly observed Bluetooth address, not the CoreBluetooth UUID shown by scanning. Pairing is required before protected board indications can be used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("AA:BB:CC:DD:EE:FF", text: $model.pairingAddress)
                        .textFieldStyle(.roundedBorder)
                    Button("Pair") { model.pairUsingAddress() }
                        .buttonStyle(.bordered)
                }
            }
            Divider()
            if model.candidates.isEmpty {
                Text("No DropMix board found yet. Make sure the board is on, then scan again.")
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
    private var model: DropMixDashboardModel?

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
        self.model = model
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.shutdown()
    }
}

func runDropMixDashboard() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = DropMixDashboardAppDelegate()
    app.delegate = delegate
    app.run()
}
