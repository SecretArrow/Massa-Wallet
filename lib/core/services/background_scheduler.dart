/// WorkManager-based periodic background sync — the DEFAULT background
/// path, replacing the always-on `dataSync` foreground service.
///
/// ## Why this solves the Android 6-hour background limit
///
/// * Android 15 (API 35) caps `dataSync` **foreground services** at 6 h
///   per 24-hour window (`Service.onTimeout()` → forced stop or crash).
///   A WorkManager worker is NOT a foreground service (we never pass
///   `foregroundServiceConfig`), so that cap simply does not apply.
/// * Each worker run is a seconds-long burst: fetch balances → diff →
///   notify → widget payload → auto-compound catch-up. No wakelocks, no
///   persistent process, no notification.
/// * The job is persisted by JobScheduler: it survives reboots and app
///   updates, and Android defers it (never drops it) under battery
///   pressure. Deferral is the price for zero restrictions — and users
///   who want tighter scheduling can grant the battery-optimization
///   exemption from Settings.
///
/// Minimum period is Android's hard floor of 15 minutes; see
/// [clampToWorkmanagerInterval].
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'background_tick.dart';

/// Unique name of the periodic job (used to cancel/replace it).
const String kPeriodicSyncUniqueName = 'pine.background.sync';

/// Task name delivered to the dispatcher.
const String kPeriodicSyncTaskName = 'pine.background.sync.tick';

@pragma('vm:entry-point')
void backgroundSyncCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Cross-run baseline: the worker isolate is recreated per run, so
      // the last-known balances MUST come from storage.
      final lastBalances = <String, String>{};
      final stored = prefs.getString('bg.lastBalances');
      if (stored != null && stored.isNotEmpty) {
        try {
          final decoded = json.decode(stored) as Map<String, dynamic>;
          lastBalances.addAll(decoded.map((k, v) => MapEntry(k, v.toString())));
        } on Exception {
          // Corrupt baseline — start fresh.
        }
      }

      await runSyncTick(
        prefs,
        lastBalances,
        // Never respawn the embedded node from a background worker —
        // that would burn CPU/memory inside a 15-minute window.
        allowEmbeddedKeepalive: false,
      );
      // runSyncTick already persisted bg.lastBalances + bg.lastTickAt.
      return true;
    } catch (e) {
      // Returning true prevents JobScheduler retry-spam; the next
      // periodic run will try again anyway.
      debugPrint('background sync worker failed: $e');
      return true;
    }
  });
}

/// Schedules / cancels the periodic sync job.
class BackgroundScheduler {
  bool _initialized = false;

  /// Initializes WorkManager once. Best-effort: on platforms without the
  /// plugin (host unit tests, iOS) this silently no-ops.
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await Workmanager().initialize(backgroundSyncCallbackDispatcher);
      _initialized = true;
    } catch (e) {
      // Catch-all: platform plugins may throw Errors (UnsupportedError),
      // never let scheduling break app startup.
      debugPrint('Workmanager.initialize failed: $e');
    }
  }

  /// Registers (or updates) the periodic sync job with the user's
  /// interval, clamped to Android's 15-minute floor. Network-constrained
  /// so workers never run without connectivity.
  Future<void> enablePeriodic(int intervalSeconds) async {
    await initialize();
    try {
      await Workmanager().registerPeriodicTask(
        kPeriodicSyncUniqueName,
        kPeriodicSyncTaskName,
        frequency: Duration(
          seconds: clampToWorkmanagerInterval(intervalSeconds),
        ),
        constraints: Constraints(networkType: NetworkType.connected),
        // `update` replaces an existing registration so interval changes
        // take effect immediately (unlike `keep`).
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
    } catch (e) {
      debugPrint('registerPeriodicTask failed: $e');
    }
  }

  /// Cancels the periodic sync job.
  Future<void> disablePeriodic() async {
    await initialize();
    try {
      await Workmanager().cancelByUniqueName(kPeriodicSyncUniqueName);
    } catch (e) {
      debugPrint('cancelByUniqueName failed: $e');
    }
  }

  /// Whether the periodic job is currently scheduled (Android only).
  Future<bool> isScheduled() async {
    try {
      await initialize();
      return await Workmanager().isScheduledByUniqueName(
        kPeriodicSyncUniqueName,
      );
    } catch (e) {
      debugPrint('isScheduledByUniqueName failed: $e');
      return false;
    }
  }
}
