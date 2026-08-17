#!/usr/bin/env python3
"""
DropMixBLEProbe (Python/Bleak edition)

Read-only BLE discovery/capture tool for an existing DropMix board.
Mirrors Sources/DropMixBLEProbe/BoardProbe.swift: dynamic GATT discovery,
read-only subscription, timestamped JSONL capture. Makes no BLE writes.

Safety rules (see ../README.md):
  - Never writes to any characteristic.
  - Never connects automatically. `capture` requires an explicit peripheral
    address/UUID chosen after reviewing `list` output.
  - Captures raw bytes only; does not interpret or decode them here.

Usage:
    python dropmix_probe.py list
        Scan and print nearby peripherals (name + address + RSSI).

    python dropmix_probe.py capture <address> <capture-name>
        Opt-in connect to a specific peripheral by address/UUID, discover
        all services/characteristics, subscribe to notifications, and
        append everything to ../captures/<capture-name>.jsonl until Ctrl-C.

Run from the python/ directory, or pass --captures-dir to point elsewhere.
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path

from bleak import BleakClient, BleakScanner
from bleak.backends.characteristic import BleakGATTCharacteristic

from known_uuids import note_for
from packet_capture import PacketCapture


async def cmd_list(timeout: float | None) -> None:
    print("Scanning for BLE peripherals. Press Ctrl-C to stop.")
    seen: set[str] = set()

    def on_detect(device, advertisement_data) -> None:
        if device.address in seen:
            return
        seen.add(device.address)
        name = device.name or advertisement_data.local_name or "(no name)"
        rssi = advertisement_data.rssi
        print(f"[{device.address}] {name}  RSSI: {rssi}")

    scanner = BleakScanner(detection_callback=on_detect)
    await scanner.start()
    try:
        if timeout:
            await asyncio.sleep(timeout)
        else:
            await asyncio.Event().wait()  # run until Ctrl-C
    finally:
        await scanner.stop()


def describe_properties(properties: list[str]) -> str:
    order = ["read", "write", "write-without-response", "notify", "indicate"]
    return ",".join(p for p in order if p in properties)


async def cmd_capture(address: str, capture_name: str, captures_dir: Path) -> None:
    captures_dir.mkdir(parents=True, exist_ok=True)
    capture_path = captures_dir / f"{capture_name}.jsonl"
    capture = PacketCapture(str(capture_path))
    print(f"Capturing to {capture_path}")
    print(f"Connecting to {address}...")

    def on_notify(characteristic: BleakGATTCharacteristic, data: bytearray) -> None:
        note = note_for(characteristic.uuid)
        hexstr = data.hex(" ")
        capture.write(
            kind="notify",
            peripheral_uuid=address,
            service_uuid=characteristic.service_uuid,
            characteristic_uuid=characteristic.uuid,
            characteristic_note=note,
            data=bytes(data),
        )
        suffix = f"  ({note})" if note else ""
        print(f"  <- {characteristic.uuid}: {hexstr}{suffix}")

    try:
        async with BleakClient(address) as client:
            capture.write(kind="connect", peripheral_uuid=address, message="Connected")
            print(f"Connected to {address}. Discovering services...")

            for service in client.services:
                capture.write(
                    kind="info",
                    peripheral_uuid=address,
                    service_uuid=service.uuid,
                    message="Discovered service",
                )
                print(f"Service: {service.uuid}")

                for characteristic in service.characteristics:
                    note = note_for(characteristic.uuid)
                    props = describe_properties(characteristic.properties)
                    capture.write(
                        kind="info",
                        peripheral_uuid=address,
                        service_uuid=service.uuid,
                        characteristic_uuid=characteristic.uuid,
                        characteristic_note=note,
                        message=f"Discovered characteristic, properties={props}",
                    )
                    suffix = f" -- {note}" if note else ""
                    print(f"  Characteristic: {characteristic.uuid} [{props}]{suffix}")

                    # Read-only interaction: subscribe if notify is supported,
                    # issue a single read if read is supported. Never write.
                    if "notify" in characteristic.properties or "indicate" in characteristic.properties:
                        try:
                            await client.start_notify(characteristic, on_notify)
                        except Exception as e:  # noqa: BLE001
                            capture.write(
                                kind="info",
                                peripheral_uuid=address,
                                characteristic_uuid=characteristic.uuid,
                                message=f"start_notify failed: {e}",
                            )
                    if "read" in characteristic.properties:
                        try:
                            value = await client.read_gatt_char(characteristic)
                            capture.write(
                                kind="read",
                                peripheral_uuid=address,
                                service_uuid=service.uuid,
                                characteristic_uuid=characteristic.uuid,
                                characteristic_note=note,
                                data=bytes(value),
                            )
                            print(f"  read {characteristic.uuid}: {bytes(value).hex(' ')}")
                        except Exception as e:  # noqa: BLE001
                            capture.write(
                                kind="info",
                                peripheral_uuid=address,
                                characteristic_uuid=characteristic.uuid,
                                message=f"read failed: {e}",
                            )

            print("Subscribed. Recording notifications until Ctrl-C...")
            try:
                await asyncio.Event().wait()
            except asyncio.CancelledError:
                pass
    except KeyboardInterrupt:
        pass
    finally:
        capture.write(kind="disconnect", peripheral_uuid=address, message="Session ended")
        capture.close()
        print("Capture closed.")


def main() -> None:
    parser = argparse.ArgumentParser(description="DropMixBLEProbe (Python/Bleak)")
    sub = parser.add_subparsers(dest="command", required=True)

    list_p = sub.add_parser("list", help="Scan and print nearby BLE peripherals")
    list_p.add_argument(
        "--timeout", type=float, default=None,
        help="Stop scanning after N seconds (default: run until Ctrl-C)",
    )

    cap_p = sub.add_parser("capture", help="Connect to one peripheral and record notifications")
    cap_p.add_argument("address", help="Peripheral address/UUID from `list` output")
    cap_p.add_argument("capture_name", help="Name for the capture file (no extension)")
    cap_p.add_argument(
        "--captures-dir", default="../captures",
        help="Directory to write <capture-name>.jsonl into (default: ../captures, shared with the Swift probe)",
    )

    args = parser.parse_args()

    try:
        if args.command == "list":
            asyncio.run(cmd_list(args.timeout))
        elif args.command == "capture":
            asyncio.run(cmd_capture(args.address, args.capture_name, Path(args.captures_dir)))
    except KeyboardInterrupt:
        print("\nStopped.")
        sys.exit(0)


if __name__ == "__main__":
    main()
