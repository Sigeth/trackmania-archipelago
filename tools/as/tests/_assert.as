// Assertion helpers for asrun --test. A failed assertion throws; the runner
// reports it as FAIL <test> : <message>.
//
// Test entry points are global functions named Test_*  taking no arguments,
// living anywhere under tools/as/tests/.

void Assert(bool cond, const string &in msg = "assertion failed") {
    if (!cond) throw(msg);
}

void AssertEq(int got, int want, const string &in what = "") {
    if (got != want)
        throw((what == "" ? "" : what + ": ") + "expected " + want + ", got " + got);
}

void AssertEq(const string &in got, const string &in want, const string &in what = "") {
    if (got != want)
        throw((what == "" ? "" : what + ": ") + "expected \"" + want + "\", got \"" + got + "\"");
}

void AssertEq(bool got, bool want, const string &in what = "") {
    if (got != want)
        throw((what == "" ? "" : what + ": ") + "expected " + (want ? "true" : "false")
              + ", got " + (got ? "true" : "false"));
}

// Not Math::Abs(): this AngelScript stub host has no C++-backed Math::* --
// every Math:: function in the generated stub is a no-op returning a
// constant, so Math::Abs(anything) is always 0 here. Plain arithmetic instead.
void AssertEq(float got, float want, const string &in what = "") {
    float diff = got - want;
    if (diff < 0) diff = -diff;
    if (diff > 0.01f)
        throw((what == "" ? "" : what + ": ") + "expected " + want + ", got " + got);
}
