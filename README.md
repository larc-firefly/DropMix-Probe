# DropMixBLEProbe

Milestone 1 of the DropMix generic card-input project: a read-only BLE
discovery and capture tool for an existing Hasbro/Harmonix DropMix board.

This does **not** depend on the discontinued DropMix app, DropMix servers,
music playback, or new RFID card manufacture. It talks directly to the board
over Bluetooth LE using CoreBluetooth.

## What this tool does

- Scans for nearby BLE peripherals and lists them (`list` mode).
- Connects to one specific, explicitly-chosen peripheral by UUID
  (`capture` mode) — it never auto-connects.
- Dynamically discovers all GATT services and characteristics on that
  peripheral (nothing is hardcoded or assumed).
- Subscribes to any notifying or indicating characteristics and issues reads on any
  readable characteristics.
- Appends every event (discovery, connect, value update, disconnect) to a
  timestamped JSONL capture file under `captures/`.

## Native board monitor

Run the basic macOS status UI with:

```bash
swift run DropMixBLEProbe ui
```

It shows the Bluetooth connection stages, a rolling activity log, discovered
nearby devices, and five DropMix-style slots. The UI never connects until you
click **Connect** for a listed device and it never writes to the board.

The slots use blue while card data is waiting, orange when protected GATT
access needs pairing/authentication, and green only after a future validated
card decoder reports a card. The current evidence cannot yet decode RFID
presence reliably, so the UI does not invent a card state.

## LED test command

`list` and `capture` remain read-only. The separate colour-test commands are
the only commands that write to a board:

```bash
swift run DropMixBLEProbe light-blue <peripheral-uuid>
swift run DropMixBLEProbe light-green <peripheral-uuid>
```

They send community-reported 20-byte payloads to the LED characteristic.
They wait for protected GATT access to succeed before writing. If macOS reports
an authentication/encryption error, no LED value is sent.

## Authentication check (macOS)

```bash
swift run DropMixBLEProbe authenticate <peripheral-uuid>
```

The original Android app contains explicit `createBond` and bond-state calls.
CoreBluetooth does not expose an equivalent API on macOS. This command therefore
accesses the board's protected GATT characteristics and records the system's
result: a successful protected read/subscription confirms the link is usable;
an authentication or encryption error means macOS has not established the bond.

If rejected, reset the board's pairing history, make sure no other phone/tablet
is connected, and remove any stale DropMix pairing from that device before
trying again. Do not send guessed authentication packets to the board.

### Experimental explicit pairing (macOS)

```bash
swift run DropMixBLEProbe pair <bluetooth-address>
```

This is an opt-in experiment using Apple's public `IOBluetoothDevicePair` API.
It reports pairing progress and completion, but never guesses a PIN or approves
a numeric comparison. Run `authenticate` afterwards to prove protected GATT
access actually works.

The CoreBluetooth UUID printed by `list` is **not** a Bluetooth address. The
pairing command accepts a freshly observed `AA:BB:CC:DD:EE:FF` address only.
BLE private addresses can rotate, so do not save or reuse an old address.

## What read-only modes deliberately do not do

- **No writes.** `list` and `capture` never call `writeValue(_:for:type:)`.
  The explicit colour-test commands are the only exceptions.
- **No auto-connect.** Scanning only lists candidates. You must pass the
  board's specific peripheral UUID to `capture` — this is the "opt-in
  chooser" required before any connection is attempted.
- **No protocol decoding.** Raw bytes are captured, not interpreted. Decoding
  happens later, against the evidence, in `PROTOCOL_NOTES.md`.

## Community-reported UUIDs (unverified leads)

- `0005cfd4-2730-4bb8-b160-502596e4c2fe` — reported button-related
- `0006cfd4-2730-4bb8-b160-502596e4c2fe` — reported LED-related

These are annotated in captures purely to make review easier if the probe
happens to see them on the board. They are **not** assumed correct and are
not used to control any probe behavior. Confirm or discard them against
actual captures before relying on them.

## Build and run (macOS)

```bash
swift build
```

### 1. Find the board's peripheral UUID

```bash
swift run DropMixBLEProbe list
```

Power on the DropMix board and watch the output for a plausible name/UUID.
If no board name is visible in the advertisement, you'll need to identify it
by process of elimination (e.g. toggle the board off/on and see which entry
disappears/reappears) — do not guess and connect blindly.

The first time you run this, macOS will prompt for Bluetooth permission for
your terminal/Xcode. Grant it in **System Settings → Privacy & Security →
Bluetooth**.

### 2. Run a controlled capture

```bash
swift run DropMixBLEProbe capture <peripheral-uuid> <capture-name>
```

This writes to `captures/<capture-name>.jsonl` and keeps running until you
press Ctrl-C. Each capture should isolate one variable at a time. Suggested
sequence for milestone 1 (rename each capture accordingly):

1. `board-idle` — board powered on, no cards, no button presses. Baseline
   noise/heartbeat traffic.
2. `slot1-insert-cardA` — insert a single known card into slot 1 only.
3. `slot1-remove-cardA` — remove that same card from slot 1.
4. `slot1-insert-cardB` — insert a *different* card into slot 1, to compare
   against capture 2 and isolate the card-identity bytes from the
   slot/position bytes.
5. `slot2-insert-cardA` — insert card A (same card as capture 2) into slot 2
   instead, to isolate slot bytes from card-identity bytes.
6. `slot1-slot2-swap` — with cards already inserted, swap two cards between
   slots without removing them fully, if the board allows it.
7. `button-press-only` — no card changes, just press each physical button
   once, to separate button events from card events.

Keep each capture short and single-purpose. Name files descriptively — they
are permanent evidence, not scratch files.

## Repository layout

```
DropMixBLEProbe/
├── Package.swift
├── README.md
├── main.swift              # CLI entry point
├── BoardProbe.swift        # CoreBluetooth central/peripheral delegate
├── PacketCapture.swift     # JSONL capture writer
├── KnownUUIDs.swift        # Unverified reported UUIDs, for annotation only
├── captures/                # Raw JSONL captures (versioned evidence)
└── PROTOCOL_NOTES.md        # GATT topology + decoding hypotheses log
```

## Incremental plan (from the project brief)

1. **This repo** — preserve docs, GATT topology, raw JSONL captures, and
   decoding hypotheses. *(current milestone)*
2. Use this probe (or Python/Bleak if easier for analysis) for controlled
   single-card / single-slot experiments.
3. Implement and validate a decoder only once stable ID, position, and
   removal transitions are evidenced from captures.
4. Build a native Swift + SwiftUI `BoardDriver` around CoreBluetooth,
   emitting `cardInserted(slot,id)`, `cardRemoved(slot,id?)`, and
   `buttonPressed`.
5. Add a five-slot reader UI.
6. Only then add verified LED control and a local card database.

Treat the reader as hardware behind an abstraction — later games should
consume high-level events, not raw BLE packets.
