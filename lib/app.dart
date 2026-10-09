/// App root: providers, routing, lock gate.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/i18n/app_i18n.dart';
import 'core/i18n/translations.dart' show translations;
import 'core/services/background_sync_service.dart';
import 'core/services/security_service.dart';
import 'core/services/settings_provider.dart';
import 'core/services/wallet_provider.dart';
import 'features/contracts/contracts_screen.dart';
import 'features/node/node_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/receive/receive_screen.dart';
import 'features/send/send_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/staking/staking_screen.dart';
import 'features/wallet/dashboard_screen.dart';
import 'ui/theme.dart';

/// Massa Wallet application widget.
class MassaWalletApp extends StatefulWidget {
  /// Creates the app.
  const MassaWalletApp({super.key});

  @override
  State<MassaWalletApp> createState() => _MassaWalletAppState();
}

class _MassaWalletAppState extends State<MassaWalletApp>
    with WidgetsBindingObserver {
  final ValueNotifier<AppLanguage> _language = ValueNotifier(
    AppLanguage.indonesian,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final settings = context.read<SettingsProvider>();
    final security = context.read<SecurityService>();
    final syncEnabled = settings.backgroundSync;
    settings.load().then((_) {
      _language.value = settings.language;
      security.setSecureFlag(true);
      if (syncEnabled) {
        unawaited(_startBackgroundSync());
      }
    });
  }

  Future<void> _startBackgroundSync() async {
    try {
      final service = BackgroundSyncService();
      await service.configure(
        autoStart: true,
        title: 'Massa Wallet',
        content: 'Sinkronisasi saldo aktif',
      );
      await service.start();
    } on Exception {
      // Background sync is best-effort.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final security = context.read<SecurityService>();
    final settings = context.read<SettingsProvider>();
    if (state == AppLifecycleState.paused) {
      security.registerInteraction();
    } else if (state == AppLifecycleState.resumed) {
      security.checkIdle();
      if (settings.biometricRequired && security.gate == SecurityGate.locked) {
        security.unlock();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _language.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppI18n(
      notifier: _language,
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          if (_language.value != settings.language) {
            _language.value = settings.language;
          }
          return MaterialApp(
            title: 'Massa Wallet',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark,
            locale: Locale(settings.language.code),
            supportedLocales: const [Locale('id'), Locale('en')],
            initialRoute: '/',
            routes: {
              '/': (_) => const _RootGate(),
              '/onboarding': (_) => const OnboardingScreen(),
              '/import': (_) => const ImportScreen(),
              '/home': (_) => const DashboardScreen(),
              '/send': (_) => const SendScreen(),
              '/receive': (_) => const ReceiveScreen(),
              '/staking': (_) => const StakingScreen(),
              '/contracts': (_) => const ContractsScreen(),
              '/node': (_) => const NodeScreen(),
              '/settings': (_) => const SettingsScreen(),
            },
          );
        },
      ),
    );
  }
}

/// Routes to onboarding or dashboard depending on stored accounts,
/// enforcing the lock gate.
class _RootGate extends StatefulWidget {
  const _RootGate();

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  bool _decided = false;
  bool _hasAccounts = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _decide());
  }

  Future<void> _decide() async {
    final wallet = context.read<WalletProvider>();
    final settings = context.read<SettingsProvider>();
    final security = context.read<SecurityService>();
    await wallet.loadAccounts();
    final has = wallet.accounts.isNotEmpty;
    var unlocked = true;
    if (has && settings.biometricRequired) {
      unlocked = await security.unlock();
    }
    if (!mounted) return;
    setState(() {
      _hasAccounts = has;
      _decided = true;
    });
    if (!unlocked && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final security = context.watch<SecurityService>();
    if (!_decided) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_hasAccounts && security.gate == SecurityGate.locked) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock, size: 64, color: Color(0xFF18C8C8)),
              const SizedBox(height: 16),
              Text(
                context.t('common.locked'),
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () async {
                  final ok = await context.read<SecurityService>().unlock(
                    reason: context.t('common.unlockReason'),
                  );
                  if (ok && context.mounted) setState(() {});
                },
                child: Text(context.t('common.unlock')),
              ),
            ],
          ),
        ),
      );
    }
    return _hasAccounts ? const DashboardScreen() : const OnboardingScreen();
  }
}

/// Exposes translations for tests.
const Map<String, Map<String, String>> appTranslations = translations;
