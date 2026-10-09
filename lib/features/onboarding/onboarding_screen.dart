/// Onboarding: welcome, create wallet, import (secret key / keystore).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/app_i18n.dart';
import '../../core/services/security_service.dart';
import '../../core/services/wallet_provider.dart';

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
      backgroundColor: const Color(0xFF1C2330),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: const EdgeInsets.all(24),
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
                style: const TextStyle(color: Color(0xFF8B949E)),
              ),
              const SizedBox(height: 16),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setSheet(() => revealed = true),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1117),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFF0883E),
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
                          ? const Color(0xFFF0883E)
                          : const Color(0xFF8B949E),
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
                        content: Text(sheetCtx.t('onboarding.security.copied')),
                      ),
                    );
                  },
                  child: Text(sheetCtx.t('common.copy')),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: revealed ? () => Navigator.of(sheetCtx).pop() : null,
                child: Text(sheetCtx.t('onboarding.iSavedIt')),
              ),
            ],
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0B6E6E), Color(0xFF18C8C8)],
                    ),
                  ),
                  child: const Icon(
                    Icons.currency_exchange,
                    size: 52,
                    color: Color(0xFF062A2A),
                  ),
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
                style: const TextStyle(color: Color(0xFF8B949E)),
              ),
              const SizedBox(height: 32),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.shield,
                        color: Color(0xFF18C8C8),
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          context.t('welcome.body'),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF8B949E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _busy ? null : _create,
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
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
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF30363D),
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
  bool _busy = false;
  int _mode = 0; // 0 = secret key, 1 = keystore

  @override
  void dispose() {
    _skController.dispose();
    _pwController.dispose();
    _nickController.dispose();
    super.dispose();
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
      } else {
        // Keystore contents pasted into the same field for simplicity.
        await wallet.importKeyStore(
          _skController.text,
          _pwController.text,
          nickname: _nickController.text.trim(),
        );
      }
      if (!mounted) return;
      unawaited(Navigator.of(context).pushReplacementNamed('/home'));
    } on FormatException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.t('onboarding.invalidKey')),
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
            SegmentedButton<int>(
              segments: [
                ButtonSegment(
                  value: 0,
                  label: Text(context.t('onboarding.import.sk')),
                  icon: const Icon(Icons.key),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text(context.t('onboarding.import.keystore')),
                  icon: const Icon(Icons.file_open),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 24),
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
