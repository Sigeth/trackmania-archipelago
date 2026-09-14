"""Completion condition for the campaign_finish goal."""
from __future__ import annotations

from typing import TYPE_CHECKING

from .constants import BLOCK_THRESHOLDS
from .items import PROGRESSIVE_MEDAL_NAME

if TYPE_CHECKING:
    from .world import TrackmaniaTurboWorld


def set_all_rules(world: TrackmaniaTurboWorld) -> None:
    player = world.player
    # Implied by the last block's entrance rule (regions.py), but kept
    # explicit as the goal proxy: a bare finish isn't a location, so the
    # generator can't see `campaign_finish` directly and instead treats
    # "every block reachable" as the completable seed.
    world.multiworld.completion_condition[player] = lambda state: state.has(
        PROGRESSIVE_MEDAL_NAME, player, BLOCK_THRESHOLDS[-1]
    )
