"""YAML options for the Trackmania Turbo world."""

from dataclasses import dataclass

from Options import Choice, PerGameCommonOptions


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
    medals_required: MedalsRequired
