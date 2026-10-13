/// Onboarding: welcome, create wallet, import (secret key / keystore).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/app_i18n.dart';
import '../../ui/theme.dart';
import '../../core/services/security_service.dart';
import '../../core/services/wallet_provider.dart';

/// Create-wallet method chooser (standard random key vs BIP-39 phrase).
Future<void> showCreateMethodSheet(
  BuildContext context, {
  required VoidCallback onStandard,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12, top: 4),
              child: Text(
                sheetCtx.t('seed.method.title'),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _MethodCard(
              icon: Icons.psychology_alt_outlined,
              color: PyramidsColors.brand,
              title: sheetCtx.t('seed.method.seed.title'),
              subtitle: sheetCtx.t('seed.method.seed.sub'),
              recommended: true,
              onTap: () {
                Navigator.of(sheetCtx).pop();
                unawaited(Navigator.of(context).pushNamed('/seedCreate'));
              },
            ),
            const SizedBox(height: 10),
            _MethodCard(
              icon: Icons.vpn_key_outlined,
              color: PyramidsColors.orange,
              title: sheetCtx.t('seed.method.random.title'),
              subtitle: sheetCtx.t('seed.method.random.sub'),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                onStandard();
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// One selectable method card.
class _MethodCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool recommended;
  final VoidCallback onTap;

  const _MethodCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.recommended = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: recommended
                ? PyramidsColors.brand.withValues(alpha: 0.5)
                : Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (recommended) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: PyramidsColors.brand.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '★',
                            style: TextStyle(
                              fontSize: 10,
                              color: PyramidsColors.brand,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// Welcome + entry screen.
class OnboardingScreen extends StatefulWidget {
  /// Creates the screen.
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _busy = false;

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final wallet = context.read<WalletProvider>();
      final account = await wallet.createWallet();
      if (!mounted) return;
      // Show backup sheet with the secret key.
      final sk = await wallet.revealSecretKey(account.address);
      if (!mounted) return;
      await _showBackupSheet(sk);
      if (!mounted) return;
      unawaited(Navigator.of(context).pushReplacementNamed('/home'));
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showBackupSheet(String secretKey) {
    var revealed = false;
    return showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: const EdgeInsets.all(24),
          // Scroll-safe on short screens.
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sheetCtx.t('onboarding.security.title'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  sheetCtx.t('onboarding.security.body'),
                  style: TextStyle(
                    color: Theme.of(sheetCtx).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setSheet(() => revealed = true),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        sheetCtx,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: PyramidsColors.orange,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      revealed
                          ? secretKey
                          : sheetCtx.t('onboarding.security.reveal'),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: revealed
                            ? PyramidsColors.orange
                            : Theme.of(sheetCtx).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                if (revealed) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: secretKey));
                      ScaffoldMessenger.of(sheetCtx).showSnackBar(
                        SnackBar(
                          content: Text(
                            sheetCtx.t('onboarding.security.copied'),
                          ),
                        ),
                      );
                    },
                    child: Text(sheetCtx.t('common.copy')),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: revealed
                      ? () => Navigator.of(sheetCtx).pop()
                      : null,
                  child: Text(sheetCtx.t('onboarding.iSavedIt')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${context.t('common.error')}: $message'),
        backgroundColor: const Color(0xFFF85149),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // Scroll-safe: on short screens (e.g. 320x568 emulators) the hero
        // content used to overflow the Column by a few pixels.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(),
                      Center(
                        child: Image.asset(
                          'assets/icon/pyramids_logo.png',
                          width: 128,
                          height: 128,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        context.t('app.title'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        context.t('app.tagline'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.shield,
                                color: PyramidsColors.brand,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  context.t('welcome.body'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: _busy
                            ? null
                            : () => showCreateMethodSheet(
                                  context,
                                  onStandard: _create,
                                ),
                        child: _busy
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(context.t('onboarding.create')),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).pushNamed('/import'),
                        child: Text(context.t('onboarding.import')),
                      ),
                      const SizedBox(height: 8),
                      // Register an interaction for the auto-lock engine.
                      TextButton(
                        onPressed: () {
                          context.read<SecurityService>().registerInteraction();
                        },
                        child: Text(
                          context.t('welcome.title'),
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.35),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Import screen (secret key or keystore file).
class ImportScreen extends StatefulWidget {
  /// Creates the screen.
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _skController = TextEditingController();
  final _pwController = TextEditingController();
  final _nickController = TextEditingController();
  final _watchController = TextEditingController();
  final _seedController = TextEditingController();
  bool _busy = false;
  int _mode = 0; // 0 = secret key, 1 = keystore, 2 = watch-only, 3 = seed

  @override
  void dispose() {
    _skController.dispose();
    _pwController.dispose();
    _nickController.dispose();
    _watchController.dispose();
    _seedController.dispose();
    super.dispose();
  }

  /// Maps BIP-39 `code:` FormatExceptions to localized messages.
  String _seedError(FormatException e) {
    final msg = e.message;
    if (msg == 'code:length') return context.t('seed.import.badLength');
    if (msg.startsWith('code:word:')) {
      final pos = int.tryParse(msg.substring('code:word:'.length)) ?? 0;
      return context.t('seed.import.badWord', args: ['${pos + 1}']);
    }
    if (msg == 'code:checksum') return context.t('seed.badChecksum');
    return context.t('seed.import.invalid');
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final wallet = context.read<WalletProvider>();
      if (_mode == 0) {
        await wallet.importSecretKey(
          _skController.text,
          nickname: _nickController.text.trim(),
        );
      } else if (_mode == 1) {
        // Keystore contents pasted into the same field for simplicity.
        await wallet.importKeyStore(
          _skController.text,
          _pwController.text,
          nickname: _nickController.text.trim(),
        );
      } else if (_mode == 3) {
        await wallet.importMnemonic(
          _seedController.text,
          nickname: _nickController.text.trim(),
        );
      } else {
        await wallet.addWatchOnly(
          _watchController.text,
          nickname: _nickController.text.trim(),
        );
      }
      if (!mounted) return;
      unawaited(Navigator.of(context).pushReplacementNamed('/home'));
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _mode == 2
                  ? context.t('send.invalidRecipient')
                  : _mode == 3
                      ? _seedError(e)
                      : context.t('onboarding.invalidKey'),
            ),
            backgroundColor: const Color(0xFFF85149),
          ),
        );
      }
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
    return Scaffold(
      appBar: AppBar(title: Text(context.t('onboarding.import'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  avatar: const Icon(Icons.key, size: 16),
                  label: Text(context.t('onboarding.import.sk')),
                  selected: _mode == 0,
                  onSelected: (_) => setState(() => _mode = 0),
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.file_open, size: 16),
                  label: Text(context.t('onboarding.import.keystore')),
                  selected: _mode == 1,
                  onSelected: (_) => setState(() => _mode = 1),
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.visibility, size: 16),
                  label: Text(context.t('onboarding.import.watch')),
                  selected: _mode == 2,
                  onSelected: (_) => setState(() => _mode = 2),
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.psychology_alt_outlined, size: 16),
                  label: Text(context.t('seed.import.segment')),
                  selected: _mode == 3,
                  onSelected: (_) => setState(() => _mode = 3),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_mode == 2) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.visibility,
                        color: PyramidsColors.brand,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.t('onboarding.import.watch.hint'),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _watchController,
                decoration: InputDecoration(
                  labelText: context.t('wallet.address'),
                  hintText: 'AU1...',
                ),
              ),
            ] if (_mode == 3) ...[
              TextField(
                controller: _seedController,
                maxLines: 3,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.visiblePassword,
                decoration: InputDecoration(
                  labelText: context.t('seed.import.label'),
                  hintText: context.t('seed.import.hint'),
                ),
              ),
            ] else ...[
              TextField(
                controller: _skController,
                maxLines: _mode == 0 ? 2 : 6,
                decoration: InputDecoration(
                  labelText: _mode == 0
                      ? context.t('onboarding.secretKey')
                      : context.t('onboarding.import.keystore'),
                  hintText: _mode == 0 ? 'S1...' : '{"Address": "AU...", ...}',
                ),
              ),
              if (_mode == 1) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _pwController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: context.t('onboarding.password'),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _nickController,
              decoration: InputDecoration(
                labelText: context.t('onboarding.nickname'),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _import,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.t('wallet.import')),
            ),
          ],
        ),
      ),
    );
  }
}
