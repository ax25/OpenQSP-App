# OpenQSP-App

> Multiplatform Flutter client for OpenQSP.

OpenQSP-App is the user-facing client for the OpenQSP messaging network. It is designed around the same callsign identity and local message history regardless of whether the active transport is Internet or amateur-radio APRS.

The application is developed separately from the OpenQSP server repository and currently targets Flutter-supported platforms, with Android providing the radio/TNC integration layer.

---

## Current status

The first usable OpenQSP client is implemented and under active development.

Currently implemented:

- Flutter application architecture for Android, Windows and Web, with shared messaging UI and domain logic;
- callsign/password authentication against the OpenQSP Internet API;
- HTTPS REST API integration;
- persistent WebSocket connection for realtime events;
- automatic reauthentication flow when an Internet session expires;
- conversation list with unread indicators;
- private message conversations with realtime send/receive;
- outgoing message lifecycle display:
  - grey tick = stored by the server;
  - green tick = delivered to the recipient transport;
  - blue tick = read by the recipient;
- persistent local message history independent of transport;
- incremental synchronization instead of reloading complete conversations;
- independent Internet and APRS synchronization cursors;
- automatic conversation scrolling and composer focus behaviour;
- Android Bluetooth Classic/SPP TNC configuration and persistent device selection;
- bidirectional KISS byte transport over Bluetooth;
- AX.25 UI frame encoding and decoding;
- APRS message parsing and encoding;
- OpenQSP Core v0.1 binary codec implemented in Dart;
- OpenQSP-over-APRS Q1 Base64url carriage, fragmentation and reassembly;
- persistent APRS application session outside the Settings screen;
- OpenQSP server capability discovery over APRS;
- private message sending and receiving over APRS;
- incremental `GET_NEW_MESSAGES` synchronization over APRS;
- progressive APRS cursor persistence so interrupted downloads resume after the last safely stored message;
- APRS ACK handling, retries, delayed-response handling and visible connection-health state;
- persistent outgoing APRS states (`processing`, `retry`, `stored`) with manual retry support;
- RF/IGate diagnostics including the most recent IGate seen on OpenQSP traffic.

The application has been exercised with the production OpenQSP server over both Internet and real APRS/IGate paths.

---

## Transport model

The user selects the active transport from the application.

### Internet

Internet mode uses the server HTTPS API and WebSocket endpoint.

It provides:

- authenticated access using callsign and password;
- conversation and message synchronization;
- realtime incoming messages;
- delivery/read updates;
- unread conversation state;
- automatic WebSocket reconnection for ordinary network failures;
- explicit reauthentication when the server rejects an expired or invalid session.

### APRS

On Android, APRS mode uses a paired Bluetooth Classic/SPP KISS TNC.

The active pipeline is:

```text
OpenQSP application objects
        |
OpenQSP Core v0.1 codec
        |
Q1 APRS carriage
        |
APRS message
        |
AX.25 UI frame
        |
KISS
        |
Bluetooth RFCOMM/SPP
        |
TNC / RF
```

Selecting APRS restores the configured TNC, opens the Bluetooth/KISS session and probes the OpenQSP server with `GET_CAPABILITIES`.

The session remains alive while navigating through the application. Switching back to Internet explicitly closes the APRS/TNC session.

The app distinguishes normal, slow and non-responding APRS server states. Late valid OpenQSP responses are still accepted, since radio delivery may take considerably longer than an Internet request.

---

## Messaging architecture

Message history belongs to the client rather than to a particular transport.

```text
UI / MessagesController
        |
LocalMessagesStore
        |
  +-----+-----+
  |           |
Internet     APRS
/sync        GET_NEW_MESSAGES
```

Messages, delivery state and synchronization cursors are stored locally. Opening a conversation therefore does not require downloading its complete history again.

Internet uses the server synchronization API with an opaque cursor. APRS uses the numeric mailbox sequence exposed by OpenQSP Core and advances its cursor only after each complete message has been persisted locally.

This allows the application to move between Internet and APRS while preserving one coherent local conversation history and avoiding unnecessary retransmission over RF.

---

## APRS sending behaviour

An outgoing radio message is shown immediately in the conversation while it is being transmitted.

OpenQSP fragments are sent as APRS messages with APRS `{NN}` message identifiers. Incoming `ackNN` packets confirm the individual APRS transmission attempt, while the OpenQSP `STORED` response confirms that the server has durably accepted the application message.

If confirmation is delayed or temporarily lost, the local message is retained and becomes retryable instead of disappearing or being permanently failed. Late ACKs and late valid OpenQSP responses can still advance the existing message state.

Current protocol limitation: `STORED` does not carry a Core request-correlation token. Consequently, unresolved APRS sends are serialized and `STORED` is associated with the oldest unresolved transmitted send. Exact APRS ACK correlation is still provided by the APRS message ID.

---

## Android Bluetooth TNC

Settings → APRS → TNC KISS Bluetooth allows the user to select a previously paired Bluetooth Classic/SPP TNC and persist that choice.

Device discovery is deliberately outside the app: pair the TNC first in Android settings.

On Android 12 and newer the app requests `BLUETOOTH_CONNECT`. On Android 11 and older it uses the legacy `BLUETOOTH` and `BLUETOOTH_ADMIN` permissions. It does not request `BLUETOOTH_SCAN` or location because it does not perform Bluetooth discovery.

The Android transport is implemented through a small Flutter platform-channel adapter over Android's public Bluetooth APIs rather than an external Classic Bluetooth Flutter package.

---

## Server configuration

The Internet API is configured through the `.env` asset. Copy `.env.example` to `.env` for local development and set:

```text
OPENQSP_SERVER_HOST
OPENQSP_SERVER_PORT
OPENQSP_SERVER_SSL
```

Do not put passwords or access tokens in a bundled environment file.

Android debug builds may allow cleartext HTTP for local development. Release builds retain Android's normal network security policy. Flutter Web deployments require the OpenQSP server to allow the web application's origin through CORS.

The public OpenQSP deployment currently exposes the server through HTTPS/WSS; the application does not use the old native OpenQSP TCP transport.

---

## Platform scope

### Android

Current primary platform and the only platform with APRS/TNC support.

Supported today:

- Internet messaging;
- WebSocket realtime events;
- local persistent history;
- Bluetooth Classic/SPP KISS TNC;
- AX.25/APRS/OpenQSP radio transport.

### Windows and Web

The shared Flutter application and Internet messaging architecture are intended to run on these platforms.

Radio transport is currently Android-only because the Bluetooth TNC integration is implemented with the Android platform API.

---

## Capabilities and current limitations

### Private messages

Implemented over both Internet and APRS.

### Bulletins

The OpenQSP Core/server protocol includes bulletin support, but the current Flutter user experience is still focused primarily on private messaging and APRS messaging integration.

### Read state over APRS

Read receipts are not transmitted over APRS in the current Core protocol. Internet read state is synchronized with the server; APRS-only operation treats opening a conversation as a local UI action.

### Fresh-install APRS history

`GET_NEW_MESSAGES` reconstructs the received mailbox incrementally over APRS. A fresh installation with no local cache cannot reconstruct historical messages previously sent by the user solely from the current APRS operation set.

### Winlink

Winlink is not currently an active client transport.

---

## Protocol interoperability

The Dart OpenQSP Core codec and APRS carriage were built to be byte-compatible with the canonical Python implementation in the OpenQSP server repository.

Tests include cross-language protocol/carriage fixtures covering:

- Core frame encoding and decoding;
- Base36 transaction IDs;
- Base64url frame text;
- Q1 fragmentation and reassembly;
- malformed frame handling;
- KISS framing;
- AX.25 encode/decode;
- APRS message parsing and encoding;
- synchronization and transport lifecycle behaviour.

---

## Development checks

Typical local validation:

```console
flutter analyze
flutter test
flutter build apk --debug
```

For protocol-heavy changes, formatting the Dart source and tests before validation is also recommended:

```console
dart format lib test
```

---

## Project direction

The current development focus is to harden the real-world radio experience while keeping the application transport-independent at the UI and local-storage layers.

Near-term work includes refining APRS reliability and synchronization, completing additional user-facing Core capabilities such as bulletins, and extending usable transports without duplicating application semantics in each transport implementation.
