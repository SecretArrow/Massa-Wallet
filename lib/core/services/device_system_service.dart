/// Device/system information via a thin MethodChannel
/// (`site.massawallet.app/system`), used for background-sync reliability:
///
/// * [androidSdkInt] — gates the legacy foreground service (Android 15+
///   caps dataSync FGS at 6 h/day, so it is hidden there).
/// * [isIgnoringBatteryOptimizations] / [requestIgnoreBatteryOptimizations]
///   — lets the user lift Doze/App-Standby deferrals for WorkManager with
///   the official system dialog (no hacky intent loops).
///
/// All calls fail soft: on unsupported platforms (host unit tests, iOS)
/// they return neutral defaults instead of throwing.
library;

import 'package:flutter/services.dart';

/// Default channel name (matches MainActivity.kt).
const String systemChannelName = 'site.massawallet.app/system';

/// MethodChannel wrapper for background-reliability system queries.
class DeviceSystemService {
  final MethodChannel _channel;

  /// Creates the service; override [channel] in tests if needed.
  DeviceSystemService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(systemChannelName);

  /// Android SDK version, or 0 when unavailable (host tests / iOS).
  Future<int> androidSdkInt() async {
    try {
      return await _channel.invokeMethod<int>('androidSdkInt') ?? 0;
    } on PlatformException {
      return 0;
    } on MissingPluginException {
      return 0;
    }
  }

  /// Whether this app is exempt from battery optimizations (Doze /
  /// App Standby deferrals), i.e. "Unrestricted" battery usage.
  Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      return await _channel.invokeMethod<bool>(
            'isIgnoringBatteryOptimizations',
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens the official system dialog asking the user to allow
  /// unrestricted battery usage. Returns false when unavailable.
  Future<bool> requestIgnoreBatteryOptimizations() async {
    try {
      return await _channel.invokeMethod<bool>(
            'requestIgnoreBatteryOptimizations',
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
