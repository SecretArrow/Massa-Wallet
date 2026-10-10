/// Encrypted multi-account backup (single `.massabak` file).
///
/// Exports **all** accounts (nicknames, addresses, public keys, versioned
/// secret keys) plus the address book into one JSON envelope encrypted with
/// PBKDF2-HMAC-SHA256 (600,000 iterations) → AES-256-GCM — the same
/// primitives as the Massa Standard keystore, applied to the whole bundle.
///
/// Envelope:
/// ```json
/// {
///   "Format": "massa-wallet-backup",
///   "Version": 1,
///   "CreatedAt": "…",
///   "Salt": "<b64 16B>",
///   "Nonce": "<b64 12B>",
///   "CipheredData": "<b64 ct||tag>"
/// }
/// ```
///
/// Watch-only entries are included **without** a secret key (they carry no
/// key material), so restoring them keeps them watch-only.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';

import '../crypto/keystore_file.dart';
import 'address_book_service.dart';
import 'wallet_repository.dart';

/// Backup format identifier.
const String backupFormat = 'massa-wallet-backup';

/// Current backup format version.
const int backupVersion = 1;

Uint8List _deriveKey(String password, Uint8List salt) {
  // Same derivation as the Massa Standard keystore (600k PBKDF2-SHA256).
  final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(salt, 600000, 32));
  return derivator.process(Uint8List.fromList(utf8.encode(password)));
}

/// Serializable account payload inside a backup.
class BackupAccount {
  /// Massa address (`AU…`).
  final String address;

  /// Public key (`P…`, empty for watch-only).
  final String publicKey;

  /// Nickname.
  final String nickname;

  /// Whether the entry is watch-only.
  final bool isWatchOnly;

  /// Base64 of the versioned private-key bytes (null for watch-only).
  final String? secretKeyB64;

  /// Creates the payload.
  const BackupAccount({
    required this.address,
    required this.publicKey,
    required this.nickname,
    required this.isWatchOnly,
    this.secretKeyB64,
  });

  Map<String, dynamic> toJson() => {
    'address': address,
    'publicKey': publicKey,
    'nickname': nickname,
    'isWatchOnly': isWatchOnly,
    'secretKey': secretKeyB64,
  };

  static BackupAccount fromJson(Map<String, dynamic> j) => BackupAccount(
    address: j['address'] as String,
    publicKey: (j['publicKey'] ?? '') as String,
    nickname: (j['nickname'] ?? '') as String,
    isWatchOnly: (j['isWatchOnly'] ?? false) as bool,
    secretKeyB64: j['secretKey'] as String?,
  );

  /// Captures a stored account (reading its secret when available).
  static Future<BackupAccount> capture(
    StoredAccount a,
    WalletRepository repo,
  ) async {
    if (a.isWatchOnly) {
      return BackupAccount(
        address: a.address,
        publicKey: a.publicKey,
        nickname: a.nickname,
        isWatchOnly: true,
      );
    }
    final sk = await repo.readVersionedSecretKey(a.address);
    return BackupAccount(
      address: a.address,
      publicKey: a.publicKey,
      nickname: a.nickname,
      isWatchOnly: false,
      secretKeyB64: base64.encode(sk),
    );
  }
}

/// Full encrypted backup builder/parser.
abstract final class MassaBackup {
  /// Builds the encrypted backup envelope for [accounts] + [contacts].
  static String export({
    required List<BackupAccount> accounts,
    required List<Contact> contacts,
    required String password,
    DateTime? createdAt,
  }) {
    final rng = Random.secure();
    final salt = Uint8List.fromList(
      List.generate(16, (_) => rng.nextInt(256)),
    );
    final nonce = Uint8List.fromList(
      List.generate(12, (_) => rng.nextInt(256)),
    );
    final payload = utf8.encode(
      json.encode({
        'accounts': accounts.map((a) => a.toJson()).toList(),
        'addressBook': contacts
            .map(
              (c) => {'name': c.name, 'address': c.address, 'domain': c.domain},
            )
            .toList(),
      }),
    );
    final key = _deriveKey(password, salt);
    final sealed = aesGcmEncrypt(payload, key, nonce);
    return const JsonEncoder.withIndent('  ').convert({
      'Format': backupFormat,
      'Version': backupVersion,
      'CreatedAt': (createdAt ?? DateTime.now()).toUtc().toIso8601String(),
      'Salt': base64.encode(salt),
      'Nonce': base64.encode(nonce),
      'CipheredData': base64.encode(sealed),
    });
  }

  /// Decrypts a backup envelope; throws [FormatException] on a wrong
  /// password or a corrupted/unknown file.
  static ({List<BackupAccount> accounts, List<Contact> contacts, DateTime createdAt})
      import(String contents, String password) {
    Map<String, dynamic> envelope;
    try {
      envelope = json.decode(contents) as Map<String, dynamic>;
    } on FormatException {
      throw const FormatException('not a massa-wallet-backup file');
    }
    if (envelope['Format'] != backupFormat) {
      throw const FormatException('not a massa-wallet-backup file');
    }
    final version = (envelope['Version'] as num).toInt();
    if (version > backupVersion) {
      throw const FormatException('backup version not supported');
    }
    final salt = base64.decode(envelope['Salt'] as String);
    final nonce = base64.decode(envelope['Nonce'] as String);
    final sealed = base64.decode(envelope['CipheredData'] as String);
    final key = _deriveKey(password, Uint8List.fromList(salt));
    Uint8List payload;
    try {
      payload = aesGcmDecrypt(
        Uint8List.fromList(sealed),
        key,
        Uint8List.fromList(nonce),
      );
    } on Exception {
      throw const FormatException('wrong password or corrupted backup');
    }
    final data = json.decode(utf8.decode(payload)) as Map<String, dynamic>;
    final accounts = (data['accounts'] as List? ?? const [])
        .map((e) => BackupAccount.fromJson(e as Map<String, dynamic>))
        .toList();
    final contacts = (data['addressBook'] as List? ?? const [])
        .map(
          (e) => Contact(
            name: (e['name'] ?? '') as String,
            address: (e['address'] ?? '') as String,
            domain: (e['domain'] ?? '') as String,
          ),
        )
        .toList();
    final createdAt =
        DateTime.tryParse((envelope['CreatedAt'] ?? '') as String) ??
        DateTime.now().toUtc();
    return (accounts: accounts, contacts: contacts, createdAt: createdAt);
  }
}
