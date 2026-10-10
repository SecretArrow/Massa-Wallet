/// Background balance sync via Android foreground service.
///
/// Uses `flutter_background_service` (foreground service with dataSync
/// type) + `flutter_local_notifications` for income alerts. The service
/// isolate polls the configured RPC endpoint every
/// `SettingsProvider.syncIntervalSeconds` and posts a notification when a
/// balance change is detected.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/massa_rpc.dart';
import 'auto_compound_service.dart';
import 'embedded_node_service.dart';
import 'settings_provider.dart' show SettingsProvider, resolveEndpoint;
import 'wallet_repository.dart';

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

  Future<void> tick() async {
    try {
      final accountsRaw = prefs.getString('mw.accounts');
      if (accountsRaw == null || accountsRaw.isEmpty) return;
      final accounts = (json.decode(accountsRaw) as List)
          .map((e) => (e as Map<String, dynamic>)['address'] as String)
          .toList();
      if (accounts.isEmpty) return;

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

      // Keepalive for the embedded node (respawn via prefs, best-effort).
      if (mode == 'embedded' && !isMainnet) {
        await EmbeddedNodeService.ensureRunningFromPrefs();
      }

      final client = MassaRpcClient(endpoint: endpoint);
      try {
        final infos = await client.getAddresses(accounts);
        for (final info in infos) {
          final key = info.address;
          final value = info.finalBalance.toString();
          final previous = lastBalances[key];
          if (previous != null && previous != value) {
            final delta = BigInt.parse(value) - BigInt.parse(previous);
            final direction = delta > BigInt.zero ? '↑' : '↓';
            await _notify(
              title: 'Pyramids Wallet — saldo berubah',
              body:
                  '$direction ${_formatNano(delta.abs())} MAS · ${_short(key)}',
            );
          }
          lastBalances[key] = value;
        }
        service.invoke('balances_updated', {
          'at': DateTime.now().toIso8601String(),
        });
        // Feed the homescreen widget (it redraws on its own schedule —
        // the MethodChannel nudge is only possible from the UI isolate).
        final active = accounts.first;
        for (final info in infos) {
          if (info.address == active) {
            await prefs.setString(
              'massa_widget',
              json.encode({
                'balance': _formatNano(info.finalBalance),
                'rolls': info.finalRollCount.toString(),
                'address': info.address,
                'network': isMainnet ? 'Mainnet' : 'Buildnet',
                'updatedAt': DateTime.now().toIso8601String(),
                'hideBalances': prefs.getBool('settings.hideBalances') ?? false,
              }),
            );
            break;
          }
        }
      } finally {
        client.dispose();
      }
      // Roll auto-compound (cycle-aware) — best-effort, uses the secure
      // store for signing when rewards arrive at cycle rollover.
      if (prefs.getBool('ac.enabled') ?? false) {
        try {
          final ac = AutoCompoundService(
            prefs: prefs,
            repository: WalletRepository(),
          );
          final outcome = await ac.tick(
            address: accounts.first,
            endpoint: endpoint,
          );
          if (outcome.action == AutoCompoundAction.bought) {
            await _notify(
              title: 'Pyramids Wallet — auto-compound',
              body:
                  'Reinvested ${outcome.rollsBought} roll(s) · cycle ${outcome.cycle}',
            );
          }
        } catch (e) {
          debugPrint('auto-compound tick failed: $e');
        }
      }
    } catch (e) {
      debugPrint('bg sync tick failed: $e');
    }
  }

  // Initial sync right away, then every ~30s check whether the configured
  // interval has elapsed.
  await tick();
  var elapsed = 0;
  Timer.periodic(const Duration(seconds: 30), (timer) async {
    elapsed += 30;
    final interval = prefs.getInt('settings.syncInterval') ?? 300;
    if (elapsed >= interval) {
      elapsed = 0;
      await tick();
    }
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        final now = DateTime.now();
        unawaited(
          service.setForegroundNotificationInfo(
            title: 'Pyramids Wallet',
            content:
                'Sinkronisasi aktif · terakhir ${now.hour}:${now.minute.toString().padLeft(2, '0')}',
          ),
        );
      }
    }
  });
}

Future<void> _notify({required String title, required String body}) async {
  final plugin = FlutterLocalNotificationsPlugin();
  const android = AndroidNotificationDetails(
    alertChannelId,
    'Pyramids Wallet alerts',
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
}

String _short(String address) => address.length <= 14
    ? address
    : '${address.substring(0, 8)}…${address.substring(address.length - 6)}';

String _formatNano(BigInt nano) {
  final negative = nano.isNegative;
  final abs = negative ? -nano : nano;
  final s = abs.toString().padLeft(10, '0');
  final intPart = s.substring(0, s.length - 9);
  var frac = s.substring(s.length - 9).replaceAll(RegExp(r'0+$'), '');
  if (frac.length > 4) frac = frac.substring(0, 4);
  return '${negative ? '-' : ''}$intPart${frac.isEmpty ? '' : '.$frac'}';
}

/// App-facing wrapper around the background service.
class BackgroundSyncService {
  final FlutterBackgroundService _service = FlutterBackgroundService();

  /// Initializes notification channels and configures the service.
  Future<void> configure({
    required bool autoStart,
    required String title,
    required String content,
  }) async {
    const channel = AndroidNotificationChannel(
      bgChannelId,
      'Pyramids Wallet background sync',
      description: 'Keeps balances fresh in the background',
      importance: Importance.low,
    );
    const alertChannel = AndroidNotificationChannel(
      alertChannelId,
      'Pyramids Wallet alerts',
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
