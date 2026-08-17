# DropMix protocol notes

This file tracks what we actually know, distinct from what's reported
online. Update it after each capture session. Every claim here should point
to a specific capture file in `captures/` as evidence.

## Status

GATT topology was captured from board `DropMix M0018AA`; see
`captures/card-presence.jsonl`.

Card discovery is currently blocked by BLE authentication. The controlled
`captures/slot1-live.jsonl` run received no card-state notification while a
card was inserted then removed from slot 1. The only unprotected value remains
`00001011… = 06`.

## GATT topology (observed)

_Fill in after running `swift run DropMixBLEProbe list` and a first
`capture` session. For each service/characteristic UUID discovered on the
real board, note here: UUID, properties (read/write/notify), and whether it
matches one of the reported leads in `KnownUUIDs.swift`._

| Service UUID | Characteristic UUID | Properties | Matches reported lead? | Notes |
|---|---|---|---|---|
| `0001CFD4-2730-4BB8-B160-502596E4C2FE` | `0006CFD4-2730-4BB8-B160-502596E4C2FE` | write | LED-related lead | A 20-byte `0f00`-repeated test was rejected with `Authentication is insufficient`; no colour payload is confirmed. |
| `0001CFD4-2730-4BB8-B160-502596E4C2FE` | `0002CFD4-2730-4BB8-B160-502596E4C2FE` | read, write | Unknown | Confirmed protected-read gate: `Authentication is insufficient` in `captures/all-read-values.jsonl`. |
| `0001CFD4-2730-4BB8-B160-502596E4C2FE` | `0003CFD4-2730-4BB8-B160-502596E4C2FE` | read, write, indicate | Unknown | Enabling indications was rejected with `Authentication is insufficient`; CCCD (`2902`) reads as `0`. |
| `0001CFD4-2730-4BB8-B160-502596E4C2FE` | `0004CFD4-2730-4BB8-B160-502596E4C2FE` | read, write, indicate | Unknown | Enabling indications was rejected with `Authentication is insufficient`; CCCD (`2902`) reads as `0`. |
| `0001CFD4-2730-4BB8-B160-502596E4C2FE` | `0005CFD4-2730-4BB8-B160-502596E4C2FE` | read, indicate | Reported button-related | Enabling indications was rejected with `Authentication is insufficient`; CCCD (`2902`) reads as `0`. |
| `00001016-D102-11E1-9B23-00025B00A5A5` | `00001011-D102-11E1-9B23-00025B00A5A5` | read | Unknown | The only readable value without authentication was `06`; its meaning is unknown. |
| `00001016-D102-11E1-9B23-00025B00A5A5` | `00001014-D102-11E1-9B23-00025B00A5A5` | read, notify | Unknown | Notification subscription succeeds (CCCD `2902` is `1`), but direct read requires authentication and no card notification arrived during `slot1-live`. |

## Authentication evidence

`captures/all-read-values.jsonl` shows that all standard information,
battery, HID, and protected custom reads fail with encryption/authentication
errors, except `00001011… = 06`. Protected indications on `0003`, `0004`, and
`0005` likewise fail and their CCCDs remain `0`.

Static analysis of the archived Android 1.9.0 client provides strong evidence
that this is **ordinary operating-system BLE bonding**, not a hidden custom
packet handshake:

- The app bundles Shatalmic's Android BLE bridge.
- Its `androidCreateBond(String)` calls Android `BluetoothDevice.createBond()`.
- It reads `getBondState()`, registers `ACTION_BOND_STATE_CHANGED`, and emits
  a `BondStateChanged` callback to the Unity layer.
- Relevant client strings include `Creating bond`, `Retry creating bond`,
  `IsBonded`, and `ClearBondedDevices`.

On macOS, CoreBluetooth has no public `createBond` equivalent. The probe now
uses a serialized protected read of `0002…` to allow system-managed pairing
time before retrying. It also exposes an opt-in experimental `pair
<bluetooth-address>` command via Apple's public `IOBluetoothDevicePair` API.
This command needs a freshly observed one-time Bluetooth address, not the
CoreBluetooth UUID; no private macOS APIs are used.

## Card identifier hypothesis

_Not yet evidenced. Do not fill in until at least captures `slot1-insert-cardA`,
`slot1-remove-cardA`, and `slot1-insert-cardB` have been compared byte-for-byte._

- Candidate characteristic:
- Candidate byte offset(s) for card ID:
- Candidate byte offset(s) for slot/position:
- Evidence (capture file + byte diff):

## Slot identifier hypothesis

_Not yet evidenced. Requires comparing `slot1-insert-cardA` against
`slot2-insert-cardA` (same card, different slot)._

## Button events

_Not yet evidenced. Requires `button-press-only` capture compared against
idle baseline._

## Community packet map (unverified external lead)

The public [DropMix BLE reverse engineer spreadsheet](https://docs.google.com/spreadsheets/d/1jcEpgToulTetG1XcjukY3sehKXVcOdtZB5H3qhg1vZI/edit)
maps a board-to-phone ATT indication (opcode `0x1d`) on ATT handle `0x0021`.
After its `81 10 a3` prefix, it labels five one-byte per-slot card counts,
followed by five two-byte card IDs. Its worked example has counts `02 01 01 00
00` and IDs `c8c1`, `c278`, `9f85`, `0000`, `0000` for slots 1 through 5.

This is not yet confirmed against our board. It does, however, align with the
custom indication-only characteristics (`0003`, `0004`, and `0005`) that our
unauthenticated central cannot subscribe to. The sheet does not document the
pairing/authentication exchange required to receive this indication.

## Open questions

- What BLE bonding/pairing or application-level authentication flow does the
  original DropMix client establish before accessing protected attributes?
  **Answered in part:** the archived Android client explicitly requests an
  OS-level BLE bond; macOS pairing still needs to be validated against the
  physical board.
- Which protected indication characteristic carries card insert/remove state?
- Does the board send periodic heartbeat/keepalive traffic even when idle?
  (Check `board-idle` capture.)
- Is card ID static per physical card, or does it rotate/pair each session?
- Are slot and card ID encoded in the same characteristic payload, or
  separate characteristics?
