import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:massa_wallet/core/api/massa_rpc.dart';
import 'package:massa_wallet/core/contracts/deweb_service.dart';
import 'package:massa_wallet/core/contracts/local_site_server.dart';
import 'package:massa_wallet/core/contracts/mns_service.dart';

http.Response _rpc(dynamic result, {int id = 0}) => http.Response(
  json.encode({'jsonrpc': '2.0', 'id': id, 'result': result}),
  200,
);

/// Builds a mock node that answers `get_datastore_entries` from an
/// in-memory datastore and `execute_read_only_call` from a handler.
http.Client _mockNode({
  Map<String, Map<String, List<int>>> datastore = const {},
  String? Function(List<int> parameter)? dnsResolve,
}) {
  return MockClient((req) async {
    final body = json.decode(req.body) as Map<String, dynamic>;
    final method = body['method'] as String;
    final params = (body['params'] as List)[0];
    if (method == 'get_datastore_entries') {
      final out = <dynamic>[];
      for (final e in params as List) {
        final addr = e['address'] as String;
        final key = (e['key'] as List).cast<int>();
        out.add({
          'final_value': datastore[addr]?[key.join(',')],
          'candidate_value': null,
        });
      }
      return _rpc(out);
    }
    if (method == 'execute_read_only_call') {
      final call = (params as List).first as Map<String, dynamic>;
      final res = dnsResolve?.call((call['parameter'] as List).cast<int>());
      if (res == null) {
        return _rpc([
          {
            'result': {'Error': 'not found'},
            'gas_cost': 100,
          },
        ]);
      }
      return _rpc([
        {
          'result': {'Ok': utf8.encode(res)},
          'gas_cost': 2100000,
        },
      ]);
    }
    if (method == 'get_addresses') {
      return _rpc([
        {
          'address': (params as List).first as String,
          'final_balance': '0',
          'candidate_balance': '0',
          'final_roll_count': 0,
          'candidate_roll_count': 0,
          'final_datastore_keys': [],
          'candidate_datastore_keys': [],
          'cycle_infos': [],
        },
      ]);
    }
    return http.Response(json.encode({'error': 'unhandled'}), 400);
  });
}

void main() {
  group('MnsService.parseInput', () {
    test('bare domain', () {
      final r = MnsService.parseInput('helloworld');
      expect(r.domain, 'helloworld');
      expect(r.address, isNull);
      expect(r.path, '');
    });

    test('domain.massa with path', () {
      final r = MnsService.parseInput('site.massa/docs/intro');
      expect(r.domain, 'site');
      expect(r.path, 'docs/intro');
    });

    test('https URL with massa host', () {
      final r = MnsService.parseInput('https://site.massa/index.html');
      expect(r.domain, 'site');
      expect(r.path, 'index.html');
    });

    test('massa scheme', () {
      final r = MnsService.parseInput('massa://name.massa');
      expect(r.domain, 'name');
    });

    test('raw SC address', () {
      final r = MnsService.parseInput(
        'AS12qKAVjU1nr66JSkQ6N4Lqu4iwuVc6rAbRTrxFoynPrPdP1sj3G/file.js',
      );
      expect(
        r.address,
        'AS12qKAVjU1nr66JSkQ6N4Lqu4iwuVc6rAbRTrxFoynPrPdP1sj3G',
      );
      expect(r.path, 'file.js');
    });
  });

  group('MnsService.resolve', () {
    test('resolves via dnsResolve read call', () async {
      final client = _mockNode(
        dnsResolve: (param) {
          // u32le len + bytes
          final len =
              param[0] | (param[1] << 8) | (param[2] << 16) | (param[3] << 24);
          return 'AS1target${utf8.decode(param.sublist(4, 4 + len))}';
        },
      );
      final svc = MnsService(
        clientFactory: () => MassaRpcClient(
          endpoint: 'https://example.org/api/v2',
          httpClient: client,
        ),
      );
      final res = await svc.resolve('hello', mainnet: false);
      expect(res.target, 'AS1targethello');
      expect(res.isSmartContract, isTrue);
      // Cached second call works.
      final res2 = await svc.resolve('hello', mainnet: false);
      expect(res2.target, 'AS1targethello');
    });

    test('throws for unknown domain', () async {
      final client = _mockNode(datastore: const {}, dnsResolve: (_) => null);
      final svc = MnsService(
        clientFactory: () => MassaRpcClient(
          endpoint: 'https://example.org/api/v2',
          httpClient: client,
        ),
      );
      expect(
        () => svc.resolve('ghost', mainnet: false),
        throwsA(isA<MnsException>()),
      );
    });
  });

  group('DeWeb file standard', () {
    test('path hash = sha256(normalized path)', () {
      // Live-verified: helloworld.massa stores files under
      // sha256('index.html') — digest observed in real datastore keys.
      final h = deWebPathHash('index.html');
      const expected = [
        0x0e, 0xb5, 0x47, 0x30, 0x46, 0x58, 0x80, 0x5a, //
        0xad, 0x78, 0x8d, 0x32, 0x0f, 0x10, 0xbf, 0x1f,
        0x29, 0x27, 0x97, 0xb5, 0xe6, 0xd7, 0x45, 0xa3,
        0xbf, 0x61, 0x75, 0x84, 0xda, 0x01, 0x70, 0x51,
      ];
      expect(h, expected);
      expect(
        h,
        deWebPathHash('/index.html'),
        reason: 'leading slash is normalized away',
      );
    });

    test('candidate paths include .html and index fallbacks', () {
      expect(deWebPathCandidates(''), ['index.html']);
      expect(deWebPathCandidates('/'), ['index.html']);
      expect(deWebPathCandidates('/about'), [
        'about',
        'about.html',
        'about/index.html',
        'index.html',
      ]);
      expect(deWebPathCandidates('/page.html'), ['page.html', 'index.html']);
    });

    test('mime types', () {
      expect(mimeTypeFor('index.html'), 'text/html');
      expect(mimeTypeFor('app.js'), 'application/javascript');
      expect(mimeTypeFor('style.css'), 'text/css');
      expect(mimeTypeFor('img.png'), 'image/png');
      expect(mimeTypeFor('blob.bin'), 'application/octet-stream');
    });

    test('fetchFile assembles chunks in order', () async {
      const site = 'AS1site';
      final hash = deWebPathHash('index.html');
      final chunkNbKey = DeWebKeys.chunkCountKey(hash);
      final datastore = <String, Map<String, List<int>>>{
        site: {
          chunkNbKey.join(','): [2, 0, 0, 0],
          DeWebKeys.chunkKey(hash, 0).join(','): utf8.encode('<html>'),
          DeWebKeys.chunkKey(hash, 1).join(','): utf8.encode('</html>'),
        },
      };
      final svc = DeWebService(
        clientFactory: () => MassaRpcClient(
          endpoint: 'https://example.org/api/v2',
          httpClient: _mockNode(datastore: datastore),
        ),
      );
      final file = await svc.fetchFile(site, '/index.html');
      expect(file.path, 'index.html');
      expect(utf8.decode(file.bytes), '<html></html>');
      expect(file.mimeType, 'text/html');
    });

    test('fetchFile falls back to index.html for SPA routes', () async {
      const site = 'AS1site';
      final idxHash = deWebPathHash('index.html');
      final datastore = <String, Map<String, List<int>>>{
        site: {
          DeWebKeys.chunkCountKey(idxHash).join(','): [1, 0, 0, 0],
          DeWebKeys.chunkKey(idxHash, 0).join(','): utf8.encode('SPA!'),
        },
      };
      final svc = DeWebService(
        clientFactory: () => MassaRpcClient(
          endpoint: 'https://example.org/api/v2',
          httpClient: _mockNode(datastore: datastore),
        ),
      );
      final file = await svc.fetchFile(site, 'dashboard/main');
      expect(utf8.decode(file.bytes), 'SPA!');
    });

    test('missing file throws DeWebException', () async {
      final svc = DeWebService(
        clientFactory: () => MassaRpcClient(
          endpoint: 'https://example.org/api/v2',
          httpClient: _mockNode(datastore: {}),
        ),
      );
      expect(
        () => svc.fetchFile('AS1x', 'index.html'),
        throwsA(isA<DeWebException>()),
      );
    });
  });

  group('LocalSiteServer', () {
    test('serves datastore content over loopback HTTP', () async {
      const site = 'AS1site';
      final hash = deWebPathHash('style.css');
      final datastore = <String, Map<String, List<int>>>{
        site: {
          DeWebKeys.chunkCountKey(hash).join(','): [1, 0, 0, 0],
          DeWebKeys.chunkKey(hash, 0).join(','): utf8.encode('body{}'),
        },
      };
      final deweb = DeWebService(
        clientFactory: () => MassaRpcClient(
          endpoint: 'https://example.org/api/v2',
          httpClient: _mockNode(datastore: datastore),
        ),
      );
      final server = LocalSiteServer(deweb: deweb);
      await server.start();
      server.serveSite(site);
      expect(server.baseUrl, startsWith('http://127.0.0.1:'));

      final client = http.Client();
      final res = await client.get(Uri.parse('${server.baseUrl}/style.css'));
      expect(res.statusCode, 200);
      expect(res.headers['content-type'], contains('text/css'));
      expect(res.body, 'body{}');

      final res404 = await client.get(
        Uri.parse('${server.baseUrl}/missing.js'),
      );
      expect(res404.statusCode, 404);

      await server.stop();
      client.close();
    });
  });
}
