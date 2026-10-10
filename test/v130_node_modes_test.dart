/// v1.3.0 — connection modes (public RPC / custom RPC / embedded node),
/// endpoint resolution, node config patching, settings migration and
/// i18n coverage for the new node UI.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:massa_wallet/core/api/massa_rpc.dart';
import 'package:massa_wallet/core/i18n/translations.dart' show translations;
import 'package:massa_wallet/core/services/embedded_node_service.dart';
import 'package:massa_wallet/core/services/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveEndpoint (pure)', () {
    const defaultUrl = 'https://buildnet.massa.net/api/v2';
    const customUrl = 'http://192.168.1.10:33035';
    const embeddedUrl = 'http://127.0.0.1:33036/api/v2';

    test('publicRpc uses the default endpoint', () {
      expect(
        resolveEndpoint(
          mode: 'publicRpc',
          customUrl: customUrl,
          defaultUrl: defaultUrl,
          embeddedUrl: embeddedUrl,
          embeddedUsable: true,
        ),
        defaultUrl,
      );
    });

    test('customRpc uses the custom URL when set', () {
      expect(
        resolveEndpoint(
          mode: 'customRpc',
          customUrl: customUrl,
          defaultUrl: defaultUrl,
          embeddedUrl: embeddedUrl,
          embeddedUsable: true,
        ),
        customUrl,
      );
    });

    test('customRpc falls back to default when URL empty', () {
      expect(
        resolveEndpoint(
          mode: 'customRpc',
          customUrl: '',
          defaultUrl: defaultUrl,
          embeddedUrl: embeddedUrl,
          embeddedUsable: true,
        ),
        defaultUrl,
      );
    });

    test('embedded uses the loopback endpoint on buildnet', () {
      expect(
        resolveEndpoint(
          mode: 'embedded',
          customUrl: customUrl,
          defaultUrl: defaultUrl,
          embeddedUrl: embeddedUrl,
          embeddedUsable: true,
        ),
        embeddedUrl,
      );
    });

    test('embedded falls back to public RPC on mainnet', () {
      expect(
        resolveEndpoint(
          mode: 'embedded',
          customUrl: customUrl,
          defaultUrl: defaultUrl,
          embeddedUrl: embeddedUrl,
          embeddedUsable: false,
        ),
        defaultUrl,
      );
    });

    test('unknown mode falls back to default', () {
      expect(
        resolveEndpoint(
          mode: 'bogus',
          customUrl: customUrl,
          defaultUrl: defaultUrl,
          embeddedUrl: embeddedUrl,
          embeddedUsable: true,
        ),
        defaultUrl,
      );
    });
  });

  group('SettingsProvider connection modes', () {
    test('legacy useCustomNode=true migrates to customRpc mode', () async {
      SharedPreferences.setMockInitialValues({
        'settings.useCustomNode': true,
        'settings.customNodeUrl': 'http://10.0.0.5:33035',
      });
      final s = SettingsProvider();
      await s.load();
      expect(s.connectionMode, NodeConnectionMode.customRpc);
      expect(s.useCustomNode, isTrue);
      expect(s.effectiveEndpoint, 'http://10.0.0.5:33035');
    });

    test('defaults to publicRpc and the network endpoint', () async {
      SharedPreferences.setMockInitialValues({});
      final s = SettingsProvider();
      await s.load();
      expect(s.connectionMode, NodeConnectionMode.publicRpc);
      expect(s.effectiveEndpoint, MassaNetwork.buildnet.apiUrl);
    });

    test('embedded mode serves loopback API v2 on buildnet', () async {
      SharedPreferences.setMockInitialValues({});
      final s = SettingsProvider();
      await s.load();
      await s.setConnectionMode(NodeConnectionMode.embedded);
      expect(s.embeddedEndpoint, 'http://127.0.0.1:33036/api/v2');
      expect(s.effectiveEndpoint, 'http://127.0.0.1:33036/api/v2');
      expect(s.embeddedUsable, isTrue);
    });

    test('embedded mode falls back to public RPC on mainnet', () async {
      SharedPreferences.setMockInitialValues({});
      final s = SettingsProvider();
      await s.load();
      await s.setConnectionMode(NodeConnectionMode.embedded);
      await s.setNetwork(MassaNetwork.mainnet);
      expect(s.embeddedUsable, isFalse);
      expect(s.effectiveEndpoint, MassaNetwork.mainnet.apiUrl);
    });

    test('mode persists and keeps the legacy flag coherent', () async {
      SharedPreferences.setMockInitialValues({});
      final s = SettingsProvider();
      await s.load();
      await s.setCustomNodeUrl('http://192.168.0.7:33035');
      await s.setConnectionMode(NodeConnectionMode.customRpc);
      final p = await SharedPreferences.getInstance();
      expect(p.getString('settings.connectionMode'), 'customRpc');
      expect(p.getBool('settings.useCustomNode'), isTrue);
      final s2 = SettingsProvider();
      await s2.load();
      expect(s2.connectionMode, NodeConnectionMode.customRpc);
      expect(s2.customNodeUrl, 'http://192.168.0.7:33035');
    });
  });

  group('patchNodeConfig (pure)', () {
    const sample = '''
[api]
    bind_private = "127.0.0.1:33034"
    bind_public = "0.0.0.0:33035"
    bind_api = "0.0.0.0:33036"
[grpc.public]
    bind = "0.0.0.0:33037"
[grpc.private]
    bind = "127.0.0.1:33038"
[metrics]
    enabled = true
    bind = "[::]:31248"
''';

    test('forces all public binds onto loopback', () {
      final out = patchNodeConfig(sample);
      expect(out.contains('bind_public = "0.0.0.0:33035"'), isFalse);
      expect(out.contains('bind_public = "127.0.0.1:33035"'), isTrue);
      expect(out.contains('bind_api = "0.0.0.0:33036"'), isFalse);
      expect(out.contains('bind_api = "127.0.0.1:33036"'), isTrue);
      expect(out.contains('bind = "0.0.0.0:33037"'), isFalse);
      expect(out.contains('bind = "127.0.0.1:33037"'), isTrue);
      expect(out.contains('bind = "[::]:31248"'), isFalse);
      expect(out.contains('bind = "127.0.0.1:31248"'), isTrue);
      // untouched
      expect(out.contains('bind_private = "127.0.0.1:33034"'), isTrue);
      expect(out.contains('bind = "127.0.0.1:33038"'), isTrue);
    });

    test('supports a custom API v2 port', () {
      final out = patchNodeConfig(sample, apiPort: 34000);
      expect(out.contains('bind_api = "127.0.0.1:34000"'), isTrue);
    });

    test('leaves the P2P protocol bind alone', () {
      final src = '$sample\n[protocol]\n    bind = "[::]:31244"\n';
      final out = patchNodeConfig(src);
      expect(out.contains('bind = "[::]:31244"'), isTrue);
    });
  });

  group('embedded node assets', () {
    test('bundled config matches the pinned massa revision', () async {
      expect(bundledNodeVersion, 'DEVN.30.2');
    });

    test('bundled base config ships the buildnet bootstrap list', () async {
      final data = await rootBundle.load('assets/node/config.toml');
      final config = utf8.decode(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      // Known buildnet bootstrap server from the official DEVN.30.2 tag.
      expect(config.contains('149.202.84.39:31245'), isTrue);
      expect(
        config.contains('N12sNdL7YwSawpnJrk9XCWDjKbgfNamAobp62AX5qfkgpBkGh2wC'),
        isTrue,
      );
      // API v2 port present for the patcher to rebind.
      expect(config.contains('bind_api = "0.0.0.0:33036"'), isTrue);
    });

    test('initial ledger asset is valid JSON', () async {
      final data = await rootBundle.load('assets/node/initial_ledger.json');
      final decoded = json.decode(
        utf8.decode(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        ),
      );
      expect(decoded, isA<Map<String, dynamic>>());
    });
  });

  group('i18n coverage for v1.3.0 keys', () {
    const newKeys = [
      'node.mode.public.title',
      'node.mode.custom.title',
      'node.mode.embedded.title',
      'node.embedded.start',
      'node.embedded.stop',
      'node.embedded.logs',
      'node.embedded.reset',
      'node.embedded.warning',
      'node.embedded.unavailable',
      'node.embedded.mainnet',
      'node.custom.save',
      'dashboard.nodeOffline',
    ];

    for (final key in newKeys) {
      test('key "$key" exists in both languages', () {
        expect(translations['en']?[key], isNotNull);
        expect(translations['id']?[key], isNotNull);
      });
    }

    test('all embedded state keys exist', () {
      for (final state in [
        'stopped',
        'starting',
        'running',
        'failed',
        'unsupported',
      ]) {
        expect(translations['en']?['node.embedded.state.$state'], isNotNull);
        expect(translations['id']?['node.embedded.state.$state'], isNotNull);
      }
    });
  });
}
