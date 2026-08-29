import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/messages/data/local_messages_store.dart';
import 'package:openqsp_app/features/messages/domain/message_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('APRS cursor recovers only the contiguous local mailbox prefix', () async {
    final store = PreferencesLocalMessagesStore();
    await store.upsertAll('EA3GNU', [
      _message(1),
      _message(2),
      _message(4),
    ]);

    expect(await store.cursor('EA3GNU', 'aprs'), '2');
    expect(await store.cursor('EA3GNU', 'internet'), isNull);
  });

  test('APRS cursor does not skip a missing first mailbox message', () async {
    final store = PreferencesLocalMessagesStore();
    await store.upsertAll('EA3GNU', [
      _message(2),
      _message(3),
    ]);

    expect(await store.cursor('EA3GNU', 'aprs'), isNull);
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
