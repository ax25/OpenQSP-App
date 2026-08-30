import 'package:flutter/foundation.dart';

import '../application/messages_controller.dart';

final pendingMessageComposer = PendingMessageComposer();

final class PendingMessageComposer extends ChangeNotifier {
  final Map<String, _PendingComposerEntry> _entries = {};

  String _key(MessagesController controller, String remoteCallsign) =>
      '${controller.callsign.trim().toUpperCase()}|${remoteCallsign.trim().toUpperCase()}';

  String textFor(MessagesController controller, String remoteCallsign) =>
      _entries[_key(controller, remoteCallsign)]?.text ?? '';

  bool isSending(MessagesController controller, String remoteCallsign) =>
      _entries[_key(controller, remoteCallsign)]?.sending ?? false;

  Future<void> send({
    required MessagesController controller,
    required String remoteCallsign,
    required String text,
  }) async {
    final key = _key(controller, remoteCallsign);
    final existing = _entries[key];
    if (existing?.sending ?? false) return;

    _entries[key] = _PendingComposerEntry(text: text, sending: true);
    notifyListeners();
    try {
      await controller.send(remoteCallsign, text);
      _entries.remove(key);
      notifyListeners();
    } on Object {
      _entries[key] = _PendingComposerEntry(text: text, sending: false);
      notifyListeners();
      rethrow;
    }
  }

  void clear(MessagesController controller, String remoteCallsign) {
    if (_entries.remove(_key(controller, remoteCallsign)) != null) {
      notifyListeners();
    }
  }
}

final class _PendingComposerEntry {
  const _PendingComposerEntry({required this.text, required this.sending});

  final String text;
  final bool sending;
}
