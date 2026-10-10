import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:massa_wallet/core/api/massa_rpc.dart';
import 'package:massa_wallet/core/contracts/mrc20_service.dart';

http.Response _rpc(dynamic result, {int id = 0}) => http.Response(
  json.encode({'jsonrpc': '2.0', 'id': id, 'result': result}),
  200,
);

http.Client _mockNode(Map<String, Map<String, List<int>>> datastore) {
  return MockClient((req) async {
    final body = json.decode(req.body) as Map<String, dynamic>;
    if (body['method'] == 'get_datastore_entries') {
      final params = (body['params'] as List)[0] as List;
      final out = <dynamic>[];
      for (final e in params) {
        final addr = e['address'] as String;
        final key = (e['key'] as List).cast<int>();
        out.add({
          'final_value': datastore[addr]?[key.join(',')],
          'candidate_value': null,
        });
      }
      return _rpc(out);
    }
    return http.Response(json.encode({'error': 'unhandled'}), 400);
  });
}

List<int> _leBytes(int width, BigInt v) {
  final out = List<int>.filled(width, 0);
  var x = v;
  for (var i = 0; i < width; i++) {
    out[i] = (x & BigInt.from(0xFF)).toInt();
    x = x >> 8;
  }
  return out;
}

void main() {
  const wmas = 'AS12FW5Rs5YN2zdpEnqwj4iHUUPt9R4Eqjq2qtpJFNKW3mn33RuLU';

  group('Mrc20Service.loadToken — live node format', () {
    test('parses NAME/SYMBOL/DECIMALS from datastore', () async {
      final datastore = <String, Map<String, List<int>>>{
        wmas: {
          'NAME'.codeUnits.join(','): utf8.encode('Wrapped Massa'),
          'SYMBOL'.codeUnits.join(','): utf8.encode('WMAS'),
          'DECIMALS'.codeUnits.join(','): [9],
          'TOTAL_SUPPLY'.codeUnits.join(','): _leBytes(32, BigInt.from(1000)),
        },
      };
      final svc = Mrc20Service(
        clientFactory: () => MassaRpcClient(
          endpoint: 'https://example.org/api/v2',
          httpClient: _mockNode(datastore),
        ),
      );
      final token = await svc.loadToken(wmas);
      expect(token.name, 'Wrapped Massa');
      expect(token.symbol, 'WMAS');
      expect(token.decimals, 9);
      expect(token.totalSupply, BigInt.from(1000));
    });

    test('not an MRC-20 throws RpcException', () async {
      final svc = Mrc20Service(
        clientFactory: () => MassaRpcClient(
          endpoint: 'https://example.org/api/v2',
          httpClient: _mockNode({}),
        ),
      );
      expect(() => svc.loadToken('AS1notatoken'), throwsA(isA<RpcException>()));
    });
  });

  group('Mrc20Service.balanceOf', () {
    test('reads BALANCE<addr> u256le entry', () async {
      const owner = 'AU126tkwrhXn9gEG5JPtrNy8NNLbVMwywokgLKshSYyzP8qusqXZL';
      final datastore = <String, Map<String, List<int>>>{
        wmas: {
          'BALANCE$owner'.codeUnits.join(','): _leBytes(32, BigInt.from(12345)),
        },
      };
      final svc = Mrc20Service(
        clientFactory: () => MassaRpcClient(
          endpoint: 'https://example.org/api/v2',
          httpClient: _mockNode(datastore),
        ),
      );
      expect(await svc.balanceOf(wmas, owner), BigInt.from(12345));
      expect(await svc.hasBalanceEntry(wmas, owner), isTrue);
    });

    test('falls back to read-only balanceOf call', () async {
      const owner = 'AU126tkwrhXn9gEG5JPtrNy8NNLbVMwywokgLKshSYyzP8qusqXZL';
      final client = MockClient((req) async {
        final body = json.decode(req.body) as Map<String, dynamic>;
        if (body['method'] == 'get_datastore_entries') {
          return _rpc([
            {'final_value': null, 'candidate_value': null},
          ]);
        }
        if (body['method'] == 'execute_read_only_call') {
          return _rpc([
            {
              'result': {'Ok': _leBytes(32, BigInt.from(777))},
              'gas_cost': 1000,
            },
          ]);
        }
        return http.Response(json.encode({'error': 'unhandled'}), 400);
      });
      final svc = Mrc20Service(
        clientFactory: () => MassaRpcClient(
          endpoint: 'https://example.org/api/v2',
          httpClient: client,
        ),
      );
      expect(await svc.balanceOf(wmas, owner), BigInt.from(777));
    });

    test('formatAmount trims trailing zeros', () {
      const t = Mrc20Token(
        address: 'AS1x',
        name: 'Test',
        symbol: 'TST',
        decimals: 9,
      );
      expect(t.formatAmount(BigInt.from(1500000000)), '1.5');
      expect(t.formatAmount(BigInt.from(1000000005)), '1.000000005');
      expect(t.formatAmount(BigInt.from(2000000000)), '2');
    });
  });
}
