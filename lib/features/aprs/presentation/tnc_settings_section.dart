import 'package:flutter/material.dart';

import '../../../core/openqsp_protocol/openqsp_models.dart';
import '../aprs/aprs_igate_registry.dart';
import '../application/tnc_settings_controller.dart';
import '../data/aprs_path_storage.dart';
import '../domain/aprs_path.dart';
import '../domain/tnc_connection_state.dart';
import '../domain/tnc_device.dart';

class TncSettingsSection extends StatefulWidget {
  const TncSettingsSection({
    super.key,
    required this.controller,
    this.aprsPathStorage,
  });

  final TncSettingsController controller;
  final AprsPathStorage? aprsPathStorage;

  @override
  State<TncSettingsSection> createState() => _TncSettingsSectionState();
}

class _TncSettingsSectionState extends State<TncSettingsSection> {
  TncSettingsController get controller => widget.controller;
  AprsIgateRegistry get digipeaterRegistry => AprsIgateRegistry.instance;
  late final AprsPathStorage _aprsPathStorage;
  AprsPathMode _aprsPathMode = AprsPathMode.oneHop;
  bool _aprsPathLoaded = false;

  @override
  void initState() {
    super.initState();
    _aprsPathStorage = widget.aprsPathStorage ?? PreferencesAprsPathStorage();
    controller.addListener(_refresh);
    digipeaterRegistry.addListener(_refresh);
    controller.initialize();
    digipeaterRegistry.load();
    _loadAprsPath();
  }

  Future<void> _loadAprsPath() async {
    final mode = await _aprsPathStorage.read();
    if (!mounted) return;
    setState(() {
      _aprsPathMode = mode;
      _aprsPathLoaded = true;
    });
  }

  Future<void> _setAprsPath(AprsPathMode mode) async {
    setState(() => _aprsPathMode = mode);
    await _aprsPathStorage.write(mode);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    digipeaterRegistry.removeListener(_refresh);
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
      child: SingleChildScrollView(
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
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(width: 105, child: Text('Path APRS:')),
                  Expanded(
                    child: DropdownButton<AprsPathMode>(
                      key: const Key('aprsPath'),
                      isExpanded: true,
                      isDense: true,
                      value: _aprsPathMode,
                      onChanged: !_aprsPathLoaded
                          ? null
                          : (value) {
                              if (value != null) _setAprsPath(value);
                            },
                      items: AprsPathMode.values
                          .map(
                            (mode) => DropdownMenuItem(
                              value: mode,
                              child: Text('${mode.label} (${mode.pathLabel})'),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(width: 105, child: Text('Forzar digi:')),
                  Expanded(
                    child: DropdownButton<String>(
                      key: const Key('forcedDigipeater'),
                      isExpanded: true,
                      isDense: true,
                      value: digipeaterRegistry.forcedIgate ?? '',
                      onChanged: (value) {
                        if (value == null) return;
                        digipeaterRegistry.setForced(value.isEmpty ? null : value);
                      },
                      items: [
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text('No'),
                        ),
                        for (final digipeater in digipeaterRegistry.knownIgates)
                          DropdownMenuItem<String>(
                            value: digipeater,
                            child: Text(digipeater),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const Key('clearDigipeatersButton'),
                  onPressed: digipeaterRegistry.hasClearableDigipeaters
                      ? digipeaterRegistry.clearDiscovered
                      : null,
                  icon: const Icon(Icons.clear_all),
                  label: const Text('Borrar lista'),
                ),
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
            ],
          ),
        ),
      ),
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
