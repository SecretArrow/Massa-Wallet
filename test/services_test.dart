import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:massa_wallet/core/services/activity_history_service.dart';
import 'package:massa_wallet/core/services/address_book_service.dart';
import 'package:massa_wallet/core/services/price_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ActivityHistoryService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('add / load roundtrip and ordering', () async {
      final svc = ActivityHistoryService();
      final older = Activity(
        id: 'a1',
        kind: ActivityKind.send,
        accountAddress: 'AU1abc',
        amountNano: BigInt.from(1500000000),
        counterparty: 'AU1def',
        createdAt: DateTime.utc(2025, 1, 1),
        status: ActivityStatus.submitted,
      );
      final newer = Activity(
        id: 'a2',
        kind: ActivityKind.tokenTransfer,
        accountAddress: 'AU1abc',
        amountNano: BigInt.zero,
        counterparty: 'AS1token',
        createdAt: DateTime.utc(2025, 6, 1),
        status: ActivityStatus.submitted,
        tokenSymbol: 'WMAS',
        tokenAmount: '1.5',
      );
      await svc.add(older);
      await svc.add(newer);
      final all = await svc.load();
      expect(all, hasLength(2));
      expect(all.first.id, 'a2', reason: 'newest first');
      final byAccount = await svc.load(accountAddress: 'AU1abc');
      expect(byAccount, hasLength(2));
      final other = await svc.load(accountAddress: 'AU1zzz');
      expect(other, isEmpty);
    });

    test('updateStatus persists', () async {
      final svc = ActivityHistoryService();
      await svc.add(
        Activity(
          id: 'x1',
          kind: ActivityKind.rollBuy,
          accountAddress: 'AU1abc',
          amountNano: BigInt.zero,
          counterparty: '',
          createdAt: DateTime.utc(2025, 1, 1),
          status: ActivityStatus.submitted,
        ),
      );
      await svc.updateStatus('x1', ActivityStatus.final_);
      final all = await svc.load();
      expect(all.single.status, ActivityStatus.final_);
    });
  });

  group('AddressBookService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('save sorts by name and updates by address', () async {
      final svc = AddressBookService();
      await svc.save(const Contact(name: 'Zed', address: 'AU1zzz'));
      await svc.save(const Contact(name: 'Ana', address: 'AU1aaa'));
      // Re-saving the same address updates the name (dedupe by address).
      await svc.save(const Contact(name: 'Ana2', address: 'AU1aaa'));
      final list = await svc.load();
      expect(list, hasLength(2));
      expect(list.first.name, 'Ana2');
      expect(list.last.name, 'Zed');
    });

    test('delete removes the contact', () async {
      final svc = AddressBookService();
      await svc.save(const Contact(name: 'Bob', address: 'AU1bob'));
      await svc.delete('AU1bob');
      expect(await svc.load(), isEmpty);
    });
  });

  group('PriceService', () {
    test('parses CoinGecko payload', () async {
      SharedPreferences.setMockInitialValues({});
      final client = MockClient((_) async => http.Response(
        json.encode({
          'massa': {
            'usd': 0.0026,
            'usd_24h_change': -0.7,
            'idr': 46.5,
            'idr_24h_change': -0.7,
          },
        }),
        200,
      ));
      final svc = PriceService();
      final price = await svc.fetch(httpClient: client);
      expect(price, isNotNull);
      expect(price!.usd, 0.0026);
      expect(price.idr, 46.5);
      expect(price.change24h, -0.7);
      // Cached on second call (no HTTP hit — MockClient would fail).
      final again = await svc.fetch();
      expect(again!.usd, 0.0026);
    });

    test('offline keeps null without throwing', () async {
      final client = MockClient((_) async => throw Exception('offline'));
      final svc = PriceService();
      final price = await svc.fetch(httpClient: client);
      expect(price, isNull);
    });
  });
}
