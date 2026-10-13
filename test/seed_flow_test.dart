/// Seed-phrase creation flow widget test:
/// reveal → confirm → quiz (answers derived from the revealed grid) →
/// wallet created → navigates home.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:massa_wallet/core/i18n/app_i18n.dart';
import 'package:massa_wallet/core/services/embedded_node_service.dart';
import 'package:massa_wallet/core/services/settings_provider.dart';
import 'package:massa_wallet/core/services/wallet_provider.dart';
import 'package:massa_wallet/core/services/wallet_repository.dart';
import 'package:massa_wallet/features/onboarding/seed_create_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/in_memory_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    FlutterSecureStoragePlatform.instance = InMemorySecureStorage();
  });

  Future<List<String>> pumpSeedFlow(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.load();
    final wallet = WalletProvider(
      repository: WalletRepository(),
      settings: settings,
    );
    await tester.pumpWidget(
      AppI18n(
        notifier: ValueNotifier(AppLanguage.english),
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
            supportedLocales: const [Locale('en')],
            locale: const Locale('en'),
            routes: {
              '/seedCreate': (_) => const SeedCreateScreen(),
              '/home': (_) =>
                  const Scaffold(body: Center(child: Text('HOME-STUB'))),
            },
            home: const SeedCreateScreen(),
          ),
        ),
      ),
    );
    await tester.pump();

    // Read the 12 hidden words by revealing all, extracting the RichText
    // spans (word tiles are the only RichTexts shaped [number, word] —
    // plain Text widgets also emit RichTexts, so filter precisely), then
    // the grid order is deterministic.
    await tester.ensureVisible(find.text('Reveal all'));
    await tester.tap(find.text('Reveal all'));
    await tester.pump();
    final tileRichTexts = tester
        .widgetList<RichText>(
          find.byWidgetPredicate(
            (w) =>
                w is RichText &&
                w.text is TextSpan &&
                ((w.text as TextSpan).children?.length ?? 0) == 2,
          ),
        )
        .toList();
    final words = <String>[];
    for (final rt in tileRichTexts) {
      final span = (rt.text as TextSpan).children![1] as TextSpan;
      words.add(span.text!);
    }
    expect(words, hasLength(12));
    expect(words.every((w) => w.isNotEmpty), isTrue);
    return words;
  }

  testWidgets('quiz success creates the wallet and lands on /home', (
    tester,
  ) async {
    final words = await pumpSeedFlow(tester);

    // Confirm reading → quiz step.
    await tester.ensureVisible(find.text('I wrote the 12 words down'));
    await tester.tap(find.text('I wrote the 12 words down'));
    await tester.pump();

    // Three slot headings tell us which positions are quizzed.
    final headings = tester
        .widgetList<Text>(
          find.byWidgetPredicate(
            (w) => w is Text && (w.data?.contains('#') ?? false),
          ),
        )
        .map((t) => int.parse(t.data!.split('#').last))
        .toList();
    expect(headings, hasLength(3));

    // 18 chips, 6 per slot, in build order.
    final chips =
        tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList();
    expect(chips, hasLength(18));

    for (var slot = 0; slot < 3; slot++) {
      final target = words[headings[slot] - 1];
      final slotChips = chips.sublist(slot * 6, slot * 6 + 6);
      final idx = slotChips.indexWhere(
        (c) => ((c.label as Text?)?.data) == target,
      );
      expect(idx, greaterThanOrEqualTo(0),
          reason: 'slot $slot must offer "$target"');
      await tester.tap(find.byType(ChoiceChip).at(slot * 6 + idx));
      await tester.pump();
    }

    await tester.ensureVisible(find.text('Check answers'));
    await tester.tap(find.text('Check answers'));
    await tester.pumpAndSettle();

    // Wallet created → pushed to /home.
    expect(find.text('HOME-STUB'), findsOneWidget);
  });

  testWidgets('quiz failure regenerates and shows the retry message', (
    tester,
  ) async {
    final words = await pumpSeedFlow(tester);
    await tester.ensureVisible(find.text('I wrote the 12 words down'));
    await tester.tap(find.text('I wrote the 12 words down'));
    await tester.pump();

    final headings = tester
        .widgetList<Text>(
          find.byWidgetPredicate(
            (w) => w is Text && (w.data?.contains('#') ?? false),
          ),
        )
        .map((t) => int.parse(t.data!.split('#').last))
        .toList();

    final chips =
        tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList();

    // Slot 0: pick a chip that is provably WRONG (5 of 6 are distractors).
    final correct0 = words[headings[0] - 1];
    var wrongIdx = 0;
    while (((chips[wrongIdx].label as Text?)?.data) == correct0) {
      wrongIdx++;
    }
    await tester.tap(find.byType(ChoiceChip).at(wrongIdx));
    await tester.pump();
    // Slots 1–2: answer correctly (irrelevant — one wrong answer fails).
    for (var slot = 1; slot < 3; slot++) {
      final target = words[headings[slot] - 1];
      final slotChips = chips.sublist(slot * 6, slot * 6 + 6);
      final idx = slotChips.indexWhere(
        (c) => ((c.label as Text?)?.data) == target,
      );
      await tester.tap(find.byType(ChoiceChip).at(slot * 6 + idx));
      await tester.pump();
    }

    await tester.ensureVisible(find.text('Check answers'));
    await tester.tap(find.text('Check answers'));
    await tester.pump();

    expect(
      find.text('Not quite — review your paper backup and try again'),
      findsOneWidget,
    );
    // Still on the quiz: the check button is back (chips were reset).
    expect(find.text('Check answers'), findsOneWidget);
    expect(find.text('HOME-STUB'), findsNothing);
  });

  testWidgets('confirm button stays disabled until all words revealed', (
    tester,
  ) async {
    await pumpSeedFlow(tester);
    // Reveal only one word.
    await tester.tap(find.byIcon(Icons.visibility_off).first);
    await tester.pump();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'I wrote the 12 words down'),
    );
    expect(button.onPressed, isNull);
  });
}
