import Foundation
import CoreBluetooth

/// Community-reported UUIDs for the DropMix board.
///
/// IMPORTANT: These are leads, not confirmed protocol knowledge. Nothing in
/// this probe assumes they are correct. The probe discovers services and
/// characteristics dynamically from whatever board it connects to, and only
/// annotates output when a discovered UUID happens to match one of these,
/// purely to make raw captures easier to read while reviewing them later.
enum ReportedUUIDs {
    static let boardService = CBUUID(string: "0001cfd4-2730-4bb8-b160-502596e4c2fe")
    /// The first protected characteristic discovered on the actual board. A
    /// read here is our low-risk trigger for OS-managed BLE pairing.
    static let authenticationProbe = CBUUID(string: "0002cfd4-2730-4bb8-b160-502596e4c2fe")
    static let protocolCharacteristics = (2...8).map {
        CBUUID(string: String(format: "000%dCFD4-2730-4BB8-B160-502596E4C2FE", $0))
    }
    static let buttonRelated = CBUUID(string: "0005cfd4-2730-4bb8-b160-502596e4c2fe")
    static let ledRelated = CBUUID(string: "0006cfd4-2730-4bb8-b160-502596e4c2fe")

    static let annotations: [CBUUID: String] = [
        buttonRelated: "reported button-related (unverified)",
        ledRelated: "reported LED-related (unverified)"
    ]

    static func note(for uuid: CBUUID) -> String? {
        annotations[uuid]
    }

    /// Access to one of these characteristics is the only reliable signal
    /// that the board's protected GATT link is usable. Standard Device
    /// Information/Battery reads do not establish that the central is paired.
    static func isProtectedBoardCharacteristic(_ uuid: CBUUID) -> Bool {
        protocolCharacteristics.contains(uuid)
    }
}
