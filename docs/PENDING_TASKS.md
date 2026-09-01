# Pending tasks

This document tracks known pending work for the OpenQSP client. It is intentionally concise and focused on actionable follow-up items.

## Conversation UI

- [x] **Keyboard / bottom anchoring behavior**
  - Opening a conversation positions the message list at the absolute bottom.
  - If the user is already at the bottom when the composer/keyboard is opened, viewport resizing keeps the absolute bottom visible above the keyboard.
  - If the user is reading older messages away from the bottom, opening the keyboard does not force-scroll the conversation.
  - Sending keeps the composer focused and forces the newest sent message into view.
  - Covered by widget tests for initial bottom position and both keyboard-resize cases.

- [x] **Persistently hide cleared messages**
  - `Vaciar conversación` hides the currently visible conversation history persistently for that client.
  - Hidden messages remain in the local database and are not deleted from the server.
  - Reopening/reloading the conversation does not make previously cleared messages visible again.
  - New messages received or sent after the clear point are visible normally.
  - A per-conversation visibility cutoff is stored separately from message persistence.
  - The conversation remains in the conversation list even when it has no visible message preview.

- [x] **Move `Vaciar conversación` into overflow menu**
  - A three-dot overflow button appears at the top-right of the conversation screen.
  - `Vaciar conversación` is the only menu item for now.

## Authentication / session handling

- [ ] Validate on a real device that expired/invalid Internet sessions always follow the same UX:
  - HTTP 401/403 or WebSocket authentication failure invalidates the token.
  - Navigation returns to Home.
  - Password dialog opens automatically.
  - Network/5xx failures must not be misclassified as authentication failures.

## APRS transport reliability and efficiency

- [ ] **Complete client readiness for burst/out-of-order receive**
  - Merge/validate the change that ACKs valid duplicate/stale-looking fragments even when a later fragment was already seen.
  - Do not infer that an earlier fragment no longer needs an ACK merely because a later fragment arrived.

- [ ] **Server-to-client APRS burst**
  - Send all fragments of one OpenQSP transaction as a burst instead of strict stop-and-wait.
  - Keep different transactions to the same peer serialized initially to keep state simple.

- [ ] **Selective fragment retry**
  - Track ACK state independently per APRS fragment.
  - After timeout, retransmit only fragments that have not been ACKed.
  - Preserve duplicate tolerance and transaction idempotency.

- [ ] **Reduce ACK overhead after successful client→server burst**
  - Real RF test: a 7-fragment `SEND_MESSAGE` burst was fully reassembled and stored by the server, but the return path still produced ACKs for every APRS fragment (`0N` through `0T`), many of them duplicated, before `STORED` arrived.
  - Investigate a negotiated mode where, when the complete burst is received and durably processed, the server can suppress the per-fragment success ACK train and answer with a single transaction-level `STORED`/commit confirmation.
  - Preserve a recovery path for incomplete bursts: if one or more fragments are missing, the protocol still needs enough information to identify and retransmit only the missing fragments rather than retransmitting the whole transaction.
  - Do not collapse fragment ACK and durable commit semantics unless the replacement remains unambiguous under loss, duplication and out-of-order delivery.
  - Goal: successful full bursts should ideally require one return RF packet instead of N fragment ACKs plus `STORED`.

- [ ] **Explicit durable transaction commit ACK**
  - Fragment receipt ACK and durable message commit are different facts and must not share the same semantic ACK.
  - Do not use the ACK of the highest-index fragment as proof that the full transaction was reconstructed/stored.
  - Add an explicit transaction-level commit response emitted only after full reassembly and durable server persistence.
  - Keep the experimental `APRS_COMMIT_ACK` capability disabled until this is unambiguous and tested under fragment loss/reordering.

- [ ] **RF loss tests**
  - Test a burst where one or more middle fragments are deliberately lost.
  - Verify the server/client do not report `stored` before full reassembly and persistence.
  - Verify only missing fragments are retransmitted.
  - Test out-of-order and duplicated ACKs/fragments.

## Message synchronization

- [ ] **Derive APRS sync position from local message data**
  - Avoid treating a mutable persisted APRS cursor as the sole source of truth.
  - Derive the safe position from the mailbox sequences actually stored locally.
  - Use the highest **contiguous** sequence, not simply the largest sequence present.

- [ ] **Detect mailbox sequence gaps**
  - Example: if local DB has `1..14, 16, 17, 18`, sequence `15` is missing and the safe contiguous high-water remains `14`.
  - A later sequence must not cause a missing earlier message to be skipped permanently.

- [ ] **Add logical message repair operation**
  - Add a Core/OpenQSP operation such as `GET_MESSAGE sequence=X` (and possibly a future batched variant) to recover a missing logical mailbox message efficiently.
  - Keep this distinct from APRS fragment retransmission: a missing logical message and a missing RF fragment are separate layers/problems.

- [ ] **Revisit APRS cursor compatibility code**
  - The current monotonic APRS cursor guard prevents regressions and should remain safe until DB-derived synchronization replaces cursor authority.
  - Once the DB/gap model is implemented, simplify/remove redundant mutable cursor logic deliberately rather than implicitly.

## Protocol efficiency

- [ ] Revisit OpenQSP APRS wire efficiency after reliability semantics are stable:
  - compact binary core;
  - APRS-safe Base91 instead of Base64 where worthwhile;
  - smaller fragment headers;
  - compact transaction/correlation identifiers;
  - preserve UTF-8 payload support, replay/idempotency and backwards negotiation.
