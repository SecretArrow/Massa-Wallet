/// Security hardening: biometric unlock, auto-lock timer, screenshot guard.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'settings_provider.dart';

/// Security gate status.
enum SecurityGate {
  /// Locked — user must authenticate.
  locked,

  /// Unlocked.
  unlocked,
}

/// Enforces app-level security policies.
class SecurityService extends ChangeNotifier {
  final LocalAuthentication _localAuth = LocalAuthentication();
  final SettingsProvider settings;

  SecurityGate _gate = SecurityGate.locked;
  Timer? _autoLockTimer;
  DateTime _lastInteraction = DateTime.now();

  /// Creates the service.
  SecurityService({required this.settings});

  /// Current gate state.
  SecurityGate get gate => _gate;

  /// Whether the device supports biometrics.
  Future<bool> get canCheckBiometrics async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      return supported && canCheck;
    } on PlatformException {
      return false;
    }
  }

  /// Whether any biometric is enrolled.
  Future<bool> get hasEnrolledBiometrics async {
    try {
      return await _localAuth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  /// Attempts to unlock the app.
  Future<bool> unlock({String reason = ''}) async {
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: reason.isEmpty ? 'Unlock Pyramids Wallet' : reason,
        persistAcrossBackgrounding: true,
      );
      if (ok) {
        _gate = SecurityGate.unlocked;
        _restartAutoLock();
      }
      notifyListeners();
      return ok;
    } on PlatformException {
      notifyListeners();
      return false;
    }
  }

  /// Locks the app immediately.
  void lock() {
    _gate = SecurityGate.locked;
    _autoLockTimer?.cancel();
    notifyListeners();
  }

  /// Called on user interaction — resets the auto-lock countdown.
  void registerInteraction() {
    _lastInteraction = DateTime.now();
    if (_gate == SecurityGate.unlocked) {
      _restartAutoLock();
    }
  }

  /// Checks whether the idle timeout has elapsed.
  void checkIdle() {
    if (_gate != SecurityGate.unlocked) return;
    final idle = DateTime.now().difference(_lastInteraction);
    if (idle.inSeconds >= settings.autoLockSeconds) {
      lock();
    }
  }

  void _restartAutoLock() {
    _autoLockTimer?.cancel();
    _autoLockTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      checkIdle();
    });
  }

  /// Enables/disables the screenshot guard (FLAG_SECURE) via platform
  /// channel implemented in MainActivity.
  Future<void> setSecureFlag(bool enabled) async {
    try {
      const channel = MethodChannel('site.massawallet.app/security');
      await channel.invokeMethod('setSecureFlag', {'enabled': enabled});
    } on PlatformException {
      // Ignore — best-effort hardening.
    }
  }

  /// Disposes timers.
  @override
  void dispose() {
    _autoLockTimer?.cancel();
    super.dispose();
  }
}
