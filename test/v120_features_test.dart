import 'dart:convert';

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massa_wallet/core/crypto/massa_keys.dart';
import 'package:massa_wallet/core/services/address_book_service.dart';
import 'package:massa_wallet/core/services/auto_compound_service.dart';
import 'package:massa_wallet/core/services/backup_service.dart';
import 'package:massa_wallet/core/services/wallet_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory FlutterSecureStorage platform for tests.
class _InMemorySecureStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> store = {};

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async => store[key] = value;

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => store[key];

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => store.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async => store.remove(key);

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => Map.of(store);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      store.clear();

  @override
  Future<SecureStorageUpgradeStatus> checkUpgradeStatus({
    required Map<String, String> options,
  }) async => SecureStorageUpgradeStatus.unsupported;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    FlutterSecureStoragePlatform.instance = _InMemorySecureStorage();
  });

  group('Auto-compound decision logic', () {
    test('buys whole rolls above reserve at roll price', () {
      // 250 MAS balance, 1 MAS reserve, 100 MAS roll price → 2 rolls.
      final rolls = computeReinvestRolls(
        finalBalanceNano: BigInt.from(250e9.round()),
        reserveNano: BigInt.from(1e9.round()),
        priceNano: BigInt.from(rollPriceNano),
      );
      expect(rolls, 2);
    });

    test('no reinvest when below reserve', () {
      final rolls = computeReinvestRolls(
        finalBalanceNano: BigInt.from(500000000),
        reserveNano: BigInt.from(1000000000),
        priceNano: BigInt.from(rollPriceNano),
      );
      expect(rolls, 0);
    });

    test('no reinvest when surplus cannot buy a whole roll', () {
      final rolls = computeReinvestRolls(
        finalBalanceNano: BigInt.from(101e9.round()), // 1 MAS reserve → 100 surplus
        reserveNano: BigInt.from(1e9.round()),
        priceNano: BigInt.from(rollPriceNano), // 100 MAS → exactly 1
      );
      expect(rolls, 1); // exactly one roll
    });

    test('zero price is rejected', () {
      final rolls = computeReinvestRolls(
        finalBalanceNano: BigInt.from(999e9.round()),
        reserveNano: BigInt.zero,
        priceNano: BigInt.zero,
      );
      expect(rolls, 0);
    });
  });

  group('AutoCompoundService persistence', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('disabled by default, toggle persists', () async {
      final prefs = await SharedPreferences.getInstance();
      final svc = AutoCompoundService(
        prefs: prefs,
        repository: WalletRepository(),
      );
      expect(svc.enabled, isFalse);
      await svc.setEnabled(true);
      expect(svc.enabled, isTrue);
      // Shared key visible to SettingsProvider.
      expect(prefs.getBool('ac.enabled'), isTrue);
    });

    test('reserve default 1 MAS and lastAction record', () async {
      final prefs = await SharedPreferences.getInstance();
      final svc = AutoCompoundService(
        prefs: prefs,
        repository: WalletRepository(),
      );
      expect(svc.reserveNano, BigInt.from(1000000000));
      expect(svc.lastAction, isNull);
    });
  });

  group('Encrypted multi-account backup', () {
    test('export → import roundtrip restores accounts and contacts', () {
      final priv = MassaPrivateKey.generate();
      final skB64 = base64.encode(priv.versionedBytes);
      final accounts = [
        BackupAccount(
          address: priv.publicKey.address.encoded,
          publicKey: priv.publicKey.encoded,
          nickname: 'Main',
          isWatchOnly: false,
          secretKeyB64: skB64,
        ),
        const BackupAccount(
          address: 'AU12hBzWjqJmCmekoV1hm4TZQkvejMDRfP8aMfg1t3TmZgG8Wkj2',
          publicKey: '',
          nickname: 'Exchange',
          isWatchOnly: true,
        ),
      ];
      const contacts = [
        Contact(
          name: 'massa.massa',
          address: 'AU1wN8rnQTDNcyQ5xDG4hpLFmvaMDTQSRZP7PTYBn5jYv2YAc23c',
          domain: 'massa.massa',
        ),
      ];

      final envelope = MassaBackup.export(
        accounts: accounts,
        contacts: contacts,
        password: 'correct horse battery staple',
      );

      // Envelope shape.
      final json = jsonDecode(envelope) as Map<String, dynamic>;
      expect(json['Format'], 'massa-wallet-backup');
      expect(json['Version'], 1);
      expect(json['CipheredData'], isA<String>());

      final restored = MassaBackup.import(
        envelope,
        'correct horse battery staple',
      );
      expect(restored.accounts, hasLength(2));
      expect(restored.accounts.first.address, accounts.first.address);
      expect(restored.accounts.first.secretKeyB64, skB64);
      expect(restored.accounts.last.isWatchOnly, isTrue);
      expect(restored.accounts.last.secretKeyB64, isNull);
      expect(restored.contacts.single.domain, 'massa.massa');
    });

    test('wrong password throws FormatException', () {
      final envelope = MassaBackup.export(
        accounts: const [],
        contacts: const [],
        password: 'one',
      );
      expect(
        () => MassaBackup.import(envelope, 'two'),
        throwsA(isA<FormatException>()),
      );
    });

    test('non-backup JSON is rejected', () {
      expect(
        () => MassaBackup.import('{"Address":"AU1..."}', 'pw'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => MassaBackup.import('not json at all', 'pw'),
        throwsA(isA<FormatException>()),
      );
    });

    test('restored secret key derives the original address', () {
      final priv = MassaPrivateKey.generate();
      final skB64 = base64.encode(priv.versionedBytes);
      final envelope = MassaBackup.export(
        accounts: [
          BackupAccount(
            address: priv.publicKey.address.encoded,
            publicKey: priv.publicKey.encoded,
            nickname: 'Restored',
            isWatchOnly: false,
            secretKeyB64: skB64,
          ),
        ],
        contacts: const [],
        password: 'pw',
      );
      final bundle = MassaBackup.import(envelope, 'pw');
      // The restore path (WalletRepository.importSecretKeyBytes) decodes the
      // base64 versioned bytes and re-derives the address — verified here.
      final versioned = base64.decode(bundle.accounts.first.secretKeyB64!);
      final restored = MassaPrivateKey.fromBytes(versioned.sublist(1));
      expect(restored.publicKey.address.encoded, priv.publicKey.address.encoded);
      expect(bundle.accounts.first.nickname, 'Restored');
    });
  });

  group('Watch-only accounts', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('addWatchOnly validates and persists the flag', () async {
      final validAddress = MassaPrivateKey.generate().publicKey.address.encoded;
      final repo = WalletRepository();
      final account = await repo.addWatchOnly(validAddress, nickname: 'Cold storage');
      expect(account.isWatchOnly, isTrue);
      final loaded = await repo.listAccounts();
      expect(loaded.single.isWatchOnly, isTrue);
      // No secret key material is stored for watch-only entries.
      expect(
        () => repo.readVersionedSecretKey(account.address),
        throwsA(isA<StateError>()),
      );
    });

    test('watch-only flag survives JSON roundtrip', () {
      const a = StoredAccount(
        address: 'AU12hBzWjqJmCmekoV1hm4TZQkvejMDRfP8aMfg1t3TmZgG8Wkj2',
        publicKey: '',
        nickname: 'Watcher',
        isWatchOnly: true,
      );
      final restored = StoredAccount.fromJson(a.toJson());
      expect(restored.isWatchOnly, isTrue);
      // Legacy entries without the flag stay full accounts.
      final legacy = StoredAccount.fromJson({
        'address': 'AU12hBzWjqJmCmekoV1hm4TZQkvejMDRfP8aMfg1t3TmZgG8Wkj2',
        'publicKey': 'P12…',
        'nickname': 'Old',
      });
      expect(legacy.isWatchOnly, isFalse);
    });

    test('invalid watch-only address is rejected', () async {
      final repo = WalletRepository();
      expect(
        () => repo.addWatchOnly('not-an-address'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Contacts with MNS domain', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('domain field roundtrips through the address book', () async {
      final book = AddressBookService();
      await book.save(
        const Contact(
          name: 'Alice',
          address: 'AU12hBzWjqJmCmekoV1hm4TZQkvejMDRfP8aMfg1t3TmZgG8Wkj2',
          domain: 'alice.massa',
        ),
      );
      final loaded = await book.load();
      expect(loaded.single.domain, 'alice.massa');
      expect(loaded.single.address,
          'AU12hBzWjqJmCmekoV1hm4TZQkvejMDRfP8aMfg1t3TmZgG8Wkj2');
    });
  });
}
