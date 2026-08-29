import 'package:flutter/material.dart';

import '../application/tnc_settings_controller.dart';
import '../ax25/ax25_decoder.dart';
import '../kiss/kiss_encoder.dart';

class AprsConsole extends StatefulWidget {
  const AprsConsole({super.key, required this.controller});

  final TncSettingsController controller;

  @override
  State<AprsConsole> createState() => _AprsConsoleState();
}

class _AprsConsoleState extends State<AprsConsole> {
  final Set<String> _seenRx = <String>{};
  final Set<String> _seenTx = <String>{};
  final List<String> _entries = <String>[];

  TncSettingsController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onChanged);
    _capture();
  }

  @override
  void didUpdateWidget(covariant AprsConsole oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == controller) return;
    oldWidget.controller.removeListener(_onChanged);
    _seenRx.clear();
    _seenTx.clear();
    _entries.clear();
    controller.addListener(_onChanged);
    _capture();
  }

  @override
  void dispose() {
    controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final changed = _capture();
    if (changed && mounted) setState(() {});
  }

  bool _capture() {
    var changed = false;
    final local = controller.aprsSsid == 0
        ? controller.sourceCallsign
        : '${controller.sourceCallsign}-${controller.aprsSsid}';

    for (final entry in controller.aprsActivity.reversed) {
      if (local == null || !entry.contains('→ $local')) continue;
      if (_seenRx.add(entry)) {
        _entries.insert(0, 'RX  $entry');
        changed = true;
      }
    }

    for (final raw in controller.kissActivity.reversed) {
      if (!raw.startsWith('TX  ')) continue;
      final decoded = _decodeTx(raw.substring(4));
      if (decoded == null) continue;
      if (_seenTx.add(decoded)) {
        _entries.insert(0, 'TX  $decoded');
        changed = true;
      }
    }

    if (_entries.length > 80) {
      _entries.removeRange(80, _entries.length);
    }
    return changed;
  }

  String? _decodeTx(String hex) {
    try {
      final encoded = hex
          .trim()
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .map((part) => int.parse(part, radix: 16))
          .toList();
      if (encoded.length < 3 || encoded.first != kissFend || encoded.last != kissFend) {
        return null;
      }
      final unescaped = <int>[];
      for (var i = 1; i < encoded.length - 1; i++) {
        final byte = encoded[i];
        if (byte == kissFesc && i + 1 < encoded.length - 1) {
          final escaped = encoded[++i];
          unescaped.add(escaped == kissTfend ? kissFend : escaped == kissTfesc ? kissFesc : escaped);
        } else {
          unescaped.add(byte);
        }
      }
      if (unescaped.length < 2 || (unescaped.first & 0x0f) != 0) return null;
      final frame = const Ax25Decoder().decode(unescaped.sublist(1));
      final call = controller.sourceCallsign;
      if (call == null || frame.source.callsign != call) return null;
      return '${frame.source} → ${frame.destination}\n${frame.informationText}';
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('APRS console', style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                Text('RX unique: ${_seenRx.length}   TX unique: ${_seenTx.length}'),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: _entries.isEmpty
                  ? const Align(
                      alignment: Alignment.topLeft,
                      child: Text('No OpenQSP APRS traffic yet'),
                    )
                  : ListView.builder(
                      reverse: false,
                      itemCount: _entries.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: SelectableText(
                          _entries[index],
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
