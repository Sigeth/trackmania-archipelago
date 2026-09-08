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
