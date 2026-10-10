/// Node & connection screen — pick how the wallet reaches the network.
///
/// Three modes (user's choice, persisted):
/// 1. Public RPC — official endpoints, light client (default).
/// 2. Custom RPC — user-operated node over HTTP.
/// 3. Embedded node — a real massa-node binary running inside the app
///    sandbox on loopback (buildnet, experimental).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/app_i18n.dart';
import '../../core/services/embedded_node_service.dart';
import '../../core/services/node_mode_service.dart';
import '../../core/services/settings_provider.dart';

/// Node mode screen.
class NodeScreen extends StatefulWidget {
  /// Creates the screen.
  const NodeScreen({super.key});

  @override
  State<NodeScreen> createState() => _NodeScreenState();
}

class _NodeScreenState extends State<NodeScreen> {
  final _url = TextEditingController();
  String? _probeResult;
  bool _probeOk = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _url.text = settings.customNodeUrl;
    // Best-effort binary detection (also warms the bg-isolate lib dir).
    context.read<EmbeddedNodeService>().detectBinary();
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    try {
      final service = NodeModeService(
        settings: context.read<SettingsProvider>(),
      );
      final health = await service.probe();
      setState(() {
        _probeOk = health.reachable;
        _probeResult = health.reachable
            ? '${context.t('node.reachable')} · '
                  '${context.t('node.version')}: ${health.version} · '
                  '${context.t('node.chainId')}: ${health.chainId} · '
                  '${context.t('node.latency')}: ${health.latency?.inMilliseconds}ms'
            : '${context.t('node.unreachable')}: ${health.error}';
      });
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _saveCustomUrl() async {
    await context.read<SettingsProvider>().setCustomNodeUrl(_url.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.t('node.custom.saved'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Scaffold(
      appBar: AppBar(title: Text(context.t('node.title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            RadioGroup<NodeConnectionMode>(
              groupValue: settings.connectionMode,
              onChanged: (m) {
                if (m != null) {
                  context.read<SettingsProvider>().setConnectionMode(m);
                }
              },
              child: Column(
                children: [
                  _ModeCard(
                    mode: NodeConnectionMode.publicRpc,
                    icon: Icons.public,
                    title: context.t('node.mode.public.title'),
                    subtitle: context.t('node.mode.public.sub'),
                    detail: settings.network.apiUrl,
                  ),
                  const SizedBox(height: 10),
                  _ModeCard(
                    mode: NodeConnectionMode.customRpc,
                    icon: Icons.dns,
                    title: context.t('node.mode.custom.title'),
                    subtitle: context.t('node.mode.custom.sub'),
                    detail: settings.customNodeUrl.isEmpty
                        ? null
                        : settings.customNodeUrl,
                  ),
                  const SizedBox(height: 10),
                  _ModeCard(
                    mode: NodeConnectionMode.embedded,
                    icon: Icons.memory,
                    title: context.t('node.mode.embedded.title'),
                    subtitle: context.t('node.mode.embedded.sub'),
                    detail: settings.embeddedEndpoint,
                    trailing: const _BuildnetBadge(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ...switch (settings.connectionMode) {
              NodeConnectionMode.publicRpc => [_PublicPanel(probe: _probe)],
              NodeConnectionMode.customRpc => [
                _CustomPanel(url: _url, onSave: _saveCustomUrl, probe: _probe),
              ],
              NodeConnectionMode.embedded => [_EmbeddedPanel()],
            },
            if (_probeResult != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        _probeOk ? Icons.check_circle : Icons.error,
                        size: 18,
                        color: _probeOk ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _probeResult!,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            _OfficialBinaryCard(),
            const SizedBox(height: 8),
            _ResourceWarning(),
          ],
        ),
      ),
    );
  }
}

/// Selectable connection-mode card (M3).
class _ModeCard extends StatelessWidget {
  final NodeConnectionMode mode;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? detail;
  final Widget? trailing;

  const _ModeCard({
    required this.mode,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.detail,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final selected = settings.connectionMode == mode;
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).dividerTheme.color!,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.read<SettingsProvider>().setConnectionMode(mode),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              Radio<NodeConnectionMode>(value: mode),
              Icon(icon, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          if (trailing != null) ...[
                            const SizedBox(width: 6),
                            trailing!,
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(subtitle, style: const TextStyle(fontSize: 12)),
                      if (detail != null && detail!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          detail!,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small "Buildnet only" badge.
class _BuildnetBadge extends StatelessWidget {
  const _BuildnetBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'Buildnet',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

/// Public RPC panel — just probe the default endpoint.
class _PublicPanel extends StatelessWidget {
  final Future<void> Function() probe;
  const _PublicPanel({required this.probe});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.t('node.mode.public.title'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              context.t('node.mode.public.body'),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: probe,
              icon: const Icon(Icons.network_check, size: 18),
              label: Text(context.t('node.probe')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom RPC panel — URL input + save + probe.
class _CustomPanel extends StatelessWidget {
  final TextEditingController url;
  final Future<void> Function() onSave;
  final Future<void> Function() probe;

  const _CustomPanel({
    required this.url,
    required this.onSave,
    required this.probe,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.t('node.mode.custom.title'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              context.t('node.mode.custom.body'),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: url,
              decoration: const InputDecoration(
                labelText: 'URL',
                hintText: 'http://192.168.1.10:33035',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onSave,
                    icon: const Icon(Icons.save, size: 18),
                    label: Text(context.t('node.custom.save')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: probe,
                    icon: const Icon(Icons.network_check, size: 18),
                    label: Text(context.t('node.probe')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Embedded node control panel.
class _EmbeddedPanel extends StatelessWidget {
  const _EmbeddedPanel();

  @override
  Widget build(BuildContext context) {
    final embedded = context.watch<EmbeddedNodeService>();
    final settings = context.watch<SettingsProvider>();

    if (!settings.embeddedUsable) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.swap_horiz, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.t('node.embedded.mainnet'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (!embedded.binaryAvailable) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.extension_off, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.t('node.embedded.unavailable'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return _EmbeddedControl(embedded: embedded);
  }
}

/// Status + start/stop + logs + reset for the embedded node.
class _EmbeddedControl extends StatelessWidget {
  final EmbeddedNodeService embedded;
  const _EmbeddedControl({required this.embedded});

  Color _stateColor(EmbeddedNodeState state) => switch (state) {
    EmbeddedNodeState.running => Colors.green,
    EmbeddedNodeState.starting => Colors.orange,
    EmbeddedNodeState.failed => Colors.red,
    _ => Colors.grey,
  };

  IconData _stateIcon(EmbeddedNodeState state) => switch (state) {
    EmbeddedNodeState.running => Icons.check_circle,
    EmbeddedNodeState.starting => Icons.hourglass_top,
    EmbeddedNodeState.failed => Icons.error,
    _ => Icons.stop_circle_outlined,
  };

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.t('node.embedded.reset')),
        content: Text(context.t('node.embedded.reset.confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.t('common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.t('common.confirm')),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await embedded.resetData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = embedded.state;
    final busy = state == EmbeddedNodeState.starting;
    final uptime = embedded.startedAt == null
        ? null
        : DateTime.now().difference(embedded.startedAt!);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status row
            Row(
              children: [
                Icon(_stateIcon(state), size: 20, color: _stateColor(state)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.t('node.embedded.state.${state.name}'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${context.t('node.embedded.port')}: '
              '127.0.0.1:${SettingsProvider.embeddedApiPort}',
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
            if (uptime != null) ...[
              const SizedBox(height: 4),
              Text(
                '${context.t('node.embedded.uptime')}: '
                '${uptime.inMinutes}m ${uptime.inSeconds % 60}s',
                style: const TextStyle(fontSize: 12),
              ),
            ],
            if (embedded.lastError != null) ...[
              const SizedBox(height: 8),
              Text(
                embedded.lastError!,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.red,
                  fontFamily: 'monospace',
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 14),
            // Start / stop
            state == EmbeddedNodeState.running
                ? FilledButton.tonalIcon(
                    onPressed: embedded.stop,
                    icon: const Icon(Icons.stop, size: 18),
                    label: Text(context.t('node.embedded.stop')),
                  )
                : FilledButton.icon(
                    onPressed: busy ? null : embedded.start,
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: Text(context.t('node.embedded.start')),
                  ),
            const SizedBox(height: 8),
            Text(
              context.t('node.embedded.keepalive'),
              style: const TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 14),
            // Logs
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: Text(
                context.t('node.embedded.logs'),
                style: const TextStyle(fontSize: 14),
              ),
              children: [
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 220),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF0D1117)
                        : const Color(0xFF1F2328),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SingleChildScrollView(
                    reverse: true,
                    child: SelectableText(
                      embedded.logs.isEmpty ? '…' : embedded.logs.join('\n'),
                      style: const TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        color: Color(0xFF3FB950),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: embedded.logs.join('\n')),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.t('node.embedded.logs.copy')),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: Text(context.t('node.embedded.logs.copy')),
                  ),
                ),
              ],
            ),
            const Divider(),
            // Danger zone
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => _confirmReset(context),
                icon: const Icon(Icons.delete_forever, size: 18),
                label: Text(context.t('node.embedded.reset')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Official binary verification pointers (kept from v1.2.0).
class _OfficialBinaryCard extends StatelessWidget {
  const _OfficialBinaryCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.verified_user,
                  color: Color(0xFF3FB950),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.t('node.official.title'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              context.t('node.official.body'),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            const SelectableText(
              'https://github.com/massalabs/massa/releases',
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: Color(0xFF58A6FF),
              ),
            ),
            const SizedBox(height: 4),
            const SelectableText(
              'https://docs.massa.net/docs/quickstart/run-node',
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: Color(0xFF58A6FF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Experimental resource-usage warning.
class _ResourceWarning extends StatelessWidget {
  const _ResourceWarning();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.battery_alert, color: Color(0xFFF0883E), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.t('node.embedded.warning'),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
