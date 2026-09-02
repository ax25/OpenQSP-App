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
        if (state == AprsMessageReceiveState.hidden) {
          return const SizedBox.shrink();
        }

        final trackedPeer = session.messageReceivePeer;
        if (trackedPeer != null &&
            peer != null &&
            trackedPeer.toUpperCase() != peer!.toUpperCase()) {
          return const SizedBox.shrink();
        }

        final (icon, tooltip, color) = switch (state) {
          AprsMessageReceiveState.receiving => (
              Icons.mark_chat_unread_outlined,
              'Receiving APRS message…',
              Theme.of(context).colorScheme.primary,
            ),
          AprsMessageReceiveState.failed => (
              Icons.sms_failed_outlined,
              'APRS message reception stalled',
              Theme.of(context).colorScheme.error,
            ),
          AprsMessageReceiveState.completed => (
              Icons.mark_chat_read_outlined,
              'APRS message received',
              Colors.green,
            ),
          AprsMessageReceiveState.hidden => throw StateError('hidden handled above'),
        };

        return Tooltip(
          message: tooltip,
          child: Semantics(
            label: tooltip,
            child: Icon(icon, key: Key('aprsReceive-${state.name}'), size: size, color: color),
          ),
        );
      },
    );
  }
}
