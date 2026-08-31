# Pending tasks

This document tracks known pending work for the OpenQSP client. It is intentionally concise and focused on actionable follow-up items.

## Conversation UI

- [ ] **Send behavior / keyboard / scroll**
  - Sending a message must not hide the keyboard.
  - The keyboard must remain visible after tapping Send or submitting from the IME.
  - After the message is added to the conversation, the conversation must scroll far enough to show the **entire newest message bubble**, not merely move near the bottom.
  - This behavior must remain correct for long outgoing messages and when the keyboard changes the viewport height.

- [ ] **Persistently hide cleared messages**
  - `Vaciar mensajes` must hide the currently visible conversation history persistently for that client.
  - Hidden messages must remain in the local database and must not be deleted from the server.
  - Reopening/reloading the conversation must **not** make previously cleared messages visible again.
  - New messages received or sent after the clear point must be visible normally.
  - Prefer persisting a per-conversation visibility cutoff/high-water marker rather than modifying/deleting stored messages.

- [ ] **Move `Vaciar mensajes` into overflow menu**
  - Add a three-dot overflow button at the top-right of the conversation screen.
  - `Vaciar mensajes` must appear as an item in that dropdown menu rather than as a permanently visible action.

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
