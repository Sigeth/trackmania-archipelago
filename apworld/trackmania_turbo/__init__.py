"""
Trackmania Turbo -- Archipelago world.

Campaign layout: 5 difficulty tiers (White/Green/Blue/Red/Black) x 4 environments
(Canyon/Valley/Lagoon/Stadium) x 10 tracks = 200. In-game the maps are numbered
"001".."200", difficulty-major then environment then 1..10, so map 001 is
"White Canyon 01" and map 200 is "Black Stadium 10". The 200 tracks split into
20 "blocks" of 10 (one tier/environment pair each), in campaign order; block
index i = tier*4 + env, i in 0..19.

Unlock model (`unlock_style: progressive`, the only implemented one):

  Block i opens once you hold 10*i "Progressive Medal" items -- one single
  currency for all 20 blocks, no grade distinction. There are no track-unlock
  items in the pool; the Progressive Medal items *are* the randomised
  progression. Per-track checks are Gold + Author by default (`medals_required`
  lowers the floor) -- once a block is open, finishing a track sends whatever
  medal the player earned. A bare finish with no medal is tracked by the
  plugin, not a check; it drives the "<Block> Complete" (x20) and "<Tier>
  Complete" (x5) milestone checks and the `campaign_finish` goal.

  A prior design used three grade-specific items (Bronze/Silver/Gold Medal),
  gating each grade's blocks on that grade alone. That was mathematically
  unsolvable solo: by the time the Silver->Gold or Bronze->Silver transition
  needed its first big lump of the new grade, not enough *other* locations had
  been reachable yet to have handed out that many -- e.g. at the default `gold`
  floor, block 16 demanded 70+150+160 = 380 medals already collected, but only
  336 checks exist anywhere before it. A single currency has no such transition:
  the running total only ever goes up, so the same capacity math (see below)
  holds at every floor down to `author`. The `real_medals` unlock_style option
  is reserved for a future, carefully-scaled reintroduction of that per-grade
  design; selecting it raises `OptionError` for now.

The world models the 20-block cascade with real region logic: `Campaign` has one
Region per block, each connected with an entrance rule requiring the same
cumulative Progressive Medal count the plugin checks client-side
(`block_thresholds` in slot_data). This lets the generator's own accessibility
sweep verify a seed is completable in the order the game actually allows,
instead of treating every location as reachable from the start.

Beyond the ~200 Progressive Medal items needed to clear all 20 blocks (plus a
surplus), every remaining location holds a filler item. That filler pool is
where traps / cosmetics eventually go (see docs/apworld-design.md Tier 3/4);
none are implemented yet, so it's all `Nitro Boost` (a no-op) for now -- the
slot count is already reserved for when that lands.

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

# --- progressive unlock model --------------------------------------------

# block i opens at 10*i received Progressive Medal items (block 0 -> 0, always).
BLOCK_THRESHOLDS: List[int] = [10 * i for i in range(BLOCKS)]
PROGRESSIVE_MEDAL_NAME = "Progressive Medal"
# headroom above the last block's threshold so you keep earning post-goal and
# Fill has slack.
PROGRESSIVE_MEDAL_SURPLUS = 10

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
    table[PROGRESSIVE_MEDAL_NAME] = ITEM_ID_BASE + idx
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
    randomizer. Medals you earn become location checks; a single Progressive
    Medal currency unlocks the campaign's 20 blocks, enforced by the Openplanet
    plugin (Turbo has no unlock API).
    """

    game = GAME_NAME
    web = TrackmaniaTurboWeb()

    options_dataclass = TrackmaniaTurboOptions
    options: TrackmaniaTurboOptions

    item_name_to_id = ITEM_NAME_TO_ID
    location_name_to_id = LOCATION_NAME_TO_ID

    # The plugin still reads these from slot_data; only "progressive" works.
    goal = "campaign_finish"

    # ---- setup ----------------------------------------------------------

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
            ItemClassification.progression if name == PROGRESSIVE_MEDAL_NAME
            else ItemClassification.filler
        )
        return TrackmaniaTurboItem(name, classification, ITEM_NAME_TO_ID[name], self.player)

    def get_filler_item_name(self) -> str:
        return FILLER_NAME

    def create_items(self) -> None:
        need = BLOCK_THRESHOLDS[-1] + PROGRESSIVE_MEDAL_SURPLUS
        pool: List[TrackmaniaTurboItem] = [
            self.create_item(PROGRESSIVE_MEDAL_NAME) for _ in range(need)
        ]

        remaining = len(self.real_location_names) - len(pool)
        if remaining < 0:
            raise OptionError(
                "Trackmania Turbo: medal pool larger than the location count "
                f"({len(pool)} > {len(self.real_location_names)})."
            )
        # Reserved for traps/cosmetics later (docs/apworld-design.md Tier 3/4);
        # not implemented yet, so it's all plain filler for now.
        pool += [self.create_item(FILLER_NAME) for _ in range(remaining)]
        self.multiworld.itempool += pool

    # ---- regions & locations --------------------------------------------

    def create_regions(self) -> None:
        # Menu -> Campaign (hub) -> one Region per block. Each block's entrance
        # rule requires the same cumulative Progressive Medal count the plugin
        # checks in `ItemManager.IsTrackUnlocked` -- so the generator's sweep
        # only ever considers a location reachable when the real game would let
        # the player stand on that track. Block 0 has threshold 0 (always open,
        # no rule needed); the rest gate on `state.has(PROGRESSIVE_MEDAL_NAME, n)`.
        player = self.player
        menu = Region("Menu", player, self.multiworld)
        campaign = Region("Campaign", player, self.multiworld)
        menu.connect(campaign)
        self.multiworld.regions += [menu, campaign]

        for i in range(BLOCKS):
            block = Region(_block_name(i), player, self.multiworld)
            for label in _labels_in_block(i):
                for medal in self.medal_tiers:
                    name = f"{label} - {medal}"
                    block.locations.append(
                        TrackmaniaTurboLocation(player, name, LOCATION_NAME_TO_ID[name], block)
                    )
            complete_name = _block_complete_name(i)
            block.locations.append(
                TrackmaniaTurboLocation(player, complete_name, LOCATION_NAME_TO_ID[complete_name], block)
            )
            if _is_last_block_of_tier(i):
                tier_name = _tier_complete_name(i)
                block.locations.append(
                    TrackmaniaTurboLocation(player, tier_name, LOCATION_NAME_TO_ID[tier_name], block)
                )
            self.multiworld.regions.append(block)

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

    # ---- rules ---------------------------------------------------------

    def set_rules(self) -> None:
        player = self.player
        # Implied by the last block's entrance rule above, but kept explicit as
        # the goal proxy: a bare finish isn't a location, so the generator can't
        # see `campaign_finish` directly and instead treats "every block
        # reachable" as the completable seed.
        self.multiworld.completion_condition[player] = lambda state: state.has(
            PROGRESSIVE_MEDAL_NAME, player, BLOCK_THRESHOLDS[-1]
        )

    # ---- slot data ---------------------------------------------------

    def fill_slot_data(self) -> Dict[str, object]:
        return {
            "unlock_style": self.options.unlock_style.current_key,
            "goal": self.goal,
            "block_thresholds": BLOCK_THRESHOLDS,
            "medals_required": self.options.medals_required.current_key,
            "seed_name": self.multiworld.seed_name,
            "slot": self.player,
        }
