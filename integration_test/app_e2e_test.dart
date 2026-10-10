/// End-to-end test: onboarding → dashboard flow on a real device/emulator.
///
/// Run via `flutter test integration_test` (see .github/workflows/e2e.yml).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:massa_wallet/app.dart';
import 'package:massa_wallet/core/services/security_service.dart';
import 'package:massa_wallet/core/services/settings_provider.dart';
import 'package:massa_wallet/core/services/wallet_provider.dart';
import 'package:massa_wallet/core/services/wallet_repository.dart';
import 'package:massa_wallet/features/onboarding/onboarding_screen.dart';
import 'package:massa_wallet/ui/widgets.dart';
import 'package:provider/provider.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('create wallet → dashboard shows balance card', (tester) async {
    const channel = MethodChannel('flutter_secure_storage');
    // In-memory secure storage stub.
    final store = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'read':
              return store[call.arguments['key'] as String];
            case 'write':
              store[call.arguments['key'] as String] =
                  call.arguments['value'] as String;
              return null;
            case 'delete':
              store.remove(call.arguments['key'] as String);
              return null;
            case 'readAll':
              return Map<String, String>.of(store);
            case 'deleteAll':
              store.clear();
              return null;
            default:
              return null;
          }
        });

    final settings = SettingsProvider();
    final security = SecurityService(settings: settings);
    // Disable biometric gate for the test environment.
    await settings.load();
    await settings.setBiometricRequired(false);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<SecurityService>.value(value: security),
          ChangeNotifierProvider<WalletProvider>(
            create: (_) => WalletProvider(
              repository: WalletRepository(),
              settings: settings,
            ),
          ),
        ],
        child: const PyramidsWalletApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Onboarding screen should be visible.
    expect(find.byType(OnboardingScreen), findsOneWidget);

    // Tap "Create wallet".
    final createButton = find.byType(FilledButton).first;
    await tester.tap(createButton);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Backup sheet appears with a secret key pattern.
    expect(find.textContaining('S1'), findsWidgets);

    // Confirm "I saved it" (button becomes enabled after reveal tap).
    final revealTile = find.textContaining('S1').first;
    await tester.tap(revealTile);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Dashboard: balance card exists.
    expect(find.byType(BalanceCard), findsOneWidget);
  });
}
