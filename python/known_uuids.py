"""
Community-reported UUIDs for the DropMix board.
 
IMPORTANT: These are leads, not confirmed protocol knowledge. Nothing in
this probe assumes they are correct. The probe discovers services and
characteristics dynamically from whatever board it connects to, and only
annotates output when a discovered UUID happens to match one of these,
purely to make raw captures easier to read while reviewing them later.
 
Kept in sync with Sources/DropMixBLEProbe/KnownUUIDs.swift.
"""
 
from __future__ import annotations
 
REPORTED_ANNOTATIONS = {
    "0005cfd4-2730-4bb8-b160-502596e4c2fe": "reported button-related (unverified)",
    "0006cfd4-2730-4bb8-b160-502596e4c2fe": "reported LED-related (unverified)",
}
 
 
def note_for(uuid: str) -> str | None:
    """Return the annotation for a characteristic/service UUID, if known."""
    return REPORTED_ANNOTATIONS.get(uuid.lower())
 
