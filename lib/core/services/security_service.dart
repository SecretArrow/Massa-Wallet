/// Security hardening: biometric unlock, auto-lock timer, screenshot guard.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'settings_provider.dart';

/// Error codes reported by local_auth that mean "the device has no
/// usable enrolled credential" — in those cases the only sane policy is
/// to fail open (the OS itself cannot protect the device either).
///
/// Pure function (unit-tested). Covers the android (`noCredentialsSet`,
/// `notEnrolled`…), darwin (`noCredentialsSet`…) and plugin-level
/// (`noCredentials`) spellings.
bool shouldFailOpenOnLocalAuthError(String code) {
  const failOpenCodes = <String>{
    'noCredentialsSet',
    'no_credentials',
    'noCredentials',
    'notEnrolled',
    'not_enrolled',
    'noBiometricEnrolled',
    'noneEnrolled',
    'noHardware',
    'no_hardware',
    'notAvailable',
    'not_available',
  };
  return failOpenCodes.contains(code);
}

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

  /// Whether any biometric is actually ENROLLED.
  ///
  /// The previous implementation returned `isDeviceSupported()`, which
  /// only checks hardware support — on a device with biometric hardware
  /// but no enrolled fingerprint/face it reported true, the unlock then
  /// threw `noCredentialsSet` forever and the wallet was bricked on the
  /// lock screen.
  Future<bool> get hasEnrolledBiometrics async {
    try {
      final available = await _localAuth.getAvailableBiometrics();
      return available.isNotEmpty;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Whether the user can authenticate at all (biometrics OR device
  /// credential fallback such as PIN/pattern/password).
  ///
  /// With `biometricOnly: false` (our default) local_auth falls back to
  /// the device credential, so a supported device with a lockscreen is
  /// always authenticatable — even without enrolled biometrics.
  Future<bool> get canAuthenticate async {
    try {
      return await _localAuth.isDeviceSupported();
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Attempts to unlock the app.
  ///
  /// Failure modes:
  /// * biometric/PIN rejected by the user → returns false (retryable via
  ///   the lock-screen button);
  /// * `LocalAuthException` with a no-credentials / not-enrolled code →
  ///   the gate FAILS OPEN and the biometric requirement is switched off
  ///   (the device has no screen lock at all, so demanding app-level
  ///   auth would brick the wallet on the lock screen forever);
  /// * platform-level `PlatformException` → returns false.
  Future<bool> unlock({String reason = ''}) async {
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: reason.isEmpty ? 'Unlock Pyramids Wallet' : reason,
        // NOTE: persistAcrossBackgrounding intentionally NOT set —
        // combined with the lifecycle handler it used to re-prompt in a
        // loop right after the app resumed (the "crazy unlock bug").
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
    } on Exception catch (e) {
      // local_auth throws LocalAuthException (e.g. noCredentialsSet,
      // notEnrolled, permanentlyLockedOut) — fail open when the device
      // simply has no usable credentials, so the user can still get in.
      final code = e is LocalAuthException
          ? e.code.toString()
          : e.runtimeType.toString();
      if (shouldFailOpenOnLocalAuthError(code)) {
        _gate = SecurityGate.unlocked;
        _restartAutoLock();
        unawaited(settings.setBiometricRequired(false));
        notifyListeners();
        return true;
      }
      notifyListeners();
      return false;
    } catch (_) {
      // Unknown auth-subsystem error — never brick the gate.
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

  /// Opens the gate without biometric authentication.
  ///
  /// Used at startup when the biometric requirement is disabled or the
  /// device has no usable biometrics — previously the gate stayed locked
  /// forever in that case, showing the lock screen on every launch.
  void markUnlocked() {
    _gate = SecurityGate.unlocked;
    _lastInteraction = DateTime.now();
    _restartAutoLock();
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
