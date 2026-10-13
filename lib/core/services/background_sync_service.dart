/// Legacy always-on background sync via Android foreground service.
///
/// ⚠️ Android 15 (API 35) caps `dataSync` foreground services at **6 hours
/// per 24-hour window** — after that the system calls `Service.onTimeout()`
/// and the app MUST stop, or Android throws
/// `ForegroundServiceDidNotStopInTimeException` and the process crashes.
///
/// Therefore this service is ONLY offered on Android ≤ 14 (SDK < 35),
/// and even there it self-caps at 5.5 h per 24 h window (see
/// [FgsRuntimeBudget]) so it always stops before the system kills it.
/// The DEFAULT background path is WorkManager (see BackgroundScheduler),
/// which is not an FGS and has no such cap.
///
/// The actual work lives in `background_tick.dart` — shared with the
/// WorkManager path so both modes behave identically.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'background_tick.dart';

/// Notification channel id (must match AndroidConfiguration).
const String bgChannelId = 'massa_wallet_bg';

/// Income-alert notification channel.
const String alertChannelId = 'massa_wallet_alerts';

/// Foreground-service notification id.
const int bgNotificationId = 112233;

@pragma('vm:entry-point')
Future<void> _onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final lastBalances = <String, String>{};
  // Restore the cross-isolate baseline so a restart does not re-notify
  // for changes that were already reported.
  try {
    final stored = prefs.getString('bg.lastBalances');
    if (stored != null && stored.isNotEmpty) {
      final decoded = json.decode(stored) as Map<String, dynamic>;
      lastBalances.addAll(decoded.map((k, v) => MapEntry(k, v.toString())));
    }
  } on Exception {
    // Corrupt baseline — start fresh (worst case: one extra notification).
  }

  // Runtime accounting: begin a session; if the 24 h window is spent,
  // stop immediately instead of waiting for the system kill.
  final budget = FgsRuntimeBudget.fromPrefs(prefs);
  budget.startSession(DateTime.now());
  await budget.save(prefs);
  if (budget.exhausted()) {
    debugPrint('FGS budget exhausted — stopping service');
    await prefs.setBool('fgs.stopRequested', true);
    service.invoke('stopService');
    return;
  }

  // 30-second supervisor loop: honors the user interval, checkpoints the
  // runtime budget, and updates the notification line.
  await runSyncTick(prefs, lastBalances, allowEmbeddedKeepalive: true);
  await budget.checkpoint(prefs);
  var elapsed = 0;
  Timer.periodic(const Duration(seconds: 30), (timer) async {
    elapsed += 30;
    try {
      final interval = prefs.getInt('settings.syncInterval') ?? 300;
      if (elapsed >= interval) {
        elapsed = 0;
        await runSyncTick(prefs, lastBalances, allowEmbeddedKeepalive: true);
        // Close + persist the session every tick so process death never
        // loses accounting, then keep counting.
        await budget.checkpoint(prefs);
        budget.startSession(DateTime.now());
        if (budget.exhausted()) {
          debugPrint('FGS self-cap reached — graceful stop before 6 h kill');
          await prefs.setBool('fgs.stopRequested', true);
          timer.cancel();
          service.invoke('stopService');
          return;
        }
      }
      if (service is AndroidServiceInstance) {
        if (await service.isForegroundService()) {
          final now = DateTime.now();
          unawaited(
            service.setForegroundNotificationInfo(
              title: 'Pine Wallet',
              content:
                  'Sync active · last '
                  '${now.hour}:${now.minute.toString().padLeft(2, '0')}',
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('FGS loop tick failed: $e');
    }
  });
}

/// App-facing wrapper around the legacy foreground service.
class BackgroundSyncService {
  final FlutterBackgroundService _service = FlutterBackgroundService();

  /// Initializes notification channels and configures the service.
  /// Safe to call on any Android version — callers gate [start] with
  /// [foregroundSyncAllowed].
  Future<void> configure({
    required bool autoStart,
    required String title,
    required String content,
  }) async {
    const channel = AndroidNotificationChannel(
      bgChannelId,
      'Pine Wallet background sync',
      description: 'Keeps balances fresh in the background',
      importance: Importance.low,
    );
    const alertChannel = AndroidNotificationChannel(
      alertChannelId,
      'Pine Wallet alerts',
      description: 'Balance change and staking alerts',
      importance: Importance.high,
    );
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(alertChannel);

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        isForegroundMode: true,
        autoStart: autoStart,
        autoStartOnBoot: autoStart,
        notificationChannelId: bgChannelId,
        initialNotificationTitle: title,
        initialNotificationContent: content,
        foregroundServiceTypes: [AndroidForegroundType.dataSync],
      ),
      iosConfiguration: IosConfiguration(),
    );
  }

  /// Starts the sync service.
  Future<bool> start() => _service.startService();

  /// Stops the sync service.
  Future<void> stop() async {
    _service.invoke('stopService');
  }

  /// Whether the service is running.
  Future<bool> isRunning() => _service.isRunning();

  /// Stream of balance-update events from the service isolate.
  Stream<dynamic> get onBalancesUpdated => _service.on('balances_updated');
}
