// Unit tests for src/ap/Protocol.as -- packet construction and frame parsing.

void Test_Connect_packet_shape() {
    string frame = Packet::Connect("MySlot", "pw", "uuid-123");
    Json::Value@ arr = Json::Parse(frame);
    Assert(arr !is null && arr.GetType() == Json::Type::Array, "frame is a JSON array");
    AssertEq(arr.Length, uint(1), "one command per frame");

    Json::Value@ p = arr[0];
    AssertEq(string(p["cmd"]),  "Connect",           "cmd");
    AssertEq(string(p["game"]), "Trackmania Turbo",  "game name matches the apworld contract");
    AssertEq(string(p["name"]), "MySlot",            "slot name");
    AssertEq(int(p["items_handling"]), 7,            "items_handling = all");
    Assert(p["slot_data"].GetType() == Json::Type::Boolean, "slot_data is a bool");
    Assert(p.HasKey("version"), "carries a version");
}

void Test_LocationChecks_packet() {
    array<int> ids = { 101, 202, 303 };
    Json::Value@ p = Json::Parse(Packet::LocationChecks(ids))[0];
    AssertEq(string(p["cmd"]), "LocationChecks", "cmd");
    Json::Value@ locs = p["locations"];
    AssertEq(locs.Length, uint(3), "three ids");
    AssertEq(int(locs[0]), 101, "first id");
    AssertEq(int(locs[2]), 303, "last id");
}

void Test_StatusUpdate_and_Sync() {
    Json::Value@ s = Json::Parse(Packet::StatusUpdate(ClientStatus::Goal))[0];
    AssertEq(string(s["cmd"]), "StatusUpdate", "cmd");
    AssertEq(int(s["status"]), 30, "Goal == 30");

    Json::Value@ y = Json::Parse(Packet::Sync())[0];
    AssertEq(string(y["cmd"]), "Sync", "sync cmd");
}

void Test_Parse_valid_and_malformed() {
    array<Json::Value@>@ ok = Packet::Parse("[{\"cmd\":\"RoomInfo\"},{\"cmd\":\"Bounced\"}]");
    AssertEq(ok.Length, uint(2), "two commands parsed");
    AssertEq(string(ok[0]["cmd"]), "RoomInfo", "first cmd");

    // A frame that is a JSON object, not an array -> dropped, empty result.
    array<Json::Value@>@ bad = Packet::Parse("{\"cmd\":\"RoomInfo\"}");
    AssertEq(bad.Length, uint(0), "non-array frame dropped");
}
