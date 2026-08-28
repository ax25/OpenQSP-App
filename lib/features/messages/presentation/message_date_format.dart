String formatMessageTime(DateTime timestamp) {
  final local = timestamp.toLocal();
  return '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
}

String formatConversationTimestamp(DateTime timestamp, {DateTime? now}) {
  final local = timestamp.toLocal();
  final localNow = (now ?? DateTime.now()).toLocal();
  if (_isSameDay(local, localNow)) return formatMessageTime(local);
  if (_isSameDay(local, _previousLocalDay(localNow))) {
    return 'Ayer ${formatMessageTime(local)}';
  }
  return '${_twoDigits(local.day)}/${_twoDigits(local.month)} '
      '${formatMessageTime(local)}';
}

String formatMessageDateSeparator(DateTime timestamp, {DateTime? now}) {
  final local = timestamp.toLocal();
  final localNow = (now ?? DateTime.now()).toLocal();
  if (_isSameDay(local, localNow)) return 'Hoy';
  if (_isSameDay(local, _previousLocalDay(localNow))) {
    return 'Ayer';
  }
  return '${_twoDigits(local.day)}/${_twoDigits(local.month)}/${local.year}';
}

bool messagesAreOnSameLocalDay(DateTime first, DateTime second) =>
    _isSameDay(first.toLocal(), second.toLocal());

bool _isSameDay(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

DateTime _previousLocalDay(DateTime value) =>
    DateTime(value.year, value.month, value.day - 1);

String _twoDigits(int value) => value.toString().padLeft(2, '0');
