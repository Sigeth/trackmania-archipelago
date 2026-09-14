"""Region graph: Menu -> Campaign -> one Region per 10-track block.

Each block's entrance requires the same cumulative Progressive Medal count
the Openplanet plugin checks client-side (ItemManager.IsTrackUnlocked), so
the generator's own accessibility sweep only ever considers a location
reachable when the real game would let the player stand on that track.
"""
from __future__ import annotations

from typing import TYPE_CHECKING

from BaseClasses import Region

from .constants import BLOCK_THRESHOLDS, BLOCKS, block_name
from .items import PROGRESSIVE_MEDAL_NAME

if TYPE_CHECKING:
    from .world import TrackmaniaTurboWorld


def create_and_connect_regions(world: TrackmaniaTurboWorld) -> None:
    player = world.player
    menu = Region("Menu", player, world.multiworld)
    campaign = Region("Campaign", player, world.multiworld)
    menu.connect(campaign)
    world.multiworld.regions += [menu, campaign]

    for i in range(BLOCKS):
        block = Region(block_name(i), player, world.multiworld)
        world.multiworld.regions.append(block)

        threshold = BLOCK_THRESHOLDS[i]
        if threshold == 0:
            campaign.connect(block, name=f"Campaign -> {block.name}")
        else:
            campaign.connect(
                block,
                name=f"Campaign -> {block.name}",
                rule=lambda state, threshold=threshold: (
                    state.has(PROGRESSIVE_MEDAL_NAME, player, threshold)
                ),
            )
