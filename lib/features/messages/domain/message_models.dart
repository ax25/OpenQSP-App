enum MessageDirection { sent, received }

class InternetMessage {
  const InternetMessage({
    required this.id,
    required this.from,
    required this.to,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String from;
  final String to;
  final String body;
  final DateTime createdAt;

  String peerFor(String localCallsign) =>
      from.toUpperCase() == localCallsign.toUpperCase() ? to : from;

  MessageDirection directionFor(String localCallsign) =>
      from.toUpperCase() == localCallsign.toUpperCase()
      ? MessageDirection.sent
      : MessageDirection.received;

  factory InternetMessage.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final from = json['from'];
    final to = json['to'];
    final body = json['body'];
    final createdAt = json['created_at'];
    if (id is! String ||
        id.isEmpty ||
        from is! String ||
        to is! String ||
        body is! String ||
        createdAt is! String) {
      throw const FormatException('Invalid message payload');
    }
    return InternetMessage(
      id: id,
      from: from.toUpperCase(),
      to: to.toUpperCase(),
      body: body,
      createdAt: DateTime.parse(createdAt).toUtc(),
    );
  }
}

class ConversationSummary {
  const ConversationSummary({
    required this.remoteCallsign,
    required this.latestMessage,
    this.unreadCount = 0,
  });

  final String remoteCallsign;
  final InternetMessage latestMessage;
  final int unreadCount;

  ConversationSummary copyWith({
    InternetMessage? latestMessage,
    int? unreadCount,
  }) => ConversationSummary(
    remoteCallsign: remoteCallsign,
    latestMessage: latestMessage ?? this.latestMessage,
    unreadCount: unreadCount ?? this.unreadCount,
  );
}

class SyncBatch {
  const SyncBatch({required this.messages, required this.cursor});
  final List<InternetMessage> messages;
  final String cursor;
}

sealed class MessagingEvent {
  const MessagingEvent();
}

class MessageReceived extends MessagingEvent {
  const MessageReceived(this.message);
  final InternetMessage message;
}

enum RealtimeConnectionState {
  connecting,
  connected,
  reconnecting,
  disconnected,
  authenticationRequired,
}
