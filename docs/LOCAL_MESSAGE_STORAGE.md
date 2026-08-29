# Local message storage and incremental synchronization

Messages are local-first. The conversation UI reads persistent client state; Internet and APRS are synchronization mechanisms, not separate histories.

## Persistent state

The client stores, per local callsign:

- canonical message data and delivery state;
- provisional `aprs-local-*` sent messages until a canonical server message is later observed;
- an opaque Internet `/sync` cursor;
- a numeric APRS recipient-mailbox cursor.

The current implementation uses the already-supported `shared_preferences` backend behind `LocalMessagesStore`. The interface intentionally permits replacing the backend with a database later without changing the controller or transports.

## Startup

1. Read and display local messages immediately.
2. Connect the selected transport.
3. If this installation has no local history/cursor, bootstrap available historical data once.
4. Synchronize only changes after that transport's persisted cursor.
5. Persist every synchronized, sent, received, delivered, or read update before relying on it for future sessions.

Internet uses `/api/v1/sync`. APRS uses Core `GET_NEW_MESSAGES` in pages of 20 until `END.has_more` is false.

## Switching transports

Both transports merge into the same local history. Server message IDs are identical whether a `MESSAGE` arrives over Internet or APRS, so normal duplicates collapse by ID.

For incoming messages the canonical ID also contains the recipient mailbox sequence. When an incoming canonical message is stored after Internet synchronization, the local store advances the APRS cursor to that sequence. Therefore switching Internet -> APRS does not require replaying already cached incoming mailbox history.

The reverse direction cannot infer the opaque signed Internet `/sync` cursor from APRS data. When Internet is used after APRS-only activity, `/sync` resumes from its last Internet cursor and may return records already present locally; they are deduplicated while the Internet cursor catches up.

## APRS sent-message limitation

The current Core `GET_NEW_MESSAGES` operation returns the recipient mailbox. It cannot reconstruct messages historically sent by this callsign on a fresh installation. Messages sent through APRS are persisted locally immediately after `STORED`, and later canonical Internet records replace matching provisional records.

A future Core operation would be required to reconstruct historical sent messages over APRS on a device that has lost or never had its local cache.
