// Unit tests for the medal-splash text composition
// (src/ui/MedalSplash.as MakeSplash, src/Main.as ChecksLine).

void Test_MakeSplash_medal_and_checks() {
    FinishEvent ev;
    ev.trackLabel = "White Canyon 03";
    ev.medal = Medal::Gold;
    ev.timeMs = 28906;

    SplashInfo@ s = MakeSplash(ev, true, "Checked: Gold, Author", "White Canyon Complete");
    AssertEq(s.title, "White Canyon 03 - Gold", "title = track + earned medal");
    AssertEq(s.checkedLine, "Checked: Gold, Author", "checked line passed through");
    AssertEq(s.milestoneLine, "White Canyon Complete", "milestone line passed through");
    AssertEq(s.medal, int(Medal::Gold), "medal accent");
    AssertEq(s.playSound, true, "sound when the finish armed a check");
}

void Test_MakeSplash_bare_finish() {
    FinishEvent ev;
    ev.trackLabel = "Black Stadium 10";
    ev.medal = Medal(0);

    SplashInfo@ s = MakeSplash(ev, false, "", "");
    AssertEq(s.title, "Black Stadium 10 - Finish", "no-medal finish title");
    AssertEq(s.checkedLine, "", "no checked line");
    AssertEq(s.playSound, false, "no sound without a check");
}

void Test_ChecksLine() {
    array<string> none;
    AssertEq(ChecksLine(none), "", "empty -> blank");

    array<string> one = { "Gold" };
    AssertEq(ChecksLine(one), "Checked: Gold", "single tier");

    array<string> two = { "Gold", "Author" };
    AssertEq(ChecksLine(two), "Checked: Gold, Author", "tiers joined with a comma");
}
