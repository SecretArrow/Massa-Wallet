/// v1.6.1 — embedded-node failure diagnostics, per-network binaries and
/// the security fail-open policy.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massa_wallet/core/api/massa_rpc.dart';
import 'package:massa_wallet/core/services/embedded_node_service.dart';
import 'package:massa_wallet/core/services/security_service.dart';

void main() {
  group('diagnoseStartFailure (pure)', () {
    test('extracts the missing library from a Bionic linker error', () {
      final diag = diagnoseStartFailure([
        '13:00:01 node started (pid 12345)',
        '13:00:01 CANNOT LINK EXECUTABLE "/data/app/.../lib/arm64/'
            'libmassa_node.so": library "libc++_shared.so" not found',
      ]);
      expect(diag.kind, EmbeddedFailureKind.missingLib);
      expect(diag.missingLib, 'libc++_shared.so');
    });

    test('handles cannot-locate-symbol linker errors', () {
      final diag = diagnoseStartFailure([
        'CANNOT LINK EXECUTABLE: cannot locate symbol "__emutls_get_address"',
      ]);
      expect(diag.kind, EmbeddedFailureKind.missingLib);
      // No quoted library name in this message shape.
      expect(diag.missingLib, isNull);
    });

    test('detects permission-denied exec failures', () {
      final diag = diagnoseStartFailure(['execve failed: Permission denied']);
      expect(diag.kind, EmbeddedFailureKind.permissionDenied);
    });

    test('detects exec-format (wrong ABI) failures', () {
      final diag = diagnoseStartFailure(['exec: Exec format error']);
      expect(diag.kind, EmbeddedFailureKind.execFormat);
    });

    test('falls back to generic for unrelated logs', () {
      final diag = diagnoseStartFailure([
        'node started (pid 1)',
        'INFO protocol: bootstrap started',
      ]);
      expect(diag.kind, EmbeddedFailureKind.generic);
      expect(diag.missingLib, isNull);
    });

    test('empty logs are generic', () {
      expect(diagnoseStartFailure(const []).kind, EmbeddedFailureKind.generic);
    });

    test('scans only the tail of long logs', () {
      final logs = <String>[
        for (var i = 0; i < 100; i++) 'log line $i',
        'CANNOT LINK EXECUTABLE: library "libfoo.so" not found',
      ];
      expect(diagnoseStartFailure(logs).missingLib, 'libfoo.so');
    });
  });

  group('per-network binary naming (pure)', () {
    test('buildnet binary and data dir keep the legacy names', () {
      expect(binaryNameFor(MassaNetwork.buildnet), 'libmassa_node.so');
      expect(dataDirNameFor(MassaNetwork.buildnet), 'massa-node');
      expect(configAssetDirFor(MassaNetwork.buildnet), 'assets/node');
      expect(configVersionFor(MassaNetwork.buildnet), 'DEVN.30.2');
    });

    test('mainnet gets a dedicated binary, data dir and asset profile', () {
      expect(binaryNameFor(MassaNetwork.mainnet), 'libmassa_node_mainnet.so');
      expect(dataDirNameFor(MassaNetwork.mainnet), 'massa-node-mainnet');
      expect(configAssetDirFor(MassaNetwork.mainnet), 'assets/node/mainnet');
      expect(configVersionFor(MassaNetwork.mainnet), 'MAIN.1');
    });
  });

  group('patchNodeConfig (regression)', () {
    test('still forces loopback binds', () {
      final patched = patchNodeConfig('''
[api]
    bind_public = "0.0.0.0:33035"
    bind_api = "0.0.0.0:33036"
''', apiPort: 34000);
      expect(patched, contains('127.0.0.1:34000'));
      expect(patched, contains('127.0.0.1:33035'));
      expect(patched, isNot(contains('0.0.0.0')));
    });
  });

  group('shouldFailOpenOnLocalAuthError (pure)', () {
    test('fails open on no-credential / not-enrolled codes', () {
      for (final code in const [
        'noCredentialsSet',
        'no_credentials',
        'notEnrolled',
        'not_enrolled',
        'noHardware',
        'notAvailable',
      ]) {
        expect(
          shouldFailOpenOnLocalAuthError(code),
          isTrue,
          reason: 'code=$code must fail open',
        );
      }
    });

    test('never fails open on user-rejection / lockout codes', () {
      for (final code in const [
        'userCancel',
        'user_cancel',
        'permanentlyLockedOut',
        'permanently_locked_out',
        'lockout',
        'authInProgress',
        '',
      ]) {
        expect(
          shouldFailOpenOnLocalAuthError(code),
          isFalse,
          reason: 'code=$code must NOT fail open',
        );
      }
    });
  });
}
