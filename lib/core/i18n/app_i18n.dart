/// Lightweight i18n for 27 locales (English + 26 more languages).
///
/// Chosen over `gen-l10n` so unit/widget tests and CI need no codegen
/// step. Keys are grouped in [AppStrings] for compile-time safety.
///
/// Supported languages (native names shown in the picker):
/// English, Bahasa Indonesia, 中文, Español, हिन्दी, Français, العربية,
/// বাংলা, Русский, Português, اردو, Deutsch, 日本語, मराठी, తెలుగు,
/// Türkçe, தமிழ், Tiếng Việt, 한국어, Italiano, ไทย, فارسی, Polski,
/// Nederlands, Bahasa Melayu, Filipino, Українська.
///
/// Arabic, Urdu and Persian are right-to-left — directionality is
/// handled automatically by `GlobalWidgetsLocalizations`.
library;

import 'package:flutter/material.dart';

import 'translations.dart';

/// A UI language descriptor (code + native display name).
class AppLanguage {
  /// ISO 639-1 code, also used as the persistence key.
  final String code;

  /// Endonym shown in the language picker (never translated).
  final String nativeName;

  const AppLanguage(this.code, this.nativeName);

  /// English (default).
  static const AppLanguage english = AppLanguage('en', 'English');

  /// Bahasa Indonesia.
  static const AppLanguage indonesian = AppLanguage('id', 'Bahasa Indonesia');

  /// All supported languages, picker order (English first).
  static const List<AppLanguage> all = [
    english,
    indonesian,
    AppLanguage('zh', '中文（简体）'),
    AppLanguage('es', 'Español'),
    AppLanguage('hi', 'हिन्दी'),
    AppLanguage('fr', 'Français'),
    AppLanguage('ar', 'العربية'),
    AppLanguage('bn', 'বাংলা'),
    AppLanguage('ru', 'Русский'),
    AppLanguage('pt', 'Português'),
    AppLanguage('ur', 'اردو'),
    AppLanguage('de', 'Deutsch'),
    AppLanguage('ja', '日本語'),
    AppLanguage('mr', 'मराठी'),
    AppLanguage('te', 'తెలుగు'),
    AppLanguage('tr', 'Türkçe'),
    AppLanguage('ta', 'தமிழ்'),
    AppLanguage('vi', 'Tiếng Việt'),
    AppLanguage('ko', '한국어'),
    AppLanguage('it', 'Italiano'),
    AppLanguage('th', 'ไทย'),
    AppLanguage('fa', 'فارسی'),
    AppLanguage('pl', 'Polski'),
    AppLanguage('nl', 'Nederlands'),
    AppLanguage('ms', 'Bahasa Melayu'),
    AppLanguage('tl', 'Filipino'),
    AppLanguage('uk', 'Українська'),
  ];

  /// Resolves [code] to a language; unknown codes fall back to English
  /// (graceful migration when a locale is ever retired).
  static AppLanguage fromCode(String code) =>
      all.firstWhere((l) => l.code == code, orElse: () => english);

  /// All locale codes (for `supportedLocales`).
  static List<Locale> get locales =>
      all.map((l) => Locale(l.code)).toList(growable: false);

  @override
  bool operator ==(Object other) => other is AppLanguage && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

/// Locale change notifier + lookup helper.
class AppI18n extends InheritedNotifier<ValueNotifier<AppLanguage>> {
  /// Creates the i18n scope.
  const AppI18n({
    super.key,
    required ValueNotifier<AppLanguage> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Scope of the nearest ancestor.
  static AppI18n of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppI18n>()!;

  /// Translates [key] using the current language.
  static String t(BuildContext context, String key) {
    final scope = of(context);
    return translations[scope.notifier!.value.code]?[key] ??
        translations['en']?[key] ??
        key;
  }
}

/// Convenience extension for `context.t('key')`.
extension AppI18nX on BuildContext {
  /// Translate a key, substituting `{0}`, `{1}`… with [args].
  String t(String key, {List<String> args = const []}) {
    var s = AppI18n.t(this, key);
    for (var i = 0; i < args.length; i++) {
      s = s.replaceAll('{$i}', args[i]);
    }
    return s;
  }
}

/// Compile-time known keys (documentation only — lookup is by string).
abstract final class AppStrings {
  /// App title.
  static const appTitle = 'app.title';

  /// Create wallet.
  static const createWallet = 'wallet.create';

  /// Import wallet.
  static const importWallet = 'wallet.import';

  /// Send.
  static const send = 'wallet.send';

  /// Receive.
  static const receive = 'wallet.receive';

  /// Balance.
  static const balance = 'wallet.balance';

  /// History.
  static const history = 'wallet.history';

  /// Staking.
  static const staking = 'staking.title';

  /// Settings.
  static const settings = 'settings.title';

  /// Seed phrase.
  static const seedPhrase = 'seed.method.seed.title';

  /// Language.
  static const language = 'settings.language';
}
