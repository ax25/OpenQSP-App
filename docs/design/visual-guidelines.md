# OpenQSP Visual Guidelines

This document is the visual source of truth for the OpenQSP client application.

The goal is to keep the interface distinctive, practical, readable, and consistent across Flutter platforms while avoiding generic AI-generated visual patterns.

## 1. Visual personality

OpenQSP should feel:

- Reliable
- Practical
- Technical
- Calm
- Field-ready
- Clear
- Modern without looking futuristic

OpenQSP is a serious communications tool for amateur radio operators. It should feel purpose-built and trustworthy rather than decorative or experimental.

Avoid:

- Cyberpunk aesthetics
- Neon-heavy palettes
- Terminal or hacker styling
- Futuristic HUD elements
- Fake telemetry
- Decorative frequency displays
- Generic SaaS dashboard styling
- Common AI-generated developer-dashboard aesthetics

## 2. General style

Design the light theme first.

The interface should use:

- Warm neutral backgrounds
- Clean sans-serif typography
- Generous spacing
- Simple geometric controls
- Strong readability
- Minimal decoration
- Technical information only when it is useful

OpenQSP may include subtle references to amateur radio, but it must not imitate the physical appearance of a transceiver or terminal.

### Suggested base colors

These values are initial design references and may be tuned later while preserving the same visual character.

| Role | Suggested color |
| --- | --- |
| Main background | `#F5F4F0` |
| Surface / cards / inputs | `#FFFFFF` |
| Primary text | `#202326` |
| Secondary text | `#667078` |
| Brand primary | `#245E66` |
| Brand secondary | `#3D7F86` |

State colors should be restrained rather than highly saturated:

- Connected: green
- Warning: amber
- Error: muted red
- Offline / unavailable: gray

## 3. Typography

Use a clean sans-serif typeface for the main UI.

Preferred direction:

- Inter
- Roboto as an acceptable platform-friendly alternative

Do not use a monospaced font as the primary UI typeface.

Monospaced typography may be used sparingly for genuinely technical values such as:

- Callsigns
- Frequencies
- Message identifiers
- Protocol values

Even these values may remain in the main sans-serif font when that improves readability.

## 4. Components

### Buttons

Buttons should be comfortable to use on mobile and visually restrained.

Use:

- Clear hierarchy
- Moderate corner radius
- Solid fills
- No gradients
- No strong shadows

Suggested corner radius: approximately 8-12 px.

Avoid oversized pill-shaped controls unless a specific interaction requires them.

### Inputs

Inputs should use:

- White or surface-colored background
- Soft neutral border
- Clearly visible labels
- Brand-color focus state
- Comfortable touch height

### Cards and surfaces

Cards should be subtle.

Use:

- Small or medium corner radius
- Little or no shadow
- Clear spacing and hierarchy

Do not overuse cards when a simple list or section is sufficient.

## 5. Iconography

Use simple line icons with consistent visual weight.

Useful icon concepts include:

- Internet
- APRS
- Bluetooth / TNC
- Connected
- Offline
- Queued
- Sent
- Delivered
- Received
- Settings

Avoid decorative radio imagery that does not communicate actual state or function.

In particular, avoid:

- Large antenna graphics
- Decorative RF waves everywhere
- Fake spectrum displays
- Simulated LCD panels
- Radio controls used only as decoration

## 6. Login screen

The login screen should be extremely simple and confidence-inspiring.

Suggested content:

```text
OpenQSP
Messaging over Internet & Radio

Callsign
[ EA3GNU                    ]

Password
[ •••••••••••••             ]

[ Sign in ]

● Server available
```

The screen may include a small OpenQSP symbol or logo, but a final logo is not required for the first application milestones.

Do not add fake technical labels such as `SYS_IN`, `TERMINAL KEY`, or fabricated security/status text.

## 7. Conversation list

The conversation list should primarily feel like a modern messaging application, not a radio dashboard.

Example hierarchy:

```text
OpenQSP                         Settings

Messages

EA3ABC                         12:42
Llegamos al refugio en una hora
●

EA3XYZ                         Yesterday
Perfecto, recibido.

EA3GNU-5                       Tue
Prueba desde APRS
```

Transport information may be shown when useful using small icons or restrained badges such as:

- Internet
- APRS

Transport indicators must remain secondary to the conversation itself.

## 8. Conversation screen

The conversation screen should resemble a lightweight modern messaging tool, with less social decoration than consumer chat apps.

Example:

```text
← EA3ABC
  ● Online

       ¿A qué hora salís?

Sobre las 09:30.
Te aviso desde APRS si no tengo cobertura.

       Perfecto.

────────────────────────────
Message...                Send
```

Optional technical state may appear discretely where it provides useful information:

- Sent
- Delivered
- Queued
- APRS
- Internet

## 9. OpenQSP communication-status identity

A restrained communications-status treatment can become a recognizable OpenQSP visual element.

Examples:

```text
● Internet    ○ APRS
```

or:

```text
Internet   Connected
APRS       TNC not connected
```

This should communicate real application state and may appear in settings, status areas, or relevant workflows.

It should not resemble a terminal readout or futuristic HUD.

## 10. Technical information rule

Show technical information only when it helps the user understand or operate the system.

Good examples:

- APRS unavailable
- TNC disconnected
- Message queued
- Server unreachable
- Connected via Internet

Avoid fabricated or irrelevant technical decoration such as:

- `[SYS_IN]`
- `NODE_US_EAST`
- `SHA-256 LOCAL KEYING`
- `INITIALIZE CONNECTION`
- A frequency display when no frequency is relevant to that screen

## 11. Platform direction

Design Android first, while keeping layouts suitable for responsive Flutter implementations across:

- Android
- iOS
- Web
- Windows
- macOS
- Linux

Platform-specific interaction conventions should be respected where appropriate, but OpenQSP should retain one coherent visual identity.

## 12. Design and implementation workflow

This document should be treated as the visual source of truth by both design and implementation work.

Figma prompts and design work should follow these guidelines.

Flutter implementation should also follow this document rather than introducing a separate visual style.

When a design decision is intentionally changed, update this document so the repository remains the authoritative record of the application's visual direction.
