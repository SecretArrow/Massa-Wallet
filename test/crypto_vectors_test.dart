import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:massa_wallet/core/crypto/varint.dart';
import 'package:massa_wallet/core/crypto/base58_check.dart';
import 'package:massa_wallet/core/crypto/massa_keys.dart';
import 'package:massa_wallet/core/crypto/operation_serializer.dart';
import 'package:massa_wallet/core/crypto/keystore_file.dart';
import 'package:massa_wallet/core/api/massa_amount.dart';

void main() {
  group('varint', () {
    test('encodes like massa-web3 varint/big-varint', () {
      expect(varintEncodeInt(0), [0]);
      expect(varintEncodeInt(1), [1]);
      expect(varintEncodeInt(2), [2]);
      expect(varintEncodeInt(3), [3]);
      expect(varintEncodeInt(127), [127]);
      expect(varintEncodeInt(128), [0x80, 0x01]);
      expect(varintEncodeInt(300), [0xAC, 0x02]);
      expect(varintEncode(BigInt.from(40000)), [0xC0, 0xB8, 0x02]);
    });

    test('roundtrip', () {
      for (final v in [0, 1, 127, 128, 300, 5455135, 77658377]) {
        final enc = varintEncodeInt(v);
        final dec = varintDecodeInt(enc);
        expect(dec, v, reason: 'roundtrip failed for $v');
      }
      final big = BigInt.parse('18446744073709551615');
      final enc = varintEncode(big);
      final dec = varintDecode(enc);
      expect(dec.value, big);
    });
  });

  group('base58check', () {
    test('decode/encode pubkey versioned bytes (official vector)', () {
      // P126AtzfcSJwdi6xsAmXbzXhhwVhS9d1hRjFNT4PfrDogt3nAihj → versioned bytes
      const pubStr = 'P126AtzfcSJwdi6xsAmXbzXhhwVhS9d1hRjFNT4PfrDogt3nAihj';
      final payload = base58CheckDecode(pubStr.substring(1));
      expect(payload, [
        0,
        143,
        111,
        199,
        160,
        227,
        187,
        57,
        238,
        223,
        80,
        251,
        169,
        64,
        21,
        116,
        165,
        95,
        187,
        192,
        76,
        97,
        33,
        64,
        208,
        119,
        99,
        182,
        139,
        174,
        219,
        61,
        109,
      ]);
      // re-encode
      expect('P' + base58CheckEncode(payload), pubStr);
    });

    test('invalid checksum throws', () {
      expect(
        () => base58CheckDecode(
          '1TXucC8nai7BYpAnMPYrotVcKCZ5oxkfWHb2ykKj2tXmaGMDL1XTU5AbC6Z13RH3q59F8QtbzKq4gzBphGPWpiDonownx',
        ),
        throwsFormatException,
      );
    });
  });

  group('massa keys (official vectors)', () {
    test('private key → public key → address', () {
      final priv = MassaPrivateKey.fromString(
        'S12jWf59Yzf2LimL89soMnAP2VEBDBpfCbZLoEFo36CxEL3j92rZ',
      );
      expect(
        priv.encoded,
        'S12jWf59Yzf2LimL89soMnAP2VEBDBpfCbZLoEFo36CxEL3j92rZ',
      );
      expect(
        priv.publicKey.encoded,
        'P126AtzfcSJwdi6xsAmXbzXhhwVhS9d1hRjFNT4PfrDogt3nAihj',
      );
      expect(
        priv.publicKey.address.encoded,
        'AU126tkwrhXn9gEG5JPtrNy8NNLbVMwywokgLKshSYyzP8qusqXZL',
      );
      expect(priv.publicKey.address.isEoa, isTrue);
    });

    test('message signature (official vector)', () {
      final priv = MassaPrivateKey.fromString(
        'S12XuWmm5jULpJGXBnkeBsuiNmsGi2F4rMiTvriCzENxBR4Ev7vd',
      );
      final sig = priv.signMessage('Test message'.codeUnits);
      expect(
        sig.encoded,
        '1TXucC8nai7BYpAnMPYrotVcKCZ5oxkfWHb2ykKj2tXmaGMDL1XTU5AbC6Z13RH3q59F8QtbzKq4gzBphGPWpiDonownxE',
      );
      // verify
      expect(priv.publicKey.verify('Test message'.codeUnits, sig), isTrue);
    });

    test('random keygen roundtrip', () {
      final priv = MassaPrivateKey.generate();
      final parsed = MassaPrivateKey.fromString(priv.encoded);
      expect(parsed.raw, priv.raw);
      expect(parsed.publicKey.encoded, priv.publicKey.encoded);
    });
  });

  group('operation serializer (official vectors)', () {
    test('serialize transfer', () {
      final op = MassaOperation.transfer(
        fee: BigInt.one,
        expirePeriod: 2,
        data: TransferOperationData(
          recipientAddress:
              'AU1wN8rn4SkwYSTDF3dHFY4U28KtsqKL1NnEjDZhHnHEy6cEQm53',
          amount: BigInt.from(3),
        ),
      );
      final bytes = OperationSerializer.serialize(op);
      expect(bytes, [
        1,
        2,
        0,
        0,
        0,
        123,
        112,
        231,
        120,
        210,
        147,
        6,
        222,
        60,
        132,
        122,
        220,
        63,
        36,
        111,
        216,
        72,
        248,
        161,
        29,
        104,
        213,
        241,
        70,
        172,
        217,
        243,
        24,
        153,
        171,
        29,
        50,
        3,
      ]);
    });

    test('serialize sell roll', () {
      final op = MassaOperation.rollSell(
        fee: BigInt.one,
        expirePeriod: 2,
        data: RollOperationData(amount: BigInt.from(3)),
      );
      expect(OperationSerializer.serialize(op), [1, 2, 2, 3]);
    });

    test('serialize execute SC', () {
      final op = MassaOperation.executeSC(
        fee: BigInt.one,
        expirePeriod: 2,
        data: ExecuteOperationData(
          contractDataBinary: [1, 2, 3, 4],
          maxGas: BigInt.from(3),
          maxCoins: BigInt.from(4),
          datastore: {
            [1, 2, 3, 4]: [1, 2, 3, 4],
          },
        ),
      );
      expect(OperationSerializer.serialize(op), [
        1,
        2,
        3,
        3,
        4,
        4,
        1,
        2,
        3,
        4,
        1,
        4,
        1,
        2,
        3,
        4,
        4,
        1,
        2,
        3,
        4,
      ]);
    });

    test('canonicalize transfer (chainId=1, official vector)', () {
      final op = MassaOperation.transfer(
        fee: BigInt.one,
        expirePeriod: 2,
        data: TransferOperationData(
          recipientAddress:
              'AU1wN8rn4SkwYSTDF3dHFY4U28KtsqKL1NnEjDZhHnHEy6cEQm53',
          amount: BigInt.from(3),
        ),
      );
      final priv = MassaPrivateKey.fromString(
        'S1edybaAp8cYXwXtchW3nfyPwwh9tvoWgSdkxK2uJwWo9zZrCH9',
      );
      final canonical = OperationSerializer.canonicalize(
        BigInt.one,
        op,
        priv.publicKey,
      );
      expect(canonical, [
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        80,
        4,
        30,
        211,
        241,
        1,
        3,
        219,
        6,
        32,
        235,
        244,
        186,
        4,
        239,
        84,
        155,
        62,
        17,
        45,
        68,
        245,
        236,
        88,
        141,
        50,
        82,
        254,
        9,
        151,
        4,
        167,
        1,
        2,
        0,
        0,
        0,
        123,
        112,
        231,
        120,
        210,
        147,
        6,
        222,
        60,
        132,
        122,
        220,
        63,
        36,
        111,
        216,
        72,
        248,
        161,
        29,
        104,
        213,
        241,
        70,
        172,
        217,
        243,
        24,
        153,
        171,
        29,
        50,
        3,
      ]);
    });

    test('sign + verify operation', () {
      final op = MassaOperation.rollBuy(
        fee: BigInt.one,
        expirePeriod: 2,
        data: RollOperationData(amount: BigInt.from(3)),
      );
      final priv = MassaPrivateKey.fromString(
        'S1edybaAp8cYXwXtchW3nfyPwwh9tvoWgSdkxK2uJwWo9zZrCH9',
      );
      final sig = OperationSerializer.sign(BigInt.from(77658366), op, priv);
      final canonical = OperationSerializer.canonicalize(
        BigInt.from(77658366),
        op,
        priv.publicKey,
      );
      expect(priv.publicKey.verify(canonical, sig), isTrue);
      // signature string roundtrip
      expect(MassaSignature.fromString(sig.encoded).raw, sig.raw);
    });
  });

  group('keystore (official vector)', () {
    test('unseal massa-web3 test keystore', () {
      // Vector from massa-web3 test/unit/account.spec.ts
      final ks = MassaKeyStore.fromJson({
        'Address': 'AU126tkwrhXn9gEG5JPtrNy8NNLbVMwywokgLKshSYyzP8qusqXZL',
        'Version': 1,
        'Nickname': '',
        'Salt': base64Encode([
          146,
          63,
          151,
          136,
          93,
          135,
          105,
          113,
          124,
          41,
          189,
          207,
          86,
          124,
          17,
          152,
        ]),
        'Nonce': base64Encode([
          250,
          104,
          81,
          250,
          235,
          79,
          110,
          84,
          243,
          225,
          144,
          242,
        ]),
        'CipheredData': base64Encode([
          191,
          181,
          5,
          198,
          76,
          145,
          242,
          89,
          253,
          215,
          151,
          10,
          245,
          32,
          241,
          9,
          171,
          181,
          76,
          103,
          121,
          184,
          33,
          16,
          227,
          83,
          53,
          133,
          194,
          38,
          20,
          217,
          34,
          61,
          169,
          108,
          156,
          217,
          196,
          74,
          34,
          127,
          129,
          33,
          103,
          215,
          117,
          66,
          78,
        ]),
        'PublicKey': base64Encode([
          0,
          143,
          111,
          199,
          160,
          227,
          187,
          57,
          238,
          223,
          80,
          251,
          169,
          64,
          21,
          116,
          165,
          95,
          187,
          192,
          76,
          97,
          33,
          64,
          208,
          119,
          99,
          182,
          139,
          174,
          219,
          61,
          109,
        ]),
      });
      final privBytes = ks.unseal('unsecurePassword');
      final priv = MassaPrivateKey.fromBytes(
        privBytes.sublist(1),
      ); // strip version varint
      expect(
        priv.publicKey.encoded,
        'P126AtzfcSJwdi6xsAmXbzXhhwVhS9d1hRjFNT4PfrDogt3nAihj',
      );
    });

    test('seal → unseal roundtrip', () {
      final priv = MassaPrivateKey.generate();
      final ks = sealPrivateKey(
        address: priv.publicKey.address.encoded,
        privateKeyBytes: priv.versionedBytes,
        versionedPublicKeyBytes: priv.publicKey.versionedBytes,
        password: 'test-pass-123',
      );
      final unsealed = ks.unseal('test-pass-123');
      expect(unsealed, priv.versionedBytes);
      // JSON roundtrip
      final ks2 = MassaKeyStore.decode(ks.encode());
      expect(ks2.unseal('test-pass-123'), priv.versionedBytes);
    });
  });

  group('amounts', () {
    test('MAS decimal string → nanoMAS', () {
      expect(
        masToNano('1012462541.490508428'),
        BigInt.parse('1012462541490508428'),
      );
      expect(masToNano('0.000000001'), BigInt.one);
      expect(masToNano('1'), BigInt.from(1000000000));
      expect(masToNano('12.5'), BigInt.from(12500000000));
      expect(
        nanoToMas(BigInt.parse('1012462541490508428')),
        '1012462541.490508428',
      );
      expect(nanoToMas(BigInt.from(12500000000)), '12.5');
      expect(nanoToMas(BigInt.one), '0.000000001');
      expect(nanoToMas(BigInt.zero), '0');
    });

    test('rejects bad input', () {
      expect(() => masToNano('abc'), throwsFormatException);
      expect(() => masToNano('1.1234567890'), throwsFormatException);
      expect(() => masToNano(''), throwsFormatException);
    });

    test('user input parsing', () {
      expect(parseUserAmount('1,5'), BigInt.from(1500000000));
      expect(parseUserAmount(' 2 '), BigInt.from(2000000000));
    });
  });
}
