// Reads live Trackmania Turbo state and emits a FinishEvent when the player
// finishes a run on an official-campaign track.
//
// Design premise: the player starts a FRESH profile ("new save"), so every medal
// is earned live during the session. We therefore only fire on an actual race
// finish -- never from polling saved progress on map load (and `challenge.MapInfo`
// carries no saved solo progress anyway: `.Medal` / `.BestTime` read blank for
// campaign maps).
//
// Finish detection: watch `CTrackManiaPlayer.RaceState`; on the transition into
// `Finished`, read the run time from `CTrackManiaScore` and derive the medal by
// comparing against the map's `TMObjective_*Time` thresholds. Dedupe per track so
// re-finishing the same tier does nothing.
//
// Campaign detection matches the Ultimate Medals plugin: an official campaign map
// is authored by "Nadeo" and named "001".."200"; that number -> series + index
// (TrackTable.as).
//
// Nod chain (verified against %USERPROFILE%\OpenplanetTurbo\Openplanet.h, 1.29.x):
//   CGameCtnApp.Challenge : CGameCtnChallenge   (.MapName wstring, .AuthorLogin,
//       .MapInfo, .TMObjective_{Bronze,Silver,Gold,Author}Time)
//   CGameCtnApp.CurrentPlayground : CGamePlayground (.GameTerminals[0].ControlledPlayer)
//   CTrackManiaPlayer.RaceState : ERaceState { BeforeStart=0 Running=1 Finished=2 Eliminated=3 }
//   CTrackManiaPlayer.Score : CTrackManiaScore   (.BestTime, .LastRaceTime -- ms)

namespace Race { const int Finished = 2; }   // CTrackManiaPlayer::ERaceState

class FinishEvent {
    string trackLabel;   // "White Canyon 01"
    string mapUid;        // kept for future map-shuffle keying
    Medal  medal;         // Settings.as Medal enum (Bronze=1 .. Author=4)
    uint   timeMs;
}

class GameState {
    private dictionary m_bestMedalSeen;   // trackLabel -> int64 (Medal 1..4)
    private dictionary m_finishedSeen;    // trackLabel -> true (crossed the line, any medal or none)
    private string m_currentUid;
    private string m_currentLabel;
    private string m_lastTracedLabel;
    private int m_lastRaceState = -1;
    private bool m_finishArmed = false;   // in a Finished episode, medal not yet resolved
    private int m_finishTries = 0;        // ticks spent waiting for a valid time
    private string m_kickedLabel;         // last locked track we bounced, debounce

    // Produced here in Update(), consumed + cleared by Main.as (same thread).
    FinishEvent@ pendingFinish;

    string get_CurrentMapUid() const { return m_currentUid; }
    string get_CurrentTrackLabel() const { return m_currentLabel; }

    void Update() {
        m_currentUid = "";
        m_currentLabel = "";

        auto app = cast<CGameCtnApp>(GetApp());
        if (app is null) return;

        auto challenge = app.Challenge;
        if (challenge is null) { m_lastRaceState = -1; m_kickedLabel = ""; return; }
        auto info = challenge.MapInfo;
        if (info is null) return;

        m_currentUid = info.MapUid;

        int number = CampaignNumber(string(challenge.MapName), challenge.AuthorLogin);
        m_currentLabel = TrackLabel(number);
        if (m_currentLabel == "") { m_lastRaceState = -1; m_kickedLabel = ""; return; }

        if (m_currentLabel != m_lastTracedLabel) {
            m_lastTracedLabel = m_currentLabel;
            Log::Trace("campaign map " + number + " -> " + m_currentLabel + " (" + m_currentUid + ")");
        }

        // Locked-track enforcement. When we know (connected + item state synced)
        // that this campaign track is not unlocked, bounce the player back to the
        // menu before they can set a time. Saved records are never touched -- the
        // run is abandoned, never finished.
        if (LockedNow()) {
            if (S_BlockLockedTracks && m_kickedLabel != m_currentLabel) {
                m_kickedLabel = m_currentLabel;
                Log::Info(m_currentLabel + " is locked -- returning to menu");
                UI::ShowNotification("Archipelago",
                    m_currentLabel + " is locked by Archipelago",
                    vec4(0.8, 0.2, 0.2, 1), 4000);
                auto mp = cast<CTrackMania>(GetApp());
                if (mp !is null) mp.BackToMainMenu();
            }
            m_lastRaceState = -1;
            m_finishArmed = false;
            return;
        }
        m_kickedLabel = "";

        auto player = CurrentPlayer(app);
        if (player is null) { m_lastRaceState = -1; m_finishArmed = false; return; }

        int raceState = int(player.RaceState);
        int prevState = m_lastRaceState;
        m_lastRaceState = raceState;

        // Arm on the edge INTO Finished; disarm on leaving it (or first load).
        if (raceState == Race::Finished && prevState >= 0 && prevState != Race::Finished) {
            m_finishArmed = true;
            m_finishTries = 0;
        } else if (raceState != Race::Finished) {
            m_finishArmed = false;
        }
        if (!m_finishArmed) return;

        // The run time is not always ready the instant RaceState flips; poll a
        // few ticks. Prefer the session best, fall back to this run.
        uint runMs = ResultTime(player);
        m_finishTries++;
        if (runMs == 0 || runMs == 0xFFFFFFFF) {
            if (m_finishTries > 120) {           // ~2 s of frames, give up
                m_finishArmed = false;
                Log::Trace(m_currentLabel + " finished but no run time surfaced");
            }
            return;
        }

        m_finishArmed = false;
        int medal = MedalForTime(challenge, runMs);
        Log::Trace(m_currentLabel + " finished: time=" + runMs + " -> medal " + medal
                   + " (A=" + challenge.TMObjective_AuthorTime
                   + " G=" + challenge.TMObjective_GoldTime
                   + " S=" + challenge.TMObjective_SilverTime
                   + " B=" + challenge.TMObjective_BronzeTime + ")");

        // Defense in depth: if the track went locked between load and finish (or
        // the block-on-load kick lost a race), don't turn this into a check.
        if (LockedNow()) { Log::Trace(m_currentLabel + " finished but locked -- ignoring"); return; }

        // Fire on the first time we see this track finish (any medal, or none --
        // a bare finish still counts for the milestone / goal), and again
        // whenever the medal improves (so a later Gold arms its check).
        bool firstFinish = !m_finishedSeen.Exists(m_currentLabel);
        m_finishedSeen.Set(m_currentLabel, true);

        int64 prev = 0;
        m_bestMedalSeen.Get(m_currentLabel, prev);
        bool improved = medal > int(prev);
        if (improved) m_bestMedalSeen.Set(m_currentLabel, int64(medal));

        if (!firstFinish && !improved) return;

        FinishEvent ev;
        ev.trackLabel = m_currentLabel;
        ev.mapUid = m_currentUid;
        ev.medal = Medal(medal);
        ev.timeMs = runMs;
        @pendingFinish = ev;
        Log::Info("Finish on " + ev.trackLabel + ": medal " + medal + " (" + ev.timeMs + " ms)");
    }

    // Best available finish time in ms, or 0xFFFFFFFF if none is ready yet.
    private uint ResultTime(CTrackManiaPlayer@ player) {
        auto score = cast<CTrackManiaScore>(player.Score);
        if (score !is null && score.BestRace !is null && score.BestRace.Time > 0) {
            return uint(score.BestRace.Time);
        }
        if (player.CurRace !is null && player.CurRace.Time > 0) {
            return uint(player.CurRace.Time);
        }
        if (score !is null) {
            if (score.BestTime != 0 && score.BestTime != 0xFFFFFFFF) return score.BestTime;
            if (score.LastRaceTime != 0 && score.LastRaceTime != 0xFFFFFFFF) return score.LastRaceTime;
        }
        if (player.CurCheckpointRaceTime != 0 && player.CurCheckpointRaceTime != 0xFFFFFFFF) {
            return player.CurCheckpointRaceTime;
        }
        return 0xFFFFFFFF;
    }

    // True only when we positively know the current campaign track is locked:
    // client connected, item state synced, label not in the unlocked set. If the
    // client is not ready we do NOT treat the track as locked (fail open).
    private bool LockedNow() {
        return m_currentLabel != ""
            && g_client !is null && g_client.IsReady
            && !g_client.items.IsTrackUnlocked(m_currentLabel);
    }

    private CTrackManiaPlayer@ CurrentPlayer(CGameCtnApp@ app) {
        auto pg = app.CurrentPlayground;
        if (pg is null || pg.GameTerminals.Length == 0) return null;
        return cast<CTrackManiaPlayer>(pg.GameTerminals[0].ControlledPlayer);
    }

    // ms -> Medal int (0 = none, 1 Bronze .. 4 Author). Thresholds of 0 = not
    // loaded yet, treated as "unreachable".
    private int MedalForTime(CGameCtnChallenge@ c, uint t) {
        if (t == 0 || t == 0xFFFFFFFF) return 0;
        if (c.TMObjective_AuthorTime > 0 && t <= c.TMObjective_AuthorTime) return int(Medal::Author);
        if (c.TMObjective_GoldTime   > 0 && t <= c.TMObjective_GoldTime)   return int(Medal::Gold);
        if (c.TMObjective_SilverTime > 0 && t <= c.TMObjective_SilverTime) return int(Medal::Silver);
        if (c.TMObjective_BronzeTime > 0 && t <= c.TMObjective_BronzeTime) return int(Medal::Bronze);
        return 0;
    }
}
