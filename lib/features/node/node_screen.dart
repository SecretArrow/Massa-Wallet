/// Node mode (experimental): connect to a user-operated massa-node.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/app_i18n.dart';
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
  bool _probeBusy = false;
  String? _probeResult;
  bool _probeOk = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _url.text = settings.customNodeUrl;
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    setState(() => _probeBusy = true);
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
      if (mounted) setState(() => _probeBusy = false);
    }
  }

  Future<void> _save(bool enable) async {
    await context.read<SettingsProvider>().setCustomNode(
      url: _url.text.trim(),
      enable: enable,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enable
                ? context.t('node.enable')
                : context.t('settings.network.buildnet'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Scaffold(
      appBar: AppBar(title: Text(context.t('node.title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.science, color: Color(0xFFF0883E)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.t('node.hint'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              value: settings.useCustomNode,
              onChanged: _save,
              title: Text(context.t('node.enable')),
              activeThumbColor: const Color(0xFF18C8C8),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _url,
              enabled: true,
              decoration: InputDecoration(
                labelText: context.t('node.url'),
                hintText: 'http://127.0.0.1:33035',
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _probeBusy ? null : _probe,
              child: _probeBusy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.t('node.probe')),
            ),
            if (_probeResult != null) ...[
              const SizedBox(height: 16),
              Card(
                color: _probeOk
                    ? const Color(0xFF12261A)
                    : const Color(0xFF2D1215),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _probeResult!,
                    style: TextStyle(
                      fontSize: 12,
                      color: _probeOk
                          ? const Color(0xFF3FB950)
                          : const Color(0xFFF85149),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
