/// HomeShell (bottom navigation) widget tests.
///
/// Verifies the 4-destination navigation bar, tab switching, the More
/// tab entries and the i18n of navigation labels.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massa_wallet/core/i18n/app_i18n.dart';
import 'package:massa_wallet/core/services/embedded_node_service.dart';
import 'package:massa_wallet/core/services/settings_provider.dart';
import 'package:massa_wallet/core/services/wallet_provider.dart';
import 'package:massa_wallet/core/services/wallet_repository.dart';
import 'package:massa_wallet/ui/home_shell.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(ValueNotifier<AppLanguage>, SettingsProvider)> pumpShell(
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.load();
    final wallet = WalletProvider(
      repository: WalletRepository(),
      settings: settings,
    );
    final language = ValueNotifier(AppLanguage.english);
    await tester.pumpWidget(
      AppI18n(
        notifier: language,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ChangeNotifierProvider<EmbeddedNodeService>.value(
              value: EmbeddedNodeService(settings: settings),
            ),
            ChangeNotifierProvider<WalletProvider>.value(value: wallet),
          ],
          child: MaterialApp(
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('id'), Locale('en')],
            locale: const Locale('en'),
            home: const HomeShell(),
          ),
        ),
      ),
    );
    // Let post-frame callbacks (balance refresh, price fetch, history
    // load, browser start page) settle. Price fetch fails fast on the
    // test binding's blocked sockets (offline-tolerant).
    await tester.pump(const Duration(milliseconds: 300));
    return (language, settings);
  }

  testWidgets('shell shows a 4-destination navigation bar', (tester) async {
    await pumpShell(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(HomeShell), findsOneWidget);
    // All four tab roots are built (IndexedStack keeps them alive), but
    // default finders only see the ACTIVE tab plus the navigation bar.
    expect(find.text('Home'), findsOneWidget); // nav label
    expect(find.text('History'), findsOneWidget); // nav label
    expect(find.text('Browser'), findsOneWidget); // nav label
    expect(find.text('More'), findsOneWidget); // nav label (app bar hidden)
  });

  testWidgets('tapping destinations switches the selected tab', (tester) async {
    await pumpShell(tester);

    NavigationBar bar() =>
        tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar().selectedIndex, 0);

    await tester.tap(find.text('History'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(bar().selectedIndex, 1);

    await tester.tap(find.text('Browser'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(bar().selectedIndex, 2);

    await tester.tap(find.byIcon(Icons.apps)); // More destination
    await tester.pump(const Duration(milliseconds: 300));
    expect(bar().selectedIndex, 3);

    await tester.tap(find.text('Home'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(bar().selectedIndex, 0);
  });

  testWidgets('More tab lists earn, asset and system entries', (tester) async {
    await pumpShell(tester);

    // Select the More tab first — IndexedStack hides inactive tabs from
    // default finders.
    await tester.tap(find.byIcon(Icons.apps));
    await tester.pump(const Duration(milliseconds: 300));
    // Section headers + subtitles visible at the top of the list.
    expect(find.text('Earn'), findsOneWidget);
    expect(find.text('Assets & tools'), findsOneWidget);
    expect(
      find.text('Buy or sell rolls, auto-compound rewards'),
      findsOneWidget,
    );
    expect(find.text('Schedule deferred ASC executions'), findsOneWidget);
    // 'System' sits below the fold — scroll the More list to it.
    await tester.scrollUntilVisible(find.text('System'), 200);
    expect(find.text('System'), findsOneWidget);
    // Version/network footer at the very bottom.
    await tester.scrollUntilVisible(
      find.textContaining('Pine Wallet ·'),
      200,
    );
    expect(find.textContaining('Pine Wallet ·'), findsOneWidget);
  });

  testWidgets('navigation labels follow the app language', (tester) async {
    final (language, _) = await pumpShell(tester);

    language.value = AppLanguage.indonesian;
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Beranda'), findsOneWidget);
    expect(find.text('Riwayat'), findsOneWidget);
    expect(find.text('Browser'), findsOneWidget);
    expect(find.text('Lainnya'), findsAtLeastNWidgets(1));
    // English labels are gone.
    expect(find.text('Home'), findsNothing);
    expect(find.text('History'), findsNothing);
  });
}
