# OpenQSP Internet Messages server contract

Internet Messages uses bearer authentication for HTTP. Messages are listed
with `GET /api/v1/messages` (`limit`, `cursor`, and optional `with`), created
with `POST /api/v1/messages` plus an `Idempotency-Key`, and reconciled with
`GET /api/v1/sync` plus its optional cursor.

Live events use `/api/v1/ws`. The Flutter client uses the documented
cross-platform query-token form (`?token=<access token>`) because browser
WebSockets cannot consistently set an `Authorization` header. The only current
messaging event is `message.created`; close code `4401` means authentication is
invalid and reconnect must stop.

The server has no message or conversation deletion endpoints and emits no
delete, update, read, or conversation events. Unread counts are therefore local
presentation state for the current app session only.
