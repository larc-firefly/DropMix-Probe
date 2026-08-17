// main.swift
// DropMixBLEProbe
//
// Read-only BLE discovery/capture tool for an existing DropMix board.
// Discovers GATT topology dynamically and records notifications with
// timestamps and raw bytes. Makes no BLE writes. See README.md
// for the controlled capture sequence.
//
// Usage:
//   swift run DropMixBLEProbe list
//       Scan and print nearby peripherals (name + UUID + RSSI) so you can
//       identify the board's peripheral UUID.
//
//   swift run DropMixBLEProbe capture <peripheral-uuid> <capture-name>
//       Opt-in connect to a specific peripheral by UUID, discover all
//       services/characteristics, subscribe to notifications, and append
//       everything to captures/<capture-name>.jsonl until Ctrl-C.
//
//   swift run DropMixBLEProbe light-blue <peripheral-uuid>
//   swift run DropMixBLEProbe light-green <peripheral-uuid>
//       Connect to a specific board and set all board LEDs to a test colour.
//
//   swift run DropMixBLEProbe authenticate <peripheral-uuid>
//       Request protected board GATT access and report whether macOS has
//       established a usable encrypted/authenticated link.
//
//   swift run DropMixBLEProbe pair <bluetooth-address>
//       Explicitly ask macOS to pair with the board using a freshly observed
//       Bluetooth address (not its CoreBluetooth peripheral UUID).
//
//   swift run DropMixBLEProbe ui
//       Open the native read-only board monitor. Select a discovered device
//       explicitly before it connects.

import Foundation

let arguments = CommandLine.arguments

func printUsageAndExit() -> Never {
    print("""
    DropMixBLEProbe

    Usage:
      swift run DropMixBLEProbe list
      swift run DropMixBLEProbe capture <peripheral-uuid> <capture-name>
      swift run DropMixBLEProbe authenticate <peripheral-uuid>
      swift run DropMixBLEProbe pair <bluetooth-address>
      swift run DropMixBLEProbe light-blue <peripheral-uuid>
      swift run DropMixBLEProbe light-green <peripheral-uuid>
      swift run DropMixBLEProbe ui
    """)
    exit(1)
}

guard arguments.count >= 2 else {
    printUsageAndExit()
}

let command = arguments[1]

if command == "ui" {
    runDropMixDashboard()
    exit(0)
}

let probe: BoardProbe

switch command {
case "list":
    probe = BoardProbe(mode: .list)
case "capture":
    guard arguments.count >= 4 else {
        print("capture requires a peripheral UUID and a capture name.")
        printUsageAndExit()
    }
    let targetUUID = arguments[2]
    let captureName = arguments[3]
    probe = BoardProbe(mode: .capture(targetUUID: targetUUID, captureName: captureName))
case "authenticate":
    guard arguments.count >= 3 else {
        print("authenticate requires a peripheral UUID.")
        printUsageAndExit()
    }
    probe = BoardProbe(mode: .authenticate(targetUUID: arguments[2]))
case "pair":
    guard arguments.count >= 3 else {
        print("pair requires a Bluetooth address (for example AA:BB:CC:DD:EE:FF).")
        printUsageAndExit()
    }
    probe = BoardProbe(mode: .pair(bluetoothAddress: arguments[2]))
case "light-blue", "light-green":
    guard arguments.count >= 3 else {
        print("\(command) requires a peripheral UUID.")
        printUsageAndExit()
    }
    let color: BoardProbe.LEDColor = command == "light-blue" ? .blue : .green
    probe = BoardProbe(mode: .light(targetUUID: arguments[2], color: color))
default:
    printUsageAndExit()
}

probe.run()
RunLoop.main.run()
