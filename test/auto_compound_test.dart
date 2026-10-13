/// Auto-compound polish tests: force tick (manual "Compound now"),
/// history persistence/cap, watermark semantics, reserve handling.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:massa_wallet/core/services/auto_compound_service.dart';
import 'package:massa_wallet/core/services/wallet_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _rpc(dynamic result, {int id = 0}) => http.Response(
  json.encode({'jsonrpc': '2.0', 'id': id, 'result': result}),
  200,
);

const _addr = 'AU126tkwrhXn9gEG5JPtrNy8NNLbVMwywokgLKshSYyzP8qusqXZL';

http.Client _node({required int cycle, required String balance}) {
  return MockClient((req) async {
    final body = json.decode(req.body) as Map<String, dynamic>;
    if (body['method'] == 'get_status') {
      return _rpc({
        'version': 'TEST.1.0',
        'chain_id': 77658366,
        'minimal_fee': '0.001',
        'last_slot': {'period': 100, 'thread': 0},
        'current_cycle': cycle,
        'next_cycle_time': 0,
        'current_time': 0,
      });
    }
    if (body['method'] == 'get_addresses') {
      return _rpc([
        {
          'address': _addr,
          'final_balance': balance,
          'candidate_balance': balance,
          'final_roll_count': 1,
          'candidate_roll_count': 1,
          'cycle_infos': [],
          'final_datastore_keys': [],
          'candidate_datastore_keys': [],
        },
      ]);
    }
    return http.Response(json.encode({'error': 'unhandled'}), 400);
  });
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<AutoCompoundService> svc() async {
    final prefs = await SharedPreferences.getInstance();
    return AutoCompoundService(prefs: prefs, repository: WalletRepository());
  }

  group('computeReinvestRolls (pure)', () {
    test('surplus above reserve buys whole rolls', () {
      expect(
        computeReinvestRolls(
          finalBalanceNano: BigInt.from(350000000000), // 350 MAS
          reserveNano: BigInt.from(1000000000), // 1 MAS
          priceNano: BigInt.from(100000000000), // 100 MAS
        ),
        3,
      );
    });

    test('no surplus, no price, exact multiples', () {
      expect(
        computeReinvestRolls(
          finalBalanceNano: BigInt.from(500000000),
          reserveNano: BigInt.from(1000000000),
          priceNano: BigInt.from(100000000000),
        ),
        0,
      );
      expect(
        computeReinvestRolls(
          finalBalanceNano: BigInt.from(350000000000),
          reserveNano: BigInt.from(1000000000),
          priceNano: BigInt.zero,
        ),
        0,
      );
    });
  });

  test('disabled: no RPC, no history', () async {
    final s = await svc();
    final o = await s.tick(address: _addr, endpoint: 'https://example.org');
    expect(o.action, AutoCompoundAction.disabled);
    expect(s.history, isEmpty);
  });

  test('same-cycle watermark blocks re-buy; force bypasses it', () async {
    final s = await svc();
    await s.setEnabled(true);
    await (await SharedPreferences.getInstance()).setInt('ac.lastCycle', 5);
    var calls = 0;
    final o = await s.tick(
      address: _addr,
      endpoint: 'https://example.org',
      httpClient: _node(cycle: 5, balance: '350'),
      broadcast: (rolls) async {
        calls++;
        return 'op1';
      },
    );
    expect(o.action, AutoCompoundAction.sameCycle);
    expect(calls, 0);
    // sameCycle is not recorded in history
    expect(s.history, isEmpty);

    final o2 = await s.tick(
      address: _addr,
      endpoint: 'https://example.org',
      force: true,
      httpClient: _node(cycle: 5, balance: '350'),
      broadcast: (rolls) async {
        calls++;
        return 'op2';
      },
    );
    expect(o2.action, AutoCompoundAction.bought);
    expect(o2.rollsBought, 3);
    expect(o2.operationId, 'op2');
    expect(o2.balanceNano, BigInt.from(350000000000));
    expect(calls, 1);
    // watermark advanced to the current cycle (no double-buy by background)
    expect(s.lastCycle, 5);
    expect(s.history, hasLength(1));
    expect(s.history.first.rolls, 3);
  });

  test('nothing to reinvest: recorded, watermark advances', () async {
    final s = await svc();
    await s.setEnabled(true);
    final o = await s.tick(
      address: _addr,
      endpoint: 'https://example.org',
      httpClient: _node(cycle: 6, balance: '50'),
      broadcast: (rolls) async => 'never',
    );
    expect(o.action, AutoCompoundAction.nothingToReinvest);
    expect(s.lastCycle, 6);
    expect(s.history, hasLength(1));
    expect(s.history.first.action, AutoCompoundAction.nothingToReinvest);
    expect(s.history.first.balanceNano, BigInt.from(50000000000));
  });

  test('failed broadcast keeps the watermark (retried next tick)', () async {
    final s = await svc();
    await s.setEnabled(true);
    final o = await s.tick(
      address: _addr,
      endpoint: 'https://example.org',
      httpClient: _node(cycle: 7, balance: '350'),
      broadcast: (rolls) async => throw Exception('node unreachable'),
    );
    expect(o.action, AutoCompoundAction.failed);
    expect(s.lastCycle, isNull);
    expect(s.history, hasLength(1));
    expect(s.history.first.action, AutoCompoundAction.failed);
    expect(s.history.first.detail, contains('node unreachable'));
  });

  test('history caps at 10, newest first', () async {
    final s = await svc();
    await s.setEnabled(true);
    for (var i = 0; i < 12; i++) {
      await s.tick(
        address: _addr,
        endpoint: 'https://example.org',
        force: true,
        rollPriceNanoOverride: BigInt.from(100000000000),
        httpClient: _node(cycle: 100 + i, balance: '350'),
        broadcast: (rolls) async => 'op$i',
      );
    }
    expect(s.history, hasLength(AutoCompoundService.historyCap));
    expect(s.history.first.operationId, 'op11');
    expect(s.history.last.operationId, 'op2');
  });

  test('reserve: default 1 MAS, round-trips', () async {
    final s = await svc();
    expect(s.reserveNano, BigInt.from(1000000000));
    await s.setReserveNano(BigInt.from(5000000000));
    expect(s.reserveNano, BigInt.from(5000000000));
    // reflect in a fresh service (persisted)
    final s2 = await svc();
    expect(s2.reserveNano, BigInt.from(5000000000));
  });

  test('AutoCompoundRecord JSON round-trip', () {
    final rec = AutoCompoundRecord(
      at: DateTime.utc(2026, 1, 2, 3, 4, 5),
      action: AutoCompoundAction.bought,
      rolls: 2,
      operationId: 'opX',
      cycle: 9,
      balanceNano: BigInt.from(123456789),
      address: _addr,
    );
    final back = AutoCompoundRecord.fromMap(rec.toMap());
    expect(back.at, rec.at);
    expect(back.action, AutoCompoundAction.bought);
    expect(back.rolls, 2);
    expect(back.operationId, 'opX');
    expect(back.cycle, 9);
    expect(back.balanceNano, BigInt.from(123456789));
    expect(back.address, _addr);
  });
}
