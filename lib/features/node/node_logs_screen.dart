/// Full-screen live viewer for the embedded massa-node logs.
///
/// Chat-log pattern: a reversed [ListView.builder] anchors the newest line
/// at the bottom. Auto-follow keeps the view pinned there while the user
/// sits at the bottom; scrolling up pauses auto-scroll and shows a
/// "jump to latest" banner instead. Lines are colored by severity
/// (see [classifyNodeLogLevel]) and rendered in a terminal-style dark
/// surface in both themes for readability. Supports filtering by level,
/// clipboard export, and clearing the buffer.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/app_i18n.dart';
import '../../core/services/embedded_node_service.dart';
import 'node_log_level.dart';

/// Live, filterable terminal view of the embedded node's stdout/stderr.
class NodeLogsScreen extends StatefulWidget {
  /// Creates the log viewer.
  const NodeLogsScreen({super.key});

  @override
  State<NodeLogsScreen> createState() => _NodeLogsScreenState();
}

class _NodeLogsScreenState extends State<NodeLogsScreen> {
  final ScrollController _scroll = ScrollController();
  NodeLogLevel? _filter; // null = show all
  bool _following = true;

  static const Color _bg = Color(0xFF0D1117);
  static const Color _info = Color(0xFF3FB950);
  static const Color _warn = Color(0xFFE3B341);
  static const Color _err = Color(0xFFF85149);
  static const Color _dim = Color(0xFF8B949E);

  /// Filter chips: level (null = all) + i18n key.
  static const List<(NodeLogLevel?, String)> _filters = [
    (null, 'node.logs.filter.all'),
    (NodeLogLevel.info, 'node.logs.filter.info'),
    (NodeLogLevel.warn, 'node.logs.filter.warn'),
    (NodeLogLevel.error, 'node.logs.filter.error'),
  ];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    // In a reversed list offset 0 is the newest line. Leaving the bottom
    // pauses auto-follow; returning near it re-arms it.
    final atBottom = _scroll.hasClients && _scroll.offset < 80;
    if (atBottom != _following && mounted) {
      setState(() => _following = atBottom);
    }
  }

  void _jumpToLatest() {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  List<String> _visible(List<String> logs) {
    if (_filter == null) {
      return logs;
    }
    return logs
        .where((l) => classifyNodeLogLevel(l) == _filter)
        .toList(growable: false);
  }

  Color _colorFor(NodeLogLevel level) => switch (level) {
        NodeLogLevel.error => _err,
        NodeLogLevel.warn => _warn,
        NodeLogLevel.info => _info,
      };

  Future<void> _copy(List<String> lines) async {
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t('node.logs.copied'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final node = context.watch<EmbeddedNodeService>();
    final lines = _visible(node.logs);
    final running = node.state == EmbeddedNodeState.running;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('node.logs.title')),
        actions: [
          IconButton(
            tooltip: context.t('node.embedded.logs.copy'),
            icon: const Icon(Icons.copy, size: 20),
            onPressed: lines.isEmpty ? null : () => _copy(lines),
          ),
          IconButton(
            tooltip: context.t('node.logs.clear'),
            icon: const Icon(Icons.delete_sweep, size: 20),
            onPressed: lines.isEmpty
                ? null
                : () {
                    node.clearLogs();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.t('node.logs.cleared'))),
                    );
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          // Status strip — LIVE dot + line counter.
          Container(
            width: double.infinity,
            color: _bg,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(
                  running ? Icons.circle : Icons.circle_outlined,
                  size: 10,
                  color: running ? _info : _dim,
                ),
                const SizedBox(width: 6),
                Text(
                  running
                      ? 'LIVE'
                      : context.t('node.embedded.state.stopped'),
                  style: const TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: _dim,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                Text(
                  context.t('node.logs.count').replaceAll(
                        '{0}',
                        '${lines.length}',
                      ),
                  style: const TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: _dim,
                  ),
                ),
              ],
            ),
          ),
          // Level filter chips.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                for (final (level, key) in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(
                        context.t(key),
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: _filter == level,
                      onSelected: (_) => setState(() => _filter = level),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              color: _bg,
              child: lines.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          context.t('node.logs.empty'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _dim, fontSize: 12),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.all(10),
                      itemCount: lines.length,
                      // Reversed list: index 0 = newest line (bottom).
                      itemBuilder: (context, i) {
                        final line = lines[lines.length - 1 - i];
                        return SelectableText(
                          line,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.35,
                            fontFamily: 'monospace',
                            color: _colorFor(classifyNodeLogLevel(line)),
                          ),
                        );
                      },
                    ),
            ),
          ),
          // Auto-scroll paused banner.
          if (!_following)
            Material(
              color: Theme.of(context).colorScheme.primary,
              child: InkWell(
                onTap: _jumpToLatest,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.arrow_downward,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '${context.t('node.logs.jump')} · '
                          '${context.t('node.logs.paused')}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
