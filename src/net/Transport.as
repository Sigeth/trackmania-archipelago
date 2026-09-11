// WebSocket client for Archipelago, implemented over Net::Socket.
//
// The Turbo build of Openplanet (1.29.x) has no Net::WebSocket, but it does have
// a TCP socket with TLS (Net::Socket.Connect(host, port, secure)). This file is
// a minimal RFC 6455 client: HTTP upgrade handshake, then masked text frames out
// / unmasked frames in, with fragmentation + ping/pong handled.
//
// It is the ONLY networking code in the plugin. Public surface consumed by
// ApClient: Connect(url) / Pump() -> inbound text messages / Send(text) / Close()
// / State / LastError / IsOpen.
//
// The receive buffer is a byte array, NOT a string: a WebSocket frame header
// carries the payload length as raw bytes, and any frame whose length has a zero
// byte (payload length a multiple of 256, or any large frame) puts a 0x00 in the
// stream. Openplanet's Net::Socket.ReadRaw + AngelScript string concatenation
// truncate at the first 0x00, which silently stalls frame parsing. ReadBuffer +
// array<uint8> are binary-safe; only the isolated payload (NUL-free JSON) is
// turned into a string.

namespace Transport {
    enum State { Idle, Connecting, Handshaking, Open, Closed, Failed }
}

// Client-initiated keepalive: if we haven't sent anything in a while, send a WS
// ping ourselves. Guards against idle disconnects from the AP server's own
// ping/pong timeout or an in-between proxy/NAT dropping a quiet connection --
// either way, traffic in either direction resets the idle clock.
const uint64 TRANSPORT_KEEPALIVE_INTERVAL_MS = 30000;

class Transport {
    private Net::Socket@ m_sock;
    private Transport::State m_state = Transport::State::Idle;
    private string m_lastError;

    private array<uint8> m_rx;           // raw bytes received, not yet consumed
    private string m_fragData;           // reassembly buffer for fragmented text
    private bool m_fragging = false;

    private string m_host;
    private uint16 m_port = 0;
    private bool m_secure = false;
    private string m_path = "/";

    private uint64 m_lastSendMs = 0;   // for the keepalive ping timer

    Transport::State get_State() const { return m_state; }
    string get_LastError() const { return m_lastError; }
    bool get_IsOpen() const { return m_state == Transport::State::Open; }

    // ---- public API -------------------------------------------------

    void Connect(const string &in url) {
        Close();
        m_state = Transport::State::Idle;
        m_lastError = "";
        m_rx.Resize(0); m_fragData = ""; m_fragging = false;

        if (!ParseUrl(url)) { Fail("malformed url: " + url); return; }

        @m_sock = Net::Socket();
        Log::Info("TCP connect " + m_host + ":" + m_port + (m_secure ? " (TLS)" : ""));
        if (!m_sock.Connect(m_host, m_port, m_secure)) { Fail("socket connect failed"); return; }
        m_state = Transport::State::Connecting;
    }

    array<string>@ Pump() {
        array<string> msgs;
        if (m_sock is null) return msgs;

        if (m_state == Transport::State::Connecting) {
            if (m_sock.IsHungUp()) { Fail("connection refused"); return msgs; }
            if (!m_sock.IsReady()) return msgs;
            SendHandshake();
            m_state = Transport::State::Handshaking;
        }

        if (m_state != Transport::State::Handshaking && m_state != Transport::State::Open) {
            return msgs;
        }

        DrainSocket();
        if (m_sock.IsHungUp() && m_rx.Length == 0) { Fail("connection closed by server"); return msgs; }

        if (m_state == Transport::State::Handshaking) {
            int r = ConsumeHandshake();
            if (r == 0) return msgs;         // need more bytes
            if (r < 0) return msgs;          // Fail() already called
            m_state = Transport::State::Open;
            m_lastSendMs = Time::Now;
            Log::Info("WebSocket open");
        }

        if (m_state == Transport::State::Open && ShouldSendKeepalive(m_lastSendMs, Time::Now)) {
            SendFrame(0x9, "");
        }

        while (m_state == Transport::State::Open) {
            WsFrame@ f = WsFrameParse(m_rx);
            if (f is null) {
                if (S_Trace && m_rx.Length >= 2) {
                    Log::Trace("rx partial: " + m_rx.Length + " bytes (b0=" + m_rx[0]
                               + " b1=" + m_rx[1] + ")");
                }
                break;
            }
            m_rx = SliceFrom(m_rx, uint(f.consumed));
            HandleFrame(f, msgs);
        }
        return msgs;
    }

    bool Send(const string &in text) {
        if (!IsOpen) return false;
        SendFrame(0x1, text);
        return true;
    }

    void Close() {
        if (m_sock !is null) {
            if (m_state == Transport::State::Open) SendFrame(0x8, "");
            m_sock.Close();
            @m_sock = null;
        }
        if (m_state == Transport::State::Connecting
            || m_state == Transport::State::Handshaking
            || m_state == Transport::State::Open) {
            m_state = Transport::State::Closed;
        }
    }

    // ---- internals -------------------------------------------------

    private bool ParseUrl(const string &in url) {
        string s = url;
        if (s.StartsWith("wss://"))      { m_secure = true;  s = s.SubStr(6); }
        else if (s.StartsWith("ws://"))  { m_secure = false; s = s.SubStr(5); }
        else return false;

        int slash = s.IndexOf("/");
        if (slash >= 0) { m_path = s.SubStr(slash); s = s.SubStr(0, slash); }
        else            { m_path = "/"; }

        int colon = s.IndexOf(":");
        if (colon >= 0) {
            m_host = s.SubStr(0, colon);
            m_port = uint16(Text::ParseUInt(s.SubStr(colon + 1)));
        } else {
            m_host = s;
            m_port = m_secure ? 443 : 80;
        }
        return m_host.Length > 0 && m_port > 0;
    }

    private void SendHandshake() {
        // The server does not check Sec-WebSocket-Key beyond echoing it, and we
        // trust the socket, so a fresh random key is all that's needed.
        string key = Crypto::RandomBase64(16);
        string req =
            "GET " + m_path + " HTTP/1.1\r\n" +
            "Host: " + m_host + ":" + m_port + "\r\n" +
            "Upgrade: websocket\r\n" +
            "Connection: Upgrade\r\n" +
            "Sec-WebSocket-Key: " + key + "\r\n" +
            "Sec-WebSocket-Version: 13\r\n" +
            "\r\n";
        m_sock.WriteRaw(req);
        Log::Trace("handshake sent");
    }

    private void DrainSocket() {
        int guard = 0;
        while (guard++ < 8192) {
            int av = m_sock.Available();
            if (av <= 0) break;
            MemoryBuffer@ buf = m_sock.ReadBuffer(av);
            if (buf is null) break;
            uint got = buf.GetSize();
            if (got == 0) break;
            buf.Seek(0);
            for (uint i = 0; i < got; i++) m_rx.InsertLast(buf.ReadUInt8());
        }
    }

    // 1 = ok, 0 = incomplete, -1 = failed
    private int ConsumeHandshake() {
        int end = -1;
        for (uint i = 0; i + 3 < m_rx.Length; i++) {
            if (m_rx[i] == 0x0D && m_rx[i + 1] == 0x0A
                && m_rx[i + 2] == 0x0D && m_rx[i + 3] == 0x0A) { end = int(i); break; }
        }
        if (end < 0) return 0;

        string head = BytesToString(m_rx, 0, uint(end));
        m_rx = SliceFrom(m_rx, uint(end + 4));           // anything after = frame data

        array<string>@ lines = head.Split("\r\n");
        if (lines.Length == 0 || !lines[0].Contains(" 101")) {
            Fail("handshake rejected: " + (lines.Length > 0 ? lines[0] : "(no status line)"));
            return -1;
        }
        return 1;
    }

    private void HandleFrame(WsFrame@ f, array<string>@ msgs) {
        switch (f.opcode) {
            case 0x0:                                // continuation
                if (m_fragging) {
                    m_fragData += f.payload;
                    if (f.fin) { msgs.InsertLast(m_fragData); m_fragData = ""; m_fragging = false; }
                }
                break;
            case 0x1:                                // text
                if (f.fin) {
                    msgs.InsertLast(f.payload);
                    if (S_Trace) Log::Trace("<< " + f.payload);
                } else {
                    m_fragData = f.payload;
                    m_fragging = true;
                }
                break;
            case 0x2: break;                         // binary: AP is text only
            case 0x8:                                // close
                Log::Info("server sent close frame");
                Close();
                break;
            case 0x9:                                      // ping -> pong
                if (S_Trace) Log::Trace("<< ping (server), replying pong");
                SendFrame(0xA, f.payload);
                break;
            case 0xA:
                if (S_Trace) Log::Trace("<< pong");
                break;
        }
    }

    private void SendFrame(uint8 opcode, const string &in payload) {
        if (m_sock is null) return;

        MemoryBuffer@ b = MemoryBuffer();
        b.Write(uint8(0x80 | opcode));               // FIN + opcode

        uint n = payload.Length;
        if (n < 126) {
            b.Write(uint8(0x80 | n));                // MASK bit + 7-bit length
        } else if (n < 65536) {
            b.Write(uint8(0x80 | 126));
            b.Write(uint8((n >> 8) & 0xFF));
            b.Write(uint8(n & 0xFF));
        } else {
            b.Write(uint8(0x80 | 127));
            for (int i = 7; i >= 0; i--) b.Write(uint8((n >> (8 * i)) & 0xFF));
        }

        // 4-byte masking key (mandatory for client -> server frames).
        array<uint8> key(4);
        MemoryBuffer@ rnd = Crypto::Random(4);
        rnd.Seek(0);
        for (uint i = 0; i < 4; i++) { key[i] = rnd.ReadUInt8(); b.Write(key[i]); }

        for (uint i = 0; i < n; i++) {
            b.Write(uint8(uint8(payload[i]) ^ key[i % 4]));
        }

        b.Seek(0);
        m_sock.Write(b, b.GetSize());
        m_lastSendMs = Time::Now;
        if (S_Trace && opcode == 0x1) Log::Trace(">> " + payload);
        else if (S_Trace && opcode == 0x9) Log::Trace(">> ping (keepalive)");
    }

    private void Fail(const string &in why) {
        m_lastError = why;
        m_state = Transport::State::Failed;
        Log::Error("Transport: " + why);
        if (m_sock !is null) { m_sock.Close(); @m_sock = null; }
    }
}

// Pure threshold check for the client-initiated keepalive, pulled out of Pump()
// so it's testable without a live Net::Socket (asrun's socket dependencies are
// inert stubs -- see tools/as/README.md).
bool ShouldSendKeepalive(uint64 lastSendMs, uint64 nowMs) {
    return nowMs - lastSendMs >= TRANSPORT_KEEPALIVE_INTERVAL_MS;
}

// One parsed inbound frame. `consumed` is how many bytes it occupied in the
// receive buffer so the caller can advance past it.
class WsFrame {
    bool fin;
    uint8 opcode;
    string payload;
    int consumed;
}

// Copy of `a` from `start` to the end. AngelScript arrays have no cheap slice and
// RemoveRange is not guaranteed on this build, so rebuild -- the RX buffer is at
// most one frame plus a partial, so this stays small.
array<uint8> SliceFrom(const array<uint8> &in a, uint start) {
    array<uint8> r;
    for (uint i = start; i < a.Length; i++) r.InsertLast(a[i]);
    return r;
}

// `count` bytes of `a` from `start`, as a string. Safe for NUL bytes (a
// WebSocket header may contain them); callers only pass ASCII/JSON ranges.
string BytesToString(const array<uint8> &in a, uint start, uint count) {
    if (count == 0) return "";
    MemoryBuffer@ b = MemoryBuffer();
    for (uint i = 0; i < count; i++) b.Write(a[start + i]);
    b.Seek(0);
    return b.ReadString(count);
}

// Parse one frame off the front of `buf`. Returns null if `buf` does not yet
// hold a whole frame. (Openplanet's AngelScript has no static class methods, so
// this is a free function.)
WsFrame@ WsFrameParse(const array<uint8> &in buf) {
    uint len = buf.Length;
    if (len < 2) return null;

    uint8 b0 = buf[0];
    uint8 b1 = buf[1];
    bool masked = (b1 & 0x80) != 0;                 // servers must not mask
    uint64 plen = (b1 & 0x7F);
    uint off = 2;

    if (plen == 126) {
        if (len < off + 2) return null;
        plen = (uint64(buf[off]) << 8) | uint64(buf[off + 1]);
        off += 2;
    } else if (plen == 127) {
        if (len < off + 8) return null;
        plen = 0;
        for (uint i = 0; i < 8; i++) plen = (plen << 8) | uint64(buf[off + i]);
        off += 8;
    }
    if (masked) {
        if (len < off + 4) return null;
        off += 4;                                   // key present but unused below
    }
    if (uint64(len) < uint64(off) + plen) return null;

    WsFrame f;
    f.fin = (b0 & 0x80) != 0;
    f.opcode = b0 & 0x0F;
    f.payload = (plen > 0) ? BytesToString(buf, off, uint(plen)) : "";
    f.consumed = int(off + uint(plen));
    if (masked) Log::Warn("received a masked frame (protocol violation); payload left raw");
    return f;
}
