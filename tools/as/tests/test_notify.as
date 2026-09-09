// Unit tests for src/ui/Notify.as -- the pure toast-sentence builder that turns
// a PrintJSON item-routing command into the server's own sentence with this
// slot rendered as "you"/"You". Mirrors the in-game bring-up checks.

namespace NotifyTest {
    DataPackage@ makeDP() {
        Json::Value@ pkg = Json::Object();

        Json::Value@ l2i = Json::Object();
        l2i["White Canyon 02 - Gold"]   = 42;
        l2i["White Canyon 02 - Author"] = 43;
        l2i["White Canyon 04 - Author"] = 44;
        l2i["White Valley 02 - Gold"]   = 45;
        pkg["location_name_to_id"] = l2i;

        Json::Value@ i2i = Json::Object();
        i2i["Bronze Medal"] = 1001;
        i2i["Silver Medal"] = 1002;
        i2i["Gold Medal"]   = 1003;
        pkg["item_name_to_id"] = i2i;

        pkg["checksum"] = "x";

        DataPackage dp;
        dp.LoadFromServer(pkg);
        return dp;
    }

    dictionary@ aliases() {
        dictionary@ d = dictionary();
        d["1"] = "Turbo1";
        d["2"] = "Turbo2";
        d["3"] = "Sigeth";
        return d;
    }

    // Build a PrintJSON command from a compact "parts" spec. Each entry is either
    // "lit:<text>" or "<type>:<text>"; `type`/`item`/`flags` set the envelope.
    Json::Value@ printJson(const string &in type, const array<string> &in parts,
                           int itemId, int locId, int player, int flags) {
        Json::Value@ cmd = Json::Object();
        cmd["cmd"] = "PrintJSON";
        if (type != "") cmd["type"] = type;
        if (itemId >= 0) {
            Json::Value@ it = Json::Object();
            it["item"] = itemId;
            it["location"] = locId;
            it["player"] = player;
            it["flags"] = flags;
            cmd["item"] = it;
        }
        Json::Value@ data = Json::Array();
        for (uint i = 0; i < parts.Length; i++) {
            array<string>@ kv = parts[i].Split(":");
            string kind = kv[0];
            string text = "";
            for (uint j = 1; j < kv.Length; j++) text += (j > 1 ? ":" : "") + kv[j];
            Json::Value@ p = Json::Object();
            p["text"] = text;
            if (kind != "lit") p["type"] = kind;
            data.Add(p);
        }
        cmd["data"] = data;
        return cmd;
    }
}

// "Turbo1 sent Bronze Medal to Sigeth (White Canyon 02 - Gold)" as slot 1.
void Test_Notify_you_sent_to_other() {
    array<string> parts = {
        "player_id:1", "lit: sent ", "item_id:1001", "lit: to ",
        "player_id:3", "lit: (", "location_id:42", "lit:)"
    };
    Json::Value@ cmd = NotifyTest::printJson("ItemSend", parts, 1001, 42, 3, 1);

    string s; int flags;
    bool toast = Notify::RouteSentence(cmd, 1, NotifyTest::aliases(), NotifyTest::makeDP(), s, flags);
    AssertEq(toast, true, "routing that involves me -> toast");
    AssertEq(s, "You sent Bronze Medal to Sigeth (White Canyon 02 - Gold)", "sentence");
    AssertEq(flags, 1, "progression flag carried through");
}

// "Turbo1 found their Gold Medal (White Canyon 04 - Author)" as slot 1 -> "your".
void Test_Notify_you_found_your_own() {
    array<string> parts = {
        "player_id:1", "lit: found their ", "item_id:1003",
        "lit: (", "location_id:44", "lit:)"
    };
    Json::Value@ cmd = NotifyTest::printJson("ItemSend", parts, 1003, 44, 1, 1);

    string s; int flags;
    bool toast = Notify::RouteSentence(cmd, 1, NotifyTest::aliases(), NotifyTest::makeDP(), s, flags);
    AssertEq(toast, true, "own-item route still toasts");
    AssertEq(s, "You found your Gold Medal (White Canyon 04 - Author)", "their -> your");
}

// "Turbo2 sent Silver Medal to Turbo1 (White Valley 02 - Gold)" as slot 1 -> "you".
void Test_Notify_other_sent_to_you() {
    array<string> parts = {
        "player_id:2", "lit: sent ", "item_id:1002", "lit: to ",
        "player_id:1", "lit: (", "location_id:45", "lit:)"
    };
    Json::Value@ cmd = NotifyTest::printJson("ItemSend", parts, 1002, 45, 2, 0);

    string s; int flags;
    bool toast = Notify::RouteSentence(cmd, 1, NotifyTest::aliases(), NotifyTest::makeDP(), s, flags);
    AssertEq(toast, true, "receiving a route -> toast");
    AssertEq(s, "Turbo2 sent Silver Medal to you (White Valley 02 - Gold)", "mid-sentence 'you'");
    AssertEq(flags, 0, "no flags -> 0");
}

// A route between two other slots is not our concern.
void Test_Notify_route_not_involving_me() {
    array<string> parts = {
        "player_id:2", "lit: sent ", "item_id:1003", "lit: to ",
        "player_id:3", "lit: (", "location_id:42", "lit:)"
    };
    Json::Value@ cmd = NotifyTest::printJson("ItemSend", parts, 1003, 42, 2, 1);

    string s; int flags;
    bool toast = Notify::RouteSentence(cmd, 1, NotifyTest::aliases(), NotifyTest::makeDP(), s, flags);
    AssertEq(toast, false, "route between others -> no toast");
    AssertEq(s, "Turbo2 sent Gold Medal to Sigeth (White Canyon 02 - Gold)", "still resolved, just not toasted");
}

// Non-routing PrintJSON (chat, joins, hints) never toasts, even if it names us.
void Test_Notify_non_routing_type_no_toast() {
    array<string> parts = { "player_id:1", "lit: : hi team" };
    Json::Value@ cmd = NotifyTest::printJson("Chat", parts, -1, -1, -1, 0);

    string s; int flags;
    bool toast = Notify::RouteSentence(cmd, 1, NotifyTest::aliases(), NotifyTest::makeDP(), s, flags);
    AssertEq(toast, false, "Chat type -> no toast");
    AssertEq(s, "You : hi team", "sentence still built with 'You'");
}

// Unknown slot -> "Player N"; capitalisation depends on position.
void Test_Notify_unknown_alias_and_capitalisation() {
    array<string> parts = {
        "player_id:9", "lit: sent ", "item_id:1001", "lit: to ",
        "player_id:1", "lit: (", "location_id:42", "lit:)"
    };
    Json::Value@ cmd = NotifyTest::printJson("ItemCheat", parts, 1001, 42, 9, 4);

    string s; int flags;
    bool toast = Notify::RouteSentence(cmd, 1, NotifyTest::aliases(), NotifyTest::makeDP(), s, flags);
    AssertEq(toast, true, "ItemCheat also toasts");
    AssertEq(s, "Player 9 sent Bronze Medal to you (White Canyon 02 - Gold)", "unknown alias fallback");
    AssertEq(flags, 4, "trap flag");
}
