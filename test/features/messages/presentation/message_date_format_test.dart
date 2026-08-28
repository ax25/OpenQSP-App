import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/messages/presentation/message_date_format.dart';

void main() {
  test('conversation timestamp formats today, yesterday, and older dates', () {
    final now = DateTime(2026, 8, 29, 12);

    expect(
      formatConversationTimestamp(DateTime(2026, 8, 29, 22, 17), now: now),
      '22:17',
    );
    expect(
      formatConversationTimestamp(DateTime(2026, 8, 28, 22, 17), now: now),
      'Ayer 22:17',
    );
    expect(
      formatConversationTimestamp(DateTime(2026, 8, 20, 22, 17), now: now),
      '20/08 22:17',
    );
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
