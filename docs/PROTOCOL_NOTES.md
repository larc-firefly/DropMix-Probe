# DropMix connection and protocol reference

For the complete recovered 231-method Android `BluetoothBoardReader` inventory,
including the named connection and card-reader states, see the
[method reference](BluetoothBoardReader_METHOD_REFERENCE.md).

This reference separates physical-board observations from Android-app reverse
engineering and emulator-only experiments. It is not a recipe for sending
guessed commands to a real board.

## Evidence labels

| Label | Meaning |
|---|---|
| **Observed** | Recorded from the physical board in this repository's JSONL captures. |
| **App-derived** | Recovered from the archived Android 1.9.0 APK's Unity IL2CPP metadata and native method map. |
| **Emulator-only** | Seen while the archived app talked to the local virtual BLE board, not physical hardware. |
| **Unknown** | Not established; do not implement it as fact. |

## Connection layers

```text
BLE advertising → OS bond/encryption → GATT discovery → CCCD indications
  → DropMix request/data/status/button protocol → card-stack decoding
```

The first four layers and the named characteristics below are established. The
packet grammar and card-stack decoder are not.

## Physical-board GATT layout

**Observed** in `captures/all-read-values.jsonl` and `captures/slot1-live.jsonl`.

### Standard services

| Service | Characteristics | Notes |
|---|---|---|
| Device Information `180A` | `2A29`, `2A24`, `2A25`, `2A27`, `2A26` | Protected on this board. |
| Battery `180F` | `2A19` | Protected. |
| Tx Power `1804` | `2A07` | Protected. |

### DropMix board service

Service: `0001CFD4-2730-4BB8-B160-502596E4C2FE`

| Char | Properties observed | App-derived name / role | Direction | Confidence |
|---|---|---|---|---|
| `0002` | read, write | `REQ_OP_CHAR` — request/operation | central → board | High |
| `0003` | read, write, indicate | `DATA_TX_CHAR` — data transfer | board → central by indication; also writable | High |
| `0004` | read, write, indicate | `OP_STS_CHAR` — operation status | board → central by indication; also writable | High |
| `0005` | read, indicate | `BTN_STS_CHAR` — board button status | board → central by indication | High |
| `0006` | write | `IMD_LED_CHAR` — immediate LED control | central → board | Name high; payload unknown |
| `0007` | write | `LED_BRT_SEQ_CHAR` — LED brightness sequence | central → board | Name high; payload unknown |
| `0008` | write | `LED_TIME_CHAR` — LED timing | central → board | Name high; payload unknown |

The Android mapping comes from decompiled `BluetoothBoardReader` constants,
not from a UUID-number guess.

### Auxiliary service

Service: `00001016-D102-11E1-9B23-00025B00A5A5`

| Char | Properties observed | Physical observation |
|---|---|---|
| `1011` | read | Value `06` in the captures. Meaning unknown. |
| `1013` | read, write | Protected; purpose unknown. |
| `1014` | read, notify | Protected; CCCD enabled in the generic capture. |
| `1018` | write | Purpose unknown. |

Do not assume the auxiliary service is part of normal card reading; it may be
firmware/bootloader related.

## Security and pairing

### Physical-board result

macOS captures received ATT errors including:

```text
Read 0002 → Authentication is insufficient
Subscribe 0003/0004/0005 → Authentication is insufficient
```

Even standard Battery and Device Information reads were protected. Seeing the
GATT layout does not mean that a central has usable board access.

### Original Android app flow

**App-derived** from `com.hasbro.dropmix` 1.9.0:

```text
scan
→ BluetoothDevice.createBond(address)
→ wait for BondStateChanged(previous, new), where new == 12 (BOND_BONDED)
→ connectGatt → discoverServices
→ enable indications on 0003, 0005, 0004
→ send board-protocol commands
```

The Android plugin sends this Unity callback:

```text
BondStateChanged~<BLE-address>~<previous-state>~<new-state>
```

`BluetoothBoardReader.IsBonded` checks for Android state `12`. No proprietary
app-level BLE bonding/key-exchange packet was found in the Java BLE bridge; it
uses Android's operating-system bond.

### macOS position

CoreBluetooth has no public `createBond` equivalent. The Swift probe performs
a safe protected read/subscribe to find whether macOS already has a usable
encrypted link. It also offers an **experimental**, explicit pairing attempt:

```bash
swift run DropMixBLEProbe pair AA:BB:CC:DD:EE:FF
swift run DropMixBLEProbe authenticate <corebluetooth-peripheral-uuid>
```

The Bluetooth address is not the CoreBluetooth UUID and may rotate. Pairing
success is not proof of board access; the protected-GATT check is the proof.
The app never guesses a PIN, confirms a numeric comparison, or sends an
invented authentication payload.

## Indication order

The Android app enables indications in this order:

```text
0003 DATA_TX_CHAR
0005 BTN_STS_CHAR
0004 OP_STS_CHAR
```

The macOS dashboard follows this order. All three physical-board
characteristics expose descriptor `2902` (CCCD), but macOS subscription was
rejected until bonding succeeds.

## Behaviour recovered from Unity

**App-derived** from the 231-method `BluetoothBoardReader` state machine:

- it sends byte and byte-array commands (`SendByte`, `SendBytes`);
- it serializes BLE work (`NeedToWaitForBLE`);
- it waits for data/status/button traffic before board readiness
  (`IsBoardReady`);
- it maintains five card-stack readers and supports stack GUID and signature
  reads;
- it handles equalizer/button events (`WasEQPressed`) separately from the
  card-stack path;
- it treats data (`0003`), operation status (`0004`), and button status
  (`0005`) as separate channels.

This establishes channel roles and state-machine shape, but not opcode values,
frame lengths, checksums, card IDs, or a complete request/response grammar.

### Scope correction

The APK includes challenge-response and signature-verification strings. They
belong to the app's card-signature verification logic and are not sufficient
evidence for a BLE connection-authentication packet. This project does not
generate one.

## Observed command examples

### Physical board

No authenticated board-protocol payload has been captured from macOS. The only
verified physical custom-service value is auxiliary `1011 = 06`.

### Original Android app against the virtual board

These are **emulator-only** observations after a successful virtual Android
bond. They identify traffic shape, not byte semantics, and must not be replayed
to a physical board:

```text
0006 ← 1FB01F031F03104F104F1F031F03104F104F14F0  (20 bytes)
0008 ← 14                                        (1 byte)
0007 ← FFEEDDCB repeated five times              (20 bytes)
0007 ← BBCDDEEF repeated five times              (20 bytes)
0007 ← ECA86420 repeated five times              (20 bytes)
0006 ← 1000100010001000100010001000100010001000  (20 bytes)
0007 ← 0000000000000000000000000000000000000000  (20 bytes)
```

These writes are consistent with the recovered LED names for `0006`–`0008`,
but their colour/brightness/timing encoding remains unverified. All-zero
20-byte indications on `0003`, `0005`, and `0004` did not advance the app to
gameplay, proving that a valid frame needs meaningful protocol content.

## Android Emulator limits

The Android Emulator exposes virtual Bluetooth through Netsim; it does not
bridge an Android app to the Mac's physical BLE adapter. Netsim is useful for
deterministic virtual-board tests and packet capture, but cannot capture a
real DropMix conversation without a physical Android device or an unsupported
custom hardware bridge.

## Safe workflows

### macOS discovery / diagnosis

```bash
swift run DropMixBLEProbe list
swift run DropMixBLEProbe authenticate <peripheral-uuid>
swift run DropMixBLEProbe ui
```

Use `pair <fresh-address>` only as an explicit macOS experiment. Use
`light-blue` or `light-green` only after protected-GATT access succeeds; they
write to the board and are not part of read-only capture.

### Capture discipline

After authentication works, capture one variable per session:

1. board idle;
2. one known card in slot 1;
3. that card removed;
4. a different card in slot 1;
5. the first card in slot 2;
6. board/equalizer button only.

For every session, record the request write, following `0003`/`0004`/`0005`
indications, lengths, and timing. A decoder needs repeated examples, not one
packet.

## Open questions

- Exact frame format, packet boundaries, checksums, and opcode mapping.
- Which `0002` requests start stack/card reads.
- How `0003` data packets encode five stack positions and card identities.
- Exact `0004` operation-status and `0005` button-status payloads.
- LED payload encoding for `0006`–`0008`.
- Whether the auxiliary `1016` service is needed in normal operation.

## Evidence in this repository

- `captures/all-read-values.jsonl` — live GATT topology and protected-access
  errors.
- `captures/slot1-live.jsonl` — independent live topology/access sample.
- `captures/card-presence.jsonl`, `captures/slots1-4-present.jsonl`, and
  `captures/slots1-3-5-present.jsonl` — placement attempts; no authenticated
  card payload has yet been decoded.

The archived APK and decompiler output are local analysis inputs, not
repository content. Do not add the APK, OBB, extracted assemblies, or
decompiler output to this repository.
