/// App settings state (network, language, security, background sync).
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/massa_rpc.dart';
import '../i18n/app_i18n.dart' show AppLanguage;

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

  /// Custom node endpoint URL (experimental node mode).
  String get customNodeUrl => _customNodeUrl;

  /// Whether the wallet talks to the custom node instead of public RPC.
  bool get useCustomNode => _useCustomNode;

  /// Effective RPC endpoint in use.
  String get effectiveEndpoint => _useCustomNode && _customNodeUrl.isNotEmpty
      ? _customNodeUrl
      : _network.apiUrl;

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

  /// Configures experimental node mode.
  Future<void> setCustomNode({
    required String url,
    required bool enable,
  }) async {
    _customNodeUrl = url;
    _useCustomNode = enable;
    await _set(_kCustomNodeUrl, url);
    await _set(_kUseCustomNode, enable);
  }
}
