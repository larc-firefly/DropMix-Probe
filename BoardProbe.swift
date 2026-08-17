import Foundation
import CoreBluetooth
import IOBluetooth

/// BLE discovery, pairing diagnosis, and controlled LED test tool for the
/// DropMix board.
///
/// Safety rules enforced here (see README.md):
///  - Never writes to any characteristic.
///  - Never connects to a peripheral automatically. Scanning only lists
///    candidates; a specific peripheral UUID must be passed explicitly
///    (the "opt-in chooser") before a connection is attempted.
///  - Subscribes (notify) and reads discovered characteristics, but only
///    ever reads bytes — it does not interpret or decode them here.
final class BoardProbe: NSObject {
    enum LEDColor: String {
        case blue
        case green

        var pair: (UInt8, UInt8) {
            switch self {
            case .blue: (0x0F, 0x00)
            case .green: (0x00, 0xF0)
            }
        }
    }

    enum Mode {
        case list
        case capture(targetUUID: String, captureName: String)
        case authenticate(targetUUID: String)
        /// Experimental, explicit opt-in pairing through Apple's public
        /// IOBluetooth API. This needs a freshly observed Bluetooth address,
        /// not the CoreBluetooth peripheral UUID.
        case pair(bluetoothAddress: String)
        case light(targetUUID: String, color: LEDColor)
    }

    private var central: CBCentralManager!
    private var targetPeripheral: CBPeripheral?
    private let mode: Mode
    private var capture: PacketCapture?
    private var seenPeripherals: Set<UUID> = []
    private var didSendLEDCommand = false
    private var didReportAuthenticationFailure = false
    private var hasAuthenticatedBoardAccess = false
    private var ledCharacteristic: CBCharacteristic?
    private var pairingAttempt: IOBluetoothDevicePair?
    private var authenticationProbeCharacteristic: CBCharacteristic?
    private var authenticationAttemptCount = 0
    private var authenticationRetryTimer: Timer?

    private let maximumAuthenticationAttempts = 6

    private static let validCaptureName = try! NSRegularExpression(
        pattern: "^[A-Za-z0-9][A-Za-z0-9._-]*$"
    )

    init(mode: Mode) {
        self.mode = mode
        super.init()
        self.central = CBCentralManager(delegate: self, queue: nil)
    }

    func run() {
        switch mode {
        case .list:
            print("Scanning for BLE peripherals. Press Ctrl-C to stop.")
        case .capture(let targetUUID, let captureName):
            guard Self.isValidCaptureName(captureName) else {
                fputs("Invalid capture name. Use letters, numbers, dots, underscores, and hyphens; it must start with a letter or number.\n", stderr)
                exit(1)
            }
            let path = "captures/\(captureName).jsonl"
            do {
                capture = try PacketCapture(path: path)
                print("Capturing to \(path)")
                print("Waiting for peripheral \(targetUUID) to appear during scan...")
            } catch {
                fputs("Failed to open capture file: \(error)\n", stderr)
                exit(1)
            }
        case .authenticate(let targetUUID):
            print("Waiting for peripheral \(targetUUID) to appear, then requesting protected GATT access...")
        case .pair(let bluetoothAddress):
            startExplicitPairing(bluetoothAddress)
        case .light(let targetUUID, _):
            print("Waiting for peripheral \(targetUUID) to appear, then authenticating before the LED test...")
        }
    }

    private static func isValidCaptureName(_ name: String) -> Bool {
        let range = NSRange(name.startIndex..., in: name)
        return validCaptureName.firstMatch(in: name, range: range) != nil
    }

    private var usesSerializedAuthenticationProbe: Bool {
        switch mode {
        case .authenticate, .light:
            true
        default:
            false
        }
    }

    private func beginSerializedAuthenticationProbe(
        for characteristic: CBCharacteristic,
        peripheral: CBPeripheral
    ) {
        guard usesSerializedAuthenticationProbe,
              characteristic.uuid == ReportedUUIDs.authenticationProbe,
              authenticationProbeCharacteristic == nil else { return }
        authenticationProbeCharacteristic = characteristic
        requestProtectedAuthenticationRead(from: peripheral)
    }

    private func requestProtectedAuthenticationRead(from peripheral: CBPeripheral) {
        guard !hasAuthenticatedBoardAccess,
              authenticationAttemptCount < maximumAuthenticationAttempts,
              let characteristic = authenticationProbeCharacteristic else { return }
        authenticationRetryTimer?.invalidate()
        authenticationRetryTimer = nil
        authenticationAttemptCount += 1
        print("Requesting protected GATT access (attempt \(authenticationAttemptCount)/\(maximumAuthenticationAttempts))...")
        peripheral.readValue(for: characteristic)
    }

    /// A protected GATT transaction can cause macOS to start an OS-managed
    /// pairing exchange. Do not declare it impossible after its first ATT
    /// error: wait briefly for that exchange and retry the same safe read.
    private func handleSerializedAuthenticationProbeError(
        _ error: Error,
        characteristic: CBCharacteristic,
        peripheral: CBPeripheral
    ) -> Bool {
        guard usesSerializedAuthenticationProbe,
              characteristic.uuid == ReportedUUIDs.authenticationProbe else { return false }

        guard isAuthenticationOrEncryptionError(error) else {
            reportAuthenticationFailure(error, operation: "read from \(characteristic.uuid.uuidString)")
            return true
        }

        guard authenticationAttemptCount < maximumAuthenticationAttempts else {
            reportAuthenticationFailure(error, operation: "protected read after \(maximumAuthenticationAttempts) attempts")
            return true
        }

        print("Protected read was rejected (\(error.localizedDescription)). Waiting 5 seconds for macOS pairing, then retrying...")
        authenticationRetryTimer?.invalidate()
        authenticationRetryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self, weak peripheral] _ in
            guard let self, let peripheral else { return }
            self.requestProtectedAuthenticationRead(from: peripheral)
        }
        return true
    }

    private func isAuthenticationOrEncryptionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == CBATTErrorDomain,
              let code = CBATTError.Code(rawValue: nsError.code) else { return false }
        return code == .insufficientAuthentication || code == .insufficientEncryption
    }

    private static func isValidBluetoothAddress(_ address: String) -> Bool {
        address.range(of: "^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$", options: .regularExpression) != nil
    }

    /// CoreBluetooth itself does not expose an API to create a bond. macOS's
    /// public IOBluetoothDevicePair API does, but it accepts a Bluetooth
    /// address rather than a CBPeripheral. BLE private addresses may rotate,
    /// so this remains an explicit, one-shot diagnostic command.
    private func startExplicitPairing(_ address: String) {
        guard Self.isValidBluetoothAddress(address) else {
            fputs("Invalid Bluetooth address. Use the form AA:BB:CC:DD:EE:FF.\n", stderr)
            exit(1)
        }
        guard let device = IOBluetoothDevice(addressString: address),
              let attempt = IOBluetoothDevicePair(device: device) else {
            fputs("macOS could not create a pairing target for \(address).\n", stderr)
            exit(1)
        }

        attempt.delegate = self
        pairingAttempt = attempt // Pairing is asynchronous; retain it for callbacks.
        let result = attempt.start()
        guard result == kIOReturnSuccess else {
            fputs("macOS could not start pairing (IOReturn \(result)).\n", stderr)
            pairingAttempt = nil
            exit(1)
        }
        print("Requested macOS pairing with \(address). Waiting for pairing callbacks...")
    }
}

extension BoardProbe: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            switch mode {
            case .list:
                central.scanForPeripherals(withServices: nil, options: [
                    CBCentralManagerScanOptionAllowDuplicatesKey: false
                ])
            case .capture(let targetUUID, _), .authenticate(let targetUUID), .light(let targetUUID, _):
                connectToKnownPeripheralOrScan(targetUUID, using: central)
            case .pair:
                break
            }
        case .poweredOff:
            print("Bluetooth is powered off. Turn it on and re-run.")
        case .unauthorized:
            print("Bluetooth permission not granted to this process. Check System Settings > Privacy > Bluetooth.")
        default:
            print("Central manager state: \(central.state.rawValue)")
        }
    }

    /// A peripheral UUID supplied by the user can often be retrieved without
    /// waiting for its next advertisement. If macOS no longer knows it, fall
    /// back to the normal explicit-UUID scan.
    private func connectToKnownPeripheralOrScan(_ targetUUID: String, using central: CBCentralManager) {
        guard let identifier = UUID(uuidString: targetUUID) else {
            print("Invalid peripheral UUID: \(targetUUID)")
            return
        }

        if let peripheral = central.retrievePeripherals(withIdentifiers: [identifier]).first {
            print("Retrieved selected peripheral \(peripheral.name ?? identifier.uuidString). Connecting...")
            targetPeripheral = peripheral
            central.connect(peripheral, options: nil)
        } else {
            central.scanForPeripherals(withServices: nil, options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: false
            ])
        }
    }

    func centralManager(_ central: CBCentralManager,
                         didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any],
                         rssi RSSI: NSNumber) {
        let uuid = peripheral.identifier.uuidString
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "(no name)"

        switch mode {
        case .list:
            if !seenPeripherals.contains(peripheral.identifier) {
                seenPeripherals.insert(peripheral.identifier)
                print("[\(uuid)] \(name)  RSSI: \(RSSI)")
            }
        case .pair:
            // The explicit IOBluetooth pairing API owns discovery for this
            // one-shot experiment; do not initiate a second CoreBluetooth
            // connection here.
            break
        case .capture(let targetUUID, _):
            if uuid.caseInsensitiveCompare(targetUUID) == .orderedSame {
                capture?.write(kind: "discovery",
                                peripheralUUID: uuid,
                                message: "Discovered target peripheral, name=\(name), RSSI=\(RSSI)")
                print("Found target \(name) [\(uuid)]. Connecting...")
                targetPeripheral = peripheral
                central.stopScan()
                central.connect(peripheral, options: nil)
            }
        case .authenticate(let targetUUID):
            if uuid.caseInsensitiveCompare(targetUUID) == .orderedSame {
                print("Found target \(name) [\(uuid)]. Requesting protected GATT access...")
                targetPeripheral = peripheral
                central.stopScan()
                central.connect(peripheral, options: nil)
            }
        case .light(let targetUUID, let color):
            if uuid.caseInsensitiveCompare(targetUUID) == .orderedSame {
                print("Found target \(name) [\(uuid)]. Connecting to set LEDs \(color.rawValue)...")
                targetPeripheral = peripheral
                central.stopScan()
                central.connect(peripheral, options: nil)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let uuid = peripheral.identifier.uuidString
        capture?.write(kind: "connect", peripheralUUID: uuid, message: "Connected")
        print("Connected to \(peripheral.name ?? uuid). Discovering services...")
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let uuid = peripheral.identifier.uuidString
        capture?.write(kind: "connect", peripheralUUID: uuid, message: "Connection failed: \(error?.localizedDescription ?? "unknown error")")
        print("Failed to connect: \(error?.localizedDescription ?? "unknown error")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        authenticationRetryTimer?.invalidate()
        authenticationRetryTimer = nil
        let uuid = peripheral.identifier.uuidString
        capture?.write(kind: "disconnect", peripheralUUID: uuid,
                        message: error?.localizedDescription ?? "Disconnected")
        print("Disconnected. \(error?.localizedDescription ?? "")")
    }
}

/// Pairing callbacks from the public IOBluetoothDevicePair API. The tool only
/// reports user-interaction requests; it must never invent a PIN or approve a
/// numeric comparison on the user's behalf.
extension BoardProbe: IOBluetoothDevicePairDelegate {
    func devicePairingStarted(_ sender: Any!) {
        print("Pairing event: started")
    }

    func devicePairingConnecting(_ sender: Any!) {
        print("Pairing event: connecting")
    }

    func devicePairingConnected(_ sender: Any!) {
        print("Pairing event: connected")
    }

    func devicePairingPINCodeRequest(_ sender: Any!) {
        print("Pairing requires a PIN. This tool will not guess or submit one.")
    }

    func devicePairingUserConfirmationRequest(_ sender: Any!, numericValue: BluetoothNumericValue) {
        print("Pairing requires numeric confirmation \(numericValue). This tool will not approve it automatically.")
    }

    func devicePairingUserPasskeyNotification(_ sender: Any!, passkey: BluetoothPasskey) {
        print("Pairing passkey displayed: \(passkey)")
    }

    func devicePairingFinished(_ sender: Any!, error: IOReturn) {
        if error == kIOReturnSuccess {
            print("Pairing completed successfully. Run authenticate with the board's CoreBluetooth UUID next.")
        } else {
            let description: String
            switch error {
            case IOReturn(kBluetoothHCIErrorPageTimeout):
                description = "page timeout (the address did not answer; it may have rotated or is not reachable)"
            case IOReturn(kBluetoothHCIErrorAuthenticationFailure):
                description = "Bluetooth authentication failure"
            case IOReturn(kBluetoothHCIErrorKeyMissing):
                description = "Bluetooth key missing"
            default:
                description = "Bluetooth/IOReturn status \(error)"
            }
            print("Pairing finished: \(description).")
        }
        pairingAttempt = nil
    }

    func deviceSimplePairingComplete(_ sender: Any!, status: BluetoothHCIEventStatus) {
        print("Simple pairing completed with status \(status).")
    }
}

extension BoardProbe: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            capture?.write(kind: "info", peripheralUUID: peripheral.identifier.uuidString,
                            message: "Service discovery error: \(error.localizedDescription)")
            return
        }
        for service in peripheral.services ?? [] {
            capture?.write(kind: "info",
                            peripheralUUID: peripheral.identifier.uuidString,
                            serviceUUID: service.uuid.uuidString,
                            message: "Discovered service")
            print("Service: \(service.uuid.uuidString)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            capture?.write(kind: "info", peripheralUUID: peripheral.identifier.uuidString,
                            serviceUUID: service.uuid.uuidString,
                            message: "Characteristic discovery error: \(error.localizedDescription)")
            return
        }
        for characteristic in service.characteristics ?? [] {
            let note = ReportedUUIDs.note(for: characteristic.uuid)
            let props = describeProperties(characteristic.properties)
            capture?.write(kind: "info",
                            peripheralUUID: peripheral.identifier.uuidString,
                            serviceUUID: service.uuid.uuidString,
                            characteristicUUID: characteristic.uuid.uuidString,
                            characteristicNote: note,
                            message: "Discovered characteristic, properties=\(props)")
            print("  Characteristic: \(characteristic.uuid.uuidString) [\(props)]" + (note.map { " -- \($0)" } ?? ""))

            // Authentication and LED-test modes deliberately serialize one
            // protected read. This gives macOS time to negotiate pairing and
            // avoids a flood of unrelated ATT errors obscuring the result.
            if usesSerializedAuthenticationProbe {
                beginSerializedAuthenticationProbe(for: characteristic, peripheral: peripheral)
            } else {
                // Capture mode remains broad and read-only: subscribe if
                // notifications or indications are supported, then read every
                // readable characteristic. Notifications change only CCCDs,
                // never a board characteristic value.
                if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
                if characteristic.properties.contains(.read) {
                    peripheral.readValue(for: characteristic)
                }
                peripheral.discoverDescriptors(for: characteristic)
            }

            if case .light = mode,
               characteristic.uuid == ReportedUUIDs.ledRelated,
               characteristic.properties.contains(.write) {
                ledCharacteristic = characteristic
                sendLEDCommandIfReady()
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            reportAuthenticationFailure(error, operation: "LED write")
            print("LED command failed: \(error.localizedDescription)")
        } else {
            print("LED command acknowledged by the board.")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            let handledAsSerializedProbe = handleSerializedAuthenticationProbeError(
                error,
                characteristic: characteristic,
                peripheral: peripheral
            )
            if !handledAsSerializedProbe,
               ReportedUUIDs.isProtectedBoardCharacteristic(characteristic.uuid) {
                reportAuthenticationFailure(error, operation: "read from \(characteristic.uuid.uuidString)")
            }
            capture?.write(kind: "info",
                            peripheralUUID: peripheral.identifier.uuidString,
                            characteristicUUID: characteristic.uuid.uuidString,
                            message: "Read/notify error: \(error.localizedDescription)")
            return
        }
        let note = ReportedUUIDs.note(for: characteristic.uuid)
        let bytes = characteristic.value ?? Data()
        recordProtectedAccessIfNeeded(characteristic, via: "read or notification")
        // CoreBluetooth uses this callback for both read responses and
        // notifications, without identifying which initiated the update.
        capture?.write(kind: "valueUpdate",
                        peripheralUUID: peripheral.identifier.uuidString,
                        serviceUUID: characteristic.service?.uuid.uuidString,
                        characteristicUUID: characteristic.uuid.uuidString,
                        characteristicNote: note,
                        bytes: bytes)
        let hex = bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
        print("  <- \(characteristic.uuid.uuidString): \(hex)" + (note.map { "  (\($0))" } ?? ""))
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            if ReportedUUIDs.isProtectedBoardCharacteristic(characteristic.uuid) {
                reportAuthenticationFailure(error, operation: "notification subscription for \(characteristic.uuid.uuidString)")
            }
            capture?.write(kind: "info",
                            peripheralUUID: peripheral.identifier.uuidString,
                            characteristicUUID: characteristic.uuid.uuidString,
                            message: "Notify state change error: \(error.localizedDescription)")
            return
        }
        capture?.write(kind: "info",
                        peripheralUUID: peripheral.identifier.uuidString,
                        characteristicUUID: characteristic.uuid.uuidString,
                        message: "Notify state now \(characteristic.isNotifying)")
        if characteristic.isNotifying {
            recordProtectedAccessIfNeeded(characteristic, via: "notification subscription")
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverDescriptorsFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            if ReportedUUIDs.isProtectedBoardCharacteristic(characteristic.uuid) {
                reportAuthenticationFailure(error, operation: "descriptor discovery for \(characteristic.uuid.uuidString)")
            }
            capture?.write(kind: "info",
                            peripheralUUID: peripheral.identifier.uuidString,
                            serviceUUID: characteristic.service?.uuid.uuidString,
                            characteristicUUID: characteristic.uuid.uuidString,
                            message: "Descriptor discovery error: \(error.localizedDescription)")
            return
        }

        for descriptor in characteristic.descriptors ?? [] {
            capture?.write(kind: "info",
                            peripheralUUID: peripheral.identifier.uuidString,
                            serviceUUID: characteristic.service?.uuid.uuidString,
                            characteristicUUID: characteristic.uuid.uuidString,
                            message: "Discovered descriptor \(descriptor.uuid.uuidString)")
            peripheral.readValue(for: descriptor)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor descriptor: CBDescriptor,
                    error: Error?) {
        let characteristic = descriptor.characteristic
        if let error {
            if let characteristic, ReportedUUIDs.isProtectedBoardCharacteristic(characteristic.uuid) {
                reportAuthenticationFailure(error, operation: "descriptor read for \(descriptor.uuid.uuidString)")
            }
            capture?.write(kind: "info",
                            peripheralUUID: peripheral.identifier.uuidString,
                            serviceUUID: characteristic?.service?.uuid.uuidString,
                            characteristicUUID: characteristic?.uuid.uuidString,
                            message: "Descriptor \(descriptor.uuid.uuidString) read error: \(error.localizedDescription)")
            return
        }

        capture?.write(kind: "info",
                        peripheralUUID: peripheral.identifier.uuidString,
                        serviceUUID: characteristic?.service?.uuid.uuidString,
                        characteristicUUID: characteristic?.uuid.uuidString,
                        message: "Descriptor \(descriptor.uuid.uuidString) value: \(String(describing: descriptor.value))")
    }

    private func describeProperties(_ props: CBCharacteristicProperties) -> String {
        var parts: [String] = []
        if props.contains(.read) { parts.append("read") }
        if props.contains(.write) { parts.append("write") }
        if props.contains(.writeWithoutResponse) { parts.append("writeNoResp") }
        if props.contains(.notify) { parts.append("notify") }
        if props.contains(.indicate) { parts.append("indicate") }
        return parts.joined(separator: ",")
    }

    private func recordProtectedAccessIfNeeded(_ characteristic: CBCharacteristic, via operation: String) {
        guard ReportedUUIDs.isProtectedBoardCharacteristic(characteristic.uuid), !hasAuthenticatedBoardAccess else { return }
        authenticationRetryTimer?.invalidate()
        authenticationRetryTimer = nil
        hasAuthenticatedBoardAccess = true
        let message = "Authenticated board GATT access confirmed via \(operation) on \(characteristic.uuid.uuidString)."
        capture?.write(kind: "info", peripheralUUID: characteristic.service?.peripheral?.identifier.uuidString,
                       serviceUUID: characteristic.service?.uuid.uuidString,
                       characteristicUUID: characteristic.uuid.uuidString, message: message)
        print(message)
        sendLEDCommandIfReady()
    }

    private func sendLEDCommandIfReady() {
        guard hasAuthenticatedBoardAccess, !didSendLEDCommand,
              case .light(_, let color) = mode,
              let peripheral = targetPeripheral, let characteristic = ledCharacteristic else { return }
        let (firstByte, secondByte) = color.pair
        let payload = Data((0..<20).map { $0.isMultiple(of: 2) ? firstByte : secondByte })
        didSendLEDCommand = true
        peripheral.writeValue(payload, for: characteristic, type: .withResponse)
        print("Authenticated access confirmed. Sent \(color.rawValue) LED command to \(characteristic.uuid.uuidString).")
    }

    private func reportAuthenticationFailure(_ error: Error, operation: String) {
        let text = error.localizedDescription.lowercased()
        guard !didReportAuthenticationFailure,
              text.contains("authentication") || text.contains("encryption") || text.contains("insufficient") else { return }
        didReportAuthenticationFailure = true
        let message = "Protected GATT access was rejected during \(operation): \(error.localizedDescription). macOS did not establish a usable BLE bond. Reset the board's pairing history, remove any old DropMix pairing from another device, then reconnect and watch for a macOS Bluetooth pairing prompt."
        capture?.write(kind: "info", peripheralUUID: targetPeripheral?.identifier.uuidString, message: message)
        print("AUTHENTICATION REQUIRED: \(message)")
    }
}
