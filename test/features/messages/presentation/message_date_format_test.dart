import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/messages/presentation/message_date_format.dart';

void main() {
  test('conversation timestamp shows only the time for today', () {
    final now = DateTime(2026, 8, 29, 12);

    expect(
      formatConversationTimestamp(DateTime(2026, 8, 29, 0, 44), now: now),
      '00:44',
    );
  });

  test('conversation timestamp shows only Ayer for yesterday', () {
    final value = formatConversationTimestamp(
      DateTime(2026, 8, 28, 22, 17),
      now: DateTime(2026, 8, 29, 12),
    );

    expect(value, 'Ayer');
    expect(value, isNot(contains(':')));
  });

  test('conversation timestamp shows only DD/MM/YY for an older date', () {
    final value = formatConversationTimestamp(
      DateTime(2026, 8, 26, 22, 17),
      now: DateTime(2026, 8, 29, 12),
    );

    expect(value, '26/08/26');
    expect(value, isNot(contains(':')));
  });

  test('date separators format today, yesterday, and older dates', () {
    final now = DateTime(2026, 8, 29, 12);
    expect(formatMessageDateSeparator(now, now: now), 'Hoy');
    expect(
      formatMessageDateSeparator(DateTime(2026, 8, 28), now: now),
      'Ayer',
    );
    expect(
      formatMessageDateSeparator(DateTime(2026, 8, 20), now: now),
      '20/08/2026',
    );
  });
}
