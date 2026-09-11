// Draws lock / medal-progress markers onto Turbo's campaign menus.
//
// Turbo has no menu API. Which screen is up:
//   - series-overview grid (200 tiles): UILayers[12].IsVisible
//   - per-series track picker (10 thumbnails): layer 11 Frame_AllBrowseTrack visible
//   - anything else: neither
//
// Series grid: tile geometry is read from layer 11's ManiaLink tree (find
// "FrameAll_Buttons", iterate its "Frame_Instance*" children, map number from the
// "MouseInput_Track_<row>:<col>" child, position from AbsolutePosition_V3) -- its
// 200 tiles line up with what layer 12 renders; layer 12's own tiles use opaque ids.
//
// Track picker: the 10 thumbnails aren't reachable as ManiaLink tiles. We read
// the series ("Label_Diff0" text) and environment (which column "Frame_Selector"
// sits in), then draw at 10 fixed slots (S_Tp* rect).
//
// The ManiaLink tile grid occupies a fixed rectangle in ML space (measured
// in-game): x in [-120.28, 843.74], y in [25.80, -424.20] (y is up). We map that
// rectangle onto a screen rectangle given as window fractions (S_GridL/T/R/B),
// tuned once by eye via the Debug "Overlay alignment" sliders (box-preview mode)
// and persisted. Re-tune for a different resolution/aspect. There is no reliable
// ML->pixel transform exposed by this build (menu mouse coords are a different
// space), hence the manual calibration.
//
// Drawn from the plugin's single Render() (Main.as), which also draws the medal
// splash. nvg may only be used from that Render() call chain. Every cast here is
// null-guarded -- an unrecognised menu just shows nothing.

namespace Overlay {
    const float PI = 3.14159265;
    const float TILE_W = 48.21;
    const float TILE_H = 45.0;

    // ML-space extent of the tile grid (col 0 left / col 19 right, row 0 top /
    // row 9 bottom). From the probe.
    const float GRID_L = -120.28;
    const float GRID_R = 843.74;
    const float GRID_T = 25.80;
    const float GRID_B = -424.20;

    const array<vec4> MEDAL_COL = {
        vec4(0, 0, 0, 0),
        vec4(0.71, 0.40, 0.16, 1),   // Bronze
        vec4(0.75, 0.75, 0.78, 1),   // Silver
        vec4(1.00, 0.82, 0.25, 1),   // Gold
        vec4(0.20, 0.76, 0.42, 1)    // Author
    };

    vec2 ToScreen(float mlx, float mly) {
        float w = float(Display::GetWidth());
        float h = float(Display::GetHeight());
        float fx = (mlx - GRID_L) / (GRID_R - GRID_L);        // 0..1 left..right
        float fy = (GRID_T - mly) / (GRID_T - GRID_B);        // 0..1 top..bottom
        return vec2((S_GridL + fx * (S_GridR - S_GridL)) * w,
                    (S_GridT + fy * (S_GridB - S_GridT)) * h);
    }

    // ---- ManiaLink tree walk ----------------------------------------------
    CGameManialinkFrame@ FindFrameById(CGameManialinkControl@ node, const string &in id, int depth) {
        if (node is null || depth > 16) return null;
        auto frame = cast<CGameManialinkFrame>(node);
        if (frame is null) return null;
        if (frame.ControlId == id) return frame;
        for (uint i = 0; i < frame.Controls.Length; i++) {
            auto hit = FindFrameById(frame.Controls[i], id, depth + 1);
            if (hit !is null) return hit;
        }
        return null;
    }

    // Which campaign screen is on:
    //   - series-overview grid (we draw here): UILayers[12].IsVisible == true
    //   - per-series track picker: layer 11's Frame_AllBrowseTrack.Visible == true
    //   - anything else (main menu, ...): layer 12 hidden
    // Tile geometry is read from layer 11 (its 200 Frame_Instance tiles line up
    // with the rendered overview grid); layer 12's own tiles use opaque ids.
    CGameManialinkFrame@ TilesFrame(CGameManiaAppTitle@ m) {
        if (m is null || m.UILayers.Length <= 12) return null;

        auto grid = cast<CGameUILayer>(m.UILayers[12]);
        if (grid is null || !grid.IsVisible) return null;      // series grid must be up

        auto l11 = cast<CGameUILayer>(m.UILayers[11]);
        if (l11 is null || l11.LocalPage is null || l11.LocalPage.MainFrame is null) return null;
        auto main = l11.LocalPage.MainFrame;
        auto root = FindFrameById(main, "Frame_AllBrowseTrack", 0);
        if (root !is null && root.Visible) return null;        // that's the track picker
        auto hit = FindFrameById(main, "FrameAll_Buttons", 0);
        if (hit !is null && hit.Controls.Length > 20) return hit;
        return null;
    }

    string VB(CGameManialinkControl@ c) { return c is null ? "?" : (c.Visible ? "1" : "0"); }

    // Live status for the Debug section.
    string DebugStatus() {
        auto app = cast<CTrackMania>(GetApp());
        if (app is null) return "no app";
        if (app.Challenge !is null) return "in a map";
        auto menu = cast<CTrackManiaMenus>(app.MenuManager);
        if (menu is null) return "no menu mgr";
        auto mm = menu.MenuCustom_CurrentManiaApp;
        if (mm is null || mm.UILayers.Length <= 12) return "no maniaApp";
        auto l12 = cast<CGameUILayer>(mm.UILayers[12]);
        auto l11 = cast<CGameUILayer>(mm.UILayers[11]);
        string brt = "?";
        if (l11 !is null && l11.LocalPage !is null && l11.LocalPage.MainFrame !is null)
            brt = VB(FindFrameById(l11.LocalPage.MainFrame, "Frame_AllBrowseTrack", 0));
        int ps = PickerState(mm);
        string picker = ps < 0 ? "-" : ("" + (ps / 4) + "/" + (ps % 4));
        string dest = (TilesFrame(mm) !is null) ? "  -> GRID"
                    : (ps >= 0 ? "  -> PICKER" : "  -> off");
        return "L12.vis=" + (l12 !is null && l12.IsVisible ? "1" : "0")
            + " L11.vis=" + (l11 !is null && l11.IsVisible ? "1" : "0")
            + " brt=" + brt + " picker(s/e)=" + picker + dest;
    }

    // ---- track-picker screen (the 10-thumbnail per-series/env view) --------
    // Not reachable as ManiaLink tiles; we detect series + environment and draw
    // markers at 10 fixed slots (S_Tp* rect). series+env packed as series*4+env,
    // or -1 when this screen is not up.
    int PickerState(CGameManiaAppTitle@ m) {
        if (m is null || m.UILayers.Length <= 11) return -1;
        auto l11 = cast<CGameUILayer>(m.UILayers[11]);
        if (l11 is null || l11.LocalPage is null || l11.LocalPage.MainFrame is null) return -1;
        auto main = l11.LocalPage.MainFrame;

        auto brt = FindFrameById(main, "Frame_AllBrowseTrack", 0);
        if (brt is null || !brt.Visible) return -1;            // not the track picker

        auto fab = FindFrameById(main, "FrameAll_Buttons", 0);
        if (fab is null || fab.Controls.Length < 4) return -1;
        auto diff = cast<CGameManialinkLabel>(fab.Controls[3]);   // "Label_Diff0"
        if (diff is null) return -1;
        string v = string(diff.Value);
        int series = -1;
        if      (v.Contains("White")) series = 0;
        else if (v.Contains("Green")) series = 1;
        else if (v.Contains("Blue"))  series = 2;
        else if (v.Contains("Red"))   series = 3;
        else if (v.Contains("Black")) series = 4;
        if (series < 0) return -1;

        auto sel = FindFrameById(main, "Frame_Selector", 0);
        if (sel is null) return -1;
        int col = int(Math::Round((sel.AbsolutePosition_V3.x - GRID_L) / TILE_W));
        int env = col / 5;
        if (env < 0) env = 0;
        if (env > 3) env = 3;
        return series * 4 + env;
    }

    // Slot k (0..9) rect on the track-picker screen.
    void TpSlot(int k, float &out x, float &out y, float &out w, float &out h) {
        float sw = float(Display::GetWidth());
        float sh = float(Display::GetHeight());
        float cw = (S_TpR - S_TpL) / 5.0f;
        float rh = (S_TpB - S_TpT) / 2.0f;
        x = (S_TpL + (k % 5) * cw) * sw;
        y = (S_TpT + (k / 5) * rh) * sh;
        w = cw * sw;
        h = rh * sh;
    }

    // "MouseInput_Track_R:C" -> 1..200, or 0.
    int MapNumber(CGameManialinkFrame@ tile) {
        for (uint i = 0; i < tile.Controls.Length; i++) {
            auto c = tile.Controls[i];
            if (c is null || !c.ControlId.StartsWith("MouseInput_Track_")) continue;
            array<string>@ parts = c.ControlId.Split("_");
            array<string>@ rc = parts[parts.Length - 1].Split(":");
            if (rc.Length != 2) return 0;
            int r = 0, col = 0;
            if (!Text::TryParseInt(rc[0], r) || !Text::TryParseInt(rc[1], col)) return 0;
            if (r < 0 || r > 9 || col < 0 || col > 19) return 0;
            return (r / 2) * 40 + (col / 5) * 10 + (r % 2) * 5 + (col % 5) + 1;
        }
        return 0;
    }

    // ---- drawing (screen rect: x,y top-left, w,h > 0) --------------------
    void DrawBox(float x, float y, float w, float h, const vec4 &in col) {
        nvg::BeginPath();
        nvg::Rect(x, y, w, h);
        nvg::StrokeColor(col);
        nvg::StrokeWidth(1.5f);
        nvg::Stroke();
    }

    void DrawLock(float x, float y, float w, float h) {
        nvg::BeginPath();
        nvg::RoundedRect(x, y, w, h, w * 0.10f);
        nvg::FillColor(vec4(0, 0, 0, 0.55));
        nvg::Fill();

        float s = Math::Min(w, h);
        float cx = x + w * 0.5f;
        float cy = y + h * 0.5f;
        float body = s * 0.30f;
        float rad  = s * 0.14f;

        nvg::BeginPath();
        nvg::Arc(vec2(cx, cy - body * 0.35f), rad, PI, 2 * PI, nvg::Winding::CW);
        nvg::StrokeColor(vec4(1, 1, 1, 0.95));
        nvg::StrokeWidth(Math::Max(2.0f, s * 0.05f));
        nvg::Stroke();

        nvg::BeginPath();
        nvg::RoundedRect(cx - body * 0.55f, cy - body * 0.35f, body * 1.1f, body * 0.9f, body * 0.15f);
        nvg::FillColor(vec4(1, 1, 1, 0.95));
        nvg::Fill();

        nvg::BeginPath();
        nvg::Circle(vec2(cx, cy + body * 0.05f), Math::Max(1.5f, s * 0.035f));
        nvg::FillColor(vec4(0, 0, 0, 0.85));
        nvg::Fill();
    }

    // availMask: medal tiers that exist as AP locations for this track.
    // checkedMask: of those, which have been checked. Only pips in availMask draw.
    void DrawPips(float x, float y, float w, float h, int availMask, int checkedMask) {
        int count = 0;
        for (int t = 1; t <= 4; t++) if ((availMask & (1 << t)) != 0) count++;
        if (count == 0) return;

        float r = Math::Max(2.5f, Math::Min(w, h) * 0.075f);
        float gap = r * 2.6f;
        float px = x + w * 0.5f - gap * (count - 1) * 0.5f;
        float py = y + h - r * 2.2f;
        int slot = 0;
        for (int t = 1; t <= 4; t++) {
            if ((availMask & (1 << t)) == 0) continue;
            vec2 c = vec2(px + slot * gap, py);
            slot++;
            bool got = (checkedMask & (1 << t)) != 0;
            nvg::BeginPath();
            nvg::Circle(c, r);
            if (got) {
                nvg::FillColor(MEDAL_COL[t]);
                nvg::Fill();
                nvg::StrokeColor(vec4(0, 0, 0, 0.5));
                nvg::StrokeWidth(1.0f);
                nvg::Stroke();
            } else {
                nvg::StrokeColor(vec4(MEDAL_COL[t].x, MEDAL_COL[t].y, MEDAL_COL[t].z, 0.5));
                nvg::StrokeWidth(1.5f);
                nvg::Stroke();
            }
        }
    }
}

// Called from the plugin's single Render() in Main.as.
void RenderCampaignOverlay() {
    if (!S_CampaignOverlay) return;
    if (g_client is null || !g_client.IsReady) return;

    auto app = cast<CTrackMania>(GetApp());
    if (app is null || app.Challenge !is null) return;         // only in menus
    auto menu = cast<CTrackManiaMenus>(app.MenuManager);
    if (menu is null) return;
    auto m = menu.MenuCustom_CurrentManiaApp;
    if (m is null) return;

    float sw = float(Display::GetWidth());
    float sh = float(Display::GetHeight());

    auto tiles = Overlay::TilesFrame(m);
    if (tiles is null) {
        // Not the series grid -- try the per-series track-picker screen.
        int ps = Overlay::PickerState(m);
        if (ps < 0) return;
        int series = ps / 4;
        int env = ps % 4;
        for (int k = 0; k < 10; k++) {
            int n = series * 40 + env * 10 + k + 1;
            if (n < 1 || n > 200) continue;
            float x = 0, y = 0, w = 0, h = 0;
            Overlay::TpSlot(k, x, y, w, h);
            if (S_GridDebug) { Overlay::DrawBox(x, y, w, h, vec4(0, 1, 1, 0.9)); continue; }
            if (g_client.items.IsTrackUnlockedByNumber(n))
                Overlay::DrawPips(x, y, w, h,
                    g_client.locations.AvailMaskForNumber(n),
                    g_client.locations.CheckedMaskForNumber(n));
            else
                Overlay::DrawLock(x, y, w, h);
        }
        return;
    }

    for (uint i = 0; i < tiles.Controls.Length; i++) {
        auto tile = cast<CGameManialinkFrame>(tiles.Controls[i]);
        if (tile is null || !tile.Visible || !tile.ControlId.StartsWith("Frame_Instance")) continue;

        int n = Overlay::MapNumber(tile);
        if (n < 1 || n > 200) continue;

        vec2 ml = tile.AbsolutePosition_V3;                       // ML top-left
        vec2 tl = Overlay::ToScreen(ml.x, ml.y);
        vec2 br = Overlay::ToScreen(ml.x + Overlay::TILE_W, ml.y - Overlay::TILE_H);
        float x = Math::Min(tl.x, br.x);
        float y = Math::Min(tl.y, br.y);
        float w = Math::Abs(br.x - tl.x);
        float hgt = Math::Abs(br.y - tl.y);
        if (w < 3 || hgt < 3 || x > sw || y > sh || x + w < 0 || y + hgt < 0) continue;

        if (S_GridDebug) {
            Overlay::DrawBox(x, y, w, hgt, vec4(1, 0, 1, 0.9));
            continue;
        }
        if (g_client.items.IsTrackUnlockedByNumber(n)) {
            Overlay::DrawPips(x, y, w, hgt,
                g_client.locations.AvailMaskForNumber(n),
                g_client.locations.CheckedMaskForNumber(n));
        } else {
            Overlay::DrawLock(x, y, w, hgt);
        }
    }
}
