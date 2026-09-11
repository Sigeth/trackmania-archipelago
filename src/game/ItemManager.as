// Applies items the server sends us (ReceivedItems) to the local game state.
//
// Turbo has no runtime API to lock/unlock campaign tracks, so "unlocks" are
// enforced by the plugin. The campaign uses a single-currency progressive
// gate: the server sends "Progressive Medal" items and block i (10 tracks in
// campaign order, i = tier*4 + env, 0..19) opens once we hold
// m_blockThresholds[i] of them -- no grade distinction. block 0 is always
// open. Once a block is open, finishing a track sends whatever medal the
// player earned (down to EffectiveRequiredMedal()); there is no per-medal
// licence.
//
// slot_data still carries `unlock_style` / `goal` for forward-compatibility;
// this plugin only implements "progressive" / "campaign_finish" and warns on
// anything else. A per-grade "real_medals" economy was tried and found
// mathematically unsolvable solo (see the apworld module docstring) -- the
// `real_medals` unlock_style is reserved but not sent by the apworld yet.

class ItemManager {
    private ApClient@ m_client;

    private int m_nextIndex = 0;             // ReceivedItems cursor
    private dictionary m_itemCounts;         // itemName -> int (medals / filler)

    // ---- slot_data ----
    private array<int> m_blockThresholds;
    private Medal m_requiredMedal = Medal::Gold;   // per-track check floor
    private bool m_goalReported = false;

    // Cached block-unlock state (index 0..19). Recomputed only when the medal
    // count changes -- the overlay queries this ~200x/frame.
    private array<bool> m_blockUnlocked;

    ItemManager(ApClient@ client) {
        @m_client = client;
        m_blockUnlocked.Resize(BLOCK_COUNT);
        DefaultBlockThresholds();
        RecomputeBlocks();
    }

    private void DefaultBlockThresholds() {
        m_blockThresholds.Resize(BLOCK_COUNT);
        for (int i = 0; i < BLOCK_COUNT; i++) m_blockThresholds[i] = 10 * i;
    }

    void Reset() {
        m_nextIndex = 0;
        m_itemCounts.DeleteAll();
        m_goalReported = false;
        m_requiredMedal = Medal::Gold;
        DefaultBlockThresholds();
        RecomputeBlocks();
    }

    // ---- slot_data ---------------------------------------------------
    void OnSlotData(Json::Value@ sd) {
        if (sd is null || sd.GetType() != Json::Type::Object) {
            Log::Info("no slot_data -- using defaults");
            return;
        }
        if (sd.HasKey("unlock_style")) {
            string style = string(sd["unlock_style"]);
            if (style != "" && style != "progressive")
                Log::Warn("unsupported unlock_style '" + style + "' -- running progressive");
        }
        if (sd.HasKey("goal")) {
            string goal = string(sd["goal"]);
            if (goal != "" && goal != "campaign_finish")
                Log::Warn("unsupported goal '" + goal + "' -- using campaign_finish");
        }
        if (sd.HasKey("medals_required")) m_requiredMedal = ParseMedal(string(sd["medals_required"]));
        if (sd.HasKey("block_thresholds")) {
            Json::Value@ bt = sd["block_thresholds"];
            if (bt !is null && bt.GetType() == Json::Type::Array && bt.Length == uint(BLOCK_COUNT)) {
                for (int i = 0; i < BLOCK_COUNT; i++) m_blockThresholds[i] = int(bt[i]);
            }
        }
        Log::Info("slot_data: unlock_style=progressive goal=campaign_finish medals_required="
                  + MEDAL_SUFFIX[int(m_requiredMedal)]);
        RecomputeBlocks();
    }

    private Medal ParseMedal(const string &in name) const {
        if (name == "bronze") return Medal::Bronze;
        if (name == "silver") return Medal::Silver;
        if (name == "author") return Medal::Author;
        return Medal::Gold;
    }

    // Recompute the 20 cached block-unlock bools from the current Progressive
    // Medal count.
    void RecomputeBlocks() {
        int held = ItemCount(PROGRESSIVE_MEDAL_ITEM);
        for (int i = 0; i < BLOCK_COUNT; i++) {
            m_blockUnlocked[i] = i <= 0 || held >= m_blockThresholds[i];
        }
    }

    // ---- queries ---------------------------------------------------
    bool IsTrackUnlocked(const string &in label) const {
        return IsTrackUnlockedByNumber(CampaignNumberFromLabel(label));
    }

    // Cheap path for the overlay (it already has the 1..200 map number).
    bool IsTrackUnlockedByNumber(int campaignNumber) const {
        int b = BlockIndex(campaignNumber);
        if (b <= 0) return true;                          // block 0 / non-campaign
        return m_blockUnlocked[b];
    }

    bool IsBlockUnlocked(int blockIndex) const {
        if (blockIndex <= 0) return true;
        if (blockIndex >= BLOCK_COUNT) return false;
        return m_blockUnlocked[blockIndex];
    }

    int BlockThreshold(int blockIndex) const {
        if (blockIndex < 0 || blockIndex >= BLOCK_COUNT) return 0;
        return m_blockThresholds[blockIndex];
    }

    int UnlockedTrackCount() const {
        int n = 0;
        for (int i = 0; i < BLOCK_COUNT; i++) if (IsBlockUnlocked(i)) n += TRACKS_PER_BLOCK;
        return n;
    }

    // The per-track check floor from slot_data (default Gold). A bare finish is
    // still tracked for the milestones / goal regardless of this.
    Medal EffectiveRequiredMedal() const {
        return m_requiredMedal;
    }

    int ItemCount(const string &in name) const {
        int64 n = 0; m_itemCounts.Get(name, n); return int(n);
    }

    void OnReceivedItems(Json::Value@ cmd) {
        int index = cmd["index"];
        Json::Value@ arr = cmd["items"];
        Log::Trace("ReceivedItems index=" + index + " count=" + arr.Length
                   + " (m_nextIndex=" + m_nextIndex + ")");

        // index 0 == full replay (response to Sync). Reset local view first.
        if (index == 0) {
            m_itemCounts.DeleteAll();
            m_nextIndex = 0;
        } else if (index != m_nextIndex) {
            // Gap: our cursor is stale. Ask for a full replay.
            Log::Warn("item index gap (" + index + " != " + m_nextIndex + "), re-syncing");
            m_client.transport.Send(Packet::Sync());
            return;
        }

        for (uint i = 0; i < arr.Length; i++) {
            int itemId = arr[i]["item"];
            Apply(m_client.data.ItemName(itemId));
        }
        m_nextIndex = index + arr.Length;
        RecomputeBlocks();
        CheckGoal();
    }

    private void Apply(const string &in itemName) {
        // Everything is counted (medals, filler, traps). Use the int64 Get/Set
        // overloads explicitly -- the generic dictionary ?&out path does not
        // reliably round-trip a 32-bit int here.
        int64 count = 0;
        m_itemCounts.Get(itemName, count);
        count += 1;
        m_itemCounts.Set(itemName, count);
        Log::Info("Received " + itemName + " (x" + count + ")");
    }

    // Goal: finish (any medal, or none) all 200 campaign tracks. Tracked
    // plugin-side in LocationManager.m_finishedTracks.
    void CheckGoal() {
        if (!S_AutoGoal || m_client is null || !m_client.IsReady || m_goalReported) return;
        if (m_client.locations.FinishedCountAll() >= 200) {
            m_goalReported = true;
            m_client.ReportGoal();
        }
    }
}
