# OpenQSP server contract for Internet Messages

This document is a client-facing summary of the current server implementation in `ax25/OpenQSP`, extracted from `server/src/openqsp/api/app.py` on `main`.

It exists so client work in `OpenQSP-App` does not need direct access to the private server repository and must not invent HTTP or WebSocket behavior.

## Base rules

All authenticated HTTP endpoints use:

```http
Authorization: Bearer <access_token>
```

Access tokens are obtained from `POST /api/v1/auth/login` and validated with `GET /api/v1/me`.

The server normalizes callsigns internally. The client should still normalize user-entered callsigns before sending requests.

## Authentication

### POST `/api/v1/auth/login`

Request:

```json
{
  "callsign": "EA3GNU",
  "password": "..."
}
```

Success response:

```json
{
  "access_token": "...",
  "token_type": "bearer",
  "user": {
    "callsign": "EA3GNU"
  }
}
```

Invalid credentials return HTTP `401` with error code `invalid_credentials`.

### GET `/api/v1/me`

Requires bearer auth.

Response:

```json
{
  "callsign": "EA3GNU"
}
```

Invalid/expired tokens return HTTP `401` with error code `invalid_token`.

## Server status

### GET `/api/v1/status`

Response:

```json
{
  "status": "ok"
}
```

## Message object

The API exposes messages as:

```json
{
  "id": "<opaque server message id>",
  "from": "EA3GNU",
  "to": "EA3ABC",
  "body": "Hello",
  "created_at": "2026-08-28T18:30:00Z"
}
```

Important client rules:

- Treat `id` as an opaque server identifier.
- Use `id` for HTTP/WebSocket deduplication.
- Do not derive or manufacture message ids in the client.
- `created_at` is UTC ISO-8601 with `Z`.

## Send message

### POST `/api/v1/messages`

Requires bearer auth.

Also requires an `Idempotency-Key` HTTP header. It is mandatory and must contain between 1 and 128 characters.

Example:

```http
POST /api/v1/messages
Authorization: Bearer <token>
Idempotency-Key: <client-generated unique key>
Content-Type: application/json
```

Request body:

```json
{
  "to": "EA3ABC",
  "body": "Hello"
}
```

Success: HTTP `201`.

```json
{
  "message": {
    "id": "...",
    "from": "EA3GNU",
    "to": "EA3ABC",
    "body": "Hello",
    "created_at": "2026-08-28T18:30:00Z"
  }
}
```

The server uses the idempotency key together with a hash of `to` and `body`.

If the same key is reused for a different request, the server returns HTTP `409` with error code `conflict`.

The client should generate one idempotency key per logical send attempt and reuse that same key only when retrying that same request after an uncertain network outcome.

Validation errors return HTTP `422`. An over-limit body is reported with error code `message_too_long`.

Do not hardcode a body-length limit in the client unless it is explicitly synchronized with the server protocol. The server remains authoritative.

## List messages

### GET `/api/v1/messages`

Requires bearer auth.

Query parameters:

- `limit`: optional, default `50`, minimum `1`, maximum `200`.
- `cursor`: optional opaque pagination cursor returned by the server.
- `with`: optional callsign. When present, returns only messages involving that peer.

Examples:

```http
GET /api/v1/messages?limit=50
```

```http
GET /api/v1/messages?with=EA3ABC&limit=200
```

Response:

```json
{
  "messages": [
    {
      "id": "...",
      "from": "EA3GNU",
      "to": "EA3ABC",
      "body": "Hello",
      "created_at": "2026-08-28T18:30:00Z"
    }
  ],
  "next_cursor": "<opaque cursor or null>"
}
```

### Conversation model in the app

The server does not expose a separate `conversation` resource.

The Flutter client should build the conversation list by grouping messages by the other participant's callsign:

- if `from == localCallsign`, peer = `to`;
- otherwise, peer = `from`.

Conversation previews/order/unread are therefore client-side presentation state built from authoritative message data and realtime events.

For opening one conversation, use `GET /api/v1/messages?with=<CALLSIGN>` and follow `next_cursor` if more history is needed.

## Get one message

### GET `/api/v1/messages/{message_id}`

Requires bearer auth.

Returns:

```json
{
  "message": {
    "id": "...",
    "from": "EA3GNU",
    "to": "EA3ABC",
    "body": "Hello",
    "created_at": "2026-08-28T18:30:00Z"
  }
}
```

A message is visible only to its sender or recipient. Missing/inaccessible messages return HTTP `404` with error code `not_found`.

## Incremental sync

### GET `/api/v1/sync`

Requires bearer auth.

Optional query parameter:

- `cursor`: opaque sync cursor previously returned by this endpoint.

Initial sync:

```http
GET /api/v1/sync
```

Incremental sync:

```http
GET /api/v1/sync?cursor=<cursor>
```

Response:

```json
{
  "messages": [
    {
      "id": "...",
      "from": "EA3GNU",
      "to": "EA3ABC",
      "body": "Hello",
      "created_at": "2026-08-28T18:30:00Z"
    }
  ],
  "cursor": "<new opaque sync cursor>"
}
```

The client should persist/use the returned sync cursor for authoritative reconciliation after reconnects when appropriate.

Do not attempt to decode or construct cursors client-side.

## WebSocket realtime

### Endpoint

```text
/api/v1/ws
```

Use `ws://` or `wss://` according to the configured server scheme.

### Authentication

The server accepts the access token in either of these forms:

1. Query parameter:

```text
/api/v1/ws?token=<access_token>
```

2. HTTP header during WebSocket upgrade:

```http
Authorization: Bearer <access_token>
```

For Flutter portability, the client may use the query-token form if adding upgrade headers is awkward on a target platform.

An invalid/expired token causes the server to close the socket with WebSocket close code `4401`.

### Server events

The current server emits one realtime event type when a message is created:

```json
{
  "type": "message.created",
  "data": {
    "id": "...",
    "from": "EA3GNU",
    "to": "EA3ABC",
    "body": "Hello",
    "created_at": "2026-08-28T18:30:00Z"
  }
}
```

The event is sent to both sender and recipient when they have an active socket.

This means a send may be observed twice by the client path:

- once in the HTTP `POST /api/v1/messages` response;
- once as a WebSocket `message.created` event.

The client must deduplicate using the server `id`.

### Client-to-server WebSocket traffic

The current server does not define application commands over WebSocket. After connecting, it simply keeps reading text frames while the server pushes events.

Do not send message commands over WebSocket. Sending remains HTTP.

A client may keep the socket open without implementing a custom application-level command protocol.

## Reconnect and reconciliation

Recommended client behavior based on the current server contract:

1. Establish the authenticated WebSocket after entering Messages.
2. On `message.created`, merge by server `id`.
3. On disconnect, reconnect with bounded exponential backoff.
4. If close code `4401` is received, stop reconnecting and return to the authentication-required flow.
5. After reconnect, reconcile potentially missed events with `GET /api/v1/sync?cursor=<last_sync_cursor>`.
6. Merge sync results by server `id` and store the newly returned cursor.

No periodic polling is required for normal realtime delivery.

## Error envelope

Server API errors use:

```json
{
  "error": {
    "code": "...",
    "message": "...",
    "details": {
      "field": "..."
    }
  }
}
```

`details` is optional.

Relevant current codes include:

- `invalid_credentials`
- `invalid_token`
- `validation_error`
- `message_too_long`
- `conflict`
- `not_found`
- `invalid_request`
- `internal_error`

## Important current server gaps

The current Internet API does **not** expose:

- an HTTP endpoint to delete an individual message;
- an HTTP endpoint to delete a conversation;
- WebSocket message-deleted events;
- WebSocket conversation-created/deleted events;
- a first-class conversation resource.

Therefore the Flutter client must **not invent** delete endpoints or delete WebSocket events.

For the current implementation:

- sending, listing, history, realtime receive and reconnect/sync can be fully implemented now;
- conversation grouping is client-side;
- individual message deletion and conversation deletion must remain disabled/unavailable in production until the server contract adds those operations.

If delete controls are kept in UI scaffolding, they must clearly be disabled or hidden when using the real production transport, rather than issuing fictional requests.

## Source of truth

Canonical implementation inspected:

```text
ax25/OpenQSP
server/src/openqsp/api/app.py
```

If this document and the server implementation ever disagree, the server implementation is authoritative and this document should be updated.
