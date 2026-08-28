enum MessageDirection { sent, received }

class InternetMessage {
  const InternetMessage({
    required this.id,
    required this.remoteCallsign,
    required this.text,
    required this.direction,
    this.sentAt,
    this.canDelete = false,
  });

  final String id;
  final String remoteCallsign;
  final String text;
  final MessageDirection direction;
  final DateTime? sentAt;
  final bool canDelete;
}

class ConversationSummary {
  const ConversationSummary({
    required this.remoteCallsign,
    this.latestMessage,
    this.latestActivity,
    this.unreadCount = 0,
  });

  final String remoteCallsign;
  final String? latestMessage;
  final DateTime? latestActivity;
  final int unreadCount;

  ConversationSummary copyWith({
    String? latestMessage,
    DateTime? latestActivity,
    int? unreadCount,
  }) => ConversationSummary(
    remoteCallsign: remoteCallsign,
    latestMessage: latestMessage ?? this.latestMessage,
    latestActivity: latestActivity ?? this.latestActivity,
    unreadCount: unreadCount ?? this.unreadCount,
  );
}

sealed class MessagingEvent {
  const MessagingEvent();
}

class MessageReceived extends MessagingEvent {
  const MessageReceived(this.message);
  final InternetMessage message;
}

class MessageRemoved extends MessagingEvent {
  const MessageRemoved(this.remoteCallsign, this.messageId);
  final String remoteCallsign;
  final String messageId;
}

class ConversationRemoved extends MessagingEvent {
  const ConversationRemoved(this.remoteCallsign);
  final String remoteCallsign;
}

enum RealtimeConnectionState { connecting, connected, reconnecting, disconnected }
