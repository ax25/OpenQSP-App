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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        'OpenQSP',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Flexible(
                        child: Text(
                          callsign,
                          key: const Key('homeCallsign'),
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        key: const Key('editCallsignButton'),
                        tooltip: 'Change callsign',
                        onPressed: onEditCallsign,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 36),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: PopupMenuButton<String>(
                      key: const Key('transportSelector'),
                      initialValue: 'Internet',
                      tooltip: 'Select transport',
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'Internet', child: Text('Internet')),
                        PopupMenuItem(enabled: false, child: Text('APRS')),
                        PopupMenuItem(enabled: false, child: Text('Winlink')),
                      ],
                      child: const _TransportButton(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _Status(state: serverState),
                  const SizedBox(height: 42),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TransportButton extends StatelessWidget {
  const _TransportButton();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: OpenQspColors.surface,
      border: Border.all(color: OpenQspColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.public, size: 20, color: OpenQspColors.brand),
        SizedBox(width: 10),
        Text('Internet'),
        SizedBox(width: 16),
        Icon(Icons.arrow_drop_down),
      ],
    ),
  );
}

class _Status extends StatelessWidget {
  const _Status({required this.state});
  final ServerConnectionState state;
  @override
  Widget build(BuildContext context) {
    final positive = state != ServerConnectionState.unavailable;
    return Row(
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
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
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
    child: ListTile(
      onTap: () {},
      minTileHeight: 72,
      leading: Icon(icon, color: OpenQspColors.brand),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
    ),
  );
}
