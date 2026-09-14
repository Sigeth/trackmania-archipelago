"""Location table: per-track medal checks plus block/tier milestones.

A bare finish (no medal) is not a check; the plugin tracks it locally to
drive the milestone locations and the campaign_finish goal (see the package
docstring in __init__.py).
"""
from __future__ import annotations

from typing import TYPE_CHECKING, Dict

from BaseClasses import Location

from .constants import (
    BLOCKS,
    ENVIRONMENTS,
    GAME_NAME,
    MEDALS,
    TRACK_LABELS,
    block_complete_name,
    block_name,
    is_last_block_of_tier,
    labels_in_block,
    tier_complete_name,
)

if TYPE_CHECKING:
    from .world import TrackmaniaTurboWorld

LOCATION_ID_BASE = 271_828_000


def _build_location_table() -> Dict[str, int]:
    table: Dict[str, int] = {}
    idx = 0
    for label in TRACK_LABELS:
        for medal in MEDALS:
            table[f"{label} - {medal}"] = LOCATION_ID_BASE + idx
            idx += 1
    for i in range(BLOCKS):
        table[block_complete_name(i)] = LOCATION_ID_BASE + idx
        idx += 1
    for i in range(0, BLOCKS, len(ENVIRONMENTS)):
        table[tier_complete_name(i)] = LOCATION_ID_BASE + idx
        idx += 1
    return table


LOCATION_NAME_TO_ID = _build_location_table()


class TrackmaniaTurboLocation(Location):
    game = GAME_NAME


def create_all_locations(world: TrackmaniaTurboWorld) -> None:
    """Add every real location to its already-created block Region.

    Must run after regions.create_and_connect_regions -- it looks up each
    block Region by name via world.get_region(). world.medal_tiers is set in
    world.generate_early(), which always runs before create_regions().
    """
    for i in range(BLOCKS):
        block = world.get_region(block_name(i))
        for label in labels_in_block(i):
            for medal in world.medal_tiers:
                name = f"{label} - {medal}"
                block.locations.append(
                    TrackmaniaTurboLocation(world.player, name, LOCATION_NAME_TO_ID[name], block)
                )
        complete_name = block_complete_name(i)
        block.locations.append(
            TrackmaniaTurboLocation(world.player, complete_name, LOCATION_NAME_TO_ID[complete_name], block)
        )
        if is_last_block_of_tier(i):
            tier_name = tier_complete_name(i)
            block.locations.append(
                TrackmaniaTurboLocation(world.player, tier_name, LOCATION_NAME_TO_ID[tier_name], block)
            )
