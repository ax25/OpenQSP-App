import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/messages/data/local_messages_store.dart';
import 'package:openqsp_app/features/messages/domain/message_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('messages and transport cursors survive store recreation', () async {
    final first = PreferencesLocalMessagesStore();
    final value = _message(
      id: _serverId('EA3GNU', 4),
      from: 'EA3ABC',
      to: 'EA3GNU',
      body: 'hola',
    );

    await first.upsert('EA3GNU', value);
    await first.setCursor('EA3GNU', 'internet', 'signed-cursor');
    await first.setCursor('EA3GNU', 'aprs', '4');

    final restored = PreferencesLocalMessagesStore();
    expect((await restored.messages('EA3GNU')).single.body, 'hola');
    expect(await restored.cursor('EA3GNU', 'internet'), 'signed-cursor');
    expect(await restored.cursor('EA3GNU', 'aprs'), '4');
  });

  test('canonical server message replaces provisional APRS send', () async {
    final store = PreferencesLocalMessagesStore();
    final createdAt = DateTime.utc(2026, 8, 29, 20, 10, 11);
    final provisional = InternetMessage(
      id: 'aprs-local-1',
      from: 'EA3GNU',
      to: 'EA3ABC',
      body: 'mensaje por radio',
      createdAt: createdAt,
    );
    final canonical = InternetMessage(
      id: _serverId('EA3ABC', 9),
      from: 'EA3GNU',
      to: 'EA3ABC',
      body: 'mensaje por radio',
      createdAt: createdAt,
      deliveryStatus: MessageDeliveryStatus.delivered,
      deliveredAt: createdAt.add(const Duration(seconds: 2)),
    );

    await store.upsert('EA3GNU', provisional);
    await store.upsert('EA3GNU', canonical);

    final messages = await store.messages('EA3GNU');
    expect(messages, hasLength(1));
    expect(messages.single.id, canonical.id);
    expect(messages.single.deliveryStatus, MessageDeliveryStatus.delivered);
  });

  test('APRS cursor is highest incoming sequence in local database', () async {
    final store = PreferencesLocalMessagesStore();
    await store.setCursor('EA3GNU', 'aprs', '5');

    await store.upsertAll('EA3GNU', [
      _message(
        id: _serverId('EA3GNU', 8),
        from: 'EA3ABC',
        to: 'EA3GNU',
        body: 'eight',
      ),
      _message(
        id: _serverId('EA3XYZ', 30),
        from: 'EA3GNU',
        to: 'EA3XYZ',
        body: 'outgoing',
      ),
    ]);

    expect(await store.cursor('EA3GNU', 'aprs'), '8');
  });

  test('APRS cursor does not require old sequences to be contiguous', () async {
    final store = PreferencesLocalMessagesStore();
    await store.upsertAll('EA3GNU', [
      _message(
        id: _serverId('EA3GNU', 55),
        from: 'EA3ABC',
        to: 'EA3GNU',
        body: '55',
      ),
      _message(
        id: _serverId('EA3GNU', 58),
        from: 'EA3ABC',
        to: 'EA3GNU',
        body: '58',
      ),
    ]);

    expect(await store.cursor('EA3GNU', 'aprs'), '58');
  });
}

InternetMessage _message({
  required String id,
  required String from,
  required String to,
  required String body,
}) => InternetMessage(
  id: id,
  from: from,
  to: to,
  body: body,
  createdAt: DateTime.utc(2026, 8, 29, 20),
);

String _serverId(String recipient, int sequence) =>
    base64Url.encode(utf8.encode('$recipient:$sequence')).replaceAll('=', '');
