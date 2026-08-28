# Task: Internet Messages UI and real-time messaging

## Goal

Implement the first complete Internet-mode Messages experience in the OpenQSP Flutter app.

The feature must allow an authenticated user to browse conversations, open a conversation with another callsign, exchange and delete messages, delete whole conversations, create new conversations, and receive updates in real time without manually refreshing or polling the server.

This task builds on the authentication flow introduced for the Messages entry point. Authentication must remain callsign-scoped and token-based.

## Scope

This task covers **Internet mode only**.

APRS/KISS messaging is out of scope for this implementation and must not be mixed into the Internet transport code.

Internet-mode messaging uses both:

- the existing HTTP API for request/response operations and initial state loading;
- WebSocket for authenticated real-time events and live updates.

The UI must not poll the server periodically for new messages.

---

## 1. Entering Messages and authentication

When the user taps **Messages** from Home:

1. Check the authentication state for the current callsign.
2. If a valid stored authentication token exists, do **not** ask for the password again.
3. If the user is not authenticated, ask for the password and authenticate against the OpenQSP server.
4. On successful authentication, persist the token using the existing secure token storage mechanism.
5. After authentication, open the Messages conversation-list screen.
6. Authentication/network/server errors must be presented clearly and must not leave the UI in a false authenticated state.

Do not create a second independent authentication implementation. Reuse and extend the existing `AuthSession`, `AuthClient`, and secure token store introduced by the authentication work.

Changing the configured callsign must continue to isolate authentication state by callsign.

---

## 2. Conversation list screen

Replace the current Messages placeholder with a real conversation-list screen.

The screen represents the user's currently existing private-message conversations.

Each conversation row should at minimum show:

- remote callsign;
- latest message preview when available;
- latest activity time/date when available;
- unread/new-message indication when applicable.

A conversation is conceptually grouped by the other participant's callsign. The UI should not expose server-internal identifiers as the primary identity of a conversation.

### Behaviour

- Tapping a conversation opens the conversation screen for that callsign.
- Incoming messages must update the conversation list immediately.
- A new incoming conversation must appear automatically without refresh.
- The latest-message preview/order/unread state must update when messages arrive or are changed.
- The screen must support a manual retry if initial loading fails, but normal operation must not require manual refresh.

---

## 3. Create a new conversation

Provide an action from the conversation-list screen to start a new private conversation.

The user must be able to enter/select a destination callsign.

Requirements:

- normalize callsigns consistently with the rest of the application;
- reject an empty or obviously invalid destination before sending a request;
- prevent creating a conversation with the user's own callsign;
- if a conversation with that callsign already exists, open the existing conversation instead of creating a duplicate UI conversation;
- if the server creates conversations implicitly when the first message is sent, the client should model that cleanly rather than inventing unnecessary server-side state.

Creating a conversation may initially open an empty conversation screen before the first message is sent.

---

## 4. Conversation screen

Opening a callsign from the conversation list must navigate to a dedicated conversation screen.

The screen should show:

- remote callsign prominently;
- chronological message history;
- clear visual distinction between sent and received messages;
- message timestamp/status information supported by the server;
- text composer;
- send action;
- conversation-level delete action.

The message history should be loaded using the HTTP API when the conversation is opened.

Once opened, new WebSocket events for that conversation must be reflected immediately in the visible message list.

The UI should remain responsive while network requests are in progress and should prevent accidental duplicate sends.

---

## 5. Send messages

The authenticated user must be able to send a private message to the remote callsign from the conversation screen.

Use the canonical Internet API endpoint defined by the OpenQSP server for message creation.

Requirements:

- send using the current authenticated session;
- validate empty input locally;
- respect server/protocol message-size limits;
- disable or otherwise protect against duplicate submission while the same send is pending;
- surface send failures clearly;
- reconcile the UI with the authoritative server response/event so the same message is not displayed twice when the HTTP response and WebSocket event both represent the same message.

Do not create client-only message IDs that conflict with server identity semantics.

---

## 6. Delete individual messages

Allow the user to delete a message when the server API authorizes that operation.

The UI must:

- expose deletion in an appropriate message action/menu;
- require a reasonable confirmation where destructive behaviour could be surprising;
- call the corresponding authenticated API endpoint;
- remove/update the message only after successful server confirmation, or restore/reconcile it if optimistic UI is used and the operation fails;
- also react correctly if deletion is announced through WebSocket.

The client must follow server authorization rules rather than assuming every visible message is deletable.

---

## 7. Delete an entire conversation

Allow the user to remove the complete conversation with a callsign when supported by the server API.

Expected UX:

1. user chooses **Delete conversation**;
2. show an explicit destructive confirmation;
3. perform the authenticated server operation;
4. return to the conversation list;
5. remove/update the conversation in the list;
6. keep state consistent with subsequent WebSocket events.

If the server semantics are actually "delete all messages with this callsign" rather than a first-class conversation resource, the client should reflect the server's real model and still present the user-facing concept as deleting the conversation.

---

## 8. WebSocket real-time connection

Real-time updates are a core requirement of this task.

After the user has authenticated for Internet messaging, establish an authenticated WebSocket connection using the protocol/endpoints exposed by the OpenQSP server.

The WebSocket layer must be separate from presentation widgets.

It should provide an application-facing stream of normalized messaging events such as, as supported by the server:

- new message;
- message updated/status changed;
- message deleted;
- conversation created/changed/removed;
- connection/authentication errors.

### Required behaviour

- Messages arriving through the WebSocket appear without user refresh.
- The conversation list updates in real time.
- An open conversation updates in real time.
- Events for other conversations must still update their list/unread state.
- Avoid duplicate messages if an HTTP operation and a WebSocket event describe the same server message.
- Disconnect/clean up the socket when the authenticated session is no longer usable or the owning application service is disposed.
- Do not open one WebSocket per conversation; use one authenticated messaging connection/session unless the server protocol explicitly requires otherwise.

### Connection loss

Handle temporary WebSocket loss gracefully.

The implementation should:

- expose connection state to the application;
- reconnect with sensible bounded/backoff behaviour rather than a tight loop;
- re-authenticate/reconnect using the current valid token as appropriate;
- after reconnecting, reconcile missed state using the server API/cursor/since mechanism if the server supports one;
- otherwise reload the minimum necessary authoritative state so messages received during the disconnect are not silently lost from the UI.

WebSocket reconnect is not a substitute for authentication validity. If the server rejects the token, transition back to the unauthenticated flow instead of reconnecting forever.

---

## 9. API and transport architecture

Keep transport/data logic outside widgets.

A reasonable feature shape is:

```text
lib/features/messages/
  application/
  data/
  domain/        # optional if useful
  presentation/
```

The exact filenames are not prescribed, but the implementation should have clear responsibilities equivalent to:

- HTTP Messages API client/repository;
- WebSocket messaging client/service;
- conversation/message models;
- session/controller/state that merges initial API state and live WebSocket events;
- conversation list UI;
- conversation detail UI.

Reuse the existing Internet server configuration rather than introducing a second hard-coded base URL.

Reuse the existing authentication token/session rather than storing credentials in the Messages feature.

Passwords must never be stored by the Messages feature.

---

## 10. HTTP API vs WebSocket responsibilities

Use the transports deliberately:

### HTTP API

Use HTTP for operations such as:

- initial conversation list;
- initial message history;
- send message, according to the server's canonical API;
- delete message;
- delete conversation/messages;
- recovery/reconciliation after reconnect where needed.

### WebSocket

Use WebSocket primarily for:

- unsolicited incoming messages;
- changes that originate elsewhere;
- immediate live synchronization of the UI;
- server-pushed message/conversation events.

Do **not** implement periodic HTTP polling for new messages while a functioning WebSocket mechanism exists.

If the actual OpenQSP server contract differs from an assumption in this document, inspect the server API/protocol and implement against the canonical server behaviour rather than inventing a client-only API.

---

## 11. State and consistency requirements

The implementation must maintain a single coherent local view of server messaging state.

Important cases to handle:

- the same new message appears in HTTP response and WebSocket event;
- a message arrives while the conversation list is visible;
- a message arrives while its conversation is open;
- a message arrives for a different callsign while another conversation is open;
- a conversation receives its first message;
- the active callsign changes;
- the authentication token expires or becomes invalid;
- WebSocket disconnects and later reconnects;
- delete/send request succeeds but its corresponding WebSocket event arrives before or after the HTTP response.

Server message identity must be used for deduplication whenever available.

---

## 12. Loading, empty and error states

Provide explicit UI states for:

- loading conversations;
- no conversations yet;
- loading message history;
- empty new conversation;
- server/API failure;
- authentication failure/expiry;
- WebSocket disconnected/reconnecting when relevant to the user;
- send/delete failure.

The application must not crash or become permanently stuck after a failed request.

---

## 13. Tests

Add tests for the new behaviour.

At minimum cover:

### Authentication gate

- valid stored token opens Messages without prompting for password;
- no token prompts for password;
- invalid/expired token falls back to password authentication;
- successful login opens Messages;
- authentication failure does not open Messages.

### Conversation list

- API conversations render correctly;
- empty state renders correctly;
- tapping a callsign opens the correct conversation;
- a WebSocket new-message event updates/creates the corresponding conversation and unread/latest state.

### Conversation

- history loads and renders in order;
- sending calls the correct authenticated client operation;
- duplicate HTTP/WebSocket representation of the same server message is shown only once;
- incoming WebSocket message appears immediately;
- individual deletion updates state correctly;
- deleting a conversation returns to/updates the list;
- error states are recoverable.

### WebSocket/session

- authenticated connection setup;
- event parsing;
- connection loss/reconnect behaviour;
- invalid authentication stops reconnect looping and returns the session to an authentication-required state;
- disposal closes subscriptions/resources.

Use fake/mock transports for deterministic tests rather than requiring a live OpenQSP server for the normal unit/widget test suite.

---

## 14. Acceptance criteria

The task is complete when all of the following are true:

- [ ] Tapping Messages prompts for a password only when the current callsign is not already authenticated.
- [ ] A valid stored token opens Messages without another password prompt.
- [ ] The placeholder Messages page has been replaced with a real conversation list.
- [ ] Existing conversations are loaded from the server and grouped/presented by remote callsign.
- [ ] A conversation can be opened and its message history viewed.
- [ ] A new conversation can be started with another callsign.
- [ ] A user can send a message from the conversation screen.
- [ ] A supported individual message can be deleted.
- [ ] An entire conversation can be deleted according to server semantics.
- [ ] Incoming messages appear in real time through WebSocket without refresh or polling.
- [ ] Conversation previews/order/unread indicators update from real-time events.
- [ ] HTTP responses and WebSocket events are deduplicated correctly.
- [ ] WebSocket connection loss is handled without a tight reconnect loop and state is reconciled after reconnect.
- [ ] Expired/invalid authentication returns to an authentication-required state.
- [ ] Internet messaging uses the existing server configuration and authentication infrastructure.
- [ ] No APRS/KISS-specific behaviour is introduced into this Internet-mode implementation.
- [ ] `dart format --set-exit-if-changed lib test` passes.
- [ ] `flutter analyze` passes.
- [ ] `flutter test` passes.

---

## Out of scope

Do not implement as part of this task:

- APRS/KISS transport for Messages;
- Bluetooth/TNC integration;
- group chats;
- attachments/media;
- typing indicators;
- voice/audio messaging;
- delivery mechanisms not already supported by the OpenQSP server;
- redesign of server protocol semantics purely to simplify the Flutter client.

If a required server endpoint or WebSocket event is missing, document the concrete server-side gap instead of silently inventing incompatible client behaviour.
