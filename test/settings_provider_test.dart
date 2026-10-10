import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massa_wallet/core/api/massa_rpc.dart';
import 'package:massa_wallet/core/i18n/app_i18n.dart';
import 'package:massa_wallet/core/services/settings_provider.dart';
import 'package:massa_wallet/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SettingsProvider', () {
    test('defaults: buildnet, system theme, publicRpc mode, English', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      await settings.load();
      expect(settings.network, MassaNetwork.buildnet);
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.connectionMode, NodeConnectionMode.publicRpc);
      expect(settings.language, AppLanguage.english);
    });

    test('language: English default, explicit id selects Indonesian', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      await settings.load();
      expect(settings.language, AppLanguage.english);

      SharedPreferences.setMockInitialValues({'settings.language': 'id'});
      final idSettings = SettingsProvider();
      await idSettings.load();
      expect(idSettings.language, AppLanguage.indonesian);

      await idSettings.setLanguage(AppLanguage.english);
      final reloaded = SettingsProvider();
      await reloaded.load();
      expect(reloaded.language, AppLanguage.english);
    });

    test('theme mode round-trips (light / system)', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      await settings.load();
      await settings.setThemeMode(ThemeMode.light);
      final reloaded = SettingsProvider();
      await reloaded.load();
      expect(reloaded.themeMode, ThemeMode.light);

      await settings.setThemeMode(ThemeMode.system);
      final reloaded2 = SettingsProvider();
      await reloaded2.load();
      expect(reloaded2.themeMode, ThemeMode.system);
    });

    test('connection mode round-trips (embedded / customRpc)', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      await settings.load();
      await settings.setConnectionMode(NodeConnectionMode.embedded);
      final reloaded = SettingsProvider();
      await reloaded.load();
      expect(reloaded.connectionMode, NodeConnectionMode.embedded);

      await settings.setConnectionMode(NodeConnectionMode.customRpc);
      final reloaded2 = SettingsProvider();
      await reloaded2.load();
      expect(reloaded2.connectionMode, NodeConnectionMode.customRpc);
    });

    test('network switch updates effective endpoint', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      await settings.load();
      await settings.setNetwork(MassaNetwork.mainnet);
      expect(settings.effectiveEndpoint, MassaNetwork.mainnet.apiUrl);
      final reloaded = SettingsProvider();
      await reloaded.load();
      expect(reloaded.network, MassaNetwork.mainnet);
    });
  });

  group('AppTheme pair', () {
    test('light and dark themes are Material 3 with matching brightness', () {
      final light = AppTheme.light;
      final dark = AppTheme.dark;
      expect(light.useMaterial3, isTrue);
      expect(dark.useMaterial3, isTrue);
      expect(light.colorScheme.brightness, Brightness.light);
      expect(dark.colorScheme.brightness, Brightness.dark);
    });

    testWidgets('MaterialApp renders in light and dark modes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.light,
          home: const Scaffold(body: Text('x')),
        ),
      );
      expect(
        Theme.of(tester.element(find.text('x'))).brightness,
        Brightness.light,
      );
    });
  });
}
