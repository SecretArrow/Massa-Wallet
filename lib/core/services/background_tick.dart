/// Shared background-sync tick logic.
///
/// One tick is a SHORT burst of work (a few seconds at most):
/// fetch balances → diff against the last known values → notify on
/// change → refresh the homescreen-widget payload → best-effort
/// auto-compound catch-up. Nothing here holds a wakelock or a process
/// alive — by design.
///
/// Both execution paths reuse this file:
///  * `BackgroundScheduler` — WorkManager periodic task (the DEFAULT
///    path; see below for why), and
///  * `BackgroundSyncService` — the legacy always-on foreground service,
///    only offered on Android ≤ 14.
///
/// ## Why the default is WorkManager instead of a foreground service
///
/// Android 15 (API 35) caps `dataSync` foreground services at **6 hours
/// per 24-hour window**. After the budget is spent the system calls
/// `Service.onTimeout()` and the app MUST stop the service — otherwise
/// Android throws `ForegroundServiceDidNotStopInTimeException` and the
/// process crashes. WorkManager workers are NOT foreground services and
/// are therefore not subject to that cap: each worker runs for seconds
/// inside a JobScheduler slot that the OS grants per App-Standby bucket.
/// The trade-off is that WorkManager's minimum period is 15 minutes and
/// the OS may defer work under battery pressure — acceptable for a
/// wallet, where balance updates and income alerts do not need
/// second-level latency.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/massa_models.dart' show AddressInfo;
import '../api/massa_rpc.dart';
import 'auto_compound_service.dart';
import 'embedded_node_service.dart';
import 'settings_provider.dart' show SettingsProvider, resolveEndpoint;
import 'wallet_repository.dart';

/// Minimum interval Android's JobScheduler accepts for periodic work.
const int workmanagerMinIntervalSeconds = 900;

/// WorkManager cannot run more often than every 15 minutes — clamp the
/// user preference so the scheduler request is always valid. The exact
/// interval still applies to the legacy foreground service.
int clampToWorkmanagerInterval(int seconds) =>
    seconds < workmanagerMinIntervalSeconds
    ? workmanagerMinIntervalSeconds
    : seconds;

/// Android 15 (SDK 35) caps `dataSync` foreground services at 6 h/day —
/// the always-on realtime service is therefore only offered below SDK 35.
bool foregroundSyncAllowed(int sdkInt) => sdkInt > 0 && sdkInt < 35;

/// Self-imposed daily cap for the foreground service (5.5 h). We stop
/// well before the system's 6-hour hard kill so the process is never
/// torn down by ForegroundServiceDidNotStopInTimeException. Only
/// relevant when a user on Android ≤ 14 shares their build with an
/// Android 15+ device via sideload — the accounting runs regardless.
const Duration fgsSelfCap = Duration(hours: 5, minutes: 30);

/// Rolling window after which the foreground-service budget resets.
const Duration fgsWindow = Duration(hours: 24);

/// Tracks cumulative foreground-service runtime per 24-hour window
/// (persisted in SharedPreferences) so the service can stop gracefully
/// BEFORE the Android 15 hard cap instead of being killed by it.
class FgsRuntimeBudget {
  int windowStartMs;
  int accumulatedMs;
  int? sessionStartMs;

  /// Creates a budget; defaults represent "nothing used yet".
  FgsRuntimeBudget({this.windowStartMs = 0, this.accumulatedMs = 0});

  /// Restores the persisted budget.
  factory FgsRuntimeBudget.fromPrefs(SharedPreferences prefs) =>
      FgsRuntimeBudget(
        windowStartMs: prefs.getInt('fgs.windowStart') ?? 0,
        accumulatedMs: prefs.getInt('fgs.accumulatedMs') ?? 0,
      );

  /// Persists the budget.
  Future<void> save(SharedPreferences prefs) async {
    await prefs.setInt('fgs.windowStart', windowStartMs);
    await prefs.setInt('fgs.accumulatedMs', accumulatedMs);
  }

  /// Begins (or continues) counting a session, rolling the 24-hour
  /// window when it has expired.
  void startSession(DateTime now) {
    final ms = now.millisecondsSinceEpoch;
    if (windowStartMs == 0 || ms - windowStartMs >= fgsWindow.inMilliseconds) {
      windowStartMs = ms;
      accumulatedMs = 0;
    }
    sessionStartMs = ms;
  }

  /// Freezes the running session into the accumulator and persists.
  /// Called every tick (cheap) so process death never loses accounting.
  Future<void> checkpoint(SharedPreferences prefs, {DateTime? now}) async {
    final s = sessionStartMs;
    sessionStartMs = null;
    if (s != null) {
      final end = (now ?? DateTime.now()).millisecondsSinceEpoch;
      if (end > s) accumulatedMs += end - s;
    }
    await save(prefs);
  }

  /// Remaining runtime before the self-cap in the current window.
  Duration remaining({DateTime? now}) {
    final s = sessionStartMs;
    var used = accumulatedMs;
    if (s != null) {
      final end = (now ?? DateTime.now()).millisecondsSinceEpoch;
      if (end > s) used += end - s;
    }
    final left = fgsSelfCap.inMilliseconds - used;
    return left <= 0 ? Duration.zero : Duration(milliseconds: left);
  }

  /// True when the service must stop now (self-cap reached).
  bool exhausted({DateTime? now}) => remaining(now: now) == Duration.zero;
}

/// Side-effect hooks injected into [runSyncTick] so unit tests can
/// observe behaviour without platform plugins (notifications would throw
/// MissingPluginException on the host).
class SyncTickHooks {
  /// Creates hooks; defaults to the real notification implementation.
  const SyncTickHooks({
    this.notify = systemNotify,
    this.onWidgetPayload,
    this.now,
  });

  /// Posts a user-facing notification.
  final Future<void> Function(String title, String body) notify;

  /// Invoked after the widget payload was persisted (test hook).
  final Future<void> Function(Map<String, dynamic> payload)? onWidgetPayload;

  /// Clock override for tests.
  final DateTime Function()? now;

  DateTime _now() => now?.call() ?? DateTime.now();
}

/// Outcome of one sync tick.
class SyncTickResult {
  /// Number of accounts checked.
  final int accounts;

  /// Notifications posted during this tick.
  final int notified;

  /// Whether the tick completed without an RPC failure.
  final bool ok;

  /// Updated per-address balance map (persisted by the caller).
  final Map<String, String> lastBalances;

  /// When the tick ran.
  final DateTime at;

  /// Creates the outcome.
  const SyncTickResult({
    required this.accounts,
    required this.notified,
    required this.ok,
    required this.lastBalances,
    required this.at,
  });
}

/// Production notification hook (real plugin).
Future<void> systemNotify(String title, String body) async {
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    const android = AndroidNotificationDetails(
      'massa_wallet_alerts',
      'Pine Wallet alerts',
      channelDescription: 'Balance change and staking alerts',
      importance: Importance.high,
      priority: Priority.high,
    );
    await plugin.show(
      id: DateTime.now().millisecondsSinceEpoch % 2147483647,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(android: android),
    );
  } on Exception catch (e) {
    // Notifications are best-effort — e.g. MissingPluginException inside
    // a freshly spawned background isolate before plugin registration.
    debugPrint('notification failed: $e');
  }
}

/// Formats nanoMAS into a human string (up to 4 decimals).
String formatNano(BigInt nano) {
  final negative = nano.isNegative;
  final abs = negative ? -nano : nano;
  final s = abs.toString().padLeft(10, '0');
  final intPart = s.substring(0, s.length - 9);
  var frac = s.substring(s.length - 9).replaceAll(RegExp(r'0+$'), '');
  if (frac.length > 4) frac = frac.substring(0, 4);
  return '${negative ? '-' : ''}$intPart${frac.isEmpty ? '' : '.$frac'}';
}

/// Shortens an address for notification bodies.
String shortAddress(String address) => address.length <= 14
    ? address
    : '${address.substring(0, 8)}…${address.substring(address.length - 6)}';

/// Computes the notifications for balance deltas against [lastBalances].
/// Pure function — unit-testable without network or plugins.
List<String> balanceChangeMessages(
  Map<String, String> lastBalances,
  Map<String, BigInt> freshBalances,
) {
  final messages = <String>[];
  for (final entry in freshBalances.entries) {
    final previous = lastBalances[entry.key];
    if (previous == null) continue;
    final BigInt prev;
    try {
      prev = BigInt.parse(previous);
    } on FormatException {
      continue;
    }
    final delta = entry.value - prev;
    if (delta == BigInt.zero) continue;
    final direction = delta > BigInt.zero ? '↑' : '↓';
    messages.add(
      '$direction ${formatNano(delta.abs())} MAS · ${shortAddress(entry.key)}',
    );
  }
  return messages;
}

/// Runs ONE balance-sync tick. Never throws — every failure is reported
/// through [SyncTickResult.ok] so callers (WorkManager, FGS isolate)
/// stay alive.
///
/// [lastBalances] is mutated in place and must be persisted by the
/// caller (background isolates are recreated between WorkManager runs,
/// so the baseline has to live in SharedPreferences, not memory).
///
/// [allowEmbeddedKeepalive] — a WorkManager worker must NEVER respawn
/// the embedded node (a full node relaunch inside a 15-minute worker
/// would burn CPU/memory for nothing); the legacy FGS may keep it warm.
///
/// [httpClient] — injectable for tests (flutter_test's binding mocks
/// away all real sockets, so tests must supply their own client).
Future<SyncTickResult> runSyncTick(
  SharedPreferences prefs,
  Map<String, String> lastBalances, {
  SyncTickHooks hooks = const SyncTickHooks(),
  bool allowEmbeddedKeepalive = true,
  http.Client? httpClient,
}) async {
  final now = hooks._now();
  var notified = 0;
  var ok = true;
  var accounts = 0;
  final fresh = <String, BigInt>{};

  try {
    final accountsRaw = prefs.getString('mw.accounts');
    if (accountsRaw != null && accountsRaw.isNotEmpty) {
      final addresses = (json.decode(accountsRaw) as List)
          .map((e) => (e as Map<String, dynamic>)['address'] as String)
          .toList();
      accounts = addresses.length;

      if (addresses.isNotEmpty) {
        final mode =
            prefs.getString('settings.connectionMode') ??
            ((prefs.getBool('settings.useCustomNode') ?? false)
                ? 'customRpc'
                : 'publicRpc');
        final customUrl = prefs.getString('settings.customNodeUrl') ?? '';
        final isMainnet = prefs.getString('settings.network') == 'mainnet';
        final defaultUrl = isMainnet
            ? MassaNetwork.mainnet.apiUrl
            : MassaNetwork.buildnet.apiUrl;
        final endpoint = resolveEndpoint(
          mode: mode,
          customUrl: customUrl,
          defaultUrl: defaultUrl,
          embeddedUrl:
              'http://127.0.0.1:${SettingsProvider.embeddedApiPort}/api/v2',
          embeddedUsable: !isMainnet,
        );

        // Keepalive for the embedded node — FGS only. From a WorkManager
        // worker, respawning a full node is exactly the kind of resource
        // abuse this whole redesign removes.
        if (mode == 'embedded' && !isMainnet && allowEmbeddedKeepalive) {
          await EmbeddedNodeService.ensureRunningFromPrefs();
        }

        final client = MassaRpcClient(
          endpoint: endpoint,
          httpClient: httpClient,
        );
        List<AddressInfo> infos = const [];
        try {
          infos = await client.getAddresses(addresses);
          for (final info in infos) {
            fresh[info.address] = info.finalBalance;
          }
        } finally {
          client.dispose();
        }

        // Balance diffs → notifications (baseline from storage).
        for (final message in balanceChangeMessages(lastBalances, fresh)) {
          await hooks.notify('Pine Wallet — balance changed', message);
          notified++;
        }
        lastBalances
          ..clear()
          ..addAll(fresh.map((k, v) => MapEntry(k, v.toString())));

        // Feed the homescreen widget (it redraws on its own schedule —
        // a MethodChannel nudge is only possible from the UI isolate).
        if (infos.isNotEmpty) {
          final active = json.decode(accountsRaw).first['address'] as String;
          for (final info in infos) {
            if (info.address == active) {
              final payload = <String, dynamic>{
                'balance': formatNano(info.finalBalance),
                'rolls': info.finalRollCount.toString(),
                'address': info.address,
                'network': isMainnet ? 'Mainnet' : 'Buildnet',
                'updatedAt': now.toIso8601String(),
                'hideBalances': prefs.getBool('settings.hideBalances') ?? false,
              };
              await prefs.setString('massa_widget', json.encode(payload));
              await hooks.onWidgetPayload?.call(payload);
              break;
            }
          }
        }

        // Roll auto-compound (cycle-aware) — best-effort. Deferred calls
        // execute on the MASSA NETWORK itself, so a missed device window
        // only delays submission; it never breaks the chain-side logic.
        if (prefs.getBool('ac.enabled') ?? false) {
          try {
            final ac = AutoCompoundService(
              prefs: prefs,
              repository: WalletRepository(),
            );
            final outcome = await ac.tick(
              address: json.decode(accountsRaw).first['address'] as String,
              endpoint: endpoint,
            );
            if (outcome.action == AutoCompoundAction.bought) {
              await hooks.notify(
                'Pine Wallet — auto-compound',
                'Reinvested ${outcome.rollsBought} roll(s) · '
                    'cycle ${outcome.cycle}',
              );
              notified++;
            }
          } catch (e) {
            debugPrint('auto-compound tick failed: $e');
          }
        }
      }
    }
  } catch (e) {
    ok = false;
    debugPrint('bg sync tick failed: $e');
  }

  // Persist the baseline + last-run stamp so the next isolate (and the
  // settings screen) sees current state.
  await prefs.setString('bg.lastBalances', json.encode(lastBalances));
  await prefs.setString('bg.lastTickAt', now.toIso8601String());

  return SyncTickResult(
    accounts: accounts,
    notified: notified,
    ok: ok,
    lastBalances: lastBalances,
    at: now,
  );
}
