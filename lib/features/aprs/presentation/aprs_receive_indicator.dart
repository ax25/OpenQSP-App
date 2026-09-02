import 'package:flutter/material.dart';

import '../application/aprs_session_controller.dart';

class AprsReceiveIndicator extends StatelessWidget {
  const AprsReceiveIndicator({
    super.key,
    required this.session,
    this.peer,
    this.size = 22,
  });

  final AprsSessionController session;
  final String? peer;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        final state = session.messageReceiveState;
        if (!session.showMessageReceiveIndicator) {
          return const SizedBox.shrink();
        }

        final trackedPeer = session.messageReceivePeer;
        if (trackedPeer != null &&
            peer != null &&
            trackedPeer.toUpperCase() != peer!.toUpperCase()) {
          return const SizedBox.shrink();
        }

        final tooltip = switch (state) {
          AprsMessageReceiveState.receiving => 'Receiving APRS message…',
          AprsMessageReceiveState.failed => 'APRS message reception stalled',
          AprsMessageReceiveState.completed => 'APRS message received',
          AprsMessageReceiveState.hidden => throw StateError('hidden handled above'),
        };
        final color = switch (state) {
          AprsMessageReceiveState.receiving => Theme.of(context).colorScheme.primary,
          AprsMessageReceiveState.failed => Theme.of(context).colorScheme.error,
          AprsMessageReceiveState.completed => Colors.green,
          AprsMessageReceiveState.hidden => throw StateError('hidden handled above'),
        };

        final icon = switch (state) {
          AprsMessageReceiveState.receiving => _ReceivingMessageIcon(
              key: const Key('aprsReceive-receiving'),
              size: size,
              color: color,
            ),
          AprsMessageReceiveState.failed => Icon(
              Icons.sms_failed_outlined,
              key: const Key('aprsReceive-failed'),
              size: size,
              color: color,
            ),
          AprsMessageReceiveState.completed => Icon(
              Icons.mark_chat_read_outlined,
              key: const Key('aprsReceive-completed'),
              size: size,
              color: color,
            ),
          AprsMessageReceiveState.hidden => throw StateError('hidden handled above'),
        };

        return Tooltip(
          message: tooltip,
          child: Semantics(label: tooltip, child: icon),
        );
      },
    );
  }
}

class _ReceivingMessageIcon extends StatelessWidget {
  const _ReceivingMessageIcon({
    super.key,
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: size, color: color),
          Padding(
            padding: EdgeInsets.only(bottom: size * 0.10),
            child: Icon(
              Icons.arrow_downward_rounded,
              size: size * 0.52,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
