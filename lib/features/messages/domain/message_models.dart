import 'dart:convert';

enum MessageDirection { sent, received }

enum MessageDeliveryStatus { processing, retry, stored, delivered, read }

/// OpenQSP v1 message body limit, measured on the wire as UTF-8 bytes.
const int maximumMessageLength = 208;

int messageBodyUtf8Length(String value) => utf8.encode(value).length;

bool messageBodyFitsProtocol(String value) =>
    messageBodyUtf8Length(value) <= maximumMessageLength;

class InternetMessage {
  const InternetMessage({
    required this.id,
    required this.from,
    required this.to,
    required this.body,
    required this.createdAt,
    this.deliveryStatus = MessageDeliveryStatus.stored,
    this.deliveredAt,
  });

  final String id;
  final String from;
  final String to;
  final String body;
  final DateTime createdAt;
  final MessageDeliveryStatus deliveryStatus;
  final DateTime? deliveredAt;

  String peerFor(String localCallsign) =>
      from.toUpperCase() == localCallsign.toUpperCase() ? to : from;

  MessageDirection directionFor(String localCallsign) =>
      from.toUpperCase() == localCallsign.toUpperCase()
      ? MessageDirection.sent
      : MessageDirection.received;

  InternetMessage copyWith({
    MessageDeliveryStatus? deliveryStatus,
    DateTime? deliveredAt,
  }) => InternetMessage(
    id: id,
    from: from,
    to: to,
    body: body,
    createdAt: createdAt,
    deliveryStatus: deliveryStatus ?? this.deliveryStatus,
    deliveredAt: deliveredAt ?? this.deliveredAt,
  );

  factory InternetMessage.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final from = json['from'];
    final to = json['to'];
    final body = json['body'];
    final createdAt = json['created_at'];
    final deliveryStatus = json['delivery_status'];
    final deliveredAt = json['delivered_at'];
    if (id is! String ||
        id.isEmpty ||
        from is! String ||
        to is! String ||
        body is! String ||
        createdAt is! String ||
        (deliveryStatus != null && deliveryStatus is! String) ||
        (deliveredAt != null && deliveredAt is! String)) {
      throw const FormatException('Invalid message payload');
    }
    return InternetMessage(
      id: id,
      from: from.toUpperCase(),
      to: to.toUpperCase(),
      body: body,
      createdAt: DateTime.parse(createdAt).toUtc(),
      deliveryStatus: _parseDeliveryStatus(deliveryStatus as String?),
      deliveredAt: deliveredAt == null
          ? null
          : DateTime.parse(deliveredAt as String).toUtc(),
    );
  }

  static MessageDeliveryStatus _parseDeliveryStatus(String? value) => switch (value) {
    'processing' => MessageDeliveryStatus.processing,
    'retry' => MessageDeliveryStatus.retry,
    null || 'stored' => MessageDeliveryStatus.stored,
    'delivered' => MessageDeliveryStatus.delivered,
    'read' => MessageDeliveryStatus.read,
    _ => throw const FormatException('Invalid message delivery status'),
  };
}

class ConversationSummary {
  const ConversationSummary({
    required this.remoteCallsign,
    required this.latestMessage,
    required this.lastActivityAt,
    this.unreadCount = 0,
  });

  final String remoteCallsign;
  final InternetMessage? latestMessage;
  final DateTime lastActivityAt;
  final int unreadCount;

  ConversationSummary copyWith({
    InternetMessage? latestMessage,
    DateTime? lastActivityAt,
    int? unreadCount,
    bool clearLatestMessage = false,
  }) => ConversationSummary(
    remoteCallsign: remoteCallsign,
    latestMessage: clearLatestMessage ? null : latestMessage ?? this.latestMessage,
    lastActivityAt: lastActivityAt ?? this.lastActivityAt,
    unreadCount: unreadCount ?? this.unreadCount,
  );
}

class SyncBatch {
  const SyncBatch({
    required this.messages,
    required this.cursor,
    this.hasMore = false,
  });

  final List<InternetMessage> messages;
  final String cursor;
  final bool hasMore;
}

sealed class MessagingEvent {
  const MessagingEvent();
}

class MessageReceived extends MessagingEvent {
  const MessageReceived(this.message, {this.syncCursor});

  final InternetMessage message;
  final String? syncCursor;
}

class MessageDelivered extends MessagingEvent {
  const MessageDelivered({required this.messageId, required this.deliveredAt});
  final String messageId;
  final DateTime deliveredAt;
}

class MessageRead extends MessagingEvent {
  const MessageRead({required this.peer, required this.lastReadMessageId});
  final String peer;
  final String lastReadMessageId;
}

class MessageSendStatusChanged extends MessagingEvent {
  const MessageSendStatusChanged({
    required this.messageId,
    required this.status,
  });

  final String messageId;
  final MessageDeliveryStatus status;
}

enum RealtimeConnectionState {
  connecting,
  connected,
  reconnecting,
  disconnected,
  authenticationRequired,
}
