/// Pyramids Wallet — per-feature end-to-end tests (real device/emulator).
///
/// Run via `flutter test integration_test` (see .github/workflows/e2e.yml).
///
/// Coverage — one test per feature surface:
///  1. onboarding: create wallet → backup sheet → dashboard
///  2. dashboard: balance card + feature tiles
///  3. settings: theme switch (dark / light / system)
///  4. settings: language switch (EN → ID → EN)
///  5. receive: address + QR code
///  6. send: recipient validation error
///  7. staking screen
///  8. contracts screen
///  9. deferred calls screen
/// 10. history (activity) screen
/// 11. MRC-20 tokens screen
/// 12. address book: add contact flow
/// 13. node: connection mode selection
/// 14. dApp browser: start page with curated sites
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:massa_wallet/app.dart';
import 'package:massa_wallet/core/i18n/app_i18n.dart' show AppLanguage;
import 'package:massa_wallet/core/services/embedded_node_service.dart';
import 'package:massa_wallet/core/services/security_service.dart';
import 'package:massa_wallet/core/services/settings_provider.dart';
import 'package:massa_wallet/core/services/wallet_provider.dart';
import 'package:massa_wallet/core/services/wallet_repository.dart';
import 'package:massa_wallet/features/onboarding/onboarding_screen.dart';
import 'package:massa_wallet/features/wallet/dashboard_screen.dart';
import 'package:massa_wallet/ui/widgets.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory secure-storage backing store (used when the stub intercepts).
final Map<String, String> _store = {};

/// Pumps frames for [duration] in small steps. Unlike `pumpAndSettle`
/// this tolerates endless animations (RPC spinners).
Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps until [finder] locates at least one widget, or [timeout] elapses.
Future<bool> _waitUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 12),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return true;
  }
  return finder.evaluate().isNotEmpty;
}

/// Stubs the flutter_secure_storage method channels with [_store].
///
/// flutter_secure_storage >=10 may use a platform-specific channel; the
/// real plugin on a fresh emulator is a valid fallback either way —
/// [_resetPersistentState] also wipes real storage via the repository.
void _stubSecureStorage() {
  for (final name in const [
    'flutter_secure_storage',
    'plugins.it_nomads.com/flutter_secure_storage',
  ]) {
    final channel = MethodChannel(name);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'read':
              final args = call.arguments as Map;
              return _store[args['key'] as String];
            case 'write':
              final args = call.arguments as Map;
              _store[args['key'] as String] = args['value'] as String;
              return null;
            case 'delete':
              final args = call.arguments as Map;
              _store.remove(args['key'] as String);
              return null;
            case 'readAll':
              return Map<String, String>.of(_store);
            case 'deleteAll':
              _store.clear();
              return null;
            default:
              return null;
          }
        });
  }
}

/// Wipes every persistent surface so each test starts from defaults:
/// secure storage (stubbed or real), SharedPreferences (language, theme,
/// node mode) and any wallets left by previous runs on this device.
Future<void> _resetPersistentState() async {
  _store.clear();
  _stubSecureStorage();
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  final repo = WalletRepository();
  for (final account in await repo.listAccounts()) {
    await repo.deleteAccount(account.address);
  }
}

/// Builds the provider tree exactly the way `main()` does.
Widget _appTree(
  SettingsProvider settings,
  SecurityService security,
  WalletProvider wallet,
) {
  final embedded = EmbeddedNodeService(settings: settings);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ChangeNotifierProvider<SecurityService>.value(value: security),
      ChangeNotifierProvider<EmbeddedNodeService>.value(value: embedded),
      ChangeNotifierProvider<WalletProvider>.value(value: wallet),
    ],
    child: const PyramidsWalletApp(),
  );
}

/// Boots the app with no wallet → onboarding screen.
Future<void> _pumpFreshApp(WidgetTester tester) async {
  await _resetPersistentState();
  final settings = SettingsProvider();
  await settings.load();
  await settings.setBiometricRequired(false); // no credentials on CI emulator
  final security = SecurityService(settings: settings);
  final wallet = WalletProvider(
    repository: WalletRepository(),
    settings: settings,
  );
  await tester.pumpWidget(_appTree(settings, security, wallet));
  expect(
    await _waitUntil(tester, find.byType(OnboardingScreen)),
    true,
    reason: 'a fresh install must land on onboarding',
  );
}

typedef SeededApp = (SettingsProvider, WalletProvider);

/// Seeds one wallet into storage, then boots the app → dashboard.
Future<SeededApp> _pumpSeededApp(WidgetTester tester) async {
  await _resetPersistentState();
  final settings = SettingsProvider();
  await settings.load();
  await settings.setBiometricRequired(false); // no credentials on CI emulator
  final security = SecurityService(settings: settings);
  final repo = WalletRepository();
  await repo.createWallet(nickname: 'E2E');
  final wallet = WalletProvider(repository: repo, settings: settings);
  await tester.pumpWidget(_appTree(settings, security, wallet));
  expect(
    await _waitUntil(tester, find.byType(DashboardScreen)),
    true,
    reason: 'a seeded wallet must boot straight into the dashboard',
  );
  return (settings, wallet);
}

/// Pushes a named feature route from the dashboard context.
Future<void> _goto(WidgetTester tester, String route) async {
  final ctx = tester.element(find.byType(DashboardScreen));
  unawaited(Navigator.of(ctx).pushNamed(route));
  await _pumpFor(tester, const Duration(seconds: 1));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // fullyLive: taps generate real pointer events; pumps render real frames.
  // (Set per binding instance below.)

  testWidgets('1. onboarding: create wallet → backup → dashboard', (
    tester,
  ) async {
    IntegrationTestWidgetsFlutterBinding.instance.framePolicy =
        LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    await _pumpFreshApp(tester);

    expect(find.byType(OnboardingScreen), findsOneWidget);

    // Tap "Create new wallet" (keystore encryption may take a while).
    await tester.tap(find.text('Create new wallet'));
    expect(
      await _waitUntil(
        tester,
        find.text('Tap to reveal secret key'),
        timeout: const Duration(seconds: 25),
      ),
      true,
      reason: 'backup sheet must appear after wallet creation',
    );

    // Reveal the secret key (enables the confirm button).
    await tester.tap(find.text('Tap to reveal secret key'));
    await _pumpFor(tester, const Duration(milliseconds: 400));
    await tester.tap(find.byType(FilledButton).last);
    expect(
      await _waitUntil(tester, find.byType(DashboardScreen)),
      true,
      reason: 'confirming the backup sheet lands on the dashboard',
    );
    expect(find.byType(BalanceCard), findsOneWidget);
  });

  testWidgets('2. dashboard: balance card + feature tiles render', (
    tester,
  ) async {
    IntegrationTestWidgetsFlutterBinding.instance.framePolicy =
        LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    await _pumpSeededApp(tester);

    expect(find.byType(BalanceCard), findsOneWidget);
    // Quick actions to every feature surface.
    expect(find.byType(ActionTile), findsAtLeastNWidgets(4));
  });

  testWidgets('3. settings: theme switch dark → light → system', (
    tester,
  ) async {
    IntegrationTestWidgetsFlutterBinding.instance.framePolicy =
        LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final (settings, _) = await _pumpSeededApp(tester);
    await _goto(tester, '/settings');

    expect(find.text('Settings'), findsOneWidget);

    // The theme section sits below the fold on small screens — the
    // settings ListView builds children lazily, so scroll until the
    // segment row exists in the tree.
    await tester.scrollUntilVisible(
      find.byIcon(Icons.light_mode_outlined),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await _pumpFor(tester, const Duration(milliseconds: 400));
    await tester.tap(find.byIcon(Icons.light_mode_outlined));
    await _pumpFor(tester, const Duration(milliseconds: 500));
    expect(settings.themeMode, ThemeMode.light);

    await tester.ensureVisible(find.byIcon(Icons.brightness_auto_outlined));
    await tester.tap(find.byIcon(Icons.brightness_auto_outlined));
    await _pumpFor(tester, const Duration(milliseconds: 500));
    expect(settings.themeMode, ThemeMode.system);

    await tester.ensureVisible(find.byIcon(Icons.dark_mode_outlined));
    await tester.tap(find.byIcon(Icons.dark_mode_outlined));
    await _pumpFor(tester, const Duration(milliseconds: 500));
    expect(settings.themeMode, ThemeMode.dark);

    // Leave system default for the remaining tests.
    await tester.ensureVisible(find.byIcon(Icons.brightness_auto_outlined));
    await tester.tap(find.byIcon(Icons.brightness_auto_outlined));
    await _pumpFor(tester, const Duration(milliseconds: 300));
    expect(settings.themeMode, ThemeMode.system);
  });

  testWidgets('4. settings: language switch EN → ID → EN', (tester) async {
    IntegrationTestWidgetsFlutterBinding.instance.framePolicy =
        LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final (settings, _) = await _pumpSeededApp(tester);
    await _goto(tester, '/settings');

    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('ID'));
    await _pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('Pengaturan'), findsOneWidget);
    expect(settings.language, AppLanguage.indonesian);

    await tester.tap(find.text('EN'));
    await _pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('Settings'), findsOneWidget);
    expect(settings.language, AppLanguage.english);
  });

  testWidgets('5. receive: address + QR code visible', (tester) async {
    IntegrationTestWidgetsFlutterBinding.instance.framePolicy =
        LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    await _pumpSeededApp(tester);
    await _goto(tester, '/receive');

    expect(find.text('Receive MAS'), findsOneWidget);
    // The wallet address starts with "AU" and is selectable/copyable.
    expect(find.textContaining('AU'), findsWidgets);
    expect(find.byType(SelectableText), findsWidgets);
    expect(find.byType(QrImageView), findsOneWidget);
  });

  testWidgets('6. send: invalid recipient shows validation error', (
    tester,
  ) async {
    IntegrationTestWidgetsFlutterBinding.instance.framePolicy =
        LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    await _pumpSeededApp(tester);
    await _goto(tester, '/send');

    expect(find.text('Send MAS'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Recipient address'),
      'not-a-valid-address',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Amount (MAS)'), '1');
    // Close the IME: on a real device it covers the confirm button and
    // would swallow the tap.
    FocusManager.instance.primaryFocus?.unfocus();
    await _pumpFor(tester, const Duration(milliseconds: 500));

    // The confirm button can sit below the fold on small screens.
    final confirm = find.text('Confirm & sign');
    await tester.ensureVisible(confirm);
    await _pumpFor(tester, const Duration(milliseconds: 300));
    await tester.tap(confirm);
    expect(
      await _waitUntil(
        tester,
        find.textContaining('Invalid recipient address'),
        timeout: const Duration(seconds: 6),
      ),
      true,
      reason: 'send must show the invalid-recipient validation error',
    );
  });

  testWidgets('7. staking: screen opens', (tester) async {
    IntegrationTestWidgetsFlutterBinding.instance.framePolicy =
        LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    await _pumpSeededApp(tester);
    await _goto(tester, '/staking');

    expect(find.text('Staking'), findsOneWidget);
  });

  testWidgets('8. contracts: screen opens', (tester) async {
    IntegrationTestWidgetsFlutterBinding.instance.framePolicy =
        LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    await _pumpSeededApp(tester);
    await _goto(tester, '/contracts');

    expect(find.text('Smart contracts'), findsOneWidget);
  });

  testWidgets('9. deferred calls: screen opens', (tester) async {
    IntegrationTestWidgetsFlutterBinding.instance.framePolicy =
        LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    await _pumpSeededApp(tester);
    await _goto(tester, '/deferred');

    expect(find.text('Deferred calls (ASC)'), findsOneWidget);
  });

  testWidgets('10. history: activity screen opens', (tester) async {
    IntegrationTestWidgetsFlutterBinding.instance.framePolicy =
        LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    await _pumpSeededApp(tester);
    await _goto(tester, '/history');

    expect(find.text('Activity'), findsOneWidget);
  });

  testWidgets('11. tokens: MRC-20 screen opens', (tester) async {
    IntegrationTestWidgetsFlutterBinding.instance.framePolicy =
        LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    await _pumpSeededApp(tester);
    await _goto(tester, '/tokens');

    expect(find.text('MRC-20 Tokens'), findsOneWidget);
  });

  testWidgets('12. address book: add contact flow', (tester) async {
    IntegrationTestWidgetsFlutterBinding.instance.framePolicy =
        LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final (_, wallet) = await _pumpSeededApp(tester);
    await _goto(tester, '/addressBook');

    expect(find.text('Address book'), findsOneWidget);

    // Open the add-contact dialog (FAB label or empty-state button).
    await tester.tap(find.text('Add contact').first);
    expect(
      await _waitUntil(tester, find.text('Name')),
      true,
      reason: 'add-contact dialog must open',
    );

    // Fill name + address (use the seeded wallet's own address).
    final address = wallet.activeAccount!.address;
    final fields = find.byType(TextField);
    expect(fields, findsAtLeastNWidgets(2));
    await tester.enterText(fields.first, 'E2E Contact');
    await tester.enterText(fields.last, address);
    // Close the IME so the dialog buttons are reachable.
    FocusManager.instance.primaryFocus?.unfocus();
    await _pumpFor(tester, const Duration(milliseconds: 500));

    // Confirm (dialog FilledButton — last 'Add contact' in the tree).
    await tester.tap(find.text('Add contact').last);
    await _pumpFor(tester, const Duration(seconds: 1));

    expect(find.text('E2E Contact'), findsOneWidget);
  });

  testWidgets('13. node: three connection modes selectable', (tester) async {
    IntegrationTestWidgetsFlutterBinding.instance.framePolicy =
        LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final (settings, _) = await _pumpSeededApp(tester);
    await _goto(tester, '/node');

    expect(
      await _waitUntil(
        tester,
        find.text('Node mode (experimental)'),
        timeout: const Duration(seconds: 6),
      ),
      true,
      reason: 'node screen must open',
    );
    expect(find.text('Public RPC'), findsOneWidget);
    expect(find.text('Custom RPC'), findsOneWidget);
    expect(find.text('Embedded node (in-app)'), findsOneWidget);

    await tester.tap(find.text('Custom RPC'));
    await _pumpFor(tester, const Duration(milliseconds: 500));
    expect(settings.connectionMode, NodeConnectionMode.customRpc);

    // Reset to the default public mode.
    await tester.tap(find.text('Public RPC'));
    await _pumpFor(tester, const Duration(milliseconds: 500));
    expect(settings.connectionMode, NodeConnectionMode.publicRpc);
  });

  testWidgets('14. browser: start page with curated dApps', (tester) async {
    IntegrationTestWidgetsFlutterBinding.instance.framePolicy =
        LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    await _pumpSeededApp(tester);
    await _goto(tester, '/browser');

    // Start page: brand title + curated sections (no WebView yet).
    expect(find.text('Pyramids Wallet'), findsOneWidget);
    expect(find.text('Massa dApps'), findsOneWidget);
    expect(find.text('Massa Explorer'), findsOneWidget);

    // Scroll to the on-chain DeWeb section.
    await tester.scrollUntilVisible(
      find.text('helloworld.massa'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('On-chain DeWeb sites'), findsOneWidget);
  });
}
