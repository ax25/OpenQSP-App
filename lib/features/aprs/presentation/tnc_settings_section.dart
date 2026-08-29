import 'package:flutter/material.dart';

import '../application/tnc_settings_controller.dart';
import '../domain/tnc_connection_state.dart';
import '../domain/tnc_device.dart';

class TncSettingsSection extends StatefulWidget {
  const TncSettingsSection({super.key, required this.controller});
  final TncSettingsController controller;

  @override
  State<TncSettingsSection> createState() => _TncSettingsSectionState();
}

class _TncSettingsSectionState extends State<TncSettingsSection> {
  TncSettingsController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_refresh);
    controller.initialize();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    controller.disconnect();
    controller.dispose();
    super.dispose();
  }

  Future<void> _selectDevice() async {
    final devices = await controller.loadDevices();
    if (!mounted || devices == null) return;
    if (devices.isEmpty) {
      _message('No hay dispositivos Bluetooth emparejados');
      return;
    }
    final selected = await showDialog<TncDevice>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Seleccionar TNC emparejada'),
        children: devices
            .map(
              (device) => SimpleDialogOption(
                key: Key('tncDevice-${device.id}'),
                onPressed: () => Navigator.pop(context, device),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.bluetooth),
                  title: Text(device.name),
                  subtitle: Text(device.id),
                ),
              ),
            )
            .toList(),
      ),
    );
    if (selected != null) await controller.select(selected);
  }

  void _message(String value) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final busy = state == TncConnectionState.loading ||
        state == TncConnectionState.connecting;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TNC KISS Bluetooth',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 18),
            _ValueRow(label: 'Estado', value: state.label),
            const SizedBox(height: 10),
            _ValueRow(
              label: 'Dispositivo',
              value: controller.device?.name ?? 'Ninguno',
              detail: controller.device?.id,
            ),
            if (controller.failure != null) ...[
              const SizedBox(height: 14),
              Text(
                controller.failure!.message,
                key: const Key('tncError'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (state != TncConnectionState.connected)
                  OutlinedButton.icon(
                    key: const Key('selectTncButton'),
                    onPressed: busy ? null : _selectDevice,
                    icon: const Icon(Icons.bluetooth_searching),
                    label: const Text('Seleccionar TNC'),
                  ),
                if (controller.device != null &&
                    state != TncConnectionState.connected)
                  FilledButton.icon(
                    key: const Key('testTncButton'),
                    onPressed: busy ? null : controller.connect,
                    icon: state == TncConnectionState.connecting
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cable),
                    label: const Text('Probar conexión'),
                  ),
                if (state == TncConnectionState.connected)
                  FilledButton.tonalIcon(
                    key: const Key('disconnectTncButton'),
                    onPressed: controller.disconnect,
                    icon: const Icon(Icons.link_off),
                    label: const Text('Desconectar'),
                  ),
                if (controller.device != null)
                  TextButton.icon(
                    key: const Key('forgetTncButton'),
                    onPressed: busy ? null : controller.forget,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Olvidar TNC'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value, this.detail});
  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(width: 105, child: Text('$label:')),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (detail != null)
              Text(detail!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ],
  );
}
