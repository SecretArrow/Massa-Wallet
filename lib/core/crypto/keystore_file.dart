/// Massa Standard wallet-file format (keystore).
///
/// Implements the format defined by
/// [massa-standards/wallet/file-format.md] and used by massa-web3's
/// `Account.toKeyStore` / `Account.fromKeyStore`:
///
/// ```json
/// {
///   "Address": "AU...",
///   "Version": 0,
///   "Nickname": "",
///   "Salt": "<base64>",
///   "Nonce": "<base64>",
///   "CipheredData": "<base64>",
///   "PublicKey": "<base64>"
/// }
/// ```
///
/// Encryption: PBKDF2-HMAC-SHA256 (600,000 iterations, 16-byte salt) →
/// AES-256-GCM (12-byte nonce, 128-bit auth tag appended to ciphertext).
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart' as pc;
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';

const int _keySizeBytes = 32;
const int _nonceSizeBytes = 12;
const int _saltSizeBytes = 16;
const int _owaspIterations = 600000;
const int _macSizeBits = 128;

Uint8List _deriveKey(String password, Uint8List salt) {
  final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(salt, _owaspIterations, _keySizeBytes));
  final pwdBytes = Uint8List.fromList(utf8.encode(password));
  return derivator.process(pwdBytes);
}

/// AES-256-GCM encrypt — returns `ciphertext || 16-byte tag`.
Uint8List aesGcmEncrypt(Uint8List plaintext, Uint8List key, Uint8List nonce) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      true,
      pc.AEADParameters(
        pc.KeyParameter(key),
        _macSizeBits,
        nonce,
        Uint8List(0),
      ),
    );
  return Uint8List.fromList(cipher.process(plaintext));
}

/// AES-256-GCM decrypt of `ciphertext || 16-byte tag`.
Uint8List aesGcmDecrypt(Uint8List sealed, Uint8List key, Uint8List nonce) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      false,
      pc.AEADParameters(
        pc.KeyParameter(key),
        _macSizeBits,
        nonce,
        Uint8List(0),
      ),
    );
  return Uint8List.fromList(cipher.process(sealed));
}

/// A serialized Massa Standard keystore.
class MassaKeyStore {
  /// User address (`AU...`).
  final String address;

  /// Keystore version (0 or 1).
  final int version;

  /// Optional nickname.
  final String nickname;

  /// PBKDF2 salt (16 bytes).
  final Uint8List salt;

  /// AES-GCM nonce (12 bytes).
  final Uint8List nonce;

  /// AES-GCM sealed private key bytes (`ciphertext || tag`).
  final Uint8List cipheredData;

  /// Versioned public key bytes.
  final Uint8List publicKey;

  MassaKeyStore({
    required this.address,
    required this.version,
    required this.nickname,
    required this.salt,
    required this.nonce,
    required this.cipheredData,
    required this.publicKey,
  });

  /// Serializes to the standard JSON representation.
  Map<String, dynamic> toJson() => {
    'Address': address,
    'Version': version,
    'Nickname': nickname,
    'Salt': base64.encode(salt),
    'Nonce': base64.encode(nonce),
    'CipheredData': base64.encode(cipheredData),
    'PublicKey': base64.encode(publicKey),
  };

  /// Serializes to a pretty-printed JSON string (file contents).
  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Parses the standard keystore representation. Tolerates both the
  /// documented base64-string fields and array-of-bytes fields.
  static MassaKeyStore fromJson(Map<String, dynamic> json) {
    Uint8List parseField(dynamic v) {
      if (v is String) return Uint8List.fromList(base64.decode(v));
      if (v is List) return Uint8List.fromList(v.cast<int>());
      throw const FormatException('invalid keystore field encoding');
    }

    return MassaKeyStore(
      address: json['Address'] as String,
      version: (json['Version'] as num).toInt(),
      nickname: (json['Nickname'] ?? '') as String,
      salt: parseField(json['Salt']),
      nonce: parseField(json['Nonce']),
      cipheredData: parseField(json['CipheredData']),
      publicKey: parseField(json['PublicKey']),
    );
  }

  /// Parses a keystore from a JSON/YAML-ish file string (JSON expected).
  static MassaKeyStore decode(String contents) =>
      fromJson(json.decode(contents) as Map<String, dynamic>);

  /// Decrypts and returns the versioned private-key bytes.
  Uint8List unseal(String password) {
    final key = _deriveKey(password, salt);
    return aesGcmDecrypt(cipheredData, key, nonce);
  }
}

/// Creates a new keystore for [privateKeyBytes] (versioned bytes).
MassaKeyStore sealPrivateKey({
  required String address,
  required Uint8List privateKeyBytes,
  required Uint8List versionedPublicKeyBytes,
  required String password,
  String nickname = '',
  int version = 0,
}) {
  final rng = Random.secure();
  final salt = Uint8List.fromList(
    List.generate(_saltSizeBytes, (_) => rng.nextInt(256)),
  );
  final nonce = Uint8List.fromList(
    List.generate(_nonceSizeBytes, (_) => rng.nextInt(256)),
  );
  final key = _deriveKey(password, salt);
  final sealed = aesGcmEncrypt(privateKeyBytes, key, nonce);
  return MassaKeyStore(
    address: address,
    version: version,
    nickname: nickname,
    salt: salt,
    nonce: nonce,
    cipheredData: sealed,
    publicKey: versionedPublicKeyBytes,
  );
}
