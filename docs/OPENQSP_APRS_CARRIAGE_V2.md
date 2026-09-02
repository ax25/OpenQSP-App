# OpenQSP APRS carriage V2 — client

The Flutter client uses the same compact APRS V2 wire profile as the OpenQSP server.

## DATA

Outbound Core frames are split into 50-byte chunks and sent as unnumbered APRS messages:

```text
Q2<BASE91>
```

The Base91 payload decodes to:

```text
transaction_id      u8
fragment_descriptor u8   # index:u4 | (total-1):u4
core_bytes          1..50 bytes
```

The Base91 alphabet is printable ASCII excluding `{`, `|`, and `~`. Q2 never carries a native APRS `{message-id}`, so APRS does not generate an ACK for every fragment.

Legacy Q1 Base64url frames remain parseable during migration, but `fragmentFrame()` emits Q2 by default.

## Reliability controls

```text
A2<BASE91(tx:u8)>
N2<BASE91(tx:u8 + missing_bitmap:u16)>
S2<BASE91(tx:u8)>
```

`A2` acknowledges receipt of a complete server-to-client transaction. `N2` asks the peer to retransmit only missing fragments. `S2` is the durable success result for a client `SEND_MESSAGE` and is translated inside the Bluetooth burst-repair shim into the existing Core `STORED` object for the rest of the app.

The receiver waits five seconds after the most recent non-final fragment before requesting repair. Once the final fragment has been observed, the repair grace is two seconds.

## Compatibility boundary

The app keeps Q1 parsing and Q1A/Q1N control parsing for migration. The active outbound client path emits Q2/A2/N2 and accepts S2.
