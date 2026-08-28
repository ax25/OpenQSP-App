# OpenQSP Home Screen Specification

This document is the source of truth for the second OpenQSP application screen and its immediate navigation behavior.

## Purpose

After the user enters a callsign during onboarding, OpenQSP should persist that callsign locally and open the Home screen.

The Home screen is the application's main entry point. It shows the currently selected transport, the current Internet/server state, and the services available to the user.

This milestone only enables Internet mode. APRS and Winlink are visible but disabled.

## Callsign persistence

The callsign entered on the onboarding screen must be stored locally after the user presses `Continue`.

The callsign is not secret data and may be stored using normal local preferences.

On later application launches:

- if no callsign is stored, show the callsign onboarding screen;
- if a callsign is stored, open the Home screen directly.

The Home screen must show the current callsign and provide a way to return to the callsign onboarding screen to change it.

Changing the callsign must update the locally stored value.

## Home screen layout

The Home screen should follow `docs/design/visual-guidelines.md`.

The visual hierarchy should remain simple, practical, and restrained.

Suggested structure:

```text
OpenQSP                         EA3GNU / edit

Internet ▾

● Server available

Services

Messages                      >
Private messages

Bulletins                     >
Community bulletins
```

The exact spacing and responsive composition may vary between mobile and desktop, but the same information hierarchy must be preserved.

## Callsign display and editing

The user's callsign should be visible near the top of the Home screen.

The UI must provide a clear but unobtrusive way to change it, for example an edit icon or a small action associated with the callsign.

Selecting that action should return to the callsign onboarding screen with the current callsign pre-filled.

## Transport selector

The Home screen must expose the current transport through a compact selector or dropdown.

For this milestone the available entries are:

- Internet — enabled and selected by default;
- APRS — visible but disabled;
- Winlink — visible but disabled.

The disabled entries should remain visible so users understand that OpenQSP is designed for multiple transports.

Do not implement APRS, Bluetooth KISS TNC, or Winlink behavior in this milestone.

The selector should preferably display the active value directly, for example:

```text
Internet ▾
```

Avoid overly technical labels such as `Operation mode` unless needed for clarity.

## Server state terminology

OpenQSP must use these user-facing Internet/server states:

### Server available

Display:

```text
● Server available
```

Use this state when the OpenQSP server can be reached but the user does not yet have an active usable server session.

This is the expected initial Home screen state after entering the callsign if no saved valid Internet session exists.

### Connected to server

Display:

```text
● Connected to server
```

Use this state when a valid server session exists and the application can use server capabilities for the current user.

Do not use `Authenticated` as user-facing terminology.

### Server unavailable

The design should also be able to represent an unavailable server, for example:

```text
○ Server unavailable
```

The exact error/retry behavior may be implemented later.

## Authentication behavior

The Home screen itself must not require the user to enter a password before it can be shown.

The expected initial flow is:

```text
Callsign onboarding
        ↓
Home
        ↓
Server available
```

The password will be requested later, only when the user tries to use a server capability that requires an Internet session, such as Messages or Bulletins.

Once credentials/session data have been successfully established, the Home status should become:

```text
● Connected to server
```

Password/session persistence and secure storage will be specified in a later milestone.

Do not store passwords in normal preferences.

## Services / capabilities

For this milestone, show exactly these two service entries:

### Messages

Label:

```text
Messages
```

Suggested supporting text:

```text
Private messages
```

### Bulletins

Label:

```text
Bulletins
```

Suggested supporting text:

```text
Community bulletins
```

Do not invent additional services merely to fill the screen.

Messages and Bulletins should be designed as capability/service entries that can become interactive in later milestones.

The architecture should not assume that these will be the only OpenQSP capabilities forever.

Future capabilities may be server-driven or added progressively.

## Interaction scope for this milestone

This screen milestone should implement:

- persistence of the callsign;
- startup routing based on whether a callsign is stored;
- navigation from callsign onboarding to Home;
- ability to return to onboarding and change the callsign;
- Home screen visual layout;
- Internet/APRS/Winlink transport selector with only Internet enabled;
- initial server-state presentation;
- Messages and Bulletins service entries.

It does not need to implement yet:

- password entry;
- account authentication;
- secure credential storage;
- Messages screen;
- Bulletins screen;
- APRS transport;
- Bluetooth KISS TNC;
- Winlink transport;
- full server capability discovery;
- automatic transport selection.

## Responsive behavior

Follow the responsive principles already established for the callsign onboarding screen.

On mobile:

- use a comfortable single-column layout;
- preserve normal horizontal padding;
- make service entries easy to tap.

On desktop/web:

- do not simply stretch mobile controls to the full window width;
- constrain content to a comfortable maximum width where appropriate;
- do not emulate a phone frame;
- larger multi-pane desktop layouts may be introduced later for Messages and other features.

## Design source of truth

All implementation must also follow:

- `docs/design/visual-guidelines.md`

This document defines the functional and information hierarchy of the Home screen.

If a future visual mockup is added, the mockup should be treated as a visual reference while this document remains the source of truth for behavior and content.
