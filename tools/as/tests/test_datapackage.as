// Unit tests for src/ap/DataPackage.as -- id <-> name resolution.

DataPackage@ makePackage() {
    Json::Value@ pkg = Json::Object();

    Json::Value@ l2i = Json::Object();
    l2i["White Canyon 01 - Gold"] = 42;
    l2i["White Canyon 01 - Author"] = 43;
    l2i["White Canyon Complete"] = 90;
    pkg["location_name_to_id"] = l2i;

    Json::Value@ i2i = Json::Object();
    i2i["Gold Medal"] = 7000;
    i2i["Unlock: White Canyon 02"] = 7001;
    pkg["item_name_to_id"] = i2i;

    pkg["checksum"] = "abc123";

    DataPackage dp;
    dp.LoadFromServer(pkg);
    return dp;
}

void Test_DataPackage_location_ids() {
    DataPackage@ dp = makePackage();
    Assert(dp.Loaded, "loaded flag set");
    AssertEq(dp.Checksum, "abc123", "checksum stored");

    AssertEq(dp.LocationId("White Canyon 01 - Gold"),   42, "gold id");
    AssertEq(dp.LocationId("White Canyon Complete"),    90, "milestone id");
    AssertEq(dp.LocationId("No Such Location"),         -1, "unknown -> -1");
}

void Test_DataPackage_name_lookup() {
    DataPackage@ dp = makePackage();
    AssertEq(dp.LocationName(43), "White Canyon 01 - Author", "id -> location name");
    AssertEq(dp.ItemName(7000),   "Gold Medal",              "id -> item name");
    AssertEq(dp.ItemName(7001),   "Unlock: White Canyon 02", "id -> item name 2");
    AssertEq(dp.ItemName(99999),  "Item#99999",              "unknown item -> placeholder");
    AssertEq(dp.LocationName(99999), "Location#99999",       "unknown location -> placeholder");
}
