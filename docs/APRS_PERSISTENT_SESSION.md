# Persistent APRS session

APRS transport activation is application-scoped rather than Settings-scoped.

## Lifecycle

- Settings observes the shared TNC controller and never owns/disposes it.
- Selecting APRS in Home activates the shared APRS session.
- Activation restores the persisted TNC, connects Bluetooth/KISS when available,
  and sends the OpenQSP `GET_CAPABILITIES` probe.
- The TNC remains connected when navigating into or out of Settings.
- Selecting Internet deactivates APRS and disconnects the TNC.
- The Home footer reports APRS availability from a real OpenQSP response rather
  than from Bluetooth connection state alone.

## Scope

This change does not route Messages or Bulletins over APRS yet. While APRS is
selected, Home does not silently fall back to Internet for Messages. Message
routing will be implemented after transport preference is added deliberately.
