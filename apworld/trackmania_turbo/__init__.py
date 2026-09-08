"""
Trackmania Turbo -- Archipelago world.

Campaign layout: 5 difficulty tiers (White/Green/Blue/Red/Black) x 4 environments
(Canyon/Valley/Lagoon/Stadium) x 10 tracks = 200. In-game the maps are numbered
"001".."200", difficulty-major then environment then 1..10, so map 001 is
"White Canyon 01" and map 200 is "Black Stadium 10". The 200 tracks split into
20 "blocks" of 10 (one tier/environment pair each), in campaign order; block
index i = tier*4 + env, i in 0..19.

Unlock model (the only one -- retail-style gating):

  Block i opens once you hold 10*i "<grade> Medal" items, grade = Bronze for
  i<8, Silver for i<16, Gold for i>=16. There are no track-unlock items in the
  pool; the medal items *are* the randomised progression. Per-track checks are
  Gold + Author by default (`medals_required` lowers the floor) -- once a block
  is open, finishing a track sends whatever medal the player earned. A bare
  finish with no medal is tracked by the plugin, not a check; it drives the
  "<Block> Complete" (x20) and "<Tier> Complete" (x5) milestone checks and the
  `campaign_finish` goal.

The generator cannot model the 20-block cascade (a fine-grained region gate over
the single-currency medal pool is not solo-fillable), so the world uses one flat
Campaign region and the plugin enforces every block gate client-side from
`block_thresholds` in slot_data.

The strings here are a contract with the Openplanet plugin -- see the workspace
CLAUDE.md "Naming conventions the .apworld must agree on".
"""

from typing import Dict, List

from BaseClasses import Item, ItemClassification, Location, Region, Tutorial
from Options import OptionError
from worlds.AutoWorld import World, WebWorld

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

# Every medal tier exists in the id-map universe; a slot only instantiates the
# tiers at or above the `medals_required` floor (default Gold -> Gold + Author).
MEDALS: List[str] = ["Bronze", "Silver", "Gold", "Author"]

# Base offsets into the AP id space. Item ids and location ids are separate
# namespaces, so they may overlap.
LOCATION_ID_BASE = 271_828_000
ITEM_ID_BASE = 271_828_000

# --- vanilla unlock model -----------------------------------------------------

# block i opens at 10*i received medal items of its grade (block 0 -> 0, always).
BLOCK_THRESHOLDS: List[int] = [10 * i for i in range(BLOCKS)]
# grades: Bronze for the first 8 blocks (White + Green), Silver for the next 8
# (Blue + Red), Gold for the last 4 (Black).
MEDAL_ITEMS: List[str] = ["Bronze Medal", "Silver Medal", "Gold Medal"]
# a few medal items beyond the last gate so you keep earning and Fill has slack.
MEDAL_SURPLUS = 2

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
    table[FILLER_NAME] = ITEM_ID_BASE + idx
    idx += 1
    for medal_item in MEDAL_ITEMS:
        table[medal_item] = ITEM_ID_BASE + idx
        idx += 1
    return table


LOCATION_NAME_TO_ID = _build_location_table()
ITEM_NAME_TO_ID = _build_item_table()


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

    # The plugin still reads these from slot_data; they are constant now.
    unlock_style = "vanilla"
    goal = "campaign_finish"

    # ---- setup ----------------------------------------------------------

    def generate_early(self) -> None:
        floor = ["bronze", "silver", "gold", "author"].index(
            self.options.medals_required.current_key
        )
        self.medal_tiers: List[str] = [m for m in MEDALS if MEDALS.index(m) >= floor]

        self.real_location_names: List[str] = [
            f"{label} - {medal}"
            for label in _TRACK_LABELS
            for medal in self.medal_tiers
        ]
        self.real_location_names += [_block_complete_name(i) for i in range(BLOCKS)]
        self.real_location_names += [
            _tier_complete_name(i) for i in range(0, BLOCKS, len(ENVIRONMENTS))
        ]

    # ---- items --------------------------------------------------------------

    def create_item(self, name: str) -> TrackmaniaTurboItem:
        classification = (
            ItemClassification.progression if name in MEDAL_ITEMS
            else ItemClassification.filler
        )
        return TrackmaniaTurboItem(name, classification, ITEM_NAME_TO_ID[name], self.player)

    def get_filler_item_name(self) -> str:
        return FILLER_NAME

    def create_items(self) -> None:
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
                "Trackmania Turbo: medal pool larger than the location count "
                f"({len(pool)} > {len(self.real_location_names)})."
            )
        pool += [self.create_item(FILLER_NAME) for _ in range(remaining)]
        self.multiworld.itempool += pool

    # ---- regions & locations --------------------------------------------

    def create_regions(self) -> None:
        # One flat Campaign region -- the medal items are macguffins and the
        # plugin enforces all 20 block gates client-side (from `block_thresholds`
        # in slot_data). A fine-grained region cascade over the single-currency
        # medal pool is not solo-fillable (`fill_restrictive` has no way to
        # front-load the grade a gate needs). Completion still needs the full
        # medal counts, so the medal items stay progression.
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
        player = self.player
        # Locations are unruled (flat region); the plugin gates blocks. Completion
        # needs the full medal counts -- holding all three means every block, and
        # hence every milestone and every checkable medal, is reachable.
        self.multiworld.completion_condition[player] = lambda state: (
            state.has("Bronze Medal", player, BLOCK_THRESHOLDS[7])
            and state.has("Silver Medal", player, BLOCK_THRESHOLDS[15])
            and state.has("Gold Medal", player, BLOCK_THRESHOLDS[19])
        )

    # ---- slot data ---------------------------------------------------

    def fill_slot_data(self) -> Dict[str, object]:
        return {
            "unlock_style": self.unlock_style,
            "goal": self.goal,
            "block_thresholds": BLOCK_THRESHOLDS,
            "medals_required": self.options.medals_required.current_key,
            "seed_name": self.multiworld.seed_name,
            "slot": self.player,
        }
