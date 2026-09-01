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

- [ ] **Symmetric aggregate fragment ACK + selective repair in both directions**
  - Apply the same reliability mechanism to both **client → server** and **server → client** OpenQSP APRS transactions.
  - The receiver must track fragment reception per OpenQSP transaction independently of the RF/APRS path that delivered each copy.
  - In particular, a client may hear the same server burst through multiple IGates. It may receive one subset of fragments via one IGate and another subset via another IGate; all valid copies must be merged into the same reassembly state by transaction ID and fragment index.
  - Duplicate and out-of-order copies must be tolerated and must never cause already collected fragments to be discarded.
  - If the burst is incomplete after the normal receive window, the receiver sends one compact aggregate fragment-status frame (for example bitmap/ranges) describing which fragments were received or equivalently which are missing.
  - The original sender then retransmits **only the missing fragment indexes**, together as a repair burst. Already acknowledged/known-received fragments must not be sent again.
  - This process may repeat until the transaction is complete or the retry policy is exhausted.
  - If all fragments are received, no fragment-by-fragment ACK train is required. The receiver can answer with one transaction-level completion response such as `RECEIVED`, `STORED`, or another explicitly defined final status appropriate to the operation.
  - For operations with durable side effects (for example `SEND_MESSAGE` reaching the server), the final status must distinguish complete reassembly from durable processing/storage; `STORED`/commit should only be emitted after durable completion.
  - For server → client delivery, define the equivalent final semantic clearly: complete message reassembled and accepted/persisted locally should be confirmable with one compact transaction-level acknowledgement rather than N physical APRS ACKs.
  - Target server → client example with multiple IGates:
    - server sends fragments `1 2 3 4 5 6 7` as one burst;
    - client hears `1 2 4 5` via IGate A and `2 5 7` via IGate B;
    - client merges them and knows it has `1 2 4 5 7`;
    - client sends one aggregate status requesting/identifying missing `3 6`;
    - server retransmits only `3 6` as one repair burst;
    - client completes reassembly and sends one final `RECEIVED`/equivalent confirmation.
  - Target client → server behavior is the mirror image: aggregate reception status, selective repair burst, then one final durable `STORED`/commit when applicable.
  - This recovery must be automatic; losing one fragment must not leave either side hanging until a manual retry is offered.

- [ ] **Reduce ACK overhead after successful burst**
  - Real RF test: a 7-fragment `SEND_MESSAGE` burst was fully reassembled and stored by the server, but the return path still produced ACKs for every APRS fragment (`0N` through `0T`), many of them duplicated, before `STORED` arrived.
  - In the negotiated aggregate-ACK mode, when the complete burst is received and processed successfully, suppress the per-fragment success ACK train and answer with a single transaction-level completion response.
  - Preserve the aggregate recovery path for incomplete bursts so missing fragments can be identified and retransmitted selectively rather than retransmitting the whole transaction.
  - Goal: successful full bursts should ideally require one return RF packet instead of N fragment ACKs plus a final status.

- [ ] **Explicit durable transaction commit ACK**
  - Fragment receipt ACK and durable message commit are different facts and must not share the same semantic ACK.
  - Do not use the ACK of the highest-index fragment as proof that the full transaction was reconstructed/stored.
  - Add an explicit transaction-level commit response emitted only after full reassembly and durable server persistence.
  - Keep the experimental `APRS_COMMIT_ACK` capability disabled until this is unambiguous and tested under fragment loss/reordering.

- [ ] **RF loss / multi-path tests**
  - Test bursts with one or more middle fragments deliberately lost in both client → server and server → client directions.
  - Verify aggregate reception status identifies the correct missing fragments.
  - Verify only missing fragments are retransmitted in the repair burst.
  - Test out-of-order and duplicated fragments/ACK-status frames.
  - Test server → client reassembly where complementary subsets of one transaction arrive through different IGates.
  - Verify the final transaction status is not emitted before complete reassembly, and durable statuses such as `STORED` are not emitted before persistence.

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
