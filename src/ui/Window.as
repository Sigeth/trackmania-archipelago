// Status + control window and the Openplanet menu entry.
//
// Connection details are edited here (they still persist via the S_* settings,
// so the Openplanet Settings tab keeps working too). Fields are locked while a
// session is live.

[Setting hidden]
bool S_WindowOpen = true;

void RenderMenu() {
    if (UI::MenuItem("\\$5cf Archipelago", "", S_WindowOpen)) {
        S_WindowOpen = !S_WindowOpen;
    }
}

void RenderInterface() {
    if (!S_WindowOpen || g_client is null) return;

    UI::SetNextWindowSize(380, 500, UI::Cond::FirstUseEver);
    if (UI::Begin("Archipelago", S_WindowOpen)) {
        RenderStatusLine();
        UI::Separator();
        RenderConnectionForm();
        UI::Separator();
        RenderProgress();
        UI::Separator();
        RenderChat();
        UI::Separator();
        if (UI::CollapsingHeader("Medal splash")) {
            if (UI::Button("Test medal splash")) MedalSplash::TriggerTest();
            UI::TextDisabled("Audition voice lines:");
            if (UI::Button("Bronze")) MedalSplash::PlayTierSound(int(Medal::Bronze));
            UI::SameLine();
            if (UI::Button("Silver")) MedalSplash::PlayTierSound(int(Medal::Silver));
            UI::SameLine();
            if (UI::Button("Gold")) MedalSplash::PlayTierSound(int(Medal::Gold));
            UI::SameLine();
            if (UI::Button("Author")) MedalSplash::PlayTierSound(int(Medal::Author));
        }
        if (UI::CollapsingHeader("Overlay alignment")) {
            UI::TextWrapped(Overlay::DebugStatus());
            UI::TextDisabled("If the overlay is off (different resolution or");
            UI::TextDisabled("aspect): open the campaign grid, tick 'boxes',");
            UI::TextDisabled("drag until the boxes sit on the tiles.");
            S_GridDebug = UI::Checkbox("Show tile boxes", S_GridDebug);
            UI::TextDisabled("Series grid:");
            S_GridL = UI::SliderFloat("Left##g",   S_GridL, 0.0f, 0.6f);
            S_GridR = UI::SliderFloat("Right##g",  S_GridR, 0.5f, 1.2f);
            S_GridT = UI::SliderFloat("Top##g",    S_GridT, 0.0f, 0.6f);
            S_GridB = UI::SliderFloat("Bottom##g", S_GridB, 0.5f, 1.2f);
            UI::TextDisabled("Track picker (10 tiles):");
            S_TpL = UI::SliderFloat("Left##t",   S_TpL, 0.0f, 0.5f);
            S_TpR = UI::SliderFloat("Right##t",  S_TpR, 0.5f, 1.2f);
            S_TpT = UI::SliderFloat("Top##t",    S_TpT, 0.0f, 0.6f);
            S_TpB = UI::SliderFloat("Bottom##t", S_TpB, 0.5f, 1.2f);
            if (UI::Button("Reset")) {
                S_GridL = 0.275f; S_GridR = 0.877f; S_GridT = 0.235f; S_GridB = 0.858f;
                S_TpL = 0.123f; S_TpR = 0.880f; S_TpT = 0.358f; S_TpB = 0.863f;
            }
        }
    }
    UI::End();
}

void RenderStatusLine() {
    string label;
    switch (g_client.Phase) {
        case Ap::Phase::Disconnected: label = "\\$888Disconnected";   break;
        case Ap::Phase::Ready:        label = "\\$3f5Connected";      break;
        case Ap::Phase::Error:        label = "\\$f55Error";          break;
        default:                      label = "\\$fd5Connecting...";   break;
    }
    UI::Text(label);
    if (g_client.Phase == Ap::Phase::Error) {
        UI::TextWrapped("\\$f77" + g_client.LastError);
    } else if (g_client.IsReady) {
        UI::Text("Seed: " + g_client.seedName);
    }
}

void RenderConnectionForm() {
    bool busy = g_client.Phase != Ap::Phase::Disconnected
             && g_client.Phase != Ap::Phase::Error;

    UI::BeginDisabled(busy);
    UI::PushItemWidth(200);
    S_Host     = UI::InputText("Host", S_Host);
    S_Port     = UI::InputInt("Port", S_Port);
    S_UseTls   = UI::Checkbox("Use TLS (wss://)", S_UseTls);
    S_SlotName = UI::InputText("Slot name", S_SlotName);
    S_Password = UI::InputText("Password", S_Password, UI::InputTextFlags::Password);
    UI::PopItemWidth();
    UI::EndDisabled();

    if (!busy) {
        UI::BeginDisabled(S_SlotName.Length == 0);
        if (UI::Button("Connect")) startnew(CoroutineFunc(g_client.Connect));
        UI::EndDisabled();
    } else {
        if (UI::Button("Disconnect")) g_client.Disconnect();
    }
    UI::SameLine();
    UI::BeginDisabled(!g_client.IsReady);
    if (UI::Button("Report goal")) g_client.ReportGoal();
    UI::EndDisabled();
}

void RenderProgress() {
    if (!g_client.IsReady) return;
    auto loc = g_client.locations;
    auto items = g_client.items;
    float frac = loc.TotalCount > 0 ? float(loc.CheckedCount) / loc.TotalCount : 0;
    UI::ProgressBar(frac, vec2(-1, 0), loc.CheckedCount + " / " + loc.TotalCount + " checks");
    UI::Text("Tracks unlocked: " + items.UnlockedTrackCount());

    UI::Text("Progressive Medals: " + items.ItemCount(PROGRESSIVE_MEDAL_ITEM));
    UI::Text("Finished: " + loc.FinishedCountAll() + " / 200");
    int nextBlock = FirstLockedBlock();
    if (nextBlock >= 0) {
        int need = items.BlockThreshold(nextBlock) - items.ItemCount(PROGRESSIVE_MEDAL_ITEM);
        UI::Text("Next: " + BlockName(nextBlock) + "  (need " + need + " more)");
    } else {
        UI::Text("\\$3f3All 20 blocks unlocked");
    }

    string labelName = g_gameState !is null ? g_gameState.CurrentTrackLabel : "";
    if (labelName != "") {
        bool unlocked = items.IsTrackUnlocked(labelName);
        UI::Text("Current: " + labelName
                 + (unlocked ? "  \\$3f3[unlocked]" : "  \\$f33[locked]"));
    }
}

// ---- chat -----------------------------------------------------------------

string g_chatDraft;
bool g_chatRefocus = false;

void RenderChat() {
    UI::Text("Chat");

    // Message log: fixed-height scroll region, sticks to the bottom on new lines.
    if (UI::BeginChild("ap_chat_log", vec2(0, 150), true)) {
        if (g_client.chatLog.Length == 0) UI::TextDisabled("No messages yet.");
        for (uint i = 0; i < g_client.chatLog.Length; i++) UI::TextWrapped(g_client.chatLog[i]);
        if (g_client.chatDirty) {
            UI::SetScrollHereY(1.0f);
            g_client.chatDirty = false;
        }
    }
    UI::EndChild();

    bool ready = g_client.IsReady;
    UI::BeginDisabled(!ready);
    if (g_chatRefocus) { UI::SetKeyboardFocusHere(); g_chatRefocus = false; }
    UI::PushItemWidth(-60);
    bool submitted = false;
    g_chatDraft = UI::InputText("##ap_chat_in", g_chatDraft, submitted,
                                UI::InputTextFlags::EnterReturnsTrue);
    UI::PopItemWidth();
    UI::SameLine();
    bool clicked = UI::Button("Send");
    UI::EndDisabled();

    if (ready && (submitted || clicked) && g_chatDraft.Trim() != "") {
        g_client.Say(g_chatDraft);
        g_chatDraft = "";
        g_chatRefocus = true;
    }
    UI::TextDisabled("Tip: server commands work here too, e.g. !hint, !help");
}

// Lowest block index that is not unlocked yet, or -1 if all are.
int FirstLockedBlock() {
    for (int i = 1; i < BLOCK_COUNT; i++) {
        if (!g_client.items.IsBlockUnlocked(i)) return i;
    }
    return -1;
}
