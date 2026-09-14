"""Item pool: the single Progressive Medal currency, filler and traps.

See the package docstring (__init__.py) for why a single ever-increasing
currency replaced an earlier per-grade (Bronze/Silver/Gold Medal) design that
was mathematically unsolvable solo.
"""
from __future__ import annotations

from typing import TYPE_CHECKING, Dict, List

from BaseClasses import Item, ItemClassification
from Options import OptionError

from .constants import BLOCK_THRESHOLDS, GAME_NAME

if TYPE_CHECKING:
    from .world import TrackmaniaTurboWorld

ITEM_ID_BASE = 271_828_000

PROGRESSIVE_MEDAL_NAME = "Progressive Medal"
# headroom above the last block's threshold so you keep earning post-goal and
# Fill has slack.
PROGRESSIVE_MEDAL_SURPLUS = 10

FILLER_NAME = "Nitro Boost"

# Trap item names -- must match the plugin's TrackTable.as TRAP_* constants.
# The full universe (kept stable for ids / forward-compat even though three of
# them are currently dormant -- see ACTIVE_TRAP_NAMES below).
TRAP_NAMES: List[str] = ["Blind Trap", "Giant Car Trap", "Tiny Car Trap", "Respawn Trap"]

# Trap names actually selected by create_all_items(). In-game testing 2026-09-12
# confirmed only Blind Trap works: Giant/Tiny Car write+restore
# CTrackManiaRace.ScaleCarValue cleanly (per the plugin log) but the car does
# not visibly resize, and Respawn Trap's BackToMainMenu() effect was rejected
# by the user ("respawn is not what I wanted" / "mark everything else not
# working"). Restore entries here once TrapManager.as fixes them -- see the
# plugin CLAUDE.md "Traps" open item / the traps-implemented memory.
ACTIVE_TRAP_NAMES: List[str] = ["Blind Trap"]


def _build_item_table() -> Dict[str, int]:
    table: Dict[str, int] = {}
    idx = 0
    table[FILLER_NAME] = ITEM_ID_BASE + idx
    idx += 1
    table[PROGRESSIVE_MEDAL_NAME] = ITEM_ID_BASE + idx
    idx += 1
    for trap_name in TRAP_NAMES:
        table[trap_name] = ITEM_ID_BASE + idx
        idx += 1
    return table


ITEM_NAME_TO_ID = _build_item_table()


class TrackmaniaTurboItem(Item):
    game = GAME_NAME


def create_item_with_correct_classification(world: TrackmaniaTurboWorld, name: str) -> TrackmaniaTurboItem:
    if name == PROGRESSIVE_MEDAL_NAME:
        classification = ItemClassification.progression
    elif name in TRAP_NAMES:
        classification = ItemClassification.trap
    else:
        classification = ItemClassification.filler
    return TrackmaniaTurboItem(name, classification, ITEM_NAME_TO_ID[name], world.player)


def create_all_items(world: TrackmaniaTurboWorld) -> None:
    need = BLOCK_THRESHOLDS[-1] + PROGRESSIVE_MEDAL_SURPLUS
    pool: List[TrackmaniaTurboItem] = [
        world.create_item(PROGRESSIVE_MEDAL_NAME) for _ in range(need)
    ]

    remaining = len(world.real_location_names) - len(pool)
    if remaining < 0:
        raise OptionError(
            "Trackmania Turbo: medal pool larger than the location count "
            f"({len(pool)} > {len(world.real_location_names)})."
        )
    trap_chance = world.options.trap_chance.value
    for _ in range(remaining):
        if trap_chance > 0 and world.random.randint(1, 100) <= trap_chance:
            pool.append(world.create_item(world.random.choice(ACTIVE_TRAP_NAMES)))
        else:
            pool.append(world.create_item(FILLER_NAME))
    world.multiworld.itempool += pool
