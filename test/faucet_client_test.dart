import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:massa_wallet/core/api/faucet_client.dart';

void main() {
  group('FaucetClient', () {
    test('200 response is accepted', () async {
      final client = FaucetClient(
        httpClient: MockClient((req) async {
          final body = json.decode(req.body) as Map<String, dynamic>;
          expect(req.method, 'POST');
          expect(body['address'], 'AU12abc');
          return http.Response(json.encode({'message': 'ok'}), 200);
        }),
      );
      final result = await client.fund('AU12abc');
      expect(result.status, FaucetStatus.accepted);
      expect(result.message, 'ok');
      client.dispose();
    });

    test('429 is reported as rate limited', () async {
      final client = FaucetClient(
        httpClient: MockClient(
          (_) async => http.Response('{"message": "rate limited"}', 429),
        ),
      );
      final result = await client.fund('AU12abc');
      expect(result.status, FaucetStatus.rejected);
      expect(result.message, contains('rate'));
      client.dispose();
    });

    test('4xx carries the faucet error message', () async {
      final client = FaucetClient(
        httpClient: MockClient(
          (_) async => http.Response('{"message": "invalid address"}', 400),
        ),
      );
      final result = await client.fund('AU12bad');
      expect(result.status, FaucetStatus.rejected);
      expect(result.message, 'invalid address');
      client.dispose();
    });

    test('network errors map to failed', () async {
      final client = FaucetClient(
        httpClient: MockClient((_) async => throw Exception('offline')),
      );
      final result = await client.fund('AU12abc');
      expect(result.status, FaucetStatus.failed);
      client.dispose();
    });

    test('empty address is rejected without a request', () async {
      var called = false;
      final client = FaucetClient(
        httpClient: MockClient((_) async {
          called = true;
          return http.Response('', 200);
        }),
      );
      final result = await client.fund('');
      expect(result.status, FaucetStatus.rejected);
      expect(called, isFalse);
      client.dispose();
    });
  });
}
