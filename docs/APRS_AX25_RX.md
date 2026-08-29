# AX.25 receive layer

The receive pipeline is `BluetoothTncService` → `KissTransport` → KISS data
frames (`port = 0`, `command = 0`) → `Ax25Decoder` → `Ax25Frame`. The decoder
only accepts an AX.25 byte sequence and has no dependency on Bluetooth, KISS,
Flutter UI, or APRS semantics.

Each seven-byte address is decoded by shifting its six callsign bytes right by
one, validating uppercase alphanumeric characters, and trimming trailing space
padding. The SSID is bits 1–4 of byte seven, H/repeated is bit 7, and extension
bit 0 marks the final address. At least destination and source are required;
up to ten total addresses are accepted to bound corrupt input.

## FCS decision

The existing KISS decoder removes only KISS framing/escaping and exposes the
data-command payload unchanged. Standard KISS puts the TNC on the HDLC side of
the link: HDLC flags and FCS are handled by the TNC and are not included in the
host data frame. Therefore `KissFrame.payload` is treated as AX.25 addresses,
control, PID, and information **without FCS**. No CRC bytes are removed or
calculated; all remaining bytes after the UI PID belong to `information`.

## Real-hardware RX check

Pair the TNC, open Settings → APRS → TNC KISS Bluetooth, and press **Probar
conexión**. Do not send a frame. With RF traffic present, verify that RX bytes,
RX KISS frames, and RX AX.25 frames increase. Compare source, destination,
digipeater path (an asterisk means H/repeated), control, PID, and INFO with a
known packet. A corrupt packet increments the decode-error counter while later
packets continue to be processed. Leaving Settings retains the existing
disconnect behavior.
