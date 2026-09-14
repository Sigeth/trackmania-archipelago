"""Website presentation: setup tutorial(s)."""
from BaseClasses import Tutorial
from worlds.AutoWorld import WebWorld


class TrackmaniaTurboWeb(WebWorld):
    tutorials = [Tutorial(
        "Multiworld Setup Guide",
        "A guide to setting up Trackmania Turbo for Archipelago.",
        "English",
        "setup_en.md",
        "setup/en",
        ["Sigeth"],
    )]
