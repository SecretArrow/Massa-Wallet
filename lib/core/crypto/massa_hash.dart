/// Hash helpers for Massa (BLAKE3, 256-bit output).
///
/// Massa derives addresses and signs messages using BLAKE3 digests —
/// verified against `@noble/hashes/blake3` as used by `massa-web3`.
library;

import 'dart:typed_data';

import 'package:blake3_dart/blake3_dart.dart';

/// Computes the BLAKE3-256 digest of [data].
Uint8List massaHash(List<int> data) => blake3(Uint8List.fromList(data));
