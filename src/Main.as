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

    // Hand any finish event to the location manager.
    if (g_gameState.pendingFinish !is null) {
        if (g_client.IsReady) {
            g_client.locations.OnFinish(g_gameState.pendingFinish);
        }
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

void OnDestroyed() { Shutdown(); }
void OnDisabled()  { Shutdown(); }

void Shutdown() {
    if (g_client !is null) g_client.Disconnect();
}
