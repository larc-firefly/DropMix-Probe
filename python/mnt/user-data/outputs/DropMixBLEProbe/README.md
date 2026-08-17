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
- Subscribes to any notifying characteristics and issues reads on any
  readable characteristics.
- Appends every event (discovery, connect, notify, read, disconnect) to a
  timestamped JSONL capture file under `captures/`.

## What this tool deliberately does not do

- **No writes.** It never calls `writeValue(_:for:type:)`. This is a safety
  constraint, not an oversight — until the protocol is understood, sending
  unknown bytes to the board risks bricking it or corrupting card state.
- **No auto-connect.** Scanning only lists candidates. You must pass the
  board's specific peripheral UUID to `capture` — this is the "opt-in
  chooser" required before any connection is attempted.
- **No protocol decoding.** Raw bytes are captured, not interpreted. Decoding
  happens later, against the evidence, in `docs/PROTOCOL_NOTES.md`.

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

## Python/Bleak alternative

For capture analysis workflows that are easier in Python (pandas, Jupyter,
etc.), or as a cross-check against a different BLE stack, see
[`python/README.md`](python/README.md). It's a functional equivalent with
identical safety rules (no writes, no auto-connect) and the same JSONL
record schema, sharing this repo's `captures/` directory.

## Repository layout

```
DropMixBLEProbe/
├── Package.swift
├── README.md
├── Sources/DropMixBLEProbe/
│   ├── main.swift          # CLI entry point
│   ├── BoardProbe.swift    # CoreBluetooth central/peripheral delegate
│   ├── PacketCapture.swift # JSONL capture writer
│   └── KnownUUIDs.swift    # Unverified reported UUIDs, for annotation only
├── python/                  # Bleak-based equivalent (see python/README.md)
│   ├── dropmix_probe.py
│   ├── packet_capture.py
│   ├── known_uuids.py
│   └── requirements.txt
├── captures/                # Raw JSONL captures (versioned evidence, shared by both tools)
└── docs/
    └── PROTOCOL_NOTES.md    # GATT topology + decoding hypotheses log
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
