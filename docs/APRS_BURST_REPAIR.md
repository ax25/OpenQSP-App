# APRS symmetric burst repair

This client implements transaction-level reliability for OpenQSP Q1 bursts at the Bluetooth/KISS link boundary.

## Controls

- `Q1A:TTT` acknowledges one complete received Q1 transaction.
- `Q1N:TTT:MMMM` requests selective retransmission using a 16-bit hexadecimal missing-fragment mask; bit 0 represents fragment 0.

Example: `Q1N:0A7:8012` requests fragments 1, 4 and 15.

## Client -> server

Normal outgoing Q1 fragments are cached for the OpenQSP carriage TTL. The server does not need to ACK them individually. If the server sends `Q1N`, the link middleware retransmits only the cached fragments selected by the mask.

For `SEND_MESSAGE`, the existing `STORED` Core response remains the only positive durable completion signal seen by the messaging layer.

## Server -> client

Incoming server Q1 fragments are tracked by transaction. A complete burst generates one `Q1A`. An incomplete burst generates one `Q1N` after the repair delay and repeats the repair request until the missing fragments arrive or the state expires.

Completed transaction IDs are cached so a repeated server burst (for example because `Q1A` was lost) gets another `Q1A` without requiring another Core delivery.

`Q1A` and `Q1N` packets are consumed by the link middleware and are not passed to the existing OpenQSP Core decoder.

## Local tests

```bash
flutter analyze
flutter test test/features/aprs/data/burst_repair_bluetooth_tnc_service_test.dart
flutter test
```

Use this branch together with the companion OpenQSP server PR for RF/end-to-end tests.
