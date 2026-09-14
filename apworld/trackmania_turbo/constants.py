"""Campaign geometry: game name, track labels, blocks and tiers.

Shared by regions.py, locations.py, items.py and world.py. See the package
docstring (__init__.py) for the full unlock-model rationale this geometry
serves.
"""
from __future__ import annotations

from typing import List

GAME_NAME = "Trackmania Turbo"

TIERS: List[str] = ["White", "Green", "Blue", "Red", "Black"]
ENVIRONMENTS: List[str] = ["Canyon", "Valley", "Lagoon", "Stadium"]
TRACKS_PER_ENV = 10
TRACKS_PER_TIER = TRACKS_PER_ENV * len(ENVIRONMENTS)          # 40
TRACKS_PER_BLOCK = TRACKS_PER_ENV                             # 10
BLOCKS = len(TIERS) * len(ENVIRONMENTS)                       # 20

# Every medal tier exists in the id-map universe; a slot only instantiates the
# tiers at or above the `medals_required` floor (default Gold -> Gold + Author).
MEDALS: List[str] = ["Bronze", "Silver", "Gold", "Author"]

# block i opens at 10*i received Progressive Medal items (block 0 -> 0, always).
BLOCK_THRESHOLDS: List[int] = [10 * i for i in range(BLOCKS)]


def _track_labels() -> List[str]:
    """All 200 labels in campaign order."""
    out: List[str] = []
    for tier in TIERS:
        for env in ENVIRONMENTS:
            for i in range(1, TRACKS_PER_ENV + 1):
                out.append(f"{tier} {env} {i:02d}")
    return out


TRACK_LABELS = _track_labels()
_CAMPAIGN_NUMBER = {label: n for n, label in enumerate(TRACK_LABELS, start=1)}


def tier_of(label: str) -> str:
    return label.split(" ", 1)[0]


def block_index(label: str) -> int:
    """0..19 block containing this track, in campaign order."""
    return (_CAMPAIGN_NUMBER[label] - 1) // TRACKS_PER_BLOCK


def block_name(i: int) -> str:
    return f"{TIERS[i // len(ENVIRONMENTS)]} {ENVIRONMENTS[i % len(ENVIRONMENTS)]}"


def tier_name(i: int) -> str:
    return TIERS[i // len(ENVIRONMENTS)]


def labels_in_block(i: int) -> List[str]:
    start = i * TRACKS_PER_BLOCK
    return TRACK_LABELS[start:start + TRACKS_PER_BLOCK]


def block_complete_name(i: int) -> str:
    return f"{block_name(i)} Complete"


def tier_complete_name(i: int) -> str:
    return f"{tier_name(i)} Complete"


def is_last_block_of_tier(i: int) -> bool:
    return i % len(ENVIRONMENTS) == len(ENVIRONMENTS) - 1
