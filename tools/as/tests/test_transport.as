// Unit tests for src/net/Transport.as -- the pure keepalive-threshold check.
//
// Transport itself is compile-checked only (its Net::Socket dependency is an
// inert stub, see tools/as/README.md), so ShouldSendKeepalive is factored out
// as a free function with no engine dependency specifically so this logic can
// be exercised for real.

void Test_ShouldSendKeepalive_below_threshold() {
    Assert(!ShouldSendKeepalive(1000, 1000 + TRANSPORT_KEEPALIVE_INTERVAL_MS - 1),
           "just under the interval must not fire");
}

void Test_ShouldSendKeepalive_at_threshold() {
    Assert(ShouldSendKeepalive(1000, 1000 + TRANSPORT_KEEPALIVE_INTERVAL_MS),
           "exactly at the interval must fire");
}

void Test_ShouldSendKeepalive_past_threshold() {
    Assert(ShouldSendKeepalive(1000, 1000 + TRANSPORT_KEEPALIVE_INTERVAL_MS + 5000),
           "well past the interval must fire");
}

void Test_ShouldSendKeepalive_resets_after_any_send() {
    // Mirrors real usage: SendFrame() stamps m_lastSendMs on every outbound
    // frame, not just our own ping -- e.g. the existing pong reply to a
    // server-initiated ping -- so a recent send of any kind holds the timer off.
    uint64 now = 1000000;
    uint64 lastSend = now - (TRANSPORT_KEEPALIVE_INTERVAL_MS - 1);
    Assert(!ShouldSendKeepalive(lastSend, now), "a send just under the interval ago must not re-fire");
}
