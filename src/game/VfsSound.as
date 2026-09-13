// Runtime extraction of the game's own medal announcer voice lines, so the
// plugin doesn't need a player to hand-extract .wav files with an external
// NadeoPak tool first (assets/README.md documents that as a manual override
// / fallback, but it's no longer required). CONFIRMED WORKING end-to-end
// in-game 2026-09-13 (heard the Gold voice line play on a real "Test medal
// splash" trigger).
//
// Investigation trail, because none of this is obvious from the Fids::
// API surface alone (no descriptions in the JSON dumps or turbo.openplanet.dev):
//   1. Fids::GetGameFolder(compoundPath) never resolves a multi-segment path
//      in one call for a subtree that hasn't been walked yet -- confirmed
//      GetGameFolder("GameData") resolves and lists "Media" as one of its
//      .Trees, but GetGameFolder("GameData\\Media") still comes back null.
//      So every folder lookup below walks one path segment at a time,
//      matching each segment against the parent's already-populated .Trees
//      by name (see ResolveFolder/FindChild), never a compound string.
//   2. The "Game" drive (Fids::GetGameFolder("")) is the literal on-disk
//      install directory (GameData\, Packs\, Openplanet\, ...) -- its
//      GameData\Media\Sounds is a real folder but completely EMPTY. Nothing
//      is unpacked there. This is NOT where the audio lives.
//   3. The **User** drive (Fids::GetUserFolder("")), which resolves to the
//      player's `Documents\TrackmaniaTurbo\` folder, mirrors a
//      runtime-populated asset-reference tree -- Media\Sounds\TMConsole\
//      Voices\ there lists 90+ entries (voice-carhit-*, checkpoint,
//      voice-medal-{bronze,silver,gold,author}, ...). Of the 5 Fids drives
//      (Resource/ProgramData/User/Game/Fake), only User had it.
//   4. BUT those entries are virtual (.FullFileName == "<virtual>") and tiny
//      (.ByteSize 38-539 bytes even for content confirmed real and
//      frequently played, like carhit) -- they're reference records, not
//      the audio payload. Fids::Extract(fid) still reports success against
//      them, and Fids::GetFullPath(fid) is USELESS here -- it returns just
//      the containing folder with no filename, no drive letter (confirmed
//      by direct test). Guessing the extracted-to location by combining
//      GetFullPath/FullFileName/the scan's own folder path with every
//      plausible base directory all failed IO::FileExists.
//   5. THE ANSWER, found by searching GitHub for other Openplanet plugins'
//      real Fids::Extract usage (AurisTFG/tm-fid-loader's FidWrapper.as):
//      extraction lands under Openplanet's own **Data folder**, in an
//      "Extract\" subfolder mirroring the DRIVE-RELATIVE path (no drive
//      name in the string) -- see ExtractedPath() below. Confirmed with
//      IO::FileExists before wiring it into the real pipeline.
// CSystemFidFile@ handles are taken directly from the folder walk's own
// .Leaves -- NOT a fresh Fids::GetGame()/GetUser() lookup (which needs the
// same segment-by-segment walk to resolve anyway, so there's nothing to gain
// by re-looking-up what's already in hand).
namespace VfsSound {
    array<array<string>> SCAN_PATHS;

    void InitScanPaths() {
        if (SCAN_PATHS.Length > 0) return;
        array<string> voices = { "User", "Media", "Sounds", "TMConsole", "Voices" };
        SCAN_PATHS.InsertLast(voices);
    }

    const uint MAX_NODES = 20000; // safety cap so a pathological tree can't hang a frame

    // index 0 unused (Medal enum starts at 1 = Bronze); parallel to Medal.
    array<string> TIER_KEYWORD = { "", "bronze", "silver", "gold", "author" };
    array<string> FALLBACK_KEYWORDS = { "victory", "record", "podium", "reward" };

    bool m_scanned = false;
    array<string> m_audioPaths;          // every .ogg/.wav leaf found, full VFS path
    array<CSystemFidFile@> m_audioFids;  // parallel to m_audioPaths -- the actual handle to extract
    uint m_visited = 0; // node budget for the current scan (WalkFolder recursion)

    string JoinPath(const array<string> &in segments) {
        string s = "";
        for (uint i = 0; i < segments.Length; i++) s += (i > 0 ? "\\" : "") + segments[i];
        return s;
    }

    string JoinRoots() {
        InitScanPaths();
        string s = "";
        for (uint i = 0; i < SCAN_PATHS.Length; i++) s += (i > 0 ? ", " : "") + JoinPath(SCAN_PATHS[i]);
        return s;
    }

    // Root folder of one of the 5 Fids drives, by name (Resource/ProgramData/
    // User/Game/Fake). Null on an unknown name or if the drive resolves to null.
    CSystemFidsFolder@ GetDriveRoot(const string &in driveName) {
        try {
            if (driveName == "Resource") return Fids::GetResourceFolder("");
            if (driveName == "ProgramData") return Fids::GetProgramDataFolder("");
            if (driveName == "User") return Fids::GetUserFolder("");
            if (driveName == "Game") return Fids::GetGameFolder("");
            if (driveName == "Fake") return Fids::GetFakeFolder("");
        } catch {}
        return null;
    }

    // First child of `parent` (after populating its tree) whose folder name
    // matches `name`, case-insensitive. Null if not found.
    CSystemFidsFolder@ FindChild(CSystemFidsFolder@ parent, const string &in name) {
        if (parent is null) return null;
        try { Fids::UpdateTree(parent, false); } catch {}
        for (uint i = 0; i < parent.Trees.Length; i++) {
            auto sub = cast<CSystemFidsFolder>(parent.Trees[i]);
            if (sub is null) continue;
            if (string(sub.DirName).ToLower() == name.ToLower()) return sub;
        }
        return null;
    }

    // Walk `segments` one at a time: segments[0] names the drive (see
    // GetDriveRoot), the rest are child-folder names matched via FindChild
    // (see the file header for why a compound path string doesn't work).
    // Logs each step so a failure shows exactly which segment didn't resolve.
    CSystemFidsFolder@ ResolveFolder(const array<string> &in segments, bool logDiag) {
        if (segments.Length == 0) return null;
        CSystemFidsFolder@ cur = GetDriveRoot(segments[0]);
        if (logDiag) Log::Trace("VfsSound: drive '" + segments[0] + "' -> " + (cur is null ? "null" : "ok"));
        if (cur is null) return null;
        for (uint i = 1; i < segments.Length && cur !is null; i++) {
            auto next = FindChild(cur, segments[i]);
            if (logDiag)
                Log::Trace("VfsSound:   ." + segments[i] + " -> "
                           + (next is null ? "not found under " + string(cur.FullDirName) : "ok"));
            @cur = next;
        }
        return cur;
    }

    // Where Fids::Extract() actually deposits bytes for a fid obtained via
    // folder-walk (as opposed to a fresh Fids::GetGame()/GetUser() lookup,
    // whose GetFullPath() we never trusted here): Openplanet's own Data
    // folder, under an "Extract\" subfolder mirroring the DRIVE-RELATIVE VFS
    // path (no drive name in the string -- "User"/"Game" is which function
    // you called, not part of the path). Confirmed in-game 2026-09-13 by
    // testing real working code from another Openplanet plugin
    // (AurisTFG/tm-fid-loader's FidWrapper.as on GitHub):
    // IO::FromDataFolder("Extract/" + <path minus filename> + fid.FileName).
    // `driveRelFolder` is that path (no drive name, no leading/trailing
    // backslash), e.g. "Media\Sounds\TMConsole\Voices".
    string ExtractedPath(CSystemFidFile@ fid, const string &in driveRelFolder) {
        return IO::FromDataFolder("Extract\\" + driveRelFolder + "\\" + fid.FileName);
    }

    // Recursion tracks progress via m_visited (a member, not a by-ref uint
    // param) -- AngelScript's real Openplanet build rejects &inout on
    // non-handle types (unsafe references disabled), even though the offline
    // asrun checker allowed it. Caller resets m_visited before the first
    // call. `driveRelFolder` is this folder's own drive-relative path (see
    // ExtractedPath), extended with the child's DirName when recursing.
    void WalkFolder(CSystemFidsFolder@ folder, const string &in driveRelFolder, bool logDiag = false) {
        if (folder is null) return;
        // Fids folders are lazily populated -- .Trees/.Leaves read empty
        // until the tree is pulled in.
        try { Fids::UpdateTree(folder, true); } catch {
            if (logDiag) Log::Trace("VfsSound: UpdateTree threw -- " + getExceptionInfo());
        }
        if (logDiag)
            Log::Trace("VfsSound: post-UpdateTree Leaves=" + folder.Leaves.Length
                       + " Trees=" + folder.Trees.Length);
        for (uint i = 0; i < folder.Leaves.Length; i++) {
            if (m_visited++ >= MAX_NODES) return;
            auto leaf = cast<CSystemFidFile>(folder.Leaves[i]);
            if (leaf is null) continue;
            // .FullFileName is the literal string "<virtual>" for a fid that
            // hasn't been extracted to disk yet (confirmed in-game
            // 2026-09-13) -- .FileName still carries the real name +
            // extension, so match/display on that instead.
            string name = leaf.FileName;
            string lower = name.ToLower();
            if (lower.EndsWith(".ogg") || lower.EndsWith(".wav")) {
                m_audioPaths.InsertLast(ExtractedPath(leaf, driveRelFolder));
                m_audioFids.InsertLast(leaf);
            }
        }
        for (uint i = 0; i < folder.Trees.Length; i++) {
            if (m_visited >= MAX_NODES) return;
            auto sub = cast<CSystemFidsFolder>(folder.Trees[i]);
            if (sub is null) continue;
            WalkFolder(sub, driveRelFolder + "\\" + string(sub.DirName));
        }
    }

    // Walk SCAN_PATHS once and cache every audio file found (path + handle).
    // Cheap after the first call. `force` re-scans even if already done
    // (debug button). MUST be called on the game thread -- same rule as the
    // Fids::/Audio:: calls it leads into.
    void EnsureScanned(bool force = false) {
        if (m_scanned && !force) return;
        m_scanned = true;
        InitScanPaths();
        m_audioPaths.Resize(0);
        m_audioFids.Resize(0);
        m_visited = 0;
        for (uint p = 0; p < SCAN_PATHS.Length; p++) {
            try {
                auto folder = ResolveFolder(SCAN_PATHS[p], true);
                if (folder is null) continue;
                // Drive-relative path is SCAN_PATHS[p] minus its first
                // element (the drive name -- see ExtractedPath).
                array<string> rel;
                for (uint s = 1; s < SCAN_PATHS[p].Length; s++) rel.InsertLast(SCAN_PATHS[p][s]);
                WalkFolder(folder, JoinPath(rel), true);
            } catch {
                Log::Warn("VfsSound: scan of '" + JoinPath(SCAN_PATHS[p]) + "' failed -- " + getExceptionInfo());
            }
        }
        Log::Trace("VfsSound: found " + m_audioPaths.Length + " audio file(s) under " + JoinRoots());
    }

    // Index of the first cached file whose full VFS path contains `keyword`
    // (case-insensitive), or -1.
    int FindIndexByKeyword(const string &in keyword) {
        for (uint i = 0; i < m_audioPaths.Length; i++) {
            if (m_audioPaths[i].IndexOfI(keyword) >= 0) return int(i);
        }
        return -1;
    }

    // Extract + load a cached file. `knownPath` is the absolute path already
    // built during the scan (folder.FullDirName + leaf.FileName) -- NOT
    // Fids::GetFullPath(fid), which was confirmed in-game (2026-09-13) to
    // return just the containing folder with no filename for a fid obtained
    // via folder-walk (as opposed to Fids::GetGame()), making it unusable
    // here. Returns null on any failure -- never throws. MUST be called on
    // the game thread.
    Audio::Sample@ LoadFile(CSystemFidFile@ fid, const string &in knownPath) {
        if (fid is null || knownPath == "") return null;
        try {
            if (!Fids::Extract(fid)) return null;
            return Audio::LoadSampleFromAbsolutePath(knownPath);
        } catch {
            Log::Trace("VfsSound: load failed for '" + knownPath + "' -- " + getExceptionInfo());
            return null;
        }
    }

    // Resolve + load the best match for medal tier `mi` (1 Bronze .. 4
    // Author): the tier's own keyword first, then the shared fallback cues in
    // order, else null (silent). MUST be called on the game thread.
    Audio::Sample@ SampleForTier(int mi) {
        if (mi < 1 || mi > 4) return null;
        EnsureScanned();
        int idx = FindIndexByKeyword(TIER_KEYWORD[mi]);
        if (idx < 0) {
            for (uint i = 0; i < FALLBACK_KEYWORDS.Length && idx < 0; i++)
                idx = FindIndexByKeyword(FALLBACK_KEYWORDS[i]);
        }
        if (idx < 0) return null;
        return LoadFile(m_audioFids[idx], m_audioPaths[idx]);
    }

    // Human-readable resolution report for the debug panel.
    string DebugSummary() {
        if (!m_scanned) return "Not scanned yet -- click Scan, or it happens automatically on the first medal.";
        string s = "Found " + m_audioPaths.Length + " audio file(s) under " + JoinRoots() + ".\n";
        array<string> names = { "Bronze", "Silver", "Gold", "Author" };
        for (uint mi = 1; mi <= 4; mi++) {
            int idx = FindIndexByKeyword(TIER_KEYWORD[mi]);
            string source = "own file";
            if (idx < 0) {
                for (uint i = 0; i < FALLBACK_KEYWORDS.Length && idx < 0; i++) {
                    idx = FindIndexByKeyword(FALLBACK_KEYWORDS[i]);
                    source = "fallback: " + FALLBACK_KEYWORDS[i];
                }
            }
            s += names[mi - 1] + ": " + (idx < 0 ? "not found -- silent" : m_audioPaths[idx] + " (" + source + ")") + "\n";
        }
        return s;
    }
}
