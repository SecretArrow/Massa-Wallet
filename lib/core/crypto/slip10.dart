/// SLIP-0010 hierarchical derivation for ed25519 (hardened only).
///
/// Spec: github.com/satoshilabs/slips/blob/master/slip-0010.md
/// ed25519 supports exclusively hardened (2^31-shifted) child keys.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;

/// Derivation result: 32-byte private key + 32-byte chain code.
class Slip10Node {
  /// 32-byte ed25519 seed/private key.
  final Uint8List key;

  /// 32-byte chain code.
  final Uint8List chainCode;

  const Slip10Node(this.key, this.chainCode);
}

/// Derives the ed25519 master node from a BIP-39 (or any) seed:
/// `I = HMAC-SHA512(key="ed25519 seed", data=seed)`.
Slip10Node slip10Ed25519Master(List<int> seed) {
  final mac = c.Hmac(c.sha512, utf8.encode('ed25519 seed'));
  final i = mac.convert(seed).bytes;
  return Slip10Node(
    Uint8List.fromList(i.sublist(0, 32)),
    Uint8List.fromList(i.sublist(32, 64)),
  );
}

/// Derives the child node at hardened [index] (0 ≤ index < 2^31):
/// `I = HMAC-SHA512(chainCode, 0x00 ‖ key ‖ ser32(index + 0x80000000))`.
Slip10Node slip10Ed25519Child(Slip10Node parent, int index) {
  if (index < 0 || index >= 1 << 31) {
    throw ArgumentError('ed25519 supports hardened indexes only (0…2^31-1)');
  }
  final data = BytesBuilder()
    ..addByte(0x00)
    ..add(parent.key)
    ..add(_ser32(index + (1 << 31)));
  final mac = c.Hmac(c.sha512, parent.chainCode);
  final i = mac.convert(data.toBytes()).bytes;
  return Slip10Node(
    Uint8List.fromList(i.sublist(0, 32)),
    Uint8List.fromList(i.sublist(32, 64)),
  );
}

/// Walks [path] of hardened indexes from the master node.
///
/// The path is given un-shifted: `[44, 4478, 0, 0, 0]` means
/// `m/44'/4478'/0'/0'/0'`.
Uint8List slip10DeriveEd25519(List<int> seed, List<int> path) {
  var node = slip10Ed25519Master(seed);
  for (final index in path) {
    node = slip10Ed25519Child(node, index);
  }
  return node.key;
}

/// Parses `"m/44'/4478'/0'/0'/0'"` into hardened indexes.
/// The bare master path `"m"` yields an empty list.
List<int> parseDerivationPath(String path) {
  final p = path.trim();
  if (p == 'm') return const [];
  if (!p.startsWith('m/')) {
    throw const FormatException('path must start with m/');
  }
  return p
      .substring(2)
      .split('/')
      .map((seg) {
        if (!seg.endsWith("'") && !seg.endsWith('h')) {
          throw FormatException(
            'non-hardened segment "$seg" (ed25519 is hardened-only)',
          );
        }
        return int.parse(seg.substring(0, seg.length - 1));
      })
      .toList();
}

Uint8List _ser32(int i) => Uint8List(4)
  ..[0] = (i >> 24) & 0xff
  ..[1] = (i >> 16) & 0xff
  ..[2] = (i >> 8) & 0xff
  ..[3] = i & 0xff;
