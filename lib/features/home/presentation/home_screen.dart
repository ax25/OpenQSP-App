import 'package:flutter/material.dart';

import '../../../app/theme/openqsp_theme.dart';

enum ServerConnectionState {
  available('Server available'),
  connected('Connected to server'),
  unavailable('Server unavailable');

  const ServerConnectionState(this.label);
  final String label;
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.callsign,
    required this.onEditCallsign,
    this.serverState = ServerConnectionState.available,
  });

  final String callsign;
  final VoidCallback onEditCallsign;
  final ServerConnectionState serverState;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewportConstraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 640,
                  minHeight: viewportConstraints.maxHeight - 64,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final title = Text(
                            'OpenQSP',
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          );
                          final headerActions = _HeaderActions(
                            callsign: callsign,
                            onEdit: onEditCallsign,
                            fillAvailableWidth: constraints.maxWidth < 480,
                          );

                          if (constraints.maxWidth < 480) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                title,
                                const SizedBox(height: 12),
                                headerActions,
                              ],
                            );
                          }

                          return Row(
                            children: [
                              title,
                              const Spacer(),
                              Flexible(child: headerActions),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 30),
                      Text(
                        'Services',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      const _CapabilityTile(
                        icon: Icons.mail_outline,
                        title: 'Messages',
                        subtitle: 'Private messages',
                      ),
                      const SizedBox(height: 12),
                      const _CapabilityTile(
                        icon: Icons.campaign_outlined,
                        title: 'Bulletins',
                        subtitle: 'Community bulletins',
                      ),
                      const Spacer(),
                      const SizedBox(height: 32),
                      Center(child: _Status(state: serverState)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderActions extends StatelessWidget {
  const _HeaderActions({
    required this.callsign,
    required this.onEdit,
    required this.fillAvailableWidth,
  });

  final String callsign;
  final VoidCallback onEdit;
  final bool fillAvailableWidth;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: fillAvailableWidth
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        _CallsignAction(
          callsign: callsign,
          onEdit: onEdit,
          fillAvailableWidth: fillAvailableWidth,
        ),
        const SizedBox(height: 2),
        const _TransportSelector(),
      ],
    );
  }
}

class _CallsignAction extends StatelessWidget {
  const _CallsignAction({
    required this.callsign,
    required this.onEdit,
    this.fillAvailableWidth = false,
  });

  final String callsign;
  final VoidCallback onEdit;
  final bool fillAvailableWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: fillAvailableWidth ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (fillAvailableWidth)
          Expanded(child: _CallsignText(callsign))
        else
          Flexible(child: _CallsignText(callsign)),
        IconButton(
          key: const Key('editCallsignButton'),
          tooltip: 'Change callsign',
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
        ),
      ],
    );
  }
}

class _CallsignText extends StatelessWidget {
  const _CallsignText(this.callsign);

  final String callsign;

  @override
  Widget build(BuildContext context) => Text(
    callsign,
    key: const Key('homeCallsign'),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: Theme.of(context).textTheme.titleMedium,
  );
}

class _TransportSelector extends StatelessWidget {
  const _TransportSelector();

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: const Key('transportSelector'),
      initialValue: 'Internet',
      padding: EdgeInsets.zero,
      tooltip: 'Select transport',
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'Internet', child: Text('Internet')),
        PopupMenuItem(enabled: false, child: Text('APRS')),
        PopupMenuItem(enabled: false, child: Text('Winlink')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Internet',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: OpenQspColors.secondaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: OpenQspColors.secondaryText,
            ),
          ],
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.state});
  final ServerConnectionState state;
  @override
  Widget build(BuildContext context) {
    final positive = state != ServerConnectionState.unavailable;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          positive ? Icons.circle : Icons.circle_outlined,
          size: 11,
          color: positive
              ? OpenQspColors.positive
              : OpenQspColors.secondaryText,
        ),
        const SizedBox(width: 9),
        Text(
          state.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: positive
                ? OpenQspColors.positive
                : OpenQspColors.secondaryText,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _CapabilityTile extends StatelessWidget {
  const _CapabilityTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Material(
    color: OpenQspColors.surface,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: OpenQspColors.border),
      borderRadius: BorderRadius.circular(10),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: OpenQspColors.brand),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: OpenQspColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    ),
  );
}
