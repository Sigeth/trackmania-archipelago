"""
Trackmania Turbo -- Archipelago world.

Campaign layout: 5 difficulty tiers (White/Green/Blue/Red/Black) x 4 environments
(Canyon/Valley/Lagoon/Stadium) x 10 tracks = 200. In-game the maps are numbered
"001".."200", difficulty-major then environment then 1..10, so map 001 is
"White Canyon 01" and map 200 is "Black Stadium 10". The 200 tracks split into
20 "blocks" of 10 (one tier/environment pair each), in campaign order; block
index i = tier*4 + env, i in 0..19.

Unlock styles (YAML `unlock_style`):

  * vanilla (default) -- retail-style gating. Block i opens once you hold 10*i
    "<grade> Medal" items, grade = Bronze for i<8, Silver for i<16, Gold for
    i>=16. No track-unlock items in the pool; the medal items are the
    progression. Per-track checks are Gold + Author -- once a block is open,
    finishing a track sends whatever medal the player earned. A bare finish with
    no medal is tracked by the plugin, not a check; it drives the
    "<Block> Complete" (x20) and "<Tier> Complete" (x5) milestone checks and the
    default `campaign_finish` goal.

  * progressive -- "Progressive <Tier>" items, one per track in campaign order.

  * individual -- not implemented yet (raises OptionError).

The strings here are a contract with the Openplanet plugin -- see the workspace
CLAUDE.md "Naming conventions the .apworld must agree on".
"""

from math import ceil
from typing import Dict, List

from BaseClasses import Item, ItemClassification, Location, Region, Tutorial
from Options import OptionError
from worlds.AutoWorld import World, WebWorld
from worlds.generic.Rules import set_rule

from .Options import TrackmaniaTurboOptions

GAME_NAME = "Trackmania Turbo"

# Kept in lockstep with info.toml / archipelago.json by tools/bump_version.py
# (semantic-release); tools/lint.py fails the build if they drift.
__version__ = "0.1.0"

TIERS: List[str] = ["White", "Green", "Blue", "Red", "Black"]
ENVIRONMENTS: List[str] = ["Canyon", "Valley", "Lagoon", "Stadium"]
TRACKS_PER_ENV = 10
TRACKS_PER_TIER = TRACKS_PER_ENV * len(ENVIRONMENTS)          # 40
TRACKS_PER_BLOCK = TRACKS_PER_ENV                             # 10
BLOCKS = len(TIERS) * len(ENVIRONMENTS)                       # 20

# Every medal tier exists in the id-map universe; a vanilla slot only instantiates
# Gold + Author locations, the progressive/individual styles use the
# `medals_required` floor.
MEDALS: List[str] = ["Bronze", "Silver", "Gold", "Author"]
VANILLA_MEDALS: List[str] = ["Gold", "Author"]

# Base offsets into the AP id space. Item ids and location ids are separate
# namespaces, so they may overlap.
LOCATION_ID_BASE = 271_828_000
ITEM_ID_BASE = 271_828_000

# --- vanilla unlock model -------------------------------------------------------

# block i opens at 10*i received medal items of its grade (block 0 -> 0, always).
BLOCK_THRESHOLDS: List[int] = [10 * i for i in range(BLOCKS)]
# grades: Bronze for the first 8 blocks (White + Green), Silver for the next 8
# (Blue + Red), Gold for the last 4 (Black).
MEDAL_ITEMS: List[str] = ["Bronze Medal", "Silver Medal", "Gold Medal"]
# a few medal items beyond the last gate so you keep earning and Fill has slack.
MEDAL_SURPLUS = 2

# --- progressive unlock model (unchanged) -------------------------------------

# How many tracks one "Progressive <Tier>" copy unlocks *for generation logic*.
# The plugin unlocks tracks 1:1 with progressive items; the generator only needs a
# coarser gate so fill has room to breathe.
TRACKS_PER_PROGRESSIVE = 5
MAX_PROGRESSIVE = -(-TRACKS_PER_TIER // TRACKS_PER_PROGRESSIVE)  # ceil = 8

FILLER_NAME = "Nitro Boost"


def _track_labels() -> List[str]:
    """All 200 labels in campaign order."""
    out: List[str] = []
    for tier in TIERS:
        for env in ENVIRONMENTS:
            for i in range(1, TRACKS_PER_ENV + 1):
                out.append(f"{tier} {env} {i:02d}")
    return out


_TRACK_LABELS = _track_labels()
_CAMPAIGN_NUMBER = {label: n for n, label in enumerate(_TRACK_LABELS, start=1)}


def _tier_of(label: str) -> str:
    return label.split(" ", 1)[0]


def _index_in_tier(label: str) -> int:
    """1..40 position of this label within its tier, in campaign order."""
    tier, env, num = label.split(" ")
    return ENVIRONMENTS.index(env) * TRACKS_PER_ENV + int(num)


def _block_index(label: str) -> int:
    """0..19 block containing this track, in campaign order."""
    return (_CAMPAIGN_NUMBER[label] - 1) // TRACKS_PER_BLOCK


def _block_grade(i: int) -> str:
    return "Bronze" if i < 8 else "Silver" if i < 16 else "Gold"


def _block_name(i: int) -> str:
    return f"{TIERS[i // len(ENVIRONMENTS)]} {ENVIRONMENTS[i % len(ENVIRONMENTS)]}"


def _tier_name(i: int) -> str:
    return TIERS[i // len(ENVIRONMENTS)]


def _labels_in_block(i: int) -> List[str]:
    start = i * TRACKS_PER_BLOCK
    return _TRACK_LABELS[start:start + TRACKS_PER_BLOCK]


def _block_complete_name(i: int) -> str:
    return f"{_block_name(i)} Complete"


def _tier_complete_name(i: int) -> str:
    return f"{_tier_name(i)} Complete"


def _is_last_block_of_tier(i: int) -> bool:
    return i % len(ENVIRONMENTS) == len(ENVIRONMENTS) - 1


def _build_location_table() -> Dict[str, int]:
    table: Dict[str, int] = {}
    idx = 0
    for label in _TRACK_LABELS:
        for medal in MEDALS:
            table[f"{label} - {medal}"] = LOCATION_ID_BASE + idx
            idx += 1
    for i in range(BLOCKS):
        table[_block_complete_name(i)] = LOCATION_ID_BASE + idx
        idx += 1
    for i in range(0, BLOCKS, len(ENVIRONMENTS)):
        table[_tier_complete_name(i)] = LOCATION_ID_BASE + idx
        idx += 1
    return table


def _build_item_table() -> Dict[str, int]:
    table: Dict[str, int] = {}
    idx = 0
    for tier in TIERS:
        table[f"Progressive {tier}"] = ITEM_ID_BASE + idx
        idx += 1
    table[FILLER_NAME] = ITEM_ID_BASE + idx
    idx += 1
    for medal_item in MEDAL_ITEMS:
        table[medal_item] = ITEM_ID_BASE + idx
        idx += 1
    return table


LOCATION_NAME_TO_ID = _build_location_table()
ITEM_NAME_TO_ID = _build_item_table()

_MEDAL_ITEM_FOR_GRADE = {
    "Bronze": "Bronze Medal",
    "Silver": "Silver Medal",
    "Gold": "Gold Medal",
}


class TrackmaniaTurboItem(Item):
    game = GAME_NAME


class TrackmaniaTurboLocation(Location):
    game = GAME_NAME


class TrackmaniaTurboWeb(WebWorld):
    tutorials = [Tutorial(
        "Multiworld Setup Guide",
        "A guide to setting up Trackmania Turbo for Archipelago.",
        "English",
        "setup_en.md",
        "setup/en",
        ["Sigeth"],
    )]


class TrackmaniaTurboWorld(World):
    """
    Trackmania Turbo -- the official 200-track solo campaign as an Archipelago
    randomizer. Medals you earn become location checks; the campaign unlocks the
    Archipelago way, enforced by the Openplanet plugin (Turbo has no unlock API).
    """

    game = GAME_NAME
    web = TrackmaniaTurboWeb()

    options_dataclass = TrackmaniaTurboOptions
    options: TrackmaniaTurboOptions

    item_name_to_id = ITEM_NAME_TO_ID
    location_name_to_id = LOCATION_NAME_TO_ID

    # ---- setup ----------------------------------------------------------

    def generate_early(self) -> None:
        self.unlock_style: str = self.options.unlock_style.current_key
        self.goal: str = self.options.goal.current_key

        if self.unlock_style == "individual":
            raise OptionError(
                "Trackmania Turbo: unlock_style 'individual' is not implemented yet "
                "-- use 'vanilla' or 'progressive'."
            )

        if self.unlock_style == "vanilla":
            self.medal_tiers: List[str] = list(VANILLA_MEDALS)
        else:
            floor = ["bronze", "silver", "gold", "author"].index(
                self.options.medals_required.current_key
            )
            self.medal_tiers = [m for m in MEDALS if MEDALS.index(m) >= floor]

        self.real_location_names: List[str] = [
            f"{label} - {medal}"
            for label in _TRACK_LABELS
            for medal in self.medal_tiers
        ]
        if self.unlock_style == "vanilla":
            self.real_location_names += [_block_complete_name(i) for i in range(BLOCKS)]
            self.real_location_names += [
                _tier_complete_name(i) for i in range(0, BLOCKS, len(ENVIRONMENTS))
            ]

    # ---- items --------------------------------------------------------------

    def create_item(self, name: str) -> TrackmaniaTurboItem:
        if name.startswith("Progressive ") or name in MEDAL_ITEMS:
            classification = ItemClassification.progression
        else:
            classification = ItemClassification.filler
        return TrackmaniaTurboItem(name, classification, ITEM_NAME_TO_ID[name], self.player)

    def get_filler_item_name(self) -> str:
        return FILLER_NAME

    def create_items(self) -> None:
        if self.unlock_style == "vanilla":
            self._create_items_vanilla()
        else:
            self._create_items_progressive()

    def _create_items_vanilla(self) -> None:
        pool: List[TrackmaniaTurboItem] = []
        need = {
            "Bronze Medal": BLOCK_THRESHOLDS[7] + MEDAL_SURPLUS,     # 70 + surplus
            "Silver Medal": BLOCK_THRESHOLDS[15] + MEDAL_SURPLUS,    # 150 + surplus
            "Gold Medal": BLOCK_THRESHOLDS[19] + MEDAL_SURPLUS,      # 190 + surplus
        }
        for name, count in need.items():
            pool += [self.create_item(name) for _ in range(count)]

        remaining = len(self.real_location_names) - len(pool)
        if remaining < 0:
            raise OptionError(
                "Trackmania Turbo: vanilla medal pool larger than the location count "
                f"({len(pool)} > {len(self.real_location_names)})."
            )
        pool += [self.create_item(FILLER_NAME) for _ in range(remaining)]
        self.multiworld.itempool += pool

    def _create_items_progressive(self) -> None:
        pool: List[TrackmaniaTurboItem] = []
        for tier in TIERS:
            self.multiworld.push_precollected(self.create_item(f"Progressive {tier}"))
            pool += [self.create_item(f"Progressive {tier}") for _ in range(TRACKS_PER_TIER - 1)]

        remaining = len(self.real_location_names) - len(pool)
        pool += [self.create_item(FILLER_NAME) for _ in range(remaining)]
        self.multiworld.itempool += pool

    # ---- regions & locations --------------------------------------------

    def create_regions(self) -> None:
        # One flat Campaign region for every style. In vanilla the medal items are
        # macguffins -- the plugin enforces all 20 block gates client-side (from
        # `block_thresholds` in slot_data); a fine-grained region cascade over a
        # ~410-item single-currency pool is not solo-fillable, `fill_restrictive`
        # has no way to front-load the grade a gate needs. Completion still needs
        # the full medal counts, so the medal items stay progression. In the item
        # styles the gating lives in per-location rules (set_rules).
        menu = Region("Menu", self.player, self.multiworld)
        campaign = Region("Campaign", self.player, self.multiworld)
        for name in self.real_location_names:
            campaign.locations.append(
                TrackmaniaTurboLocation(self.player, name, LOCATION_NAME_TO_ID[name], campaign)
            )
        menu.connect(campaign)
        self.multiworld.regions += [menu, campaign]

    # ---- rules ---------------------------------------------------------

    def set_rules(self) -> None:
        if self.unlock_style == "vanilla":
            self._set_rules_vanilla()
        else:
            self._set_rules_progressive()

    def _set_rules_vanilla(self) -> None:
        player = self.player
        # Locations are unruled (flat region); the plugin gates blocks. Completion
        # needs the full medal counts -- holding all three means every block, and
        # hence every milestone and every Gold/Author check, is reachable.
        self.multiworld.completion_condition[player] = lambda state: (
            state.has("Bronze Medal", player, BLOCK_THRESHOLDS[7])
            and state.has("Silver Medal", player, BLOCK_THRESHOLDS[15])
            and state.has("Gold Medal", player, BLOCK_THRESHOLDS[19])
        )

    def _set_rules_progressive(self) -> None:
        player = self.player
        for label in _TRACK_LABELS:
            required_item = f"Progressive {_tier_of(label)}"
            required_count = ceil(_index_in_tier(label) / TRACKS_PER_PROGRESSIVE)
            for medal in self.medal_tiers:
                set_rule(
                    self.multiworld.get_location(f"{label} - {medal}", player),
                    lambda state, item=required_item, n=required_count: state.has(item, player, n),
                )

        self.multiworld.completion_condition[player] = lambda state: all(
            state.has(f"Progressive {t}", player, MAX_PROGRESSIVE) for t in TIERS
        )

    # ---- slot data ---------------------------------------------------

    def fill_slot_data(self) -> Dict[str, object]:
        return {
            "unlock_style": self.unlock_style,
            "goal": self.goal,
            "block_thresholds": BLOCK_THRESHOLDS,
            "medals_required": self.options.medals_required.current_key,
            "map_shuffle": "off",
            "seed_name": self.multiworld.seed_name,
            "slot": self.player,
        }
