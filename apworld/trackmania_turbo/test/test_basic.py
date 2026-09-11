from Options import OptionError

from . import TrackmaniaTurboTestBase


class TestProgressiveDefault(TrackmaniaTurboTestBase):
    """Default YAML -> unlock_style: progressive, medals_required: gold."""

    def test_id_map_universe(self):
        # The id map is the stable universe: 200 tracks x 4 medal tiers + 20
        # block milestones + 5 tier milestones; items are filler + 1 medal item.
        self.assertEqual(len(self.world.location_name_to_id), 200 * 4 + 20 + 5)
        self.assertEqual(len(self.world.item_name_to_id), 1 + 1)

    def test_instantiated_location_count(self):
        # Gold + Author per track, plus the 25 milestones.
        locs = [loc for loc in self.multiworld.get_locations(1)]
        self.assertEqual(len(locs), 200 * 2 + 25)

    def test_no_track_unlock_items_in_pool(self):
        # The descoped `individual` unlock style used "Unlock: <Track>" items;
        # make sure it doesn't quietly come back.
        for item in self.multiworld.itempool:
            self.assertFalse(item.name.startswith("Unlock: "))

    def test_medal_item_is_progression(self):
        medals = [i for i in self.multiworld.itempool if i.name == "Progressive Medal"]
        self.assertTrue(medals)
        self.assertTrue(all(i.advancement for i in medals))

    def test_first_track_reachable_from_start(self):
        loc = self.multiworld.get_location("White Canyon 01 - Gold", 1)
        self.assertTrue(loc.can_reach(self.multiworld.state))

    def test_milestones_exist(self):
        self.multiworld.get_location("White Canyon Complete", 1)
        self.multiworld.get_location("Black Complete", 1)

    def test_deep_block_locked_without_medals(self):
        # Block 19 (Black Stadium) needs 190 Progressive Medal -- unreachable
        # from an empty state. This is the region protection: without it, every
        # location was reachable from turn zero regardless of items held.
        loc = self.multiworld.get_location("Black Stadium 10 - Gold", 1)
        self.assertFalse(loc.can_reach(self.multiworld.state))

    def test_deep_block_reachable_with_enough_medals(self):
        self.collect_by_name(["Progressive Medal"] * 190)
        loc = self.multiworld.get_location("Black Stadium 10 - Gold", 1)
        self.assertTrue(loc.can_reach(self.multiworld.state))

    def test_completion_needs_full_medal_count(self):
        # collect_by_name(["X"] * n) dedupes by name and grabs every copy in
        # the pool regardless of n, so collect an explicit slice instead.
        medals = self.get_items_by_name("Progressive Medal")
        self.collect(medals[:189])
        self.assertBeatable(False)
        self.collect(medals[189:190])
        self.assertBeatable(True)


class TestProgressiveMedalsRequired(TrackmaniaTurboTestBase):
    options = {"medals_required": "bronze"}

    def test_lower_floor_instantiates_lower_tiers(self):
        loc_names = {loc.name for loc in self.multiworld.get_locations(1)}
        self.assertIn("White Canyon 01 - Bronze", loc_names)
        self.assertIn("White Canyon 01 - Silver", loc_names)
        self.assertIn("White Canyon 01 - Gold", loc_names)
        self.assertIn("White Canyon 01 - Author", loc_names)

    def test_milestones_still_present(self):
        self.multiworld.get_location("White Canyon Complete", 1)
        self.multiworld.get_location("Black Complete", 1)


class TestRealMedalsNotImplemented(TrackmaniaTurboTestBase):
    """unlock_style: real_medals is reserved but not implemented yet."""

    options = {"unlock_style": "real_medals"}
    auto_construct = False

    def test_raises_option_error(self):
        with self.assertRaises(OptionError):
            self.world_setup()
