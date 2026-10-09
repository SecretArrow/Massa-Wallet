import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:massa_wallet/core/api/massa_amount.dart';
import 'package:massa_wallet/core/api/massa_models.dart';
import 'package:massa_wallet/core/api/massa_rpc.dart';
import 'package:massa_wallet/core/crypto/massa_keys.dart';
import 'package:massa_wallet/core/crypto/operation_serializer.dart';

http.Response _rpc(dynamic result, {int id = 0}) => http.Response(
  json.encode({'jsonrpc': '2.0', 'id': id, 'result': result}),
  200,
);

void main() {
  group('MassaRpcClient', () {
    test('getStatus parses chainId, minimal fee, period', () async {
      final client = MassaRpcClient.forNetwork(
        MassaNetwork.buildnet,
        httpClient: MockClient((req) async {
          final body = json.decode(req.body) as Map<String, dynamic>;
          expect(body['method'], 'get_status');
          expect(body['params'], isEmpty);
          return _rpc({
            'version': 'TESTN.30.2',
            'chain_id': 77658366,
            'minimal_fee': '0.00001',
            'last_slot': {'period': 5455135, 'thread': 21},
            'current_cycle': 42618,
          });
        }),
      );
      final status = await client.getStatus();
      expect(status.chainId, 77658366);
      expect(status.minimalFee, BigInt.from(10000));
      expect(status.currentPeriod, 5455135);
      expect(status.currentCycle, 42618);
    });

    test('getAddresses parses decimal balance string', () async {
      final client = MassaRpcClient(
        endpoint: 'https://buildnet.massa.net/api/v2',
        httpClient: MockClient((req) async {
          final body = json.decode(req.body) as Map<String, dynamic>;
          expect(body['method'], 'get_addresses');
          expect(body['params'], [
            ['AU126tkwrhXn9gEG5JPtrNy8NNLbVMwywokgLKshSYyzP8qusqXZL'],
          ]);
          return _rpc([
            {
              'address':
                  'AU126tkwrhXn9gEG5JPtrNy8NNLbVMwywokgLKshSYyzP8qusqXZL',
              'thread': 21,
              'final_balance': '12.500000001',
              'final_roll_count': 3,
              'final_datastore_keys': [],
              'candidate_balance': '12.600000000',
              'candidate_roll_count': 3,
              'candidate_datastore_keys': [],
              'deferred_credits': [],
              'next_block_draws': [],
              'next_endorsement_draws': [],
              'created_blocks': [],
              'created_operations': [],
              'created_endorsements': [],
              'cycle_infos': [
                {'cycle': 42, 'active_roll_count': 3, 'produced_blocks': []},
              ],
            },
          ]);
        }),
      );
      final info = await client.getAddressInfo(
        'AU126tkwrhXn9gEG5JPtrNy8NNLbVMwywokgLKshSYyzP8qusqXZL',
      );
      expect(info.finalBalance, BigInt.from(12500000001));
      expect(info.candidateBalance, BigInt.from(12600000000));
      expect(info.finalRollCount, BigInt.from(3));
      expect(info.activeRolls, BigInt.from(3));
    });

    test('RPC error surfaces message', () async {
      final client = MassaRpcClient(
        endpoint: 'https://example.org/api/v2',
        httpClient: MockClient(
          (_) async => http.Response(
            json.encode({
              'jsonrpc': '2.0',
              'id': 0,
              'error': {'code': -32602, 'message': 'Invalid params'},
            }),
            200,
          ),
        ),
      );
      await expectLater(
        client.getStatus(),
        throwsA(
          isA<RpcException>().having(
            (e) => e.message,
            'message',
            contains('Invalid params'),
          ),
        ),
      );
    });

    test('sendOperations wraps params array like massa-web3', () async {
      final client = MassaRpcClient(
        endpoint: 'https://example.org/api/v2',
        httpClient: MockClient((req) async {
          final body = json.decode(req.body) as Map<String, dynamic>;
          expect(body['method'], 'send_operations');
          final params = body['params'] as List;
          expect(params, hasLength(1));
          final opList = params[0] as List;
          expect(opList, hasLength(1));
          final op = opList[0] as Map<String, dynamic>;
          expect(op['serialized_content'], isA<List<dynamic>>());
          expect(op['creator_public_key'], startsWith('P'));
          return _rpc(['OP1234567890abcdefghij']);
        }),
      );
      // Build & sign a real 1 nanoMAS transfer for a generated key.
      final priv = MassaPrivateKey.generate();
      final op = MassaOperation.transfer(
        fee: BigInt.one,
        expirePeriod: 2,
        data: TransferOperationData(
          recipientAddress: priv.publicKey.address.encoded,
          amount: BigInt.one,
        ),
      );
      final sig = OperationSerializer.sign(BigInt.from(77658366), op, priv);
      final ids = await client.sendOperations([
        SendOperationInput(
          serializedContent: OperationSerializer.serialize(op).toList(),
          creatorPublicKey: priv.publicKey.encoded,
          signature: sig.encoded,
        ),
      ]);
      expect(ids, ['OP1234567890abcdefghij']);
    });

    test('executeReadOnlyCall builds correct input', () async {
      final client = MassaRpcClient(
        endpoint: 'https://example.org/api/v2',
        httpClient: MockClient((req) async {
          final body = json.decode(req.body) as Map<String, dynamic>;
          expect(body['method'], 'execute_read_only_call');
          final callList = (body['params'] as List)[0] as List;
          final call = callList[0] as Map<String, dynamic>;
          expect(call['max_gas'], 1000000);
          expect(call['target_function'], 'version');
          return _rpc([
            {
              'result': {
                'Ok': {
                  'return_value': base64Encode([1, 2, 3]),
                },
              },
              'gas_cost': 1000,
            },
          ]);
        }),
      );
      final res = await client.executeReadOnlyCall(
        ReadOnlyCallInput(
          targetAddress: 'AS12BqZEQ6sByhRLyEuf0YbQmcF2PsDdkNNG1akBJu9XcjZA1eT',
          targetFunction: 'version',
        ),
      );
      expect(res.ok, isTrue);
      expect(res.returnValue, [1, 2, 3]);
      expect(res.gasCost, BigInt.from(1000));
    });

    test('amount formatting roundtrip', () {
      const balance = '1012462541.490508428';
      final nano = masToNano(balance);
      expect(nanoToMas(nano), balance);
    });
  });
}
