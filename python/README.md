# DropMixBLEProbe (Python/Bleak edition)

A Python equivalent of the Swift probe (`../Sources/DropMixBLEProbe`), useful
if you'd rather do capture analysis in Python/pandas/jupyter, or the Swift
version hits a CoreBluetooth quirk worth cross-checking against a different
BLE stack. Same safety rules, same JSONL record schema, same `captures/`
directory — captures from either tool are directly comparable.

## What this does / does not do

Identical contract to the Swift probe:
- Dynamic GATT discovery only — no assumptions about service/characteristic
  layout.
- **No writes.** Only `start_notify` and `read_gatt_char` are ever called.
- **No auto-connect.** `capture` requires an explicit peripheral address you
  identified from `list` output first.
- Captures raw bytes with timestamps; does not decode anything.

## Setup

```bash
cd python
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Usage

### 1. Find the board's address

```bash
python dropmix_probe.py list
```

Prints `[address] name  RSSI: n` for each newly-seen peripheral. On macOS,
Bleak/CoreBluetooth exposes a randomized UUID as the "address" rather than a
MAC — that's expected and fine, it's still a stable identifier for the
`capture` command.

Press Ctrl-C to stop, or pass `--timeout 10` to auto-stop after 10 seconds.

### 2. Run a controlled capture

```bash
python dropmix_probe.py capture <address> <capture-name>
```

Writes to `../captures/<capture-name>.jsonl` by default (the same directory
the Swift probe uses — override with `--captures-dir` if you want them kept
separate). Runs until Ctrl-C.

Follow the same controlled sequence described in the top-level
[`README.md`](../README.md#2-run-a-controlled-capture): idle baseline, then
isolate card identity from slot from button events one variable at a time.

## Record schema

Same fields as the Swift version's JSONL output, so you can concatenate or
diff captures from either tool:

```json
{
  "timestamp": "2026-08-17T07:30:00.000+00:00",
  "monotonicMillis": 1234.5,
  "kind": "notify",
  "peripheralUUID": "XXXX-XXXX-...",
  "serviceUUID": "...",
  "characteristicUUID": "...",
  "characteristicNote": "reported button-related (unverified)",
  "hexBytes": "01ff00",
  "byteCount": 3,
  "message": null
}
```

## Notes on Bleak specifics

- On macOS, Bleak requires the same Bluetooth permission grant as the Swift
  tool — the first run will trigger a system prompt if it hasn't been
  granted to your terminal/Python interpreter yet.
- `client.services` is populated automatically on connect in recent Bleak
  versions (0.22+, pinned in `requirements.txt`). If you're on an older
  Bleak, you may need `await client.get_services()` explicitly.
