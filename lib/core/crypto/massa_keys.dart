/// Massa account keys, addresses and signatures.
///
/// Wire formats are byte-compatible with `@massalabs/massa-web3` v5
/// (VarintVersioner, V0):
///
/// | Object     | Format                                                     |
/// |------------|------------------------------------------------------------|
/// | PrivateKey | `"S"  + base58check(varint(0) + 32-byte raw key)`           |
/// | PublicKey  | `"P"  + base58check(varint(0) + 32-byte raw public key)`    |
/// | Address    | `"AU" + base58check(varint(0) + blake3(versioned pubkey))`  |
/// | SC address | `"AS" + base58check(varint(1) + 32-byte digest)`            |
/// | Signature  | `base58check(varint(0) + 64-byte ed25519 signature)` (no prefix) |
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;

import 'base58_check.dart';
import 'massa_hash.dart';
import 'varint.dart';

const String _privateKeyPrefix = 'S';
const String _publicKeyPrefix = 'P';
const String _addressUserPrefix = 'AU';
const String _addressContractPrefix = 'AS';

/// Address type byte — externally owned account.
const int addressTypeEoa = 0x00;

/// Address type byte — smart contract.
const int addressTypeContract = 0x01;

/// Key / address / signature scheme version (VarintVersioner V0).
const int massaVersionV0 = 0x00;

/// Generates cryptographically-secure random bytes.
Uint8List randomBytes(int length) {
  final rng = Random.secure();
  return Uint8List.fromList(
    List<int>.generate(length, (_) => rng.nextInt(256)),
  );
}

/// Prepends the varint-encoded version byte to [data]
/// (mirror of massa-web3 `VarintVersioner.attach`).
Uint8List attachVersion(List<int> data, [int version = massaVersionV0]) =>
    Uint8List.fromList([...varintEncodeInt(version), ...data]);

/// Extracts the versioned payload from [data].
({int version, Uint8List data}) extractVersion(List<int> data) {
  final r = varintDecode(data);
  return (
    version: r.value.toInt(),
    data: Uint8List.fromList(data.sublist(r.bytes)),
  );
}

/// A Massa private key (ed25519).
class MassaPrivateKey {
  /// Raw 32-byte ed25519 seed.
  final Uint8List raw;

  MassaPrivateKey._(this.raw);

  /// Generates a new random private key.
  factory MassaPrivateKey.generate() {
    final seed = randomBytes(32);
    return MassaPrivateKey._(seed);
  }

  /// Parses a `"S..."` Massa secret key string.
  factory MassaPrivateKey.fromString(String str) {
    if (!str.startsWith(_privateKeyPrefix)) {
      throw const FormatException('invalid private key: expected "S" prefix');
    }
    final payload = base58CheckDecode(str.substring(1));
    final extracted = extractVersion(payload);
    if (extracted.data.length != 32) {
      throw const FormatException('invalid private key length');
    }
    return MassaPrivateKey._(extracted.data);
  }

  /// Builds a key from the raw 32-byte seed.
  factory MassaPrivateKey.fromBytes(List<int> bytes) {
    if (bytes.length != 32) {
      throw const FormatException('invalid private key length');
    }
    return MassaPrivateKey._(Uint8List.fromList(bytes));
  }

  /// Derives the matching public key.
  MassaPublicKey get publicKey {
    final pub = ed.public(_edKey);
    return MassaPublicKey._(Uint8List.fromList(pub.bytes));
  }

  ed.PrivateKey get _edKey => ed.newKeyFromSeed(Uint8List.fromList(raw));

  /// Versioned private-key bytes (`varint(0) + seed`).
  Uint8List get versionedBytes => attachVersion(raw);

  /// Serializes to `"S..."` Massa secret key string.
  String get encoded => _privateKeyPrefix + base58CheckEncode(versionedBytes);

  /// Signs [message] (hashed internally with BLAKE3, exactly like massa-web3).
  MassaSignature signMessage(List<int> message) {
    final digest = massaHash(message);
    final sig = ed.sign(_edKey, Uint8List.fromList(digest));
    return MassaSignature._(Uint8List.fromList(sig));
  }

  /// Signs already-serialized operation payload bytes.
  MassaSignature signOperation(List<int> canonicalBytes) =>
      signMessage(canonicalBytes);
}

/// A Massa public key (ed25519).
class MassaPublicKey {
  /// Raw 32-byte ed25519 public key.
  final Uint8List raw;

  MassaPublicKey._(this.raw);

  /// Parses a `"P..."` Massa public key string.
  factory MassaPublicKey.fromString(String str) {
    if (!str.startsWith(_publicKeyPrefix)) {
      throw const FormatException('invalid public key: expected "P" prefix');
    }
    final payload = base58CheckDecode(str.substring(1));
    final extracted = extractVersion(payload);
    if (extracted.data.length != 32) {
      throw const FormatException('invalid public key length');
    }
    return MassaPublicKey._(extracted.data);
  }

  /// Builds a public key from the raw 32 bytes.
  factory MassaPublicKey.fromBytes(List<int> bytes) {
    if (bytes.length != 32) {
      throw const FormatException('invalid public key length');
    }
    return MassaPublicKey._(Uint8List.fromList(bytes));
  }

  /// Versioned public-key bytes (`varint(0) + 32B`).
  Uint8List get versionedBytes => attachVersion(raw);

  /// Serializes to `"P..."` Massa public key string.
  String get encoded => _publicKeyPrefix + base58CheckEncode(versionedBytes);

  /// Derives the user address (`AU...`).
  MassaAddress get address => MassaAddress.fromPublicKey(this);

  /// Verifies a signature over [message] (BLAKE3-hashed internally).
  bool verify(List<int> message, MassaSignature signature) {
    final digest = massaHash(message);
    return ed.verify(
      ed.PublicKey(Uint8List.fromList(raw)),
      Uint8List.fromList(digest),
      Uint8List.fromList(signature.raw),
    );
  }
}

/// A Massa address (`AU...` user / `AS...` smart contract).
class MassaAddress {
  /// Type (0 = EOA, 1 = contract) followed by versioned digest.
  final Uint8List bytes;

  MassaAddress._(this.bytes);

  /// Derives the EOA address from a public key:
  /// `AU + b58check(varint(0) + blake3(versioned pubkey))`.
  factory MassaAddress.fromPublicKey(MassaPublicKey publicKey) {
    final digest = massaHash(publicKey.versionedBytes);
    final payload = attachVersion(digest);
    return MassaAddress._(Uint8List.fromList([addressTypeEoa, ...payload]));
  }

  /// Parses `"AU..."` (user) or `"AS..."` (contract) address strings.
  factory MassaAddress.fromString(String str) {
    final bool isEoa;
    final String rest;
    if (str.startsWith(_addressUserPrefix)) {
      isEoa = true;
      rest = str.substring(2);
    } else if (str.startsWith(_addressContractPrefix)) {
      isEoa = false;
      rest = str.substring(2);
    } else {
      throw const FormatException(
        'invalid address: expected "AU" or "AS" prefix',
      );
    }
    final payload = base58CheckDecode(rest);
    final extracted = extractVersion(payload);
    if (extracted.data.length != 32) {
      throw const FormatException('invalid address length');
    }
    final type = isEoa ? addressTypeEoa : addressTypeContract;
    return MassaAddress._(
      Uint8List.fromList([
        type,
        ...varintEncodeInt(extracted.version),
        ...extracted.data,
      ]),
    );
  }

  /// Builds a contract address from a raw 32-byte digest.
  factory MassaAddress.contract(List<int> digest) {
    if (digest.length != 32) {
      throw const FormatException('invalid contract address length');
    }
    return MassaAddress._(
      Uint8List.fromList([addressTypeContract, ...attachVersion(digest)]),
    );
  }

  /// Whether this is an externally owned account address.
  bool get isEoa => bytes.isNotEmpty && bytes.first == addressTypeEoa;

  /// Bytes used inside serialized operations (type + version + 32B digest).
  Uint8List get operationBytes => bytes;

  /// Serializes to `"AU..."` / `"AS..."`.
  String get encoded {
    final type = bytes.first;
    final payload = bytes.sublist(1);
    final prefix = type == addressTypeEoa
        ? _addressUserPrefix
        : _addressContractPrefix;
    return prefix + base58CheckEncode(payload);
  }
}

/// A Massa signature — serialized without prefix:
/// `base58check(varint(0) + 64-byte ed25519 signature)`.
class MassaSignature {
  /// Raw 64-byte ed25519 signature.
  final Uint8List raw;

  MassaSignature._(this.raw);

  /// Builds a signature from the raw 64 bytes.
  factory MassaSignature.fromBytes(List<int> bytes) {
    if (bytes.length != 64) {
      throw const FormatException('invalid signature length');
    }
    return MassaSignature._(Uint8List.fromList(bytes));
  }

  /// Parses a serialized Massa signature (no textual prefix).
  factory MassaSignature.fromString(String str) {
    final payload = base58CheckDecode(str);
    final extracted = extractVersion(payload);
    if (extracted.data.length != 64) {
      throw const FormatException('invalid signature length');
    }
    return MassaSignature._(extracted.data);
  }

  /// Serializes to the prefix-less Massa signature string.
  String get encoded => base58CheckEncode(attachVersion(raw));
}
