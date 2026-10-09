/// Secure wallet persistence.
///
/// Private keys never leave `flutter_secure_storage` (Android Keystore
/// backed, AES-GCM encrypted). Public metadata goes to regular
/// SharedPreferences-friendly storage via the same secure store for
/// simplicity.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../crypto/keystore_file.dart';
import '../crypto/massa_keys.dart';

/// A stored wallet account.
class StoredAccount {
  /// Massa address (`AU...`).
  final String address;

  /// Public key (`P...`).
  final String publicKey;

  /// Optional nickname.
  final String nickname;

  /// Whether this is the active account.
  final bool isActive;

  /// Network the account was created on (informational only — keys are
  /// network-agnostic in Massa).
  final String networkName;

  /// Creates a stored account.
  const StoredAccount({
    required this.address,
    required this.publicKey,
    this.nickname = '',
    this.isActive = false,
    this.networkName = 'Buildnet',
  });

  /// Serializes to JSON.
  Map<String, dynamic> toJson() => {
    'address': address,
    'publicKey': publicKey,
    'nickname': nickname,
    'isActive': isActive,
    'networkName': networkName,
  };

  /// Deserializes from JSON.
  factory StoredAccount.fromJson(Map<String, dynamic> json) => StoredAccount(
    address: json['address'] as String,
    publicKey: json['publicKey'] as String,
    nickname: (json['nickname'] ?? '') as String,
    isActive: (json['isActive'] ?? false) as bool,
    networkName: (json['networkName'] ?? 'Buildnet') as String,
  );

  StoredAccount copyWith({
    String? nickname,
    bool? isActive,
    String? networkName,
  }) => StoredAccount(
    address: address,
    publicKey: publicKey,
    nickname: nickname ?? this.nickname,
    isActive: isActive ?? this.isActive,
    networkName: networkName ?? this.networkName,
  );
}

/// Reads/writes wallet secrets from the secure store.
///
/// Storage layout:
/// - `mw.accounts`  → JSON array of [StoredAccount] metadata
/// - `mw.sk.<addr>` → versioned private-key bytes (base64)
/// - `mw.vault`     → seal password hash hint (PBKDF2-verified) — the app
///   unlock is enforced by biometrics/PIN at OS level; this store keeps the
///   private keys sealed behind `flutter_secure_storage` itself.
class WalletRepository {
  final FlutterSecureStorage _storage;

  /// Creates the repository.
  WalletRepository([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _accountsKey = 'mw.accounts';

  /// Lists stored accounts.
  Future<List<StoredAccount>> listAccounts() async {
    final raw = await _storage.read(key: _accountsKey);
    if (raw == null || raw.isEmpty) return [];
    final list = (json.decode(raw) as List)
        .map((e) => StoredAccount.fromJson(e as Map<String, dynamic>))
        .toList();
    return list;
  }

  /// Saves the account list metadata.
  Future<void> saveAccounts(List<StoredAccount> accounts) => _storage.write(
    key: _accountsKey,
    value: json.encode(accounts.map((a) => a.toJson()).toList()),
  );

  /// Creates a new random wallet and stores it.
  Future<StoredAccount> createWallet({String nickname = ''}) async {
    final priv = MassaPrivateKey.generate();
    return _persistPrivateKey(priv, nickname: nickname);
  }

  /// Imports a wallet from a `S...` secret key string.
  Future<StoredAccount> importSecretKey(
    String secretKey, {
    String nickname = '',
  }) async {
    final priv = MassaPrivateKey.fromString(secretKey.trim());
    final accounts = await listAccounts();
    final address = priv.publicKey.address.encoded;
    final existing = accounts.where((a) => a.address == address).toList();
    if (existing.isNotEmpty) {
      return existing.first;
    }
    return _persistPrivateKey(priv, nickname: nickname);
  }

  /// Imports a wallet from a Massa Standard keystore JSON file.
  Future<StoredAccount> importKeyStore(
    String fileContents,
    String password, {
    String nickname = '',
  }) async {
    final ks = MassaKeyStore.decode(fileContents);
    final versioned = ks.unseal(password);
    if (versioned.isEmpty || versioned.first != massaVersionV0) {
      throw const FormatException('unsupported key version');
    }
    final priv = MassaPrivateKey.fromBytes(versioned.sublist(1));
    final address = priv.publicKey.address.encoded;
    if (address != ks.address) {
      throw const FormatException('keystore address mismatch');
    }
    final accounts = await listAccounts();
    final existing = accounts.where((a) => a.address == address).toList();
    if (existing.isNotEmpty) return existing.first;
    return _persistPrivateKey(priv, nickname: nickname);
  }

  /// Exports the account as a Massa Standard keystore JSON string.
  Future<String> exportKeyStore(String address, String password) async {
    final versioned = await readVersionedSecretKey(address);
    final priv = MassaPrivateKey.fromBytes(versioned.sublist(1));
    return sealPrivateKey(
      address: address,
      privateKeyBytes: versioned,
      versionedPublicKeyBytes: priv.publicKey.versionedBytes,
      password: password,
    ).encode();
  }

  /// Reveals the `S...` secret key (requires active unlock in the UI).
  Future<String> revealSecretKey(String address) async {
    final versioned = await readVersionedSecretKey(address);
    final priv = MassaPrivateKey.fromBytes(versioned.sublist(1));
    return priv.encoded;
  }

  /// Reads versioned secret key bytes for [address].
  Future<Uint8List> readVersionedSecretKey(String address) async {
    final b64 = await _storage.read(key: 'mw.sk.$address');
    if (b64 == null) {
      throw StateError('secret key not found for $address');
    }
    return Uint8List.fromList(base64.decode(b64));
  }

  /// Signs a canonical operation payload with the account key.
  Future<MassaSignature> signCanonical(
    String address,
    List<int> canonical,
  ) async {
    final versioned = await readVersionedSecretKey(address);
    final priv = MassaPrivateKey.fromBytes(versioned.sublist(1));
    return priv.signMessage(canonical);
  }

  /// Deletes an account and its secret.
  Future<void> deleteAccount(String address) async {
    final accounts = await listAccounts();
    accounts.removeWhere((a) => a.address == address);
    await saveAccounts(accounts);
    await _storage.delete(key: 'mw.sk.$address');
  }

  Future<StoredAccount> _persistPrivateKey(
    MassaPrivateKey priv, {
    required String nickname,
  }) async {
    final address = priv.publicKey.address.encoded;
    await _storage.write(
      key: 'mw.sk.$address',
      value: base64.encode(priv.versionedBytes),
    );
    final accounts = await listAccounts();
    final account = StoredAccount(
      address: address,
      publicKey: priv.publicKey.encoded,
      nickname: nickname,
      isActive: accounts.isEmpty,
    );
    accounts.add(account);
    await saveAccounts(accounts);
    return account;
  }
}
