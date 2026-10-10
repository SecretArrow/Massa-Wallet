/// App root: providers, routing, lock gate.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/i18n/app_i18n.dart';
import 'core/i18n/translations.dart' show translations;
import 'core/services/background_sync_service.dart';
import 'core/services/security_service.dart';
import 'core/services/settings_provider.dart';
import 'core/services/wallet_provider.dart';
import 'features/browser/dapp_browser_screen.dart';
import 'features/contracts/contracts_screen.dart';
import 'features/contracts/deferred_screen.dart';
import 'features/history/address_book_screen.dart';
import 'features/history/history_screen.dart';
import 'features/node/node_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/receive/receive_screen.dart';
import 'features/send/send_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/staking/staking_screen.dart';
import 'features/tokens/tokens_screen.dart';
import 'features/wallet/dashboard_screen.dart';
import 'ui/theme.dart';

/// Pyramids Wallet application widget.
class PyramidsWalletApp extends StatefulWidget {
  /// Creates the app.
  const PyramidsWalletApp({super.key});

  @override
  State<PyramidsWalletApp> createState() => _PyramidsWalletAppState();
}

class _PyramidsWalletAppState extends State<PyramidsWalletApp>
    with WidgetsBindingObserver {
  final ValueNotifier<AppLanguage> _language = ValueNotifier(
    AppLanguage.english,
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
        title: 'Pyramids Wallet',
        content: 'Balance sync active',
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
            title: 'Pyramids Wallet',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: settings.themeMode,
            locale: Locale(settings.language.code),
            supportedLocales: const [Locale('id'), Locale('en')],
            initialRoute: '/',
            // Edge-to-edge: keep system-bar icon brightness correct on
            // screens that have no AppBar (covers the whole navigator).
            builder: (context, child) {
              final platformDark =
                  MediaQuery.platformBrightnessOf(context) == Brightness.dark;
              final dark = switch (settings.themeMode) {
                ThemeMode.light => false,
                ThemeMode.dark => true,
                ThemeMode.system => platformDark,
              };
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: dark ? AppTheme.overlayDark : AppTheme.overlayLight,
                child: child ?? const SizedBox.shrink(),
              );
            },
            routes: {
              '/': (_) => const _RootGate(),
              '/onboarding': (_) => const OnboardingScreen(),
              '/import': (_) => const ImportScreen(),
              '/home': (_) => const DashboardScreen(),
              '/send': (_) => const SendScreen(),
              '/receive': (_) => const ReceiveScreen(),
              '/staking': (_) => const StakingScreen(),
              '/contracts': (_) => const ContractsScreen(),
              '/deferred': (_) => const DeferredCallsScreen(),
              '/node': (_) => const NodeScreen(),
              '/settings': (_) => const SettingsScreen(),
              '/browser': (_) => const DappBrowserScreen(),
              '/tokens': (_) => const TokensScreen(),
              '/history': (_) => const HistoryScreen(),
              '/addressBook': (_) => const AddressBookScreen(),
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
      try {
        final canAuth = await security.canCheckBiometrics;
        if (canAuth) {
          unlocked = await security.unlock();
        } else {
          // Device has no usable biometrics — requiring them here would
          // leave the wallet stuck on the splash forever (LocalAuthException
          // noCredentialsSet). Fail open and stop demanding biometrics so
          // the user can re-enable the toggle after enrolling.
          unawaited(settings.setBiometricRequired(false));
        }
      } catch (_) {
        // Never brick the gate on an auth subsystem error.
        unlocked = true;
      }
    } else {
      // No biometric requirement — open the gate silently. Without this
      // the gate stayed SecurityGate.locked and the lock screen blocked
      // every launch for users with biometrics disabled.
      security.markUnlocked();
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
      // Branded splash: red pyramid logo while accounts are loading.
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/icon/pyramids_logo.png',
                width: 112,
                height: 112,
                filterQuality: FilterQuality.high,
              ),
              const SizedBox(height: 24),
              Text(
                'Pyramids Wallet',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ],
          ),
        ),
      );
    }
    if (_hasAccounts && security.gate == SecurityGate.locked) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock, size: 64, color: PyramidsColors.brand),
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
