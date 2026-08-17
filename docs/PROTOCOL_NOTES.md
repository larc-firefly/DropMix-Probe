# DropMix protocol notes

This file tracks what we actually know, distinct from what's reported
online. Update it after each capture session. Every claim here should point
to a specific capture file in `captures/` as evidence.

## Status

GATT topology discovered from a live board (`board-idle` capture, 2026-08-17).
No card/button/slot events decoded yet — this section is topology only.

## GATT topology (observed)

Observed via `python dropmix_probe.py capture <address> board-idle`.

**Standard BLE services (ignore for card protocol purposes):**

| Service | Purpose | Characteristics |
|---|---|---|
| `0000180a-...` | Device Information | `2a29` mfr name, `2a24` model, `2a25` serial, `2a27` hw rev, `2a26` fw rev — all `read` |
| `0000180f-...` | Battery | `2a19` battery level — `read` |
| `00001804-...` | Tx Power | `2a07` tx power level — `read` |

**Custom DropMix service — primary suspect for card/button/LED protocol:**

Service `0001cfd4-2730-4bb8-b160-502596e4c2fe`

| Characteristic UUID | Properties | Matches reported lead? | Notes |
|---|---|---|---|
| `0002cfd4-...` | read, write | no | |
| `0003cfd4-...` | read, write, indicate | no | |
| `0004cfd4-...` | read, write, indicate | no | |
| `0005cfd4-...` | read, indicate | **yes — reported button-related** | unverified, but real characteristic on this board |
| `0006cfd4-...` | write | **yes — reported LED-related** | unverified; write-only, consistent with an LED-control lead |
| `0007cfd4-...` | write | no | |
| `0008cfd4-...` | write | no | |

**Unlabeled Nordic-base service — secondary lead, not yet tied to cards:**

Service `00001016-d102-11e1-9b23-00025b00a5a5` (Nordic 128-bit UUID base;
possibly DFU/bootloader-related, unconfirmed)

| Characteristic UUID | Properties | Notes |
|---|---|---|
| `1011-d102-...` | read | Static read value observed: `0x06` |
| `1013-d102-...` | read, write | |
| `1014-d102-...` | read, notify | |
| `1018-d102-...` | write | |


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

## Open questions

- Does the board send periodic heartbeat/keepalive traffic even when idle?
  (Check `board-idle` capture.)
- Is card ID static per physical card, or does it rotate/pair each session?
- Are slot and card ID encoded in the same characteristic payload, or
  separate characteristics?
