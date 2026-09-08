from . import TrackmaniaTurboTestBase


class TestVanillaDefault(TrackmaniaTurboTestBase):
    """Default YAML -> medals_required: gold."""

    def test_id_map_universe(self):
        # The id map is the stable universe: 200 tracks x 4 medal tiers + 20
        # block milestones + 5 tier milestones; items are filler + 3 medal items.
        self.assertEqual(len(self.world.location_name_to_id), 200 * 4 + 20 + 5)
        self.assertEqual(len(self.world.item_name_to_id), 1 + 3)

    def test_instantiated_location_count(self):
        # Gold + Author per track, plus the 25 milestones.
        locs = [loc for loc in self.multiworld.get_locations(1)]
        self.assertEqual(len(locs), 200 * 2 + 25)

    def test_no_track_unlock_items_in_pool(self):
        for item in self.multiworld.itempool:
            self.assertFalse(item.name.startswith("Progressive "))
            self.assertFalse(item.name.startswith("Unlock: "))

    def test_medal_items_are_progression(self):
        medals = [i for i in self.multiworld.itempool if i.name.endswith(" Medal")]
        self.assertTrue(medals)
        self.assertTrue(all(i.advancement for i in medals))

    def test_first_track_reachable_from_start(self):
        loc = self.multiworld.get_location("White Canyon 01 - Gold", 1)
        self.assertTrue(loc.can_reach(self.multiworld.state))

    def test_milestones_exist(self):
        self.multiworld.get_location("White Canyon Complete", 1)
        self.multiworld.get_location("Black Complete", 1)

    def test_completion_needs_full_medal_counts(self):
        self.collect_by_name(["Bronze Medal"] * 70)
        self.collect_by_name(["Silver Medal"] * 150)
        self.assertBeatable(False)
        self.collect_by_name(["Gold Medal"] * 190)
        self.assertBeatable(True)


class TestVanillaMedalsRequired(TrackmaniaTurboTestBase):
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
