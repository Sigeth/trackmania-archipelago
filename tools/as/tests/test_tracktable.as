// Unit tests for src/game/TrackTable.as -- the pure campaign-number <-> label
// <-> location-name mapping and the vanilla block model.

void Test_TrackLabel_endpoints() {
    AssertEq(TrackLabel(1),   "White Canyon 01", "map 1");
    AssertEq(TrackLabel(10),  "White Canyon 10", "map 10");
    AssertEq(TrackLabel(11),  "White Valley 01", "map 11");
    AssertEq(TrackLabel(41),  "Green Canyon 01", "map 41");
    AssertEq(TrackLabel(200), "Black Stadium 10", "map 200");
    AssertEq(TrackLabel(0),   "", "out of range low");
    AssertEq(TrackLabel(201), "", "out of range high");
}

void Test_CampaignNumber_guards() {
    AssertEq(CampaignNumber("001", "Nadeo"),      1,  "001/Nadeo");
    AssertEq(CampaignNumber("200", "nadeolabs"),  200, "200/nadeolabs (VR)");
    AssertEq(CampaignNumber("045", "Nadeo"),      45, "leading zero");
    AssertEq(CampaignNumber("001", "SomeUser"),   0,  "wrong author");
    AssertEq(CampaignNumber("201", "Nadeo"),      0,  "number too high");
    AssertEq(CampaignNumber("abc", "Nadeo"),      0,  "not a number");
}

void Test_label_roundtrips_all_200() {
    for (int n = 1; n <= 200; n++) {
        string label = TrackLabel(n);
        Assert(label != "", "label for " + n);
        AssertEq(CampaignNumberFromLabel(label), n, "roundtrip " + label);
    }
    AssertEq(CampaignNumberFromLabel("White Canyon 11"), 0, "idx > 10");
    AssertEq(CampaignNumberFromLabel("Purple Canyon 01"), 0, "bad tier");
    AssertEq(CampaignNumberFromLabel("White Desert 01"), 0, "bad env");
}

void Test_TrackLocationName() {
    AssertEq(TrackLocationName("White Canyon 01", Medal::Gold),   "White Canyon 01 - Gold");
    AssertEq(TrackLocationName("Black Stadium 10", Medal::Author), "Black Stadium 10 - Author");
    AssertEq(TrackLocationName("White Canyon 01", Medal(0)),  "", "medal 0 rejected");
    AssertEq(TrackLocationName("", Medal::Gold),              "", "empty label rejected");
}

void Test_block_model() {
    AssertEq(BlockIndex(1),   0,  "map 1 -> block 0");
    AssertEq(BlockIndex(11),  1,  "map 11 -> block 1");
    AssertEq(BlockIndex(200), 19, "map 200 -> block 19");
    AssertEq(BlockIndex(0),   -1, "out of range");

    AssertEq(int(BlockGrade(0)),  int(Medal::Bronze), "block 0 grade");
    AssertEq(int(BlockGrade(7)),  int(Medal::Bronze), "block 7 grade");
    AssertEq(int(BlockGrade(8)),  int(Medal::Silver), "block 8 grade");
    AssertEq(int(BlockGrade(15)), int(Medal::Silver), "block 15 grade");
    AssertEq(int(BlockGrade(16)), int(Medal::Gold),   "block 16 grade");

    AssertEq(BlockName(0),  "White Canyon",  "block 0 name");
    AssertEq(BlockName(19), "Black Stadium", "block 19 name");
    AssertEq(BlockCompleteLocation(0), "White Canyon Complete", "block 0 milestone");
    AssertEq(TierCompleteLocation(0),  "White Complete", "tier milestone for block 0");
    AssertEq(TierCompleteLocation(16), "Black Complete", "tier milestone for block 16");

    AssertEq(BlockTrackNumber(0, 0), 1,   "block 0 track 0");
    AssertEq(BlockTrackNumber(1, 9), 20,  "block 1 track 9");
    AssertEq(BlockTrackNumber(0, 10), 0,  "k out of range");
    AssertEq(TierIndexForBlock(19), 4,    "block 19 tier");
}
