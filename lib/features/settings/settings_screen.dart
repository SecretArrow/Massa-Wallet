/// Settings: language, network, security, background sync, export.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/massa_rpc.dart' show MassaNetwork;
import '../../core/i18n/app_i18n.dart';
import '../../core/services/security_service.dart';
import '../../core/services/settings_provider.dart';
import '../../core/services/wallet_provider.dart';

/// Settings screen.
class SettingsScreen extends StatelessWidget {
  /// Creates the screen.
  const SettingsScreen({super.key});

  Future<void> _confirmPinDialog(
    BuildContext context,
    WidgetBuilder builder,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1C2330),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: builder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final security = context.watch<SecurityService>();

    return Scaffold(
      appBar: AppBar(title: Text(context.t('settings.title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Language
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(context.t('settings.language')),
            trailing: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'id', label: Text('ID')),
                ButtonSegment(value: 'en', label: Text('EN')),
              ],
              selected: {settings.language.code},
              onSelectionChanged: (s) =>
                  context.read<SettingsProvider>().setLanguage(
                    s.first == 'en'
                        ? AppLanguage.english
                        : AppLanguage.indonesian,
                  ),
            ),
          ),
          const Divider(),

          // Network
          ListTile(
            leading: const Icon(Icons.public),
            title: Text(context.t('settings.network')),
          ),
          ListTile(
            leading: Icon(
              settings.network == MassaNetwork.buildnet
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: const Color(0xFF18C8C8),
            ),
            onTap: () => context.read<SettingsProvider>().setNetwork(
              MassaNetwork.buildnet,
            ),
            title: Text(context.t('settings.network.buildnet')),
          ),
          ListTile(
            leading: Icon(
              settings.network == MassaNetwork.mainnet
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: const Color(0xFF18C8C8),
            ),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (dCtx) => AlertDialog(
                  backgroundColor: const Color(0xFF1C2330),
                  title: Text(dCtx.t('settings.network.mainnet')),
                  content: Text(dCtx.t('settings.network.warning')),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dCtx, false),
                      child: Text(dCtx.t('common.cancel')),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dCtx, true),
                      child: Text(dCtx.t('common.confirm')),
                    ),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                await context.read<SettingsProvider>().setNetwork(
                  MassaNetwork.mainnet,
                );
              }
            },
            title: Text(context.t('settings.network.mainnet')),
          ),
          const Divider(),

          // Security
          ListTile(
            leading: const Icon(Icons.security),
            title: Text(context.t('settings.security')),
          ),
          SwitchListTile(
            value: settings.biometricRequired,
            onChanged: (v) =>
                context.read<SettingsProvider>().setBiometricRequired(v),
            title: Text(context.t('settings.biometric')),
            activeThumbColor: const Color(0xFF18C8C8),
          ),
          SwitchListTile(
            value: true,
            onChanged: security.setSecureFlag,
            title: Text(context.t('settings.secureFlag')),
            activeThumbColor: const Color(0xFF18C8C8),
          ),
          ListTile(
            title: Text(context.t('settings.autoLock')),
            trailing: DropdownButton<int>(
              value: settings.autoLockSeconds,
              dropdownColor: const Color(0xFF1C2330),
              items: [
                DropdownMenuItem(
                  value: 60,
                  child: Text(context.t('settings.autoLock.60')),
                ),
                DropdownMenuItem(
                  value: 120,
                  child: Text(context.t('settings.autoLock.120')),
                ),
                DropdownMenuItem(
                  value: 300,
                  child: Text(context.t('settings.autoLock.300')),
                ),
              ],
              onChanged: (v) {
                if (v != null) {
                  unawaited(
                    context.read<SettingsProvider>().setAutoLockSeconds(v),
                  );
                }
              },
            ),
          ),
          const Divider(),

          // Background sync
          SwitchListTile(
            secondary: const Icon(Icons.sync),
            value: settings.backgroundSync,
            onChanged: (v) =>
                context.read<SettingsProvider>().setBackgroundSync(v),
            title: Text(context.t('settings.background')),
            activeThumbColor: const Color(0xFF18C8C8),
          ),
          ListTile(
            title: Text(context.t('settings.background.interval')),
            trailing: DropdownButton<int>(
              value: settings.syncIntervalSeconds,
              dropdownColor: const Color(0xFF1C2330),
              items: [
                DropdownMenuItem(
                  value: 60,
                  child: Text(context.t('settings.background.60')),
                ),
                DropdownMenuItem(
                  value: 300,
                  child: Text(context.t('settings.background.300')),
                ),
                DropdownMenuItem(
                  value: 900,
                  child: Text(context.t('settings.background.900')),
                ),
              ],
              onChanged: (v) {
                if (v != null) {
                  context.read<SettingsProvider>().setSyncIntervalSeconds(v);
                }
              },
            ),
          ),

          // Privacy
          SwitchListTile(
            secondary: const Icon(Icons.visibility_off),
            value: settings.hideBalances,
            onChanged: (v) =>
                context.read<SettingsProvider>().setHideBalances(v),
            title: Text(context.t('settings.privacy')),
            activeThumbColor: const Color(0xFF18C8C8),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.attach_money),
            value: settings.showFiat,
            onChanged: (v) =>
                context.read<SettingsProvider>().setShowFiat(v),
            title: Text(context.t('settings.showFiat')),
            activeThumbColor: const Color(0xFF18C8C8),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: Text(context.t('settings.theme')),
            trailing: DropdownButton<ThemeMode>(
              value: settings.themeMode,
              dropdownColor: const Color(0xFF1C2330),
              items: [
                DropdownMenuItem(
                  value: ThemeMode.dark,
                  child: Text(context.t('settings.theme.dark')),
                ),
                DropdownMenuItem(
                  value: ThemeMode.light,
                  child: Text(context.t('settings.theme.light')),
                ),
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text(context.t('settings.theme.system')),
                ),
              ],
              onChanged: (v) {
                if (v != null) {
                  context.read<SettingsProvider>().setThemeMode(v);
                }
              },
            ),
          ),
          const Divider(),

          // Node mode
          ListTile(
            leading: const Icon(Icons.dns, color: Color(0xFFF0883E)),
            title: Text(context.t('node.title')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/node'),
          ),
          const Divider(),

          // Export / reveal
          ListTile(
            leading: const Icon(Icons.file_download),
            title: Text(context.t('settings.export')),
            onTap: () => _confirmPinDialog(
              context,
              (sheetCtx) => _ExportSheet(address: _activeAddress(context)),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(context.t('settings.version')),
            trailing: const Text('1.1.0'),
          ),
        ],
      ),
    );
  }

  String _activeAddress(BuildContext context) {
    final wallet = context.read<WalletProvider>();
    return wallet.activeAccount?.address ?? '';
  }
}

/// Export keystore bottom sheet.
class _ExportSheet extends StatefulWidget {
  final String address;

  const _ExportSheet({required this.address});

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  final _pw = TextEditingController();
  bool _busy = false;
  String? _exported;

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    if (_pw.text.isEmpty) return;
    setState(() => _busy = true);
    try {
      final wallet = context.read<WalletProvider>();
      final content = await wallet.exportKeyStore(widget.address, _pw.text);
      setState(() => _exported = content);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.t('common.error')}: $e'),
            backgroundColor: const Color(0xFFF85149),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t('settings.export'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            context.t('settings.export.hint'),
            style: const TextStyle(fontSize: 12, color: Color(0xFF8B949E)),
          ),
          const SizedBox(height: 16),
          if (_exported == null) ...[
            TextField(
              controller: _pw,
              obscureText: true,
              decoration: InputDecoration(
                labelText: context.t('settings.export.password'),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _export,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.t('common.confirm')),
            ),
          ] else
            Flexible(
              child: SingleChildScrollView(
                child: SelectableText(
                  _exported!,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
