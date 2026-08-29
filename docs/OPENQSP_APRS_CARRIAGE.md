# OpenQSP APRS carriage reference

This document mirrors the canonical APRS carriage behavior implemented by the OpenQSP server in:

- `server/src/openqsp/transport/aprs/carriage.py`
- `server/src/openqsp/transport/aprs/state.py`

The server implementation remains the reference implementation. Client and server changes to this profile must be cross-tested together.

## Purpose

The OpenQSP Core frame is transport-independent binary data. Over APRS messages, one complete Core frame is encoded as unpadded Base64url text and split into one or more APRS message fragments.

The carriage layer does not change the OpenQSP Core frame contents or application semantics.

## Constants

- Data chunk size: `48` Base64url characters per fragment.
- Maximum fragments per OpenQSP frame: `16`.
- Transaction ID width: `3` uppercase base36 characters.
- Fragment index width: `2` uppercase base36 characters.
- Fragment total width: `2` uppercase base36 characters.
- Base36 alphabet: `0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ`.

## Encoded Core frame text

A complete OpenQSP frame is encoded using URL-safe Base64 with trailing `=` padding removed.

Allowed encoded characters are:

```text
A-Z a-z 0-9 _ -
```

The encoded text must not be empty. A Base64url string whose length modulo 4 equals 1 is invalid.

After Base64url decoding, the resulting bytes must decode as one valid complete OpenQSP Core frame.

## Fragment format

Each fragment body uses this exact format:

```text
Q1:<transaction_id>:<index>/<total>:<data>
```

Example shape:

```text
Q1:0AZ:00/03:AbCdEf0123_-...
```

Where:

- `Q1` identifies this APRS carriage profile.
- `transaction_id` is exactly 3 uppercase base36 characters.
- `index` is exactly 2 uppercase base36 characters and is zero-based.
- `total` is exactly 2 uppercase base36 characters.
- `data` contains 1 to 48 Base64url characters.

The complete canonical fragment regex is conceptually:

```text
Q1:([0-9A-Z]{3}):([0-9A-Z]{2})/([0-9A-Z]{2}):([A-Za-z0-9_-]{1,48})
```

Validation rules:

- `1 <= total <= 16`.
- `index < total`.
- transaction ID, index and total must use uppercase base36 only.

## APRS message ID suffix

A fragment may carry an APRS message ID suffix:

```text
Q1:<transaction_id>:<index>/<total>:<data>{<message_id>
```

The APRS `message_id`:

- must contain 1 to 5 characters;
- must use uppercase base36 characters only (`0-9`, `A-Z`).

The APRS message ID is transport metadata. It is not part of the OpenQSP Core frame and is not a persistent OpenQSP message identifier.

## Fragmentation

To fragment a Core frame:

1. Validate that the input is one complete valid OpenQSP Core frame.
2. Encode the complete frame as unpadded Base64url.
3. Split the encoded text into consecutive chunks of at most 48 characters.
4. Reject the frame if more than 16 fragments would be required.
5. Emit fragments with indices `0 .. total-1`, all sharing the same transaction ID.

## Reassembly

Reassembly is keyed by:

```text
(peer, transaction_id)
```

Fragments may arrive out of order.

For one active assembly:

- every fragment must declare the same `total`;
- receiving the same index and identical data is allowed as a duplicate;
- receiving the same index with different data is a transaction conflict;
- receiving the same transaction ID with a different total is a transaction conflict.

Once all indices `0 .. total-1` are present, concatenate their `data` fields in index order and decode the result as unpadded Base64url. The decoded bytes must form one valid complete OpenQSP Core frame.

## Reassembly bounds used by the server

The canonical server `Reassembler` currently uses:

- TTL: `120` seconds;
- maximum active assemblies: `128`.

Expired assemblies are discarded. When the capacity limit is reached, the oldest active assembly is evicted.

These values are operational bounds of the current server implementation and may be represented as configurable defaults in the client rather than protocol constants if appropriate.

## Transaction conflicts

The server treats these as transaction conflicts:

- same `(peer, transaction_id)` but a different fragment count;
- duplicate fragment index containing different data.

A conflict invalidates and removes the affected partial assembly.

## Replay cache

The server also maintains a completed-request replay cache keyed by `(peer, transaction_id)` to support retries and duplicate request suppression.

Current server defaults are:

- TTL: `600` seconds;
- maximum entries: `256`;
- maximum entries per peer: `16`.

This replay cache is primarily server-side request-processing behavior. A client-side carriage implementation does not need to reproduce server replay semantics merely to encode, parse, fragment and reassemble frames.

## Separation of acknowledgements

Do not confuse:

```text
APRS ack<ID>
```

with:

```text
OpenQSP STORED
```

An APRS ACK confirms receipt at the APRS transport-message level. `STORED` is an OpenQSP Core application result confirming durable storage. Neither replaces the other.

## Client implementation boundary

The first client carriage implementation should remain transport-focused and independent from Bluetooth, KISS, AX.25 and UI code.

Target boundary:

```text
OpenQSP Core bytes
↕
OpenQSP APRS carriage
↕
fragment body strings
```

A later integration step will connect those fragment body strings to APRS message objects and then to AX.25/KISS transmission and reception.
