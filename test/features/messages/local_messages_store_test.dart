import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/messages/data/local_messages_store.dart';
import 'package:openqsp_app/features/messages/domain/message_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('APRS cursor uses the highest local mailbox sequence', () async {
    final store = PreferencesLocalMessagesStore();
    await store.upsertAll('EA3GNU', [
      _message(1),
      _message(2),
      _message(4),
    ]);

    expect(await store.cursor('EA3GNU', 'aprs'), '4');
    expect(await store.cursor('EA3GNU', 'internet'), isNull);
  });

  test('APRS cursor may skip historical gaps in the local mailbox', () async {
    final store = PreferencesLocalMessagesStore();
    await store.upsertAll('EA3GNU', [
      _message(2),
      _message(3),
    ]);

    expect(await store.cursor('EA3GNU', 'aprs'), '3');
  });

  test('APRS cursor ignores a stale lower persisted cursor', () async {
    final store = PreferencesLocalMessagesStore();
    await store.setCursor('EA3GNU', 'aprs', '5');
    await store.upsertAll(
      'EA3GNU',
      List.generate(10, (index) => _message(index + 1)),
    );

    expect(await store.cursor('EA3GNU', 'aprs'), '10');
  });

  test('APRS cursor uses latest local sequence despite historical gaps', () async {
    final store = PreferencesLocalMessagesStore();
    await store.setCursor('EA3GNU', 'aprs', '5');
    await store.upsertAll('EA3GNU', [
      ...List.generate(7, (index) => _message(index + 1)),
      _message(9),
      _message(10),
    ]);

    expect(await store.cursor('EA3GNU', 'aprs'), '10');
  });

  test('persisted APRS cursor cannot outrank the local database', () async {
    final store = PreferencesLocalMessagesStore();
    await store.setCursor('EA3GNU', 'aprs', '15');
    await store.upsertAll(
      'EA3GNU',
      List.generate(10, (index) => _message(index + 1)),
    );

    expect(await store.cursor('EA3GNU', 'aprs'), '10');
  });

  test('APRS cursor is null when the local database has no received messages', () async {
    final store = PreferencesLocalMessagesStore();

    await store.setCursor('EA3GNU', 'aprs', '15');
    await store.setCursor('EA3GNU', 'aprs', '12');

    expect(await store.cursor('EA3GNU', 'aprs'), isNull);
  });

  test('non-APRS cursor writes retain replacement semantics', () async {
    final store = PreferencesLocalMessagesStore();

    await store.setCursor('EA3GNU', 'internet', '15');
    await store.setCursor('EA3GNU', 'internet', '12');

    expect(await store.cursor('EA3GNU', 'internet'), '12');
  });
}

InternetMessage _message(int sequence) => InternetMessage(
  id: base64Url
      .encode(utf8.encode('EA3GNU:$sequence'))
      .replaceAll('=', ''),
  from: 'EA3ABC',
  to: 'EA3GNU',
  body: 'message $sequence',
  createdAt: DateTime.utc(2026, 1, sequence),
);
