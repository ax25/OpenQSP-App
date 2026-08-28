# Internet messaging server contract gap

The repository contains no OpenQSP server source, OpenAPI document, WebSocket
schema, or authentication contract. Its Git configuration also has no remote
from which a related server repository can be identified. Consequently this
client does **not** guess any HTTP path, request/response payload, WebSocket URL,
authentication header/query/subprotocol, event name, size limit, cursor, or
delete authorization rule.

The feature is split into injectable `AuthClient`, `MessagesApi`, and
`MessagesSocket` boundaries. Models, state reconciliation, server-ID
deduplication, secure callsign-scoped token storage, and the complete UI are
implemented and can be connected once the canonical contract is supplied.

To enable production networking, the server project must publish at least:

* authentication login and token-validation operations;
* conversation list, history, send, message deletion, and conversation deletion
  HTTP operations, including schemas and authorization rules;
* the WebSocket URL and exact token transport;
* event envelopes for new/deleted/updated messages and authentication failure;
* message identity, timestamp, size-limit, reconnect/cursor semantics.

`UndocumentedMessagesApi` intentionally fails without issuing a request. The
production composition root leaves messaging disabled with an explanatory
dialog, rather than silently speaking a fictitious protocol.
