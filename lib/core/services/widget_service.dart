/// Homescreen balance widget bridge (Android).
///
/// The Kotlin `MassaWidgetProvider` (AppWidgetProvider) reads the JSON
/// blob written by this service from `FlutterSharedPreferences`
/// (key `flutter.massa_widget`) and renders it via RemoteViews. Dart
/// refreshes the data after every balance sync; a MethodChannel nudge
/// (`site.massawallet.app/widget` → `refresh`) forces an immediate
/// redraw. The widget also self-updates every 30 minutes (see
/// `massa_widget_info.xml`).
///
/// Payload:
/// ```json
/// {"balance":"12.3456","rolls":"3","address":"AU1…","network":"Buildnet",
///  "updatedAt":"2026-…","hideBalances":false}
/// ```
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Platform channel id (must match MainActivity.kt).
const MethodChannel _widgetChannel = MethodChannel('site.massawallet.app/widget');

/// Writes widget data + asks Android to redraw all wallet widgets.
///
/// Best-effort: silently no-ops on non-Android platforms or when the
/// engine is not attached (e.g. tests).
Future<void> updateBalanceWidget({
  required String balance,
  required BigInt rolls,
  required String address,
  required String network,
  required bool hideBalances,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'massa_widget',
      json.encode({
        'balance': balance,
        'rolls': rolls.toString(),
        'address': address,
        'network': network,
        'updatedAt': DateTime.now().toIso8601String(),
        'hideBalances': hideBalances,
      }),
    );
    await _widgetChannel.invokeMethod<void>('refresh');
  } on MissingPluginException {
    // Platform channel unavailable (test / non-Android) — ignore.
  } on PlatformException {
    // Engine not attached yet — ignore, next sync will retry.
  }
}
