/// Lightweight bilingual i18n (Bahasa Indonesia / English).
///
/// Chosen over `gen-l10n` so unit/widget tests and CI need no codegen
/// step. Keys are grouped in [AppStrings] for compile-time safety.
library;

import 'package:flutter/material.dart';

import 'translations.dart';

/// UI language.
enum AppLanguage {
  /// English.
  english('en'),

  /// Bahasa Indonesia.
  indonesian('id');

  const AppLanguage(this.code);

  /// ISO code.
  final String code;
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
  /// Translate a key.
  String t(String key) => AppI18n.t(this, key);
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
}
