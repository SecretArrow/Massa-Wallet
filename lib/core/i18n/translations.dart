/// i18n registry — 27 locales, English is the fallback for missing keys.
///
/// Per-locale tables live in `locales/<code>.dart`. A unit test
/// (`i18n_completeness_test.dart`) enforces that every locale carries
/// exactly the same key set as English, so a missing key can never ship.
library;

import 'locales/en.dart';
import 'locales/id.dart';
import 'locales/zh.dart';
import 'locales/es.dart';
import 'locales/hi.dart';
import 'locales/fr.dart';
import 'locales/ar.dart';
import 'locales/bn.dart';
import 'locales/ru.dart';
import 'locales/pt.dart';
import 'locales/ur.dart';
import 'locales/de.dart';
import 'locales/ja.dart';
import 'locales/mr.dart';
import 'locales/te.dart';
import 'locales/tr.dart';
import 'locales/ta.dart';
import 'locales/vi.dart';
import 'locales/ko.dart';
import 'locales/it.dart';
import 'locales/th.dart';
import 'locales/fa.dart';
import 'locales/pl.dart';
import 'locales/nl.dart';
import 'locales/ms.dart';
import 'locales/tl.dart';
import 'locales/uk.dart';

/// Map: language code → key → localized string.
const Map<String, Map<String, String>> translations = {
  'en': enTranslations,
  'id': idTranslations,
  'zh': zhTranslations,
  'es': esTranslations,
  'hi': hiTranslations,
  'fr': frTranslations,
  'ar': arTranslations,
  'bn': bnTranslations,
  'ru': ruTranslations,
  'pt': ptTranslations,
  'ur': urTranslations,
  'de': deTranslations,
  'ja': jaTranslations,
  'mr': mrTranslations,
  'te': teTranslations,
  'tr': trTranslations,
  'ta': taTranslations,
  'vi': viTranslations,
  'ko': koTranslations,
  'it': itTranslations,
  'th': thTranslations,
  'fa': faTranslations,
  'pl': plTranslations,
  'nl': nlTranslations,
  'ms': msTranslations,
  'tl': tlTranslations,
  'uk': ukTranslations,
};
