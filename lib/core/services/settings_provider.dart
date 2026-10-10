/// App settings state (network, language, security, background sync).
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/massa_rpc.dart';
import '../i18n/app_i18n.dart' show AppLanguage;

/// How the wallet reaches the Massa network.
enum NodeConnectionMode {
  /// Official public RPC endpoints (light client, default).
  publicRpc,

  /// A user-operated massa-node reachable over HTTP (LAN/VPS/Termux).
  customRpc,

  /// A real massa-node binary bundled in the APK and executed inside the
  /// app sandbox (loopback RPC only). Buildnet only.
  embedded,
}

/// Resolves the effective JSON-RPC v2 endpoint from persisted settings.
///
/// Pure function shared between the UI isolate, the background service
/// isolate and tests.
String resolveEndpoint({
  required String mode,
  required String customUrl,
  required String defaultUrl,
  required String embeddedUrl,
  required bool embeddedUsable,
}) {
  switch (mode) {
    case 'customRpc':
      if (customUrl.isNotEmpty) return customUrl;
      return defaultUrl;
    case 'embedded':
      // The embedded binary is buildnet-only; on mainnet fall back to the
      // public RPC rather than pointing users at the wrong chain.
      if (embeddedUsable) return embeddedUrl;
      return defaultUrl;
    default:
      return defaultUrl;
  }
}

/// App-wide settings, persisted via SharedPreferences.
class SettingsProvider extends ChangeNotifier {
  static const _kNetwork = 'settings.network';
  static const _kLanguage = 'settings.language';
  static const _kAutoLockSeconds = 'settings.autoLock';
  static const _kBiometricRequired = 'settings.biometricRequired';
  static const _kBackgroundSync = 'settings.backgroundSync';
  static const _kSyncInterval = 'settings.syncInterval';
  static const _kHideBalances = 'settings.hideBalances';
  static const _kCustomNodeUrl = 'settings.customNodeUrl';
  static const _kUseCustomNode = 'settings.useCustomNode';
  static const _kThemeMode = 'settings.themeMode';
  static const _kShowFiat = 'settings.showFiat';
  static const _kAutoCompound = 'ac.enabled';
  static const _kConnectionMode = 'settings.connectionMode';

  /// Loopback API v2 port exposed by the embedded node.
  static const embeddedApiPort = 33036;

  SharedPreferences? _prefs;

  MassaNetwork _network = MassaNetwork.buildnet;
  AppLanguage _language = AppLanguage.indonesian;
  int _autoLockSeconds = 120;
  bool _biometricRequired = true;
  bool _backgroundSync = true;
  int _syncIntervalSeconds = 300;
  bool _hideBalances = false;
  String _customNodeUrl = '';
  bool _useCustomNode = false;
  NodeConnectionMode _connectionMode = NodeConnectionMode.publicRpc;
  ThemeMode _themeMode = ThemeMode.dark;
  bool _showFiat = true;
  bool _autoCompound = false;

  /// Active network.
  MassaNetwork get network => _network;

  /// UI language.
  AppLanguage get language => _language;

  /// Auto-lock timeout in seconds.
  int get autoLockSeconds => _autoLockSeconds;

  /// Whether biometric/device credential is required to unlock.
  bool get biometricRequired => _biometricRequired;

  /// Whether background balance sync runs.
  bool get backgroundSync => _backgroundSync;

  /// Background sync interval seconds.
  int get syncIntervalSeconds => _syncIntervalSeconds;

  /// Whether balances are hidden (privacy mode).
  bool get hideBalances => _hideBalances;

  /// Custom node endpoint URL (custom RPC mode).
  String get customNodeUrl => _customNodeUrl;

  /// Legacy flag kept for existing callers: true in custom RPC mode.
  bool get useCustomNode => _connectionMode == NodeConnectionMode.customRpc;

  /// Selected connection mode.
  NodeConnectionMode get connectionMode => _connectionMode;

  /// Loopback endpoint served by the embedded node (API v2).
  String get embeddedEndpoint =>
      'http://127.0.0.1:$embeddedApiPort/api/v2';

  /// Whether the embedded node can serve the currently selected network
  /// (the bundled binary targets buildnet only).
  bool get embeddedUsable => _network == MassaNetwork.buildnet;

  /// Active theme mode (dark / light / system).
  ThemeMode get themeMode => _themeMode;

  /// Whether the fiat equivalent is shown on the dashboard.
  bool get showFiat => _showFiat;

  /// Whether roll auto-compound is enabled (shares the `ac.enabled` key
  /// with AutoCompoundService).
  bool get autoCompoundEnabled => _autoCompound;

  /// Effective RPC endpoint in use.
  String get effectiveEndpoint => resolveEndpoint(
        mode: _connectionMode.name,
        customUrl: _customNodeUrl,
        defaultUrl: _network.apiUrl,
        embeddedUrl: embeddedEndpoint,
        embeddedUsable: embeddedUsable,
      );

  /// Loads persisted settings.
  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;
    _network = p.getString(_kNetwork) == 'mainnet'
        ? MassaNetwork.mainnet
        : MassaNetwork.buildnet;
    _language = p.getString(_kLanguage) == 'en'
        ? AppLanguage.english
        : AppLanguage.indonesian;
    _autoLockSeconds = p.getInt(_kAutoLockSeconds) ?? 120;
    _biometricRequired = p.getBool(_kBiometricRequired) ?? true;
    _backgroundSync = p.getBool(_kBackgroundSync) ?? true;
    _syncIntervalSeconds = p.getInt(_kSyncInterval) ?? 300;
    _hideBalances = p.getBool(_kHideBalances) ?? false;
    _customNodeUrl = p.getString(_kCustomNodeUrl) ?? '';
    _useCustomNode = p.getBool(_kUseCustomNode) ?? false;
    final legacyMode = _useCustomNode
        ? NodeConnectionMode.customRpc
        : NodeConnectionMode.publicRpc;
    _connectionMode = switch (p.getString(_kConnectionMode)) {
      'customRpc' => NodeConnectionMode.customRpc,
      'embedded' => NodeConnectionMode.embedded,
      'publicRpc' => NodeConnectionMode.publicRpc,
      // Migration from v1.2.0 (useCustomNode bool) — falls back to legacy.
      null || _ => legacyMode,
    };
    _themeMode = switch (p.getString(_kThemeMode)) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    _showFiat = p.getBool(_kShowFiat) ?? true;
    _autoCompound = p.getBool(_kAutoCompound) ?? false;
    notifyListeners();
  }

  Future<void> _set(String key, Object value) async {
    final p = _prefs;
    if (p == null) return;
    if (value is String) await p.setString(key, value);
    if (value is bool) await p.setBool(key, value);
    if (value is int) await p.setInt(key, value);
    notifyListeners();
  }

  /// Switches network.
  Future<void> setNetwork(MassaNetwork n) async {
    _network = n;
    await _set(_kNetwork, n == MassaNetwork.mainnet ? 'mainnet' : 'buildnet');
  }

  /// Switches language.
  Future<void> setLanguage(AppLanguage l) async {
    _language = l;
    await _set(_kLanguage, l.code);
  }

  /// Sets auto-lock timeout.
  Future<void> setAutoLockSeconds(int s) async {
    _autoLockSeconds = s;
    await _set(_kAutoLockSeconds, s);
  }

  /// Toggles biometric requirement.
  Future<void> setBiometricRequired(bool v) async {
    _biometricRequired = v;
    await _set(_kBiometricRequired, v);
  }

  /// Toggles background sync.
  Future<void> setBackgroundSync(bool v) async {
    _backgroundSync = v;
    await _set(_kBackgroundSync, v);
  }

  /// Sets background sync interval.
  Future<void> setSyncIntervalSeconds(int s) async {
    _syncIntervalSeconds = s;
    await _set(_kSyncInterval, s);
  }

  /// Toggles privacy mode.
  Future<void> setHideBalances(bool v) async {
    _hideBalances = v;
    await _set(_kHideBalances, v);
  }

  /// Saves the custom node URL (custom RPC mode).
  Future<void> setCustomNodeUrl(String url) async {
    _customNodeUrl = url;
    await _set(_kCustomNodeUrl, url);
  }

  /// Switches the connection mode.
  Future<void> setConnectionMode(NodeConnectionMode mode) async {
    _connectionMode = mode;
    await _set(_kConnectionMode, mode.name);
    // Keep the legacy flag coherent for background isolate reads.
    await _set(_kUseCustomNode, mode == NodeConnectionMode.customRpc);
  }

  /// Switches theme mode.
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _set(_kThemeMode, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
      _ => 'dark',
    });
  }

  /// Toggles fiat value display.
  Future<void> setShowFiat(bool v) async {
    _showFiat = v;
    await _set(_kShowFiat, v);
  }

  /// Toggles roll auto-compound.
  Future<void> setAutoCompound(bool v) async {
    _autoCompound = v;
    await _set(_kAutoCompound, v);
  }
}
