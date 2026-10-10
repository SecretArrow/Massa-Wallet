import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:massa_wallet/core/contracts/web3_provider.dart';
import 'package:massa_wallet/features/browser/browser_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('massaProviderScript (injected window.massa provider)', () {
    final js = massaProviderScript(
      address: 'AU12abc',
      nickname: 'test',
      chainId: 77658366,
      networkName: 'Buildnet',
    );

    test('registers a single window.massa provider', () {
      expect(js, contains('window.massa = makeProvider()'));
      expect(js, contains('window.massaWallet = window.massa'));
      expect(js, contains('__massaInjected'));
    });

    test('exposes the classic provider methods', () {
      for (final method in [
        'enable',
        'accounts',
        'sign',
        'signOperation',
        'sendTransaction',
        'buyRolls',
        'sellRolls',
        'callSC',
        'balance',
        'request',
      ]) {
        expect(js, contains(method), reason: 'missing $method');
      }
    });

    test('is MassaStation provider-list compatible', () {
      expect(js, contains("providerName = 'MASSAMOBILE'"));
      expect(js, contains('getProviders'));
      expect(js, contains('registerProvider'));
      expect(js, contains("'0'"));
    });

    test('bridges through the MassaMobile channel', () {
      expect(js, contains('MassaMobile.postMessage'));
      expect(js, contains('JSON.stringify'));
      expect(js, contains('__massaResolve'));
    });

    test('injects only once', () {
      expect(js, contains('if (window.__massaInjected) return;'));
    });
  });

  group('Web3Request', () {
    test('tryParse round-trips a valid request', () {
      final req = Web3Request.tryParse(
        json.encode({
          'id': 3,
          'method': 'balance',
          'params': {'address': 'AU1'},
        }),
      );
      expect(req, isNotNull);
      expect(req!.id, 3);
      expect(req.method, 'balance');
      expect(req.params['address'], 'AU1');
    });

    test('tryParse rejects malformed payloads', () {
      expect(Web3Request.tryParse('not json'), isNull);
      expect(Web3Request.tryParse('[1,2]'), isNull);
      expect(Web3Request.tryParse('{"method":"x"}'), isNull);
    });

    test('resolveJs / rejectJs wrap payload for __massaResolve', () {
      final req = Web3Request(id: 7, method: 'accounts', params: const {});
      final resolve = req.resolveJs(['AU1']);
      expect(resolve, contains('__massaResolve(7,'));
      expect(resolve, contains('result'));

      final reject = req.rejectJs('boom');
      expect(reject, contains('__massaResolve(7,'));
      expect(reject, contains('boom'));
    });
  });

  group('BrowserStore', () {
    late BrowserStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      store = BrowserStore(prefs);
    });

    test('bookmarks: empty, add, dedupe-most-recent, remove', () {
      expect(store.bookmarks(), isEmpty);
      store.addBookmark('Explorer', 'https://explorer.massa.net');
      store.addBookmark('Docs', 'https://docs.massa.net');
      expect(store.bookmarks().length, 2);

      // Most recent first.
      expect(store.bookmarks().first.url, 'https://docs.massa.net');

      // Re-adding moves it to the top instead of duplicating.
      store.addBookmark('Explorer', 'https://explorer.massa.net');
      expect(store.bookmarks().length, 2);
      expect(store.bookmarks().first.url, 'https://explorer.massa.net');

      expect(store.isBookmarked('https://explorer.massa.net'), isTrue);
      store.removeBookmark('https://explorer.massa.net');
      expect(store.isBookmarked('https://explorer.massa.net'), isFalse);
    });

    test('history: records, dedupes consecutive, caps at 30', () {
      for (var i = 0; i < 40; i++) {
        store.recordVisit('site$i', 'https://example.com/$i');
      }
      final history = store.history();
      expect(history.length, kHistoryCap);
      expect(history.first.url, 'https://example.com/39');

      // Recording the same page again does not duplicate.
      store.recordVisit('site39', 'https://example.com/39');
      expect(store.history().length, kHistoryCap);
      expect(store.history().first.url, 'https://example.com/39');
    });

    test('history ignores non-http urls', () {
      store.recordVisit('blank', 'about:blank');
      expect(store.history(), isEmpty);
    });

    test('clearHistory empties the list', () {
      store.recordVisit('x', 'https://example.com');
      store.clearHistory();
      expect(store.history(), isEmpty);
    });
  });

  group('kCuratedDapps', () {
    test('entries are https and unique', () {
      final urls = kCuratedDapps.map((d) => d.url).toSet();
      expect(urls.length, kCuratedDapps.length);
      for (final d in kCuratedDapps) {
        expect(d.url, startsWith('https://'));
        expect(d.name, isNotEmpty);
      }
    });
  });
}
