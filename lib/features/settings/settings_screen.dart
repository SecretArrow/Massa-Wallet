/// Settings: language, network, security, background sync, export.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/api/massa_rpc.dart' show MassaNetwork;
import '../../core/i18n/app_i18n.dart';
import '../../ui/theme.dart';
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
                ButtonSegment(value: 'en', label: Text('EN')),
                ButtonSegment(value: 'id', label: Text('ID')),
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
              color: PyramidsColors.brand,
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
              color: PyramidsColors.brand,
            ),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (dCtx) => AlertDialog(
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
            activeThumbColor: PyramidsColors.brand,
          ),
          SwitchListTile(
            value: true,
            onChanged: security.setSecureFlag,
            title: Text(context.t('settings.secureFlag')),
            activeThumbColor: PyramidsColors.brand,
          ),
          ListTile(
            title: Text(context.t('settings.autoLock')),
            trailing: DropdownButton<int>(
              value: settings.autoLockSeconds,
              dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
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
            activeThumbColor: PyramidsColors.brand,
          ),
          ListTile(
            title: Text(context.t('settings.background.interval')),
            trailing: DropdownButton<int>(
              value: settings.syncIntervalSeconds,
              dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
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
            activeThumbColor: PyramidsColors.brand,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.currency_exchange),
            value: settings.showFiat,
            onChanged: (v) => context.read<SettingsProvider>().setShowFiat(v),
            title: Text(context.t('settings.showFiat')),
            activeThumbColor: PyramidsColors.brand,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.palette_outlined),
                    const SizedBox(width: 16),
                    Text(context.t('settings.theme')),
                  ],
                ),
                const SizedBox(height: 10),
                SegmentedButton<ThemeMode>(
                  segments: [
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: const Icon(Icons.dark_mode_outlined, size: 18),
                      label: Text(context.t('settings.theme.dark')),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: const Icon(Icons.light_mode_outlined, size: 18),
                      label: Text(context.t('settings.theme.light')),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: const Icon(
                        Icons.brightness_auto_outlined,
                        size: 18,
                      ),
                      label: Text(context.t('settings.theme.system')),
                    ),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (selection) {
                    context.read<SettingsProvider>().setThemeMode(
                      selection.first,
                    );
                  },
                ),
              ],
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

          // Backup / restore (all accounts, encrypted)
          ListTile(
            leading: const Icon(
              Icons.backup_outlined,
              color: Color(0xFF3FB950),
            ),
            title: Text(context.t('settings.backup')),
            subtitle: Text(
              context.t('settings.backup.sub'),
              style: const TextStyle(fontSize: 11),
            ),
            onTap: () =>
                _confirmPinDialog(context, (sheetCtx) => const _BackupSheet()),
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: Text(context.t('settings.restore')),
            onTap: () =>
                _confirmPinDialog(context, (sheetCtx) => const _RestoreSheet()),
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
            trailing: const Text('1.4.0'),
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

/// Encrypted multi-account backup sheet.
class _BackupSheet extends StatefulWidget {
  const _BackupSheet();

  @override
  State<_BackupSheet> createState() => _BackupSheetState();
}

class _BackupSheetState extends State<_BackupSheet> {
  final _pw = TextEditingController();
  bool _busy = false;
  String? _exported;
  String? _path;

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
      final content = await wallet.exportBackup(_pw.text);
      // Persist to Documents for easy sharing.
      String? savedPath;
      try {
        final dir = await getApplicationDocumentsDirectory();
        final stamp = DateTime.now().toIso8601String().substring(0, 10);
        final f = File('${dir.path}/massa-wallet-backup-$stamp.massabak');
        await f.writeAsString(content, flush: true);
        savedPath = f.path;
      } on Exception {
        // File write is best-effort — the JSON is still shown below.
      }
      setState(() {
        _exported = content;
        _path = savedPath;
      });
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
            context.t('settings.backup'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            context.t('settings.backup.hint'),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (_exported == null) ...[
            TextField(
              controller: _pw,
              obscureText: true,
              decoration: InputDecoration(
                labelText: context.t('settings.backup.password'),
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
          ] else ...[
            if (_path != null)
              Card(
                color: const Color(0xFF12261A),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '${context.t('settings.backup.saved')}: $_path',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: SelectableText(
                  _exported!,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Restore-from-backup sheet.
class _RestoreSheet extends StatefulWidget {
  const _RestoreSheet();

  @override
  State<_RestoreSheet> createState() => _RestoreSheetState();
}

class _RestoreSheetState extends State<_RestoreSheet> {
  final _contents = TextEditingController();
  final _pw = TextEditingController();
  bool _busy = false;
  String? _result;

  @override
  void dispose() {
    _contents.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    if (_pw.text.isEmpty || _contents.text.isEmpty) return;
    setState(() => _busy = true);
    try {
      final wallet = context.read<WalletProvider>();
      final n = await wallet.importBackup(_contents.text, _pw.text);
      setState(
        () => _result = context.t('settings.restore.done', args: ['$n']),
      );
    } on FormatException catch (e) {
      setState(() => _result = e.message);
    } catch (e) {
      setState(() => _result = e.toString());
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
            context.t('settings.restore'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            context.t('settings.restore.hint'),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (_result == null) ...[
            TextField(
              controller: _contents,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: context.t('settings.restore.contents'),
                hintText: '{"Format": "massa-wallet-backup", ...}',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pw,
              obscureText: true,
              decoration: InputDecoration(
                labelText: context.t('settings.backup.password'),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _restore,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.t('settings.restore')),
            ),
          ] else
            Card(
              color: const Color(0xFF12261A),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_result!, style: const TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
    );
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
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
