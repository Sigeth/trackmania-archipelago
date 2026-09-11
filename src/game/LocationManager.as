// Turns game achievements into Archipelago location checks.
//
// A "location" in this apworld is one (track, medal-tier) pair, plus
// "<Block> Complete" (x20) and "<Tier> Complete" (x5) milestones. The mapping
// between a Turbo map and its AP location name lives in TrackTable.as; this
// class resolves those names to ids via the server data package and tracks
// which checks have already been sent so we never double-report.
//
// A bare finish (crossing the line with no medal) is NOT a check. We record it
// in m_finishedTracks (persisted per seed): that set drives the milestone checks
// and the `campaign_finish` goal.

class LocationManager {
    private ApClient@ m_client;

    private array<int> m_checked;        // location ids confirmed by the server
    private array<int> m_missing;        // location ids still in play this seed
    private array<int> m_pendingSend;    // resolved, not yet acknowledged
    private dictionary m_checkedSet;     // "id" -> true, O(1) membership for m_checked
    private dictionary m_knownIds;       // "id" -> true for every location THIS slot defines
                                         // (checked + missing). The data package name
                                         // map is the whole-game universe, so a name
                                         // resolving to an id does not mean the slot
                                         // has that location -- a seed only defines
                                         // the medal tiers at/above its floor
                                         // (default Gold + Author) plus milestones.

    private dictionary m_finishedTracks; // trackLabel -> true (any completion)

    // What the most recent OnFinish() armed -- read once by Main.as to build the
    // medal splash (same-thread hand-off, like GameState.pendingFinish).
    private array<string> m_lastArmedTiers;   // medal suffixes, e.g. ["Gold","Author"]
    private string m_lastMilestone;           // "" or a milestone location name
    bool lastFinishEarnedCheck = false;

    array<string>@ get_LastArmedTiers() { return m_lastArmedTiers; }
    string get_LastMilestone() const { return m_lastMilestone; }

    // Per-campaign-number medal-tier bitmasks, cached -- the overlay asks for
    // these ~200x/frame. m_availMask is fixed once the seed is known; m_checkedMask
    // is rebuilt lazily after any check lands. Indexed 1..200.
    private array<int> m_availMask;
    private array<int> m_checkedMask;
    private bool m_checkedMaskDirty = true;

    LocationManager(ApClient@ client) {
        @m_client = client;
        m_availMask.Resize(201);
        m_checkedMask.Resize(201);
    }

    void Reset() {
        m_checked.Resize(0);
        m_missing.Resize(0);
        m_pendingSend.Resize(0);
        m_checkedSet.DeleteAll();
        m_knownIds.DeleteAll();
        m_finishedTracks.DeleteAll();
        m_lastArmedTiers.Resize(0);
        m_lastMilestone = "";
        lastFinishEarnedCheck = false;
        for (int n = 0; n <= 200; n++) { m_availMask[n] = 0; m_checkedMask[n] = 0; }
        m_checkedMaskDirty = true;
    }

    // Does this slot actually define the location with this id?
    bool KnownLocation(int id) const { return m_knownIds.Exists(tostring(id)); }

    int get_CheckedCount() const { return m_checked.Length; }
    int get_TotalCount() const { return m_checked.Length + m_missing.Length; }

    // How many of the 200 campaign tracks the player has crossed the line on.
    int FinishedCountAll() const { return m_finishedTracks.GetSize(); }
    bool IsFinished(const string &in label) const { return m_finishedTracks.Exists(label); }

    // Which medal tiers of a track exist / have been checked, as bitmasks (bit t
    // = Medal enum, Bronze=1 .. Author=4). Number-keyed, cached -- the overlay
    // asks per tile every frame.
    int AvailMaskForNumber(int n) {
        return (n >= 1 && n <= 200) ? m_availMask[n] : 0;
    }
    int CheckedMaskForNumber(int n) {
        if (m_checkedMaskDirty) RebuildCheckedMasks();
        return (n >= 1 && n <= 200) ? m_checkedMask[n] : 0;
    }

    // Label-keyed wrappers (Window / any non-overlay caller).
    int CheckedMedalMask(const string &in trackLabel) {
        return CheckedMaskForNumber(CampaignNumberFromLabel(trackLabel));
    }
    int AvailableMedalMask(const string &in trackLabel) {
        return AvailMaskForNumber(CampaignNumberFromLabel(trackLabel));
    }

    private void RebuildAvailMasks() {
        for (int n = 1; n <= 200; n++) {
            int mask = 0;
            string label = TrackLabel(n);
            for (int t = int(Medal::Bronze); t <= int(Medal::Author); t++) {
                int id = m_client.data.LocationId(TrackLocationName(label, Medal(t)));
                if (id >= 0 && KnownLocation(id)) mask |= (1 << t);
            }
            m_availMask[n] = mask;
        }
    }
    private void RebuildCheckedMasks() {
        for (int n = 1; n <= 200; n++) {
            int mask = 0;
            string label = TrackLabel(n);
            for (int t = int(Medal::Bronze); t <= int(Medal::Author); t++) {
                int id = m_client.data.LocationId(TrackLocationName(label, Medal(t)));
                if (id >= 0 && IsChecked(id)) mask |= (1 << t);
            }
            m_checkedMask[n] = mask;
        }
        m_checkedMaskDirty = false;
    }

    // From the Connected packet.
    void SeedFromServer(Json::Value@ checked, Json::Value@ missing) {
        m_checked.Resize(0);
        m_checkedSet.DeleteAll();
        m_knownIds.DeleteAll();
        for (uint i = 0; i < checked.Length; i++) {
            int id = int(checked[i]);
            m_checked.InsertLast(id);
            m_checkedSet.Set(tostring(id), true);
            m_knownIds.Set(tostring(id), true);
        }
        m_missing.Resize(0);
        for (uint i = 0; i < missing.Length; i++) {
            int id = int(missing[i]);
            m_missing.InsertLast(id);
            m_knownIds.Set(tostring(id), true);
        }
        Log::Info("Locations: " + m_checked.Length + " checked / " + get_TotalCount() + " total");
        RebuildAvailMasks();
        m_checkedMaskDirty = true;
        ReconstructFinishedFromChecks();
    }

    // A checked "<Block> Complete" / "<Tier> Complete" milestone, or a checked
    // per-track Gold/Author, implies those tracks were finished -- rebuild what we
    // can so reconnects don't lose milestone progress the persisted file missed.
    private void ReconstructFinishedFromChecks() {
        for (int n = 1; n <= 200; n++) {
            string label = TrackLabel(n);
            if (m_finishedTracks.Exists(label)) continue;
            for (int t = int(Medal::Bronze); t <= int(Medal::Author); t++) {
                int id = m_client.data.LocationId(TrackLocationName(label, Medal(t)));
                if (id >= 0 && IsChecked(id)) { m_finishedTracks.Set(label, true); break; }
            }
        }
        for (int b = 0; b < BLOCK_COUNT; b++) {
            int bid = m_client.data.LocationId(BlockCompleteLocation(b));
            if (bid >= 0 && IsChecked(bid)) {
                for (int k = 0; k < TRACKS_PER_BLOCK; k++)
                    m_finishedTracks.Set(TrackLabel(BlockTrackNumber(b, k)), true);
            }
        }
    }

    // From RoomUpdate: ids other clients (or we) completed.
    void MarkChecked(Json::Value@ ids) {
        for (uint i = 0; i < ids.Length; i++) AddChecked(int(ids[i]));
    }

    // Called by Main.as when GameState reports a finish (any medal, or none).
    void OnFinish(FinishEvent@ ev) {
        Log::Trace("OnFinish " + ev.trackLabel + " medal=" + int(ev.medal));

        m_lastArmedTiers.Resize(0);
        m_lastMilestone = "";
        lastFinishEarnedCheck = false;

        bool newFinish = !m_finishedTracks.Exists(ev.trackLabel);
        m_finishedTracks.Set(ev.trackLabel, true);

        bool unlocked = m_client.items.IsTrackUnlocked(ev.trackLabel);

        // Per-track checks: every tier from the effective floor up to the medal
        // the player actually earned, skipping ids the slot does not define.
        int floor = int(m_client.items.EffectiveRequiredMedal());
        for (int tier = floor; tier <= int(ev.medal); tier++) {
            if (!unlocked) break;
            string locName = TrackLocationName(ev.trackLabel, Medal(tier));
            int id = m_client.data.LocationId(locName);
            if (id < 0 || !KnownLocation(id)) continue;   // not a location this slot defines
            if (IsChecked(id) || IsPending(id)) continue;
            m_pendingSend.InsertLast(id);
            m_lastArmedTiers.InsertLast(MEDAL_SUFFIX[tier]);
            lastFinishEarnedCheck = true;
            Log::Info("Location armed: " + locName);
        }

        if (newFinish) CheckMilestones(BlockIndexFromLabel(ev.trackLabel));
        Flush();
        PersistFinished();
    }

    // Arm "<Block> Complete" / "<Tier> Complete" when every track is finished.
    void CheckMilestones(int blockIndex) {
        if (blockIndex < 0 || blockIndex >= BLOCK_COUNT) return;

        bool blockDone = true;
        for (int k = 0; k < TRACKS_PER_BLOCK; k++) {
            if (!m_finishedTracks.Exists(TrackLabel(BlockTrackNumber(blockIndex, k)))) {
                blockDone = false; break;
            }
        }
        if (blockDone && ArmByName(BlockCompleteLocation(blockIndex)))
            m_lastMilestone = BlockCompleteLocation(blockIndex);

        int tierIdx = TierIndexForBlock(blockIndex);
        bool tierDone = true;
        for (int n = tierIdx * 40 + 1; n <= tierIdx * 40 + 40; n++) {
            if (!m_finishedTracks.Exists(TrackLabel(n))) { tierDone = false; break; }
        }
        if (tierDone && ArmByName(TierCompleteLocation(blockIndex)))
            m_lastMilestone = TierCompleteLocation(blockIndex);
    }

    // Returns true when it actually queued a new check.
    private bool ArmByName(const string &in locName) {
        if (locName == "") return false;
        int id = m_client.data.LocationId(locName);
        if (id < 0 || !KnownLocation(id) || IsChecked(id) || IsPending(id)) return false;
        m_pendingSend.InsertLast(id);
        lastFinishEarnedCheck = true;
        Log::Info("Milestone armed: " + locName);
        return true;
    }

    // Push everything resolved-but-unsent to the server.
    void Flush() {
        if (m_pendingSend.Length == 0 || !m_client.IsReady) return;
        m_client.SendLocationChecks(m_pendingSend);
        // Optimistically mark as checked; RoomUpdate will confirm.
        for (uint i = 0; i < m_pendingSend.Length; i++) AddChecked(m_pendingSend[i]);
        m_pendingSend.Resize(0);
    }

    private void AddChecked(int id) {
        if (IsChecked(id)) return;
        m_checked.InsertLast(id);
        m_checkedSet.Set(tostring(id), true);
        m_checkedMaskDirty = true;
        int idx = m_missing.Find(id);
        if (idx >= 0) m_missing.RemoveAt(idx);
    }
    private bool IsChecked(int id) const { return m_checkedSet.Exists(tostring(id)); }
    private bool IsPending(int id) const { return m_pendingSend.Find(id) >= 0; }

    // ---- persistence (finished set, per seed) ----------------------
    private string FinishedPath() {
        return IO::FromStorageFolder("seed-" + m_client.seedName + "-finished.json");
    }
    private void PersistFinished() {
        if (m_client.seedName == "") return;
        Json::Value@ root = Json::Object();
        Json::Value@ arr = Json::Array();
        array<string>@ keys = m_finishedTracks.GetKeys();
        for (uint i = 0; i < keys.Length; i++) arr.Add(Json::Value(keys[i]));
        root["finished"] = arr;
        Json::ToFile(FinishedPath(), root);
    }
    void LoadFinished() {
        if (m_client.seedName == "" || !IO::FileExists(FinishedPath())) return;
        Json::Value@ root = Json::FromFile(FinishedPath());
        if (root is null || !root.HasKey("finished")) return;
        Json::Value@ arr = root["finished"];
        for (uint i = 0; i < arr.Length; i++) m_finishedTracks.Set(string(arr[i]), true);
        Log::Info("Restored " + m_finishedTracks.GetSize() + " finished tracks");
    }
}
