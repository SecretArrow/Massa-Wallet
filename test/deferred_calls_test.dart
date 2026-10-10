import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:massa_wallet/core/api/massa_models.dart';
import 'package:massa_wallet/core/api/massa_rpc.dart';
import 'package:massa_wallet/core/services/deferred_calls_service.dart';

http.Response _rpc(dynamic result, {int id = 0}) => http.Response(
  json.encode({'jsonrpc': '2.0', 'id': id, 'result': result}),
  200,
);

void main() {
  group('Slot clock (T0=16s, 32 threads)', () {
    // Buildnet genesis derived on the live node: 1704289800000.
    const genesis = 1704289800000;

    test('genesisFromStatus via cycle timing', () {
      final status = NodeStatus.fromJson({
        'version': 'TESTN.30.1',
        'chain_id': 77658366,
        'minimal_fee': '0.00001',
        'last_slot': {'period': 5457129, 'thread': 30},
        'current_cycle': 42633,
        'current_time': 1791603879359,
        'next_cycle_time': 1791604232000,
      });
      expect(DeferredCallsService.genesisFromStatus(status), genesis);
    });

    test('genesisFromStatus fallback to current_time/last_slot', () {
      final status = NodeStatus.fromJson({
        'version': 'TESTN.30.1',
        'chain_id': 77658366,
        'last_slot': {'period': 100, 'thread': 8},
        'current_time': genesis + 100 * 16000 + 8 * 500 + 123,
      });
      // Fallback is exact up to the thread tick (123 ms drift within the
      // 500 ms thread slot) — assert within one thread.
      final g = DeferredCallsService.genesisFromStatus(status);
      expect((g - genesis).abs(), lessThan(500));
    });

    test('datetimeToSlot / slotToDateTime round trip', () {
      final dt = DateTime.fromMillisecondsSinceEpoch(
        genesis + 12345 * 16000 + 7 * 500 + 123,
        isUtc: true,
      );
      final slot = DeferredCallsService.dateTimeToSlot(dt, genesis);
      expect(slot.period, 12345);
      expect(slot.thread, 7);
      // Round trip is exact to the containing thread tick.
      final back = DeferredCallsService.slotToDateTime(slot, genesis);
      expect(back.millisecondsSinceEpoch, genesis + 12345 * 16000 + 7 * 500);
    });

    test('before genesis throws', () {
      expect(
        () => DeferredCallsService.dateTimeToSlot(
          DateTime.fromMillisecondsSinceEpoch(genesis - 1, isUtc: true),
          genesis,
        ),
        throwsArgumentError,
      );
    });

    test('genericRegisterArgs serializes the documented order', () {
      final args = DeferredCallsService.genericRegisterArgs(
        targetAddress: 'AS1test',
        targetFunction: 'run',
        slot: const MassaSlot(period: 0x01020304, thread: 0x1F),
        maxGas: BigInt.from(0xAABBCCDD),
        params: const [0x11, 0x22],
        coinsNano: BigInt.from(5),
      );
      // string: u32le len + utf8
      expect(args.sublist(0, 4), [7, 0, 0, 0]);
      expect(utf8.decode(args.sublist(4, 11)), 'AS1test');
      var i = 11;
      expect(args.sublist(i, i + 4), [3, 0, 0, 0]); // len 'run'
      i += 4;
      expect(utf8.decode(args.sublist(i, i + 3)), 'run');
      i += 3;
      expect(args.sublist(i, i + 8), [4, 3, 2, 1, 0, 0, 0, 0]); // period u64le
      i += 8;
      expect(args[i], 0x1F); // thread u8
      i += 1;
      expect(args.sublist(i, i + 8), [0xDD, 0xCC, 0xBB, 0xAA, 0, 0, 0, 0]);
      i += 8;
      expect(args.sublist(i, i + 4), [2, 0, 0, 0]); // params len
      i += 4;
      expect(args.sublist(i, i + 2), [0x11, 0x22]);
      i += 2;
      expect(args.sublist(i, i + 8), [5, 0, 0, 0, 0, 0, 0, 0]); // coins u64le
      expect(args.length, i + 8);
    });
  });

  group('Deferred call RPC', () {
    test(
      'getDeferredCallQuote builds node-shaped params and parses price',
      () async {
        String? rawParams;
        final client = MassaRpcClient(
          endpoint: 'https://buildnet.massa.net/api/v2',
          httpClient: MockClient((req) async {
            final body = json.decode(req.body) as Map<String, dynamic>;
            expect(body['method'], 'get_deferred_call_quote');
            rawParams = json.encode(body['params']);
            return _rpc([
              {
                'target_slot': {'period': 5457163, 'thread': 28},
                'max_gas_request': 20750000,
                'available': true,
                'price': '0.2441',
              },
            ]);
          }),
        );
        final quotes = await client.getDeferredCallQuote([
          const DeferredCallQuoteInput(
            targetSlot: MassaSlot(period: 5457163, thread: 28),
            maxGasRequest: 20000000,
          ),
        ]);
        // The node API expects params: [[{...}]] (one arg = array of requests).
        expect(
          rawParams,
          '[[{"target_slot":{"period":5457163,"thread":28},"max_gas_request":20000000,"params_size":0}]]',
        );
        expect(quotes, hasLength(1));
        expect(quotes.first.available, isTrue);
        expect(
          quotes.first.targetSlot,
          const MassaSlot(period: 5457163, thread: 28),
        );
        expect(quotes.first.maxGas, BigInt.from(20750000));
        // "0.2441" MAS = 244100000 nanoMAS.
        expect(quotes.first.priceNano, BigInt.from(244100000));
      },
    );

    test(
      'getDeferredCallInfo parses nested call and numeric amounts',
      () async {
        final client = MassaRpcClient(
          endpoint: 'https://buildnet.massa.net/api/v2',
          httpClient: MockClient((req) async {
            final body = json.decode(req.body) as Map<String, dynamic>;
            expect(body['method'], 'get_deferred_call_info');
            expect(body['params'], [
              ['D1abc'],
            ]);
            return _rpc([
              {
                'call_id': 'D1abc',
                'call': {
                  'sender_address': 'AU1sender',
                  'target_slot': {'period': 5457200, 'thread': 3},
                  'target_address': 'AS1target',
                  'target_function': 'processTask',
                  'parameters': [1, 2, 3],
                  'coins': 1000000000,
                  'max_gas': 20000000,
                  'fee': '0.1',
                  'cancelled': false,
                },
              },
            ]);
          }),
        );
        final infos = await client.getDeferredCallInfo(['D1abc']);
        expect(infos, hasLength(1));
        final info = infos.first;
        expect(info.callId, 'D1abc');
        expect(info.senderAddress, 'AU1sender');
        expect(info.targetSlot, const MassaSlot(period: 5457200, thread: 3));
        expect(info.targetAddress, 'AS1target');
        expect(info.targetFunction, 'processTask');
        expect(info.parameters, [1, 2, 3]);
        expect(info.coinsNano, BigInt.from(1000000000));
        expect(info.maxGas, BigInt.from(20000000));
        expect(info.feeNano, BigInt.from(100000000));
        expect(info.cancelled, isFalse);
      },
    );

    test('getDeferredCallIdsBySlot parses ids', () async {
      final client = MassaRpcClient(
        endpoint: 'https://buildnet.massa.net/api/v2',
        httpClient: MockClient((req) async {
          final body = json.decode(req.body) as Map<String, dynamic>;
          expect(body['method'], 'get_deferred_call_ids_by_slot');
          expect(body['params'], [
            [
              {'period': 5457200, 'thread': 3},
            ],
          ]);
          return _rpc([
            {
              'slot': {'period': 5457200, 'thread': 3},
              'call_ids': ['D1abc', 'D2def'],
            },
          ]);
        }),
      );
      final res = await client.getDeferredCallIdsBySlot([
        const MassaSlot(period: 5457200, thread: 3),
      ]);
      expect(res, hasLength(1));
      expect(res.first.callIds, ['D1abc', 'D2def']);
    });
  });
}
