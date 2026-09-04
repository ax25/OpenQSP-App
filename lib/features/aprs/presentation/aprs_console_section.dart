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
  bool _followTail = true;
  bool _scrollScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _scrollController.addListener(_scrollPositionChanged);
    _scheduleScrollToEnd();
  }

  @override
  void didUpdateWidget(covariant AprsConsoleSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_changed);
    widget.controller.addListener(_changed);
    _followTail = true;
    _scheduleScrollToEnd();
  }

  void _scrollPositionChanged() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    _followTail = position.maxScrollExtent - position.pixels <= 24;
  }

  void _changed() {
    if (!mounted) return;
    final shouldFollow = _followTail;
    setState(() {});
    if (shouldFollow) _scheduleScrollToEnd();
  }

  void _scheduleScrollToEnd() {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_scrollController.hasClients || !_followTail) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _scrollController.removeListener(_scrollPositionChanged);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.controller.aprsConsoleEntries;
    if (_followTail && entries.isNotEmpty) _scheduleScrollToEnd();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Traffic received and transmitted by the KISS TNC.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            TextButton.icon(
              key: const Key('clearAprsConsole'),
              onPressed: entries.isEmpty ? null : widget.controller.clearAprsConsole,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Clear'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            key: const Key('aprsConsole'),
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border.all(color: Colors.grey.shade800),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: entries.isEmpty
                ? const Center(
                    child: Text(
                      'No APRS traffic yet',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
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
                        final appearance = _appearance(entry);
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
                              color: appearance.color,
                              fontWeight: appearance.bold
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  _AprsConsoleAppearance _appearance(AprsConsoleEntry entry) {
    if (entry.direction == AprsConsoleDirection.tx) {
      return const _AprsConsoleAppearance(
        color: Colors.red,
        bold: true,
      );
    }

    final sourceCallsign = widget.controller.sourceCallsign?.trim().toUpperCase();
    final localIdentity = sourceCallsign == null || sourceCallsign.isEmpty
        ? null
        : widget.controller.aprsSsid == 0
        ? sourceCallsign
        : '$sourceCallsign-${widget.controller.aprsSsid}';
    final destination = entry.destination.trim().toUpperCase();

    if (localIdentity != null && destination == localIdentity) {
      return const _AprsConsoleAppearance(
        color: Colors.green,
        bold: true,
      );
    }

    return const _AprsConsoleAppearance(
      color: Colors.blue,
      bold: false,
    );
  }

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

final class _AprsConsoleAppearance {
  const _AprsConsoleAppearance({required this.color, required this.bold});

  final Color color;
  final bool bold;
}
