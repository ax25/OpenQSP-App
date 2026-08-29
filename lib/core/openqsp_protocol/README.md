# OpenQSP Core codec

This transport-independent Dart layer maps complete OpenQSP Core frames to
protocol objects and back. It deliberately contains no APRS, AX.25, Bluetooth,
Internet, or UI integration.

The normative definition is [`docs/OPENQSP_PROTOCOL.md`](../../../docs/OPENQSP_PROTOCOL.md),
and the Python server codec is the reference implementation. Protocol changes
must update and cross-test the server and client together.
