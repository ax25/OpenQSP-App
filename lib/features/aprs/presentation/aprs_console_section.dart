import 'package:flutter/material.dart';

import '../application/tnc_settings_controller.dart';

class AprsConsoleSection extends StatefulWidget {
  const AprsConsoleSection({super.key, required this.controller});

  final TncSettingsController controller;

  @override
  State<AprsConsoleSection> createState() => _AprsConsoleSectionState();
}

class _AprsConsoleSectionState extends State<AprsConsoleSection> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant AprsConsoleSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_changed);
    widget.controller.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    final shouldFollow = !_scrollController.hasClients ||
        _scrollController.position.maxScrollExtent -
                _scrollController.position.pixels <=
            48;
    setState(() {});
    if (shouldFollow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.controller.aprsConsoleEntries;
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Tráfico recibido y transmitido por la TNC KISS.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            TextButton.icon(
              key: const Key('clearAprsConsole'),
              onPressed: entries.isEmpty ? null : widget.controller.clearAprsConsole,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Limpiar'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          key: const Key('aprsConsole'),
          height: 420,
          decoration: BoxDecoration(
            color: colors.surfaceContainerLowest,
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: entries.isEmpty
              ? const Center(child: Text('Sin tráfico APRS todavía'))
              : Scrollbar(
                  controller: _scrollController,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          _format(entry),
                          key: Key('aprsConsoleEntry-$index'),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontFamilyFallback: const ['Courier'],
                            fontSize: 11,
                            height: 1.25,
                            color: _entryColor(context, entry.direction),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  static Color _entryColor(
    BuildContext context,
    AprsConsoleDirection direction,
  ) => switch (direction) {
    AprsConsoleDirection.tx => Colors.red.shade700,
    AprsConsoleDirection.rx => Colors.green.shade700,
    AprsConsoleDirection.other => Colors.blue.shade700,
  };

  static String _format(AprsConsoleEntry entry) {
    String two(int value) => value.toString().padLeft(2, '0');
    final time = entry.timestamp;
    final millis = time.millisecond.toString().padLeft(3, '0');
    final timestamp =
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.$millis';
    final direction = switch (entry.direction) {
      AprsConsoleDirection.tx => 'TX',
      AprsConsoleDirection.rx => 'RX',
      AprsConsoleDirection.other => '--',
    };
    return '$timestamp $direction ${entry.source} -> ${entry.destination} | '
        '${entry.via} | ${entry.type} | ${entry.content}';
  }
}
