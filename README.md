# OpenQSP App

OpenQSP App is the Flutter client for OpenQSP.

The application is designed as a multiplatform client, with Internet messaging available across supported Flutter targets and APRS/KISS transport work focused on Android.

## Current status

- Flutter application structure and primary user interface are implemented.
- Callsign onboarding and local identity storage are implemented.
- Internet authentication is implemented.
- Internet conversations and messages are implemented.
- Realtime message updates use WebSocket rather than polling.
- Message delivery/read state is represented in the UI.
- Local message storage is implemented.
- APRS protocol support includes AX.25, KISS, APRS parsing/encoding and OpenQSP-over-APRS carriage.
- Android Bluetooth TNC configuration and KISS transport are implemented and under active integration/testing.
- APRS session lifecycle and server availability checks are implemented.
- Debug builds provide a concise TNC traffic monitor. Each useful packet is shown once as `direction origin -> destination | type | content`; transmitted packets are red, received packets addressed to the local APRS identity are green, and other received traffic is blue.

## Repository scope

This repository contains the OpenQSP client application only. The OpenQSP server is maintained separately in the `ax25/OpenQSP` repository.
