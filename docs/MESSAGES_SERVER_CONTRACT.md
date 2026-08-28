# Internet messaging server contract status

The app repository documents the authentication endpoints (`POST
/api/v1/auth/login` and `GET /api/v1/me`) and the status endpoint (`GET
/api/v1/status`). It does **not** contain the OpenQSP server source, an OpenAPI
document, or a messaging/WebSocket protocol specification.

Consequently, this change intentionally does not define production messaging
URLs, JSON payloads, authentication handshakes, or event names. The Internet
messages feature is split behind injectable `MessagesRepository` and
`MessagesRealtimeClient` interfaces. Its screens and coordinating state can be
tested with deterministic transports, while the production defaults report the
missing contract instead of issuing incompatible requests.

To finish the production transport, the server project must publish at least:

- conversation-list, history, send, message-delete, and conversation-delete
  HTTP routes, including response schemas, authorization errors, size limits,
  and deletion permissions;
- the WebSocket URL and exact token authentication mechanism;
- event envelopes and server message identity fields for create/delete events;
- reconnect/resume semantics (cursor or authoritative reload behavior).

Once those facts are available, only concrete implementations of the two
transport interfaces should be needed; presentation code must remain unaware of
wire-level protocol details.
