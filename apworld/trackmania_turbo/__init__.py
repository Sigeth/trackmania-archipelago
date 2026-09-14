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
surplus), every remaining location holds a filler item: `Nitro Boost` (a
no-op), or -- when `trap_chance` (default 0, opt-in) rolls one -- a trap item,
picked uniformly from TRAP_NAMES. Traps are `ItemClassification.trap` so they
route through the normal filler-swap machinery; the Openplanet plugin's
TrapManager.as is what actually applies them (car-scale is flagged there as
unverified end to end -- everything else is confirmed).

The strings here are a contract with the Openplanet plugin -- see the workspace
CLAUDE.md "Naming conventions the .apworld must agree on".

File layout (same file-split convention the reference apworld APQuest
teaches): constants.py (campaign geometry) -> regions.py -> locations.py ->
items.py -> rules.py -> web_world.py -> world.py (ties it all together).
Options live in Options.py.
"""

# Kept in lockstep with info.toml / archipelago.json by tools/bump_version.py
# (semantic-release); tools/lint.py fails the build if they drift.
__version__ = "0.1.0"

# Re-exported for callers that expect these on the package itself (e.g. the
# test suite: `from .. import ACTIVE_TRAP_NAMES, TRAP_NAMES`) and per the
# workspace CLAUDE.md naming contract.
from .items import ACTIVE_TRAP_NAMES as ACTIVE_TRAP_NAMES
from .items import TRAP_NAMES as TRAP_NAMES

# Importing the world class registers it with AutoWorld.
from .world import TrackmaniaTurboWorld as TrackmaniaTurboWorld
