/// i18n completeness guard: every locale must carry EXACTLY the same key
/// set as English, with placeholders ({0}, {minutes}…) and line breaks
/// intact — a missing key would otherwise silently fall back to English.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massa_wallet/core/i18n/app_i18n.dart';
import 'package:massa_wallet/core/i18n/translations.dart';

void main() {
  final en = translations['en']!;

  group('registry shape', () {
    test('27 locales registered, one per AppLanguage', () {
      expect(translations, hasLength(27));
      for (final lang in AppLanguage.all) {
        expect(translations.containsKey(lang.code), isTrue,
            reason: 'missing table for ${lang.code}');
      }
      final codes = AppLanguage.all.map((l) => l.code).toSet();
      expect(codes, translations.keys.toSet());
    });

    test('English is present and complete', () {
      expect(en, isNotEmpty);
      expect(AppLanguage.fromCode('en').nativeName, 'English');
      // unknown codes fall back to English
      expect(AppLanguage.fromCode('xx').code, 'en');
      expect(AppLanguage.fromCode('id').code, 'id');
    });
  });

  group('every locale matches the English key set', () {
    for (final lang in AppLanguage.all.skip(1)) {
      test('${lang.code} (${lang.nativeName})', () {
        final table = translations[lang.code]!;
        final missing = en.keys.toSet().difference(table.keys.toSet());
        final extra = table.keys.toSet().difference(en.keys.toSet());
        expect(missing, isEmpty, reason: 'missing keys → EN fallback');
        expect(extra, isEmpty, reason: 'stale keys');

        // placeholders must survive translation
        for (final key in en.keys) {
          final expected = RegExp(r'\{\w+\}').allMatches(en[key]!);
          if (expected.isEmpty) continue;
          for (final m in expected) {
            expect(table[key]!, contains(m.group(0)),
                reason: '$key lost placeholder ${m.group(0)}');
          }
        }

        // multi-line values keep their line breaks
        for (final key in en.keys) {
          final nl = '\n'.allMatches(en[key]!).length;
          final got = '\n'.allMatches(table[key] ?? '').length;
          expect(got, nl, reason: '$key line-break count changed');
          expect((table[key] ?? '').trim(), isNotEmpty);
        }
      });
    }
  });

  group('new seed-phrase keys are translated everywhere', () {
    const seedKeys = [
      'seed.method.seed.title',
      'seed.generate.title',
      'seed.verify.title',
      'seed.import.segment',
      'account.source.seed',
      'settings.language.sub',
    ];
    for (final key in seedKeys) {
      test(key, () {
        expect(en[key], isNotNull);
        for (final lang in AppLanguage.all) {
          final v = translations[lang.code]![key];
          expect(v, isNotNull, reason: '${lang.code} missing $key');
          expect(v!.trim(), isNotEmpty);
        }
      });
    }
    // the example BIP-39 words stay English in every locale
    test('seed.import.hint keeps BIP-39 example words', () {
      for (final lang in AppLanguage.all) {
        expect(translations[lang.code]!['seed.import.hint'],
            contains('abandon'));
      }
    });
  });
}
