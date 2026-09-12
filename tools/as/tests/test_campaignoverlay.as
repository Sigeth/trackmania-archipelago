// Unit tests for src/ui/CampaignOverlay.as -- the self-calibrating grid bounds
// and the pan-relative picker environment detection.
//
// Bug fixed 2026-09-12: the campaign menu pans the whole FrameAll_Buttons
// ManiaLink tree in ML-space depending on which series/environment was last
// browsed in the track picker. The old code assumed a fixed, probe-measured
// ML origin, so after visiting any picker other than White Canyon: the
// picker's own environment detection always read back as Canyon, and
// returning to the series grid left every tile's overlay offset. These tests
// build fake ManiaLink trees (real script objects -- see tools/as/README.md,
// CGameManialinkFrame et al. are plain data classes with working fields in
// this stub, not opaque natives) and assert the fix is pan-invariant.
//
// Two stub gotchas this file works around:
//  - vec2's constructors are no-ops in the generated stub (only the C++ host's
//    real types are backed by working code; vec2 isn't one of them) -- set
//    .x/.y on a default-constructed vec2 directly instead of vec2(x, y).
//  - Math:: functions are likewise no-op stubs (Math::Round always returns 0),
//    which is why PickerState() uses the free function RoundToInt() instead --
//    same reasoning as Transport.as's ShouldSendKeepalive.

CGameManialinkFrame@ SetMLPos(CGameManialinkFrame@ ctrl, float x, float y) {
    vec2 p;
    p.x = x;
    p.y = y;
    ctrl.AbsolutePosition_V3 = p;
    return ctrl;
}

// Every real ManiaLink frame has a (possibly empty) Controls array --
// FindFrameById() recurses into it unconditionally for any non-matching
// frame, so a leaf tile must still carry an empty one rather than a null
// handle.
CGameManialinkFrame@ MakeTile(const string &in id, bool visible, float x, float y) {
    CGameManialinkFrame tile;
    tile.ControlId = id;
    tile.Visible = visible;
    array<CGameManialinkControl@> noChildren;
    @tile.Controls = noChildren;
    return SetMLPos(tile, x, y);
}

CGameManialinkFrame@ MakeContainer(array<CGameManialinkControl@>@ children) {
    CGameManialinkFrame frame;
    @frame.Controls = children;
    return frame;
}

void Test_GridBounds_bbox_from_visible_tiles() {
    array<CGameManialinkControl@> tiles = {
        MakeTile("Frame_Instance0", true, -50.0f, 20.0f),
        MakeTile("Frame_Instance1", true, 200.0f, -100.0f),
        MakeTile("Frame_Instance2", false, 9999.0f, 9999.0f),  // hidden -- ignored
        MakeTile("Frame_Other", true, -9999.0f, -9999.0f),     // wrong id -- ignored
    };
    CGameManialinkFrame@ frame = MakeContainer(tiles);

    float gridL = 0, gridR = 0, gridT = 0, gridB = 0;
    Assert(Overlay::GridBounds(frame, gridL, gridR, gridT, gridB), "visible Frame_Instance tiles were found");
    AssertEq(gridL, -50.0f, "left = leftmost tile's x");
    AssertEq(gridR, 200.0f + Overlay::TILE_W, "right = rightmost tile's x + tile width");
    AssertEq(gridT, 20.0f, "top = topmost tile's y");
    AssertEq(gridB, -100.0f - Overlay::TILE_H, "bottom = bottommost tile's y - tile height");
}

void Test_GridBounds_no_matching_tiles_returns_false() {
    array<CGameManialinkControl@> tiles = {
        MakeTile("Frame_Instance0", false, 0.0f, 0.0f),
        MakeTile("Frame_Other", true, 0.0f, 0.0f),
    };
    CGameManialinkFrame@ frame = MakeContainer(tiles);

    float gridL = 0, gridR = 0, gridT = 0, gridB = 0;
    Assert(!Overlay::GridBounds(frame, gridL, gridR, gridT, gridB), "no visible Frame_Instance* tiles");
}

// The regression test for the series-grid half of the bug: panning the whole
// tile set must pan the computed bounds by exactly the same amount, so the
// live ML<->screen mapping self-heals instead of drifting.
void Test_GridBounds_tracks_menu_pan() {
    float panX = -241.05f;   // one environment-column's worth, per the bug report
    float panY = 17.0f;

    array<CGameManialinkControl@> unpanned = {
        MakeTile("Frame_Instance0", true, -120.28f, 25.80f),
        MakeTile("Frame_Instance1", true, 843.74f - Overlay::TILE_W, -424.20f + Overlay::TILE_H),
    };
    array<CGameManialinkControl@> panned = {
        MakeTile("Frame_Instance0", true, -120.28f + panX, 25.80f + panY),
        MakeTile("Frame_Instance1", true, 843.74f - Overlay::TILE_W + panX, -424.20f + Overlay::TILE_H + panY),
    };

    float l0 = 0, r0 = 0, t0 = 0, b0 = 0;
    Assert(Overlay::GridBounds(MakeContainer(unpanned), l0, r0, t0, b0), "unpanned tiles found");
    float l1 = 0, r1 = 0, t1 = 0, b1 = 0;
    Assert(Overlay::GridBounds(MakeContainer(panned), l1, r1, t1, b1), "panned tiles found");

    AssertEq(l1, l0 + panX, "left tracks the pan");
    AssertEq(r1, r0 + panX, "right tracks the pan");
    AssertEq(t1, t0 + panY, "top tracks the pan");
    AssertEq(b1, b0 + panY, "bottom tracks the pan");
}

// ---- picker environment detection --------------------------------------

CGameManialinkLabel@ MakeDiffLabel(const string &in value) {
    CGameManialinkLabel lbl;
    lbl.Value = value;
    return lbl;
}

// Builds the fake tree PickerState() walks: a MainFrame containing
// Frame_AllBrowseTrack (visible marks the picker as up), FrameAll_Buttons
// (Controls[3] is the series label) and Frame_Selector, positioned fabX/fabY
// and selX/selY apart -- i.e. everything under this tree can be shifted by a
// uniform "menu pan" without changing what PickerState() should compute.
CGameManiaAppTitle@ MakePickerApp(const string &in seriesLabel, float fabX, float fabY, float selX, float selY) {
    CGameManialinkFrame@ brt = MakeTile("Frame_AllBrowseTrack", true, 0.0f, 0.0f);

    array<CGameManialinkControl@> fabChildren = {
        MakeTile("Filler0", true, 0.0f, 0.0f),
        MakeTile("Filler1", true, 0.0f, 0.0f),
        MakeTile("Filler2", true, 0.0f, 0.0f),
        MakeDiffLabel(seriesLabel),   // Controls[3] == "Label_Diff0"
    };
    CGameManialinkFrame@ fab = MakeContainer(fabChildren);
    fab.ControlId = "FrameAll_Buttons";
    SetMLPos(fab, fabX, fabY);

    CGameManialinkFrame@ sel = MakeTile("Frame_Selector", true, selX, selY);

    array<CGameManialinkControl@> mainChildren = { brt, fab, sel };
    CGameManialinkFrame@ main = MakeContainer(mainChildren);

    CGameManialinkPage page;
    @page.MainFrame = main;

    CGameUILayer l11;
    @l11.LocalPage = page;

    array<CGameUILayer@> layers;
    for (int i = 0; i < 11; i++) layers.InsertLast(null);
    layers.InsertLast(l11);

    CGameManiaAppTitle app;
    @app.UILayers = layers;
    return app;
}

void Test_PickerState_reads_series_and_env_from_relative_offset() {
    // White Lagoon: series 0, env 2. relX = env * 5 columns of TILE_W each --
    // an exact multiple so rounding can't hide a wrong axis/scale.
    float relX = 2.0f * 5.0f * Overlay::TILE_W;
    CGameManiaAppTitle@ app = MakePickerApp("White", 37.0f, -12.0f, 37.0f + relX, -12.0f);

    float relXOut = 0;
    int ps = Overlay::PickerState(app, relXOut);
    Assert(ps >= 0, "recognised as the track picker");
    AssertEq(ps / 4, 0, "series = White");
    AssertEq(ps % 4, 2, "env = Lagoon");
    AssertEq(relXOut, relX, "reports the relative offset it used");
}

// The regression test for the picker half of the bug: FrameAll_Buttons and
// Frame_Selector both live under the same panned tree, so reading
// Frame_Selector relative to FrameAll_Buttons (instead of a fixed ML origin)
// must give the same series/env no matter where the menu panned them to.
void Test_PickerState_immune_to_menu_pan() {
    float relX = 1.0f * 5.0f * Overlay::TILE_W;   // env 1 (Valley)

    CGameManiaAppTitle@ atOrigin = MakePickerApp("Green", 0.0f, 0.0f, relX, 0.0f);
    float relXOut1 = 0;
    int ps1 = Overlay::PickerState(atOrigin, relXOut1);
    Assert(ps1 >= 0, "sanity: origin case recognised");
    AssertEq(ps1 / 4, 1, "sanity: series = Green");
    AssertEq(ps1 % 4, 1, "sanity: env = Valley");

    float panX = -973.4f, panY = 288.0f;   // an arbitrary menu pan
    CGameManiaAppTitle@ panned = MakePickerApp("Green", panX, panY, panX + relX, panY);
    float relXOut2 = 0;
    int ps2 = Overlay::PickerState(panned, relXOut2);

    AssertEq(ps2, ps1, "same series/env before and after an arbitrary menu pan");
    AssertEq(relXOut2, relXOut1, "relative offset is pan-invariant too");
}

void Test_PickerState_not_the_picker_screen_returns_negative_one() {
    CGameManiaAppTitle@ app = MakePickerApp("White", 0.0f, 0.0f, 0.0f, 0.0f);

    // Hide Frame_AllBrowseTrack -- this is what the series-overview grid (or
    // any other menu) looks like from PickerState()'s point of view.
    auto l11 = cast<CGameUILayer>(app.UILayers[11]);
    auto brt = l11.LocalPage.MainFrame.Controls[0];
    cast<CGameManialinkFrame>(brt).Visible = false;

    float relXOut = 0;
    AssertEq(Overlay::PickerState(app, relXOut), -1, "not the track picker when Frame_AllBrowseTrack is hidden");
}

void Test_PickerState_unknown_series_text_returns_negative_one() {
    CGameManiaAppTitle@ app = MakePickerApp("Purple", 0.0f, 0.0f, 0.0f, 0.0f);
    float relXOut = 0;
    AssertEq(Overlay::PickerState(app, relXOut), -1, "unrecognised tier text");
}

// ---- grid tile -> campaign number ---------------------------------------

void Test_MapNumber_from_control_id() {
    CGameManialinkFrame tile;
    array<CGameManialinkControl@> children = { MakeTile("MouseInput_Track_0:0", true, 0.0f, 0.0f) };
    @tile.Controls = children;
    AssertEq(Overlay::MapNumber(tile), 1, "row 0 col 0 -> map 1 (White Canyon 01)");

    CGameManialinkFrame tile2;
    array<CGameManialinkControl@> children2 = { MakeTile("MouseInput_Track_9:19", true, 0.0f, 0.0f) };
    @tile2.Controls = children2;
    AssertEq(Overlay::MapNumber(tile2), 200, "row 9 col 19 -> map 200 (Black Stadium 10)");
}

void Test_MapNumber_no_mouse_input_child_returns_zero() {
    CGameManialinkFrame tile;
    array<CGameManialinkControl@> children = { MakeTile("SomethingElse", true, 0.0f, 0.0f) };
    @tile.Controls = children;
    AssertEq(Overlay::MapNumber(tile), 0, "no MouseInput_Track_ child");
}
