/// App root: providers, routing, lock gate.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/i18n/app_i18n.dart';
import 'core/i18n/translations.dart' show translations;
import 'core/services/background_scheduler.dart';
import 'core/services/background_sync_service.dart';
import 'core/services/background_tick.dart' show foregroundSyncAllowed;
import 'core/services/device_system_service.dart';
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
import 'ui/home_shell.dart';
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
  SettingsProvider? _observedSettings;

  /// Background-sync coordinator state (null until first apply).
  BackgroundScheduler? _scheduler;
  (bool, bool, int)? _lastAppliedSync;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final settings = context.read<SettingsProvider>();
    final security = context.read<SecurityService>();
    // Keep the i18n notifier in sync OUTSIDE the build phase — mutating a
    // ValueNotifier during build throws "markNeedsBuild called during
    // build" whenever the user switches language at runtime.
    _observedSettings = settings;
    settings.addListener(_onSettingsChanged);
    settings.load().then((_) {
      _language.value = settings.language;
      security.setSecureFlag(true);
      unawaited(_applyBackgroundSync());
    });
  }

  void _onSettingsChanged() {
    final settings = _observedSettings;
    if (settings != null && _language.value != settings.language) {
      _language.value = settings.language;
    }
    // Re-apply the sync topology when one of the relevant settings
    // changed (toggle / interval / realtime switch).
    final tuple = (
      settings?.backgroundSync ?? true,
      settings?.realtimeSync ?? false,
      settings?.syncIntervalSeconds ?? 300,
    );
    if (tuple != _lastAppliedSync && _lastAppliedSync != null) {
      unawaited(_applyBackgroundSync());
    }
  }

  /// Decides and applies which background path runs:
  ///
  /// * realtime switch ON + Android ≤ 14 → legacy always-on foreground
  ///   service (no 6 h cap below Android 15); WorkManager cancelled.
  /// * otherwise → WorkManager periodic (the DEFAULT; a dataSync FGS on
  ///   Android 15+ would be limited to 6 h/day and crash on timeout).
  /// * periodic switch OFF → nothing scheduled.
  Future<void> _applyBackgroundSync() async {
    try {
      final settings = context.read<SettingsProvider>();
      final tuple = (
        settings.backgroundSync,
        settings.realtimeSync,
        settings.syncIntervalSeconds,
      );
      _lastAppliedSync = tuple;
      _scheduler ??= BackgroundScheduler();
      final service = BackgroundSyncService();
      await service.configure(
        autoStart: false,
        title: 'Pyramids Wallet',
        content: 'Balance sync active',
      );
      final sdk = await DeviceSystemService().androidSdkInt();
      final realtimeAllowed = foregroundSyncAllowed(sdk);
      if (settings.realtimeSync && realtimeAllowed) {
        // Always-on FGS covers everything — no periodic worker needed.
        await _scheduler!.disablePeriodic();
        await service.start();
      } else {
        // Stop any FGS (also fixes stale auto-start config from older
        // versions) and use WorkManager instead.
        await service.stop();
        if (settings.backgroundSync) {
          await _scheduler!.enablePeriodic(settings.syncIntervalSeconds);
        } else {
          await _scheduler!.disablePeriodic();
        }
      }
    } catch (e) {
      // Background sync is best-effort — even platform Errors (missing
      // plugin on tests, iOS UnsupportedError) must never break startup.
      debugPrint('background sync apply failed: $e');
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
      // Sync-on-open: the most reliable path there is (no OS quota
      // applies in the foreground). Cheap — refreshBalances no-ops
      // without accounts.
      try {
        unawaited(context.read<WalletProvider>().refreshBalances());
      } catch (_) {
        // Never let a refresh error break the lock flow.
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _observedSettings?.removeListener(_onSettingsChanged);
    _language.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppI18n(
      notifier: _language,
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          // NOTE: never mutate _language here — build-phase notifications
          // throw; sync happens via _onSettingsChanged instead.
          return MaterialApp(
            title: 'Pyramids Wallet',
            debugShowCheckedModeBanner: false,
            // MaterialLocalizations must exist for EVERY supported locale —
            // DefaultMaterialLocalizations is English-only, so switching to
            // Indonesian used to break the whole app on real devices
            // (RefreshIndicator/DropdownButton/tooltips threw on build).
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: settings.themeMode,
            locale: Locale(settings.language.code),
            // 27 supported locales — ar/ur/fa get RTL automatically via
            // GlobalWidgetsLocalizations.
            supportedLocales: AppLanguage.locales,
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
              // Post-onboarding / gate landing: bottom-nav shell with
              // Home · History · Browser · More tabs.
              '/home': (_) => const HomeShell(),
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
    return _hasAccounts ? const HomeShell() : const OnboardingScreen();
  }
}

/// Exposes translations for tests.
const Map<String, Map<String, String>> appTranslations = translations;
