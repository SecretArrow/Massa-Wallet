/// Seed-phrase crypto tests: official BIP-39 + SLIP-0010 vectors and the
/// Pyramids Wallet derivation pin (m/44'/4478'/0'/0'/0').
///
/// The expected values were computed independently in Python (hashlib /
/// hmac) and cross-checked against the published spec vectors
/// (SLIP-0010 Test Vector 1, BIP-39 trezor vectors).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massa_wallet/core/crypto/bip39.dart';
import 'package:massa_wallet/core/crypto/seed_derivation.dart';
import 'package:massa_wallet/core/crypto/slip10.dart';

void main() {
  group('BIP-39 — official vectors (mnemonic + seed)', () {
    const vectors = <(String, String, String)>[
      (
        '00000000000000000000000000000000',
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
        '5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4',
      ),
      (
        '7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f',
        'legal winner thank year wave sausage worth useful legal winner thank yellow',
        '878386efb78845b3355bd15ea4d39ef97d179cb712b77d5c12b6be415fffeffe5f377ba02bf3f8544ab800b955e51fbff09828f682052a20faa6addbbddfb096',
      ),
      (
        'ffffffffffffffffffffffffffffffff',
        'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong',
        'b6a6d8921942dd9806607ebc2750416b289adea669198769f2e15ed926c3aa92bf88ece232317b4ea463e84b0fcd3b53577812ee449ccc448eb45e6f544e25b6',
      ),
      (
        '000000000000000000000000000000000000000000000000',
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art',
        '4975bb3d1faf5308c86a30893ee903a976296609db223fd717e227da5a813a34dc1428b71c84a787fc51f3b9f9dc28e9459f48c08bd9578e9d1b170f2d7ea506',
      ),
      (
        '9e885d952ad362caeb4efe34a8e91bd2',
        'ozone drill grab fiber curtain grace pudding thank cruise elder eight picnic',
        'e2f88a043776c828063d4c3c97173944d32cf847a925b6e40b0b8bd0b4bead3ba734bdda5250d4698b310a71c9934e1a48e562315ce22bf85f89459df0e73a6c',
      ),
    ];

    for (final (entropyHex, mnemonic, seedHex) in vectors) {
      test('entropy $entropyHex', () {
        final entropy = [
          for (var i = 0; i < entropyHex.length; i += 2)
            int.parse(entropyHex.substring(i, i + 2), radix: 16),
        ];
        // mnemonic encoding
        expect(mnemonicFromEntropy(entropy), mnemonic);
        // seed derivation (PBKDF2-HMAC-SHA512, 2048 iters)
        expect(
          bytesToHex(mnemonicToSeed(mnemonic)),
          seedHex,
        );
        // validation + entropy roundtrip
        expect(isValidMnemonic(mnemonic), isTrue);
        expect(bytesToHex(mnemonicToEntropy(mnemonic)), entropyHex);
      });
    }
  });

  group('BIP-39 — rejection', () {
    test('bad checksum (12× abandon)', () {
      const bad = 'abandon abandon abandon abandon abandon abandon '
          'abandon abandon abandon abandon abandon abandon';
      expect(isValidMnemonic(bad), isFalse);
      expect(() => mnemonicToEntropy(bad),
          throwsA(predicate((e) => e is FormatException && e.message == 'code:checksum')));
    });

    test('unknown word', () {
      const bad = 'abandon ability able about above absent absorb abstract absurd '
          'abuse access notaword';
      expect(isValidMnemonic(bad), isFalse);
      expect(
        () => mnemonicToEntropy(bad),
        throwsA(predicate((e) => e is FormatException && e.message == 'code:word:11')),
      );
    });

    test('wrong length (11 words)', () {
      const bad = 'abandon abandon abandon abandon abandon abandon '
          'abandon abandon abandon abandon abandon';
      expect(isValidMnemonic(bad), isFalse);
      expect(() => mnemonicToEntropy(bad),
          throwsA(predicate((e) => e is FormatException && e.message == 'code:length')));
    });
  });

  group('BIP-39 — normalization & generation', () {
    test('normalize collapses whitespace and case', () {
      expect(
        normalizeMnemonic('  ABANDON   ability\tAble  about\nabove '),
        'abandon ability able about above',
      );
    });

    test('generate(128) → 12 valid words', () {
      final m = generateMnemonic(strength: 128);
      expect(m.split(' '), hasLength(12));
      expect(isValidMnemonic(m), isTrue);
      // determinism: same mnemonic → same seed
      expect(bytesToHex(mnemonicToSeed(m)), bytesToHex(mnemonicToSeed(normalizeMnemonic(m))));
    });

    test('generate(256) → 24 valid words', () {
      final m = generateMnemonic(strength: 256);
      expect(m.split(' '), hasLength(24));
      expect(isValidMnemonic(m), isTrue);
    });

    test('passphrase changes the seed', () {
      const m = 'legal winner thank year wave sausage worth useful legal winner thank yellow';
      expect(
        bytesToHex(mnemonicToSeed(m, passphrase: 'TREZOR')),
        isNot(bytesToHex(mnemonicToSeed(m))),
      );
    });
  });

  group('SLIP-0010 ed25519 — Test Vector 1 (seed 000102…0f)', () {
    const seedHex = '000102030405060708090a0b0c0d0e0f';
    const expected = <String, String>{
      'm': '2b4be7f19ee27bbf30c667b642d5f4aa69fd169872f8fc3059c08ebae2eb19e7',
      "m/0'": '68e0fe46dfb67e368c75379acec591dad19df3cde26e63b93a8e704f1dade7a3',
      "m/0'/1'": 'b1d0bad404bf35da785a64ca1ac54b2617211d2777696fbffaf208f746ae84f2',
      "m/0'/1'/2'": '92a5b23c0b8a99e37d07df3fb9966917f5d06e02ddbd909c7e184371463e9fc9',
      "m/0'/1'/2'/2'": '30d1dc7e5fc04c31219ab25a27ae00b50f6fd66622f6e9c913253d6511d1e662',
      "m/0'/1'/2'/2'/1000000000'":
          '8f94d394a8e8fd6b1bc2f3f49f5c47e385281d5c17e65324b0f62483e37e8793',
    };
    final seed = [
      for (var i = 0; i < seedHex.length; i += 2)
        int.parse(seedHex.substring(i, i + 2), radix: 16),
    ];

    for (final entry in expected.entries) {
      test(entry.key, () {
        final path = parseDerivationPath(entry.key);
        expect(bytesToHex(slip10DeriveEd25519(seed, path)), entry.value);
      });
    }

    test('non-hardened segment is rejected', () {
      expect(() => parseDerivationPath("m/44/4478'"), throwsFormatException);
    });
  });

  group('Pyramids Wallet derivation (m/44\'/4478\'/0\'/0\'/0\')', () {
    const vector = 'abandon abandon abandon abandon abandon abandon '
        'abandon abandon abandon abandon abandon about';

    // Python-computed regression pin.
    const expectedKeyHex =
        '56f4d7e8c10ce6398f878b413e716ef44be0f13ce9bf18b1bd5fc9571020b820';

    test('deterministic key at the Pyramids path', () {
      final priv = privateKeyFromMnemonic(vector);
      expect(bytesToHex(priv.raw), expectedKeyHex);
      // re-derivation is stable and case/whitespace-insensitive
      final again = privateKeyFromMnemonic('  ${vector.toUpperCase()}  ');
      expect(bytesToHex(again.raw), expectedKeyHex);
    });

    test('same mnemonic → same address (import == create)', () {
      final a = privateKeyFromMnemonic(vector).publicKey.address.encoded;
      final b = privateKeyFromMnemonic(normalizeMnemonic(vector.toUpperCase()))
          .publicKey
          .address
          .encoded;
      expect(a, b);
      expect(a.startsWith('AU'), isTrue);
    });

    test('different mnemonic → different address', () {
      final a = privateKeyFromMnemonic(vector).publicKey.address.encoded;
      const other = 'legal winner thank year wave sausage worth useful '
          'legal winner thank yellow';
      final b = privateKeyFromMnemonic(other).publicKey.address.encoded;
      expect(a, isNot(b));
    });

    test('invalid mnemonic propagates a coded FormatException', () {
      expect(
        () => privateKeyFromMnemonic('not a real phrase'),
        throwsFormatException,
      );
    });
  });
}
