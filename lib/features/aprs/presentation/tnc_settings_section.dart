import 'package:flutter/material.dart';

import '../../../core/openqsp_protocol/openqsp_models.dart';
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

  String get _openQspStatus => switch (controller.openQspCheckState) {
    OpenQspCheckState.notChecked => 'No comprobado',
    OpenQspCheckState.waiting => 'Esperando respuesta…',
    OpenQspCheckState.available => 'Disponible',
    OpenQspCheckState.noResponse => 'Sin respuesta',
    OpenQspCheckState.error => 'Error',
  };

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final busy = state == TncConnectionState.loading ||
        state == TncConnectionState.connecting;
    final capabilities = controller.lastOpenQspObject;
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
            const SizedBox(height: 16),
            _ValueRow(label: 'Estado', value: state.label),
            const SizedBox(height: 8),
            _ValueRow(
              label: 'Dispositivo',
              value: controller.device?.name ?? 'Ninguno',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(width: 105, child: Text('SSID APRS:')),
                DropdownButton<int>(
                  key: const Key('aprsSsid'),
                  value: controller.aprsSsid,
                  onChanged: busy
                      ? null
                      : (value) {
                          if (value != null) controller.setAprsSsid(value);
                        },
                  items: [
                    for (var value = 0; value <= 15; value++)
                      DropdownMenuItem(value: value, child: Text('$value')),
                  ],
                ),
              ],
            ),
            if (controller.failure != null) ...[
              const SizedBox(height: 10),
              Text(
                controller.failure!.message,
                key: const Key('tncError'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 8,
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
                    icon: const Icon(Icons.cable),
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
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 10),
            Text('OpenQSP', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _ValueRow(label: 'Estado', value: _openQspStatus),
            if (capabilities is OpenQspCapabilities) ...[
              const SizedBox(height: 8),
              _ValueRow(
                label: 'Protocolo',
                value: '${capabilities.protocolVersion}',
              ),
              const SizedBox(height: 8),
              _ValueRow(
                label: 'Capabilities',
                value:
                    '0x${capabilities.capabilities.toRadixString(16).toUpperCase().padLeft(8, '0')}',
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const Key('checkOpenQspButton'),
              onPressed:
                  controller.kissReady &&
                      controller.openQspCheckState != OpenQspCheckState.waiting
                  ? controller.checkOpenQsp
                  : null,
              icon: const Icon(Icons.cell_tower),
              label: const Text('Comprobar OpenQSP'),
            ),
            const SizedBox(height: 16),
            const Divider(),
            ExpansionTile(
              key: const Key('tncDiagnostics'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text('Diagnóstico TNC/APRS'),
              subtitle: const Text('Contadores y últimas tramas recibidas'),
              children: [
                _DiagnosticsCounters(controller: controller),
                const SizedBox(height: 16),
                _ActivityLog(
                  title: 'Últimos KISS RX/TX',
                  entries: controller.kissActivity,
                ),
                const SizedBox(height: 12),
                _ActivityLog(
                  title: 'Últimos AX.25 RX',
                  entries: controller.ax25Activity,
                ),
                const SizedBox(height: 12),
                _ActivityLog(
                  title: 'Últimos APRS RX',
                  entries: controller.aprsActivity,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticsCounters extends StatelessWidget {
  const _DiagnosticsCounters({required this.controller});

  final TncSettingsController controller;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _DiagnosticCounter(label: 'Bluetooth RX bytes', value: controller.rxBytes),
      _DiagnosticCounter(label: 'KISS RX frames', value: controller.rxKissFrames),
      _DiagnosticCounter(label: 'KISS TX frames', value: controller.txKissFrames),
      _DiagnosticCounter(label: 'AX.25 RX frames', value: controller.rxAx25Frames),
      _DiagnosticCounter(
        label: 'AX.25 decode errors',
        value: controller.ax25DecodeErrors,
      ),
      _DiagnosticCounter(label: 'APRS RX packets', value: controller.rxAprsPackets),
      _DiagnosticCounter(
        label: 'APRS parse errors',
        value: controller.aprsParseErrors,
      ),
      _DiagnosticCounter(label: 'APRS messages', value: controller.aprsMessages),
      _DiagnosticCounter(label: 'APRS ACKs RX', value: controller.aprsAcks),
      _DiagnosticCounter(label: 'APRS rejects RX', value: controller.aprsRejects),
      _DiagnosticCounter(
        label: 'OpenQSP packets RX',
        value: controller.openQspRxPackets,
      ),
      _DiagnosticCounter(
        label: 'OpenQSP fragments RX',
        value: controller.openQspFragmentsRx,
      ),
      _DiagnosticCounter(
        label: 'OpenQSP complete frames',
        value: controller.openQspFramesRx,
      ),
      _DiagnosticCounter(
        label: 'OpenQSP decode errors',
        value: controller.openQspErrors,
      ),
      _DiagnosticTextValue(
        label: 'Último OpenQSP válido',
        value: controller.lastValidOpenQspRx?.toLocal().toIso8601String() ?? '-',
      ),
    ],
  );
}

class _DiagnosticCounter extends StatelessWidget {
  const _DiagnosticCounter({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => _DiagnosticTextValue(
    label: label,
    value: '$value',
  );
}

class _DiagnosticTextValue extends StatelessWidget {
  const _DiagnosticTextValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        SelectableText(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

class _ActivityLog extends StatelessWidget {
  const _ActivityLog({required this.title, required this.entries});

  final String title;
  final List<String> entries;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(minHeight: 52, maxHeight: 220),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: entries.isEmpty
              ? const Text('Sin actividad')
              : SingleChildScrollView(
                  child: SelectableText(
                    entries.join('\n\n'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(width: 105, child: Text('$label:')),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
}
