// Plugin entry point and per-frame wiring.
//
// Ownership:
//   g_client    -- Archipelago session (transport, protocol, managers)
//   g_gameState -- reads the Turbo game nod, emits FinishEvent
//
// Main() starts one coroutine that pumps the client. Update() (called by
// Openplanet every frame, on the game thread) is where we touch engine nods.

ApClient@  g_client;
GameState@ g_gameState;

void Main() {
    @g_client = ApClient();
    @g_gameState = GameState();

    g_client.data.LoadCache();

    if (S_AutoConnect && S_SlotName != "") {
        g_client.Connect();
    }

    // Client pump loop: network IO is safe off the game thread.
    while (true) {
        g_client.Update();
        yield();
    }
}

// Runs on the game thread -- the only safe place to read CGameCtnApp.
void Update(float dt) {
    if (g_gameState is null || g_client is null) return;

    g_gameState.Update();

    // Hand any finish event to the location manager, then celebrate it.
    if (g_gameState.pendingFinish !is null) {
        auto ev = g_gameState.pendingFinish;
        bool earnedCheck = false;
        string checkedLine, milestoneLine;
        if (g_client.IsReady) {
            g_client.locations.OnFinish(ev);
            earnedCheck = g_client.locations.lastFinishEarnedCheck;
            checkedLine = ChecksLine(g_client.locations.LastArmedTiers);
            milestoneLine = g_client.locations.LastMilestone;
        }
        MedalSplash::Trigger(MakeSplash(ev, earnedCheck, checkedLine, milestoneLine));
        @g_gameState.pendingFinish = null;
    }

    // Retry queued checks once the session is (re)established.
    if (g_client.IsReady) {
        g_client.locations.Flush();
        // The goal advances on finishes, not on item receipt -- re-check here
        // too (idempotent; guarded by m_goalReported).
        g_client.items.CheckGoal();
    }
}

// The plugin's single Render() (nvg / foreground draw list). Dispatches to the
// campaign-menu overlay (its own menu guard) and the medal splash (drawn anywhere,
// including the in-map results screen).
void Render() {
    RenderCampaignOverlay();
    MedalSplash::Render();
}

void OnDestroyed() { Shutdown(); }
void OnDisabled()  { Shutdown(); }

void Shutdown() {
    if (g_client !is null) g_client.Disconnect();
}

// "Checked: Gold, Author" from the tier suffixes LocationManager just armed.
string ChecksLine(array<string>@ tiers) {
    if (tiers is null || tiers.Length == 0) return "";
    string s = "Checked: ";
    for (uint i = 0; i < tiers.Length; i++) {
        if (i > 0) s += ", ";
        s += tiers[i];
    }
    return s;
}
