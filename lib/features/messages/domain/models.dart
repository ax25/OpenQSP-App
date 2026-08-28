class InternetMessage {
  const InternetMessage({
    required this.id,
    required this.sender,
    required this.recipient,
    required this.text,
    required this.sentAt,
    this.canDelete = false,
  });

  final String id;
  final String sender;
  final String recipient;
  final String text;
  final DateTime sentAt;
  final bool canDelete;

  String remoteFor(String local) =>
      sender.toUpperCase() == local.toUpperCase() ? recipient : sender;
}

class Conversation {
  const Conversation({
    required this.remoteCallsign,
    this.latestMessage,
    this.unread = 0,
  });

  final String remoteCallsign;
  final InternetMessage? latestMessage;
  final int unread;
}

sealed class MessagingEvent {
  const MessagingEvent();
}

class MessageReceived extends MessagingEvent {
  const MessageReceived(this.message);
  final InternetMessage message;
}

class MessageDeleted extends MessagingEvent {
  const MessageDeleted(this.messageId);
  final String messageId;
}

enum MessagingConnectionState { disconnected, connecting, connected, reconnecting }
