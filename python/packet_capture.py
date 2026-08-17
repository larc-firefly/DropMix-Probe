"""
Appends timestamped, raw-byte records to a JSONL file so that every capture
session is preserved as versionable evidence rather than summarized or
discarded. One JSON object per line.

Record schema is kept identical to Sources/DropMixBLEProbe/PacketCapture.swift
so captures from either tool can be analyzed with the same scripts.
"""

import json
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional


class PacketCapture:
    def __init__(self, path: str):
        self._path = Path(path)
        self._path.parent.mkdir(parents=True, exist_ok=True)
        self._file = open(self._path, "a", encoding="utf-8")
        self._start = time.monotonic()

    def write(
        self,
        kind: str,
        peripheral_uuid: Optional[str] = None,
        service_uuid: Optional[str] = None,
        characteristic_uuid: Optional[str] = None,
        characteristic_note: Optional[str] = None,
        data: Optional[bytes] = None,
        message: Optional[str] = None,
    ) -> None:
        record = {
            "timestamp": datetime.now(timezone.utc).isoformat(timespec="milliseconds"),
            "monotonicMillis": (time.monotonic() - self._start) * 1000,
            "kind": kind,
            "peripheralUUID": peripheral_uuid,
            "serviceUUID": service_uuid,
            "characteristicUUID": characteristic_uuid,
            "characteristicNote": characteristic_note,
            "hexBytes": data.hex() if data is not None else None,
            "byteCount": len(data) if data is not None else None,
            "message": message,
        }
        self._file.write(json.dumps(record) + "\n")
        self._file.flush()

    def close(self) -> None:
        self._file.close()

    def __enter__(self) -> "PacketCapture":
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:
        self.close()
