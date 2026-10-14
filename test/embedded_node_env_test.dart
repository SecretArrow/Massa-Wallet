// Unit tests for the embedded-node child-process environment and the
// background-keepalive crash-loop cooldown.
//
// Regression coverage for the "CANNOT LINK EXECUTABLE: library
// libc++_shared.so not found" crash loop: Process.start(environment:)
// REPLACES the inherited environment, so the spawn map must merge the
// base environment and put nativeLibraryDir at the FRONT of
// LD_LIBRARY_PATH.

import 'package:flutter_test/flutter_test.dart';
import 'package:massa_wallet/core/services/embedded_node_service.dart';

void main() {
  group('buildNodeEnv', () {
    const libDir = '/data/app/~~abc/site.massawallet.app-xyz==/lib/arm64';

    test('injects MASSA_CONFIG_PATH', () {
      final env = buildNodeEnv(libDir, '/cfg/config.toml', base: {});
      expect(env['MASSA_CONFIG_PATH'], '/cfg/config.toml');
    });

    test('prepends libDir to an existing LD_LIBRARY_PATH', () {
      final env = buildNodeEnv(
        libDir,
        '/cfg/config.toml',
        base: {'LD_LIBRARY_PATH': '/vendor/lib64:/system/lib64'},
      );
      expect(
        env['LD_LIBRARY_PATH'],
        '$libDir:/vendor/lib64:/system/lib64',
      );
    });

    test('creates LD_LIBRARY_PATH when the base has none', () {
      final env = buildNodeEnv(libDir, '/cfg/config.toml', base: {'HOME': '/'});
      expect(env['LD_LIBRARY_PATH'], libDir);
      // The rest of the base environment must be preserved (merge, not
      // replace) — HOME, PATH, TMPDIR, OEM additions …
      expect(env['HOME'], '/');
    });

    test('handles empty and dangling-colon entries', () {
      final env = buildNodeEnv(
        libDir,
        '/cfg/config.toml',
        base: {'LD_LIBRARY_PATH': ':/system/lib64:'},
      );
      expect(env['LD_LIBRARY_PATH'], '$libDir:/system/lib64');
    });

    test('deduplicates libDir when already present', () {
      final env = buildNodeEnv(
        libDir,
        '/cfg/config.toml',
        base: {'LD_LIBRARY_PATH': '$libDir:/system/lib64'},
      );
      expect(env['LD_LIBRARY_PATH'], '$libDir:/system/lib64');
    });

    test('does not mutate the provided base map', () {
      final base = {'LD_LIBRARY_PATH': '/system/lib64'};
      buildNodeEnv(libDir, '/cfg/config.toml', base: base);
      expect(base['LD_LIBRARY_PATH'], '/system/lib64');
      expect(base.containsKey('MASSA_CONFIG_PATH'), isFalse);
    });
  });

  group('nodeRestartBlocked (background keepalive cooldown)', () {
    test('null marker never blocks', () {
      expect(nodeRestartBlocked(null, DateTime(2026, 1, 1)), isFalse);
    });

    test('expired marker does not block', () {
      final now = DateTime(2026, 1, 1, 12, 0);
      final expired = now
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch;
      expect(nodeRestartBlocked(expired, now), isFalse);
    });

    test('future marker blocks the respawn', () {
      final now = DateTime(2026, 1, 1, 12, 0);
      final active = now
          .add(const Duration(minutes: 5))
          .millisecondsSinceEpoch;
      expect(nodeRestartBlocked(active, now), isTrue);
    });

    test('cooldown constant is 10 minutes', () {
      expect(nodeRestartCooldown, const Duration(minutes: 10));
    });
  });

  group('diagnoseStartFailure (regression: linker crash loop)', () {
    test('classifies the exact Bionic error from the field report', () {
      final logs = <String>[
        '16:06:06 base config installed (MAIN.1 · Mainnet)',
        '16:06:06 node started (pid 19088)',
        '16:06:06 CANNOT LINK EXECUTABLE '
            '"/data/app/~~x/site.massawallet.app-y==/lib/arm64/'
            'libmassa_node_mainnet.so": library "libc++_shared.so" '
            'not found: needed by main executable',
      ];
      final diag = diagnoseStartFailure(logs);
      expect(diag.kind, EmbeddedFailureKind.missingLib);
      expect(diag.missingLib, 'libc++_shared.so');
    });

    test('generic exit without linker evidence stays generic', () {
      final diag = diagnoseStartFailure(<String>['node started (pid 1)']);
      expect(diag.kind, EmbeddedFailureKind.generic);
    });
  });
}
