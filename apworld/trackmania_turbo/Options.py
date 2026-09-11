"""YAML options for the Trackmania Turbo world."""

from dataclasses import dataclass

from Options import Choice, PerGameCommonOptions


class UnlockStyle(Choice):
    """How the campaign's 20 blocks unlock.

    progressive (default, the only implemented style): the multiworld sends a
    single "Progressive Medal" item; block i opens once you've received
    block_thresholds[i] of them. No grade distinction, so a single running
    total gates every block -- this is what keeps the seed solvable solo (see
    the world module docstring for why a per-grade currency wasn't).

    real_medals: NOT IMPLEMENTED YET. Reserved for a future opt-in that gates
    each block on the exact Bronze/Silver/Gold medal grade it needs (the
    original design). Selecting it raises an error at generation time.
    """
    display_name = "Unlock Style"
    option_progressive = 0
    option_real_medals = 1
    default = 0


class MedalsRequired(Choice):
    """Lowest medal tier that sends a per-track location check.

    The campaign always unlocks the "vanilla" way -- 20 blocks of 10 tracks,
    each block opened by receiving "<grade> Medal" items (see the world module
    docstring). This option only controls which medal tiers are checkable:

      gold (default): Gold + Author per track (~400 checks).
      author: Author only (~200 checks).
      silver: Silver + Gold + Author (~600).
      bronze: all four tiers (~800).

    A bare finish (no medal) is never a check; the plugin tracks it for the
    milestone locations and the goal.
    """
    display_name = "Medals Required"
    option_bronze = 0
    option_silver = 1
    option_gold = 2
    option_author = 3
    default = 2


@dataclass
class TrackmaniaTurboOptions(PerGameCommonOptions):
    unlock_style: UnlockStyle
    medals_required: MedalsRequired
