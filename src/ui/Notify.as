// In-game toast notifications for Archipelago item routing.
//
// A thin wrapper over UI::ShowNotification -- it renders in the Openplanet
// overlay corner even while the overlay is closed, so the player sees checks and
// received items land without opening the chat panel.
//
// Driven from ApClient.OnPrintJson off the PrintJSON ItemSend/ItemCheat feed,
// only for routes that touch this slot. The text is the server's own sentence
// with our slot rendered as "you"/"You". The server never replays that feed, so
// reconnects stay quiet for free. Gated on S_Notifications.
//
// RouteSentence / RouteColour are pure -- unit-tested in tools/as/tests.

namespace Notify {
    // Background colour by item classification (matches the chat feed palette):
    // progression, useful, trap, otherwise a neutral blue.
    vec4 RouteColour(int flags) {
        if ((flags & 1) != 0) return vec4(0.42, 0.28, 0.58, 1);   // progression
        if ((flags & 2) != 0) return vec4(0.20, 0.45, 0.62, 1);   // useful
        if ((flags & 4) != 0) return vec4(0.60, 0.20, 0.20, 1);   // trap
        return vec4(0.16, 0.42, 0.52, 1);
    }

    // One JSONMessagePart -> plain text: ids resolved to names via `data`,
    // player ids to aliases via `slotAlias`. No colour, no "you" substitution
    // (RouteSentence handles the player_id == our slot case).
    string PlainPart(const string &in type, const string &in text,
                     dictionary@ slotAlias, DataPackage@ data) {
        int id;
        if (type == "item_id" && data !is null && Text::TryParseInt(text, id))
            return data.ItemName(id);
        if (type == "location_id" && data !is null && Text::TryParseInt(text, id))
            return data.LocationName(id);
        if (type == "player_id") {
            string alias;
            if (slotAlias !is null && slotAlias.Get(text, alias)) return alias;
            return "Player " + text;
        }
        return text;
    }

    // Build the toast sentence for a PrintJSON command: the server's parts joined
    // into plain text, with `mySlot` rendered as "You" (sentence start) or "you"
    // (elsewhere), and "found their" -> "found your" when that slot is the
    // finder. `flags` is taken from the routed item (0 if absent).
    //
    // Returns true only when the command is item routing (ItemSend / ItemCheat)
    // that involves `mySlot` -- i.e. when the caller should raise a toast.
    bool RouteSentence(Json::Value@ cmd, int mySlot, dictionary@ slotAlias,
                       DataPackage@ data, string &out sentence, int &out flags) {
        sentence = "";
        flags = 0;
        if (cmd is null || !cmd.HasKey("data")) return false;

        Json::Value@ parts = cmd["data"];
        if (parts is null || parts.GetType() != Json::Type::Array) return false;

        string s;
        bool involvesMe = false;
        for (uint i = 0; i < parts.Length; i++) {
            Json::Value@ part = parts[i];
            string text = part.HasKey("text") ? string(part["text"]) : "";
            string type = part.HasKey("type") ? string(part["type"]) : "text";
            if (type == "player_id" && mySlot >= 0 && text == tostring(mySlot)) {
                involvesMe = true;
                s += (s == "" ? "You" : "you");
            } else {
                s += PlainPart(type, text, slotAlias, data);
            }
        }
        sentence = s.Replace(" found their ", " found your ");

        if (cmd.HasKey("item") && cmd["item"].HasKey("flags"))
            flags = int(cmd["item"]["flags"]);

        string msgType = cmd.HasKey("type") ? string(cmd["type"]) : "";
        return involvesMe && (msgType == "ItemSend" || msgType == "ItemCheat");
    }

    void Route(const string &in sentence, int flags) {
        if (!S_Notifications) return;
        Log::Trace("notify: " + sentence);
        UI::ShowNotification("Archipelago", sentence, RouteColour(flags), 6000);
    }
}
