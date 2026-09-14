"""The TrackmaniaTurboWorld class -- wires regions/locations/items/rules together.

Each concern lives in its own file (constants.py, regions.py, locations.py,
items.py, rules.py, web_world.py), the same file-split convention the
reference apworld APQuest teaches. See this package's docstring
(__init__.py) for the full campaign/unlock-model design.
"""
from __future__ import annotations

from typing import Dict, List

from Options import OptionError
from worlds.AutoWorld import World

from . import items, locations, regions, rules
from .constants import BLOCK_THRESHOLDS, BLOCKS, ENVIRONMENTS, GAME_NAME, MEDALS, TRACK_LABELS
from .constants import block_complete_name, tier_complete_name
from .items import TrackmaniaTurboItem
from .Options import TrackmaniaTurboOptions
from .web_world import TrackmaniaTurboWeb


class TrackmaniaTurboWorld(World):
    """
    Trackmania Turbo -- the official 200-track solo campaign as an Archipelago
    randomizer. Medals you earn become location checks; a single Progressive
    Medal currency unlocks the campaign's 20 blocks, enforced by the Openplanet
    plugin (Turbo has no unlock API).
    """

    game = GAME_NAME
    web = TrackmaniaTurboWeb()

    options_dataclass = TrackmaniaTurboOptions
    options: TrackmaniaTurboOptions

    item_name_to_id = items.ITEM_NAME_TO_ID
    location_name_to_id = locations.LOCATION_NAME_TO_ID

    # The plugin still reads these from slot_data; only "progressive" works.
    goal = "campaign_finish"

    # ---- setup ------------------------------------------------------------

    def generate_early(self) -> None:
        if self.options.unlock_style.current_key == "real_medals":
            raise OptionError(
                "Trackmania Turbo: unlock_style 'real_medals' is not implemented "
                "yet -- use 'progressive' (the default)."
            )

        floor = ["bronze", "silver", "gold", "author"].index(
            self.options.medals_required.current_key
        )
        self.medal_tiers: List[str] = [m for m in MEDALS if MEDALS.index(m) >= floor]

        self.real_location_names: List[str] = [
            f"{label} - {medal}"
            for label in TRACK_LABELS
            for medal in self.medal_tiers
        ]
        self.real_location_names += [block_complete_name(i) for i in range(BLOCKS)]
        self.real_location_names += [
            tier_complete_name(i) for i in range(0, BLOCKS, len(ENVIRONMENTS))
        ]

    # ---- items --------------------------------------------------------------

    def create_item(self, name: str) -> TrackmaniaTurboItem:
        return items.create_item_with_correct_classification(self, name)

    def get_filler_item_name(self) -> str:
        return items.FILLER_NAME

    def create_items(self) -> None:
        items.create_all_items(self)

    # ---- regions & locations ------------------------------------------------

    def create_regions(self) -> None:
        regions.create_and_connect_regions(self)
        locations.create_all_locations(self)

    # ---- rules --------------------------------------------------------------

    def set_rules(self) -> None:
        rules.set_all_rules(self)

    # ---- slot data ------------------------------------------------------

    def fill_slot_data(self) -> Dict[str, object]:
        return {
            "unlock_style": self.options.unlock_style.current_key,
            "goal": self.goal,
            "block_thresholds": BLOCK_THRESHOLDS,
            "medals_required": self.options.medals_required.current_key,
            "seed_name": self.multiworld.seed_name,
            "slot": self.player,
        }
