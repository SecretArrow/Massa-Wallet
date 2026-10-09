import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:massa_wallet/core/i18n/app_i18n.dart';
import 'package:massa_wallet/core/i18n/translations.dart';
import 'package:massa_wallet/ui/theme.dart';
import 'package:massa_wallet/ui/widgets.dart';

void main() {
  group('translations', () {
    test('id and en tables have identical key sets', () {
      final en = translations['en']!.keys.toSet();
      final id = translations['id']!.keys.toSet();
      expect(id, en, reason: 'bilingual tables must stay in sync');
    });

    test('no empty translations', () {
      translations.forEach((lang, table) {
        table.forEach((key, value) {
          expect(value.trim(), isNotEmpty, reason: '$lang/$key is empty');
        });
      });
    });
  });

  group('AppI18n', () {
    testWidgets('resolves id and en strings', (tester) async {
      final notifier = ValueNotifier(AppLanguage.indonesian);
      addTearDown(notifier.dispose);
      await tester.pumpWidget(
        AppI18n(
          notifier: notifier,
          child: MaterialApp(
            home: Builder(
              builder: (context) =>
                  Scaffold(body: Text(context.t('wallet.send'))),
            ),
          ),
        ),
      );
      expect(find.text('Kirim'), findsOneWidget);

      notifier.value = AppLanguage.english;
      await tester.pump();
      expect(find.text('Send'), findsOneWidget);
    });
  });

  group('widgets', () {
    testWidgets('BalanceCard hides balance in privacy mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: BalanceCard(balance: '12.34', hidden: true),
          ),
        ),
      );
      expect(find.text('••••••'), findsOneWidget);
      expect(find.text('12.34'), findsNothing);
    });

    testWidgets('BalanceCard shows balance', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: BalanceCard(balance: '12.34')),
        ),
      );
      expect(find.text('12.34'), findsOneWidget);
      expect(find.text('MAS'), findsOneWidget);
    });

    testWidgets('ActionTile triggers onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActionTile(
              icon: Icons.send,
              label: 'Send',
              onTap: () => tapped = true,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(ActionTile));
      expect(tapped, isTrue);
    });
  });
}
