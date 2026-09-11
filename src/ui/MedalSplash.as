// Medal-earned celebration splash.
//
// A player on a fresh Turbo profile gets the game's own "new record" screen +
// jingle every time they earn a medal. A player using their real profile does
// not -- and the game's ceremony cannot be triggered from a plugin
// (`Solo_SetNewRecord` / `PlayUiSound` / `PlaySoundLibrary` are all
// ManiaScript-only). So we draw our own: a centred banner for ~3 s on every
// campaign finish.
//
// SOUND is the game's own extracted medal voice lines (native-only, not bundled;
// see assets/README.md). Two triggers, both routed through PlayTierSound():
//   * a received medal ITEM  -> Bronze / Silver / Gold voice line
//     (ItemManager queues the tier; Update drains it on the game thread)
//   * a Gold-or-Author FINISH that armed a check -> Gold / Author voice line
//     (Trigger(); Author wins when the run cleared both)
// A missing file just means that tier is silent -- no synthesised fallback.
//
// Driven from Main.as: MedalSplash::Trigger(...) after a finish is processed,
// MedalSplash::PlayTierSound(...) for drained item sounds, MedalSplash::Render()
// from the plugin's single Render(). Render() here draws anywhere on screen --
// including the in-map results screen -- so it must not sit behind a menu guard.

class SplashInfo {
    string title;          // "White Canyon 03 - Gold" / "White Canyon 03 - Finish"
    string checkedLine;    // "Checked: Gold, Author"    ("" if none)
    string milestoneLine;  // "White Canyon Complete"    ("" if none)
    int    medal = 0;      // Medal enum 0..4 -> banner accent colour
    bool   playSound = false;
}

// Build a SplashInfo from a finish. `checkedLine` / `milestoneLine` come from
// LocationManager after OnFinish; pass "" when not connected.
SplashInfo@ MakeSplash(FinishEvent@ ev, bool earnedCheck,
                       const string &in checkedLine, const string &in milestoneLine) {
    SplashInfo info;
    string medalName = (int(ev.medal) >= 1 && int(ev.medal) <= 4)
        ? MEDAL_SUFFIX[int(ev.medal)] : "Finish";
    info.title = ev.trackLabel + " - " + medalName;
    info.medal = int(ev.medal);
    info.checkedLine = checkedLine;
    info.milestoneLine = milestoneLine;
    info.playSound = earnedCheck;
    return info;
}

namespace MedalSplash {
    const float SHOW_SECONDS = 3.2f;
    const float FADE_SECONDS = 0.45f;
    const float LINE_H = 26.0f;

    SplashInfo@ m_active = null;
    uint64 m_startMs = 0;

    // Per-tier sound file, indexed by the Medal enum (1 Bronze .. 4 Author).
    // Index 0 (no medal / bare finish) never plays a sound -- a bare finish does
    // not arm a check. Drop the game's extracted ceremony .ogg here under these
    // names; .ogg and .wav both load (see assets/README.md for what to extract).
    // A missing file just means that tier is silent -- no fallback, by design.
    array<string> SAMPLE_FILE = {
        "",
        "assets/voice-medal-bronze.wav",
        "assets/voice-medal-silver.wav",
        "assets/voice-medal-gold.wav",
        "assets/voice-medal-author.wav"
    };
    array<Audio::Sample@> m_samples(5);
    array<bool> m_sampleTried(5, false);

    // TODO(native-sound-auto): instead of the player extracting the .ogg by hand,
    // pull it from the decrypted VFS on first use:
    //   auto fid = Fids::GetGame("Media\\Sounds\\...\\Victory.ogg");
    //   if (fid !is null && Fids::Extract(fid))
    //       @m_samples[mi] = Audio::LoadSampleFromAbsolutePath(<extracted path>);
    // Blocked only on the exact in-pack path string (see assets/README.md).

    // Load (once) the voice line for tier `mi` (1..4), or null if the file is
    // absent. No fallback: native sound or silence.
    Audio::Sample@ SampleFor(int mi) {
        mi = Math::Clamp(mi, 0, 4);
        if (mi == 0 || SAMPLE_FILE[mi] == "") return null;
        if (!m_sampleTried[mi]) {
            m_sampleTried[mi] = true;
            // Audio::LoadSample throws (not null) when the file is absent.
            try {
                @m_samples[mi] = Audio::LoadSample(SAMPLE_FILE[mi]);
            } catch {
                @m_samples[mi] = null;
            }
            if (m_samples[mi] is null)
                Log::Trace("medal splash: " + SAMPLE_FILE[mi]
                           + " not present -- tier " + mi + " silent");
        }
        return m_samples[mi];
    }

    // Play the medal voice line for `tier` (Medal enum 1..4). Used for both
    // received medal items (Bronze/Silver/Gold) and gold+ finishes. Safe to call
    // from the game thread (Update). Silent if S_MedalSound is off or the file
    // is missing. MUST be called on the game thread.
    void PlayTierSound(int tier) {
        if (!S_MedalSound) return;
        auto sample = SampleFor(tier);
        if (sample is null) return;
        try {
            Audio::Play(sample, Math::Clamp(S_MedalSoundVolume, 0.0f, 1.0f));
        } catch {
            Log::Warn("medal splash: Audio::Play failed -- " + getExceptionInfo());
        }
    }

    void Trigger(SplashInfo@ info) {
        if (info is null) return;
        @m_active = info;
        m_startMs = Time::Now;
        // Finish sound: only a Gold or Author finish that armed a check speaks,
        // and Author wins when the run cleared both (info.medal is already the
        // single best tier the run earned). Bronze/Silver finishes are silent --
        // those voice lines fire on item receipt instead.
        bool finishSpeaks = info.playSound && info.medal >= int(Medal::Gold);
        Log::Trace("medal splash: " + info.title + (finishSpeaks ? " (+sound)" : ""));
        if (finishSpeaks) PlayTierSound(info.medal);
    }

    // Debug panel: fire a sample splash with no game finish.
    void TriggerTest() {
        SplashInfo i;
        i.title = "White Canyon 03 - Gold";
        i.checkedLine = "Checked: Gold";
        i.milestoneLine = "White Canyon Complete";
        i.medal = int(Medal::Gold);
        i.playSound = true;
        Trigger(i);
    }

    void Render() {
        if (!S_MedalSplash || m_active is null) return;

        float t = float(Time::Now - m_startMs) / 1000.0f;
        if (t < 0 || t >= SHOW_SECONDS) { @m_active = null; return; }

        float a = 1.0f;
        if (t < FADE_SECONDS) a = t / FADE_SECONDS;
        else if (t > SHOW_SECONDS - FADE_SECONDS) a = (SHOW_SECONDS - t) / FADE_SECONDS;
        a = Math::Clamp(a, 0.0f, 1.0f);

        auto dl = UI::GetForegroundDrawList();
        if (dl is null) return;

        float sw = float(Display::GetWidth());
        float sh = float(Display::GetHeight());

        int mi = Math::Clamp(m_active.medal, 0, 4);
        vec4 accent = mi >= 1 ? Overlay::MEDAL_COL[mi] : vec4(0.85f, 0.85f, 0.9f, 1);

        int lines = 1
            + (m_active.checkedLine != "" ? 1 : 0)
            + (m_active.milestoneLine != "" ? 1 : 0);
        float panelW = Math::Min(sw * 0.42f, 560.0f);
        float panelH = 40.0f + lines * LINE_H;
        float px = (sw - panelW) * 0.5f;
        float py = sh * 0.15f - (1.0f - a) * 14.0f;   // slight rise while fading in

        dl.AddRectFilled(vec4(px, py, panelW, panelH), vec4(0.05f, 0.06f, 0.08f, 0.86f * a), 8.0f);
        dl.AddRect(vec4(px, py, panelW, panelH),
                   vec4(accent.x, accent.y, accent.z, 0.9f * a), 8.0f, 2.0f);
        dl.AddRectFilled(vec4(px, py, 5.0f, panelH), vec4(accent.x, accent.y, accent.z, a), 8.0f);

        float tx = px + 22.0f;
        float ty = py + 12.0f;
        DrawText(dl, m_active.title, vec2(tx, ty), vec4(1, 1, 1, a), 20.0f);
        ty += LINE_H + 2.0f;
        if (m_active.checkedLine != "") {
            DrawText(dl, m_active.checkedLine, vec2(tx, ty),
                     vec4(accent.x, accent.y, accent.z, a), 16.0f);
            ty += LINE_H;
        }
        if (m_active.milestoneLine != "") {
            DrawText(dl, m_active.milestoneLine, vec2(tx, ty), vec4(1, 1, 1, 0.85f * a), 16.0f);
        }
    }

    void DrawText(UI::DrawList@ dl, const string &in s, vec2 pos,
                  const vec4 &in col, float size) {
        dl.AddText(vec2(pos.x + 1, pos.y + 1), vec4(0, 0, 0, col.w * 0.55f), s, null, size);
        dl.AddText(pos, col, s, null, size);
    }
}
