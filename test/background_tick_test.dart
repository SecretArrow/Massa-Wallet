/// Tests for the background-sync redesign that solves Android 15's
/// 6-hour/day dataSync foreground-service limit:
///  * interval clamping + FGS gating (pure logic),
///  * FgsRuntimeBudget self-cap accounting (never hit the system kill),
///  * runSyncTick end-to-end against a fake RPC server (notifications,
///    widget payload, persisted baseline) with zero platform plugins.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:massa_wallet/core/api/massa_rpc.dart';

import 'package:massa_wallet/core/services/background_tick.dart';

/// A fake Massa RPC served entirely in-memory (flutter_test's binding
/// mocks away real sockets, so no HTTP server can be used here).
http.Client fakeRpcClient(String address, String balanceMas, int rolls) =>
    MockClient((request) async {
      final body = json.decode(request.body) as Map<String, dynamic>;
      return http.Response(
        json.encode({
          'jsonrpc': '2.0',
          'id': body['id'],
          'result': [
            {
              'address': address,
              'thread': 0,
              'final_balance': balanceMas,
              'candidate_balance': balanceMas,
              'final_roll_count': rolls,
              'candidate_roll_count': rolls,
              'final_datastore_keys': [],
              'candidate_datastore_keys': [],
              'cycle_infos': [],
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('interval clamping & FGS gating', () {
    test('clampToWorkmanagerInterval enforces the 15-minute floor', () {
      expect(clampToWorkmanagerInterval(60), 900);
      expect(clampToWorkmanagerInterval(300), 900);
      expect(clampToWorkmanagerInterval(900), 900);
      expect(clampToWorkmanagerInterval(1800), 1800);
      expect(clampToWorkmanagerInterval(3600), 3600);
    });

    test('foregroundSyncAllowed — dataSync FGS banned on Android 15+', () {
      expect(foregroundSyncAllowed(33), isTrue); // emulator API 33
      expect(foregroundSyncAllowed(34), isTrue); // Android 14
      expect(foregroundSyncAllowed(35), isFalse); // Android 15 — 6 h cap
      expect(foregroundSyncAllowed(36), isFalse); // Android 16
      expect(foregroundSyncAllowed(0), isFalse); // unknown / host tests
    });
  });

  group('FgsRuntimeBudget', () {
    test('fresh budget has full headroom and is not exhausted', () {
      final budget = FgsRuntimeBudget();
      final now = DateTime(2026, 1, 1, 12);
      budget.startSession(now);
      expect(budget.exhausted(now: now), isFalse);
      expect(budget.remaining(now: now), fgsSelfCap);
    });

    test('self-cap reached BEFORE the system 6-hour kill', () {
      final budget = FgsRuntimeBudget(
        windowStartMs: DateTime(2026, 1, 1).millisecondsSinceEpoch,
        accumulatedMs: const Duration(hours: 5, minutes: 30).inMilliseconds,
      );
      final now = DateTime(2026, 1, 1, 5, 31);
      expect(budget.exhausted(now: now), isTrue);
      expect(budget.remaining(now: now), Duration.zero);
    });

    test(
      'checkpoint freezes the running session into the accumulator',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final budget = FgsRuntimeBudget();
        final start = DateTime(2026, 1, 1, 10);
        budget.startSession(start);
        final later = start.add(const Duration(minutes: 7));
        await budget.checkpoint(prefs, now: later);

        final restored = FgsRuntimeBudget.fromPrefs(prefs);
        expect(
          restored.accumulatedMs,
          const Duration(minutes: 7).inMilliseconds,
        );
        expect(
          restored.remaining(now: later),
          fgsSelfCap - const Duration(minutes: 7),
        );
      },
    );

    test('24-hour window rollover resets the accumulated budget', () async {
      SharedPreferences.setMockInitialValues({});
      final windowStart = DateTime(2026, 1, 1);
      final budget = FgsRuntimeBudget(
        windowStartMs: windowStart.millisecondsSinceEpoch,
        accumulatedMs: const Duration(hours: 6).inMilliseconds,
      );
      // 25 hours later — a new window must open with a fresh budget.
      final later = windowStart.add(const Duration(hours: 25));
      budget.startSession(later);
      expect(budget.accumulatedMs, 0);
      expect(budget.exhausted(now: later), isFalse);
    });

    test(
      'budget survives process death via prefs (checkpoint → restore)',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final start = DateTime(2026, 3, 1, 8);
        final a = FgsRuntimeBudget();
        a.startSession(start);
        await a.checkpoint(prefs, now: start.add(const Duration(hours: 4)));

        // "Process death" — reconstruct from storage and keep counting.
        final b = FgsRuntimeBudget.fromPrefs(prefs);
        b.startSession(start.add(const Duration(hours: 4)));
        final after = start.add(const Duration(hours: 4, minutes: 30));
        // 4h + 30m used, 1h left of the 5.5 h self-cap.
        expect(b.remaining(now: after), const Duration(hours: 1));
        expect(b.exhausted(now: after), isFalse);
      },
    );
  });

  group('balanceChangeMessages', () {
    test('first baseline produces no notifications', () {
      final messages = balanceChangeMessages({}, {'AU12abc': BigInt.from(100)});
      expect(messages, isEmpty);
    });

    test('increase and decrease produce directional messages', () {
      final messages = balanceChangeMessages(
        {'AU12abc': '1000000000', 'AU12def': '5000000000'},
        {
          'AU12abc': BigInt.from(1500000000),
          'AU12def': BigInt.from(4000000000),
        },
      );
      expect(messages.length, 2);
      expect(messages.first, contains('↑'));
      expect(messages.first, contains('0.5 MAS'));
      expect(messages.last, contains('↓'));
      expect(messages.last, contains('1 MAS'));
    });

    test('no change → no message; corrupt baseline skipped', () {
      final messages = balanceChangeMessages(
        {'AU12abc': '1000000000', 'AU12bad': 'xyz'},
        {'AU12abc': BigInt.from(1000000000), 'AU12bad': BigInt.from(1)},
      );
      expect(messages, isEmpty);
    });
  });

  group('runSyncTick (fake RPC server)', () {
    const address = 'AU12hJ8YfM4MH1aPdA4cw8PEhz3Bs3gFZuwDUGjNKnY3um4UnDDft';

    test(
      'first tick: no notify, widget payload + baseline persisted',
      () async {
        SharedPreferences.setMockInitialValues({
          'mw.accounts': json.encode([
            {'address': address, 'label': 'Main'},
          ]),
        });
        final prefs = await SharedPreferences.getInstance();
        final notifications = <String>[];
        Map<String, dynamic>? widgetPayload;
        final result = await runSyncTick(
          prefs,
          <String, String>{},
          hooks: SyncTickHooks(
            notify: (title, body) async => notifications.add('$title|$body'),
            onWidgetPayload: (p) async => widgetPayload = p,
          ),
          httpClient: fakeRpcClient(address, '123.456789012', 2),
        );

        expect(result.ok, isTrue);
        expect(result.accounts, 1);
        expect(notifications, isEmpty); // baseline — never notify on first run
        expect(result.lastBalances[address], '123456789012');
        expect(prefs.getString('bg.lastBalances'), isNotNull);
        expect(prefs.getString('bg.lastTickAt'), isNotNull);
        expect(widgetPayload, isNotNull);
        expect(widgetPayload!['balance'], '123.4567');
        expect(widgetPayload!['rolls'], '2');
        expect(widgetPayload!['address'], address);
      },
    );

    test('second tick with changed balance notifies exactly once', () async {
      SharedPreferences.setMockInitialValues({
        'mw.accounts': json.encode([
          {'address': address, 'label': 'Main'},
        ]),
        // Baseline from a previous run (cross-isolate persistence).
        'bg.lastBalances': json.encode({address: '123456789012'}),
      });
      final prefs = await SharedPreferences.getInstance();

      final notifications = <String>[];
      // Mirror production: the worker loads the persisted baseline.
      final baseline = <String, String>{};
      final stored = prefs.getString('bg.lastBalances');
      if (stored != null) {
        baseline.addAll(
          (json.decode(stored) as Map<String, dynamic>).map(
            (k, v) => MapEntry(k, v.toString()),
          ),
        );
      }
      await runSyncTick(
        prefs,
        baseline,
        hooks: SyncTickHooks(
          notify: (title, body) async => notifications.add(body),
        ),
        httpClient: fakeRpcClient(address, '133.456789012', 2),
      );

      expect(notifications.length, 1);
      expect(notifications.first, contains('↑'));
      expect(notifications.first, contains('10 MAS'));
    });

    test(
      'RPC failure → ok=false, tick never throws, stamp still set',
      () async {
        SharedPreferences.setMockInitialValues({
          'mw.accounts': json.encode([
            {'address': address, 'label': 'Main'},
          ]),
        });
        final prefs = await SharedPreferences.getInstance();

        final result = await runSyncTick(
          prefs,
          <String, String>{},
          // Deterministic failure — no real network involved.
          httpClient: MockClient((request) async {
            return http.Response('server exploded', 400);
          }),
          hooks: const SyncTickHooks(),
        );

        expect(result.ok, isFalse);
        expect(prefs.getString('bg.lastTickAt'), isNotNull);
      },
    );

    test('no accounts → ok tick, zero work', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final result = await runSyncTick(prefs, <String, String>{});
      expect(result.ok, isTrue);
      expect(result.accounts, 0);
      expect(prefs.getString('bg.lastTickAt'), isNotNull);
    });
  });
}
