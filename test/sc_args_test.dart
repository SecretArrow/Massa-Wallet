import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:massa_wallet/core/crypto/sc_args.dart';
import 'package:massa_wallet/core/contracts/mrc20_service.dart';

void main() {
  group('ScArgs — massa-sc-toolkit compatible serialization', () {
    test('u32 is little-endian 4 bytes', () {
      final a = ScArgs()..addU32(1);
      expect(a.bytes, [1, 0, 0, 0]);
      expect((ScArgs()..addU32(0x12345678)).bytes, [0x78, 0x56, 0x34, 0x12]);
    });

    test('string = u32le length + utf8 bytes', () {
      final a = ScArgs()..addString('massa');
      expect(a.bytes, [
        5, 0, 0, 0, //
        ...utf8.encode('massa'),
      ]);
    });

    test('dnsResolve parameter matches live probe payload', () {
      final a = ScArgs()..addString('massa');
      expect(a.bytes, [5, 0, 0, 0, 109, 97, 115, 115, 97]);
    });

    test('u256 little-endian 32 bytes', () {
      final a = ScArgs()..addU256(BigInt.one);
      final bytes = a.bytes;
      expect(bytes, hasLength(32));
      expect(bytes.first, 1);
      expect(bytes.sublist(1).every((b) => b == 0), isTrue);
    });

    test('u256 large value roundtrip', () {
      const v = '123456789012345678901234567890123456789012345678901234567890';
      final a = ScArgs()..addU256(BigInt.parse(v));
      final r = ScArgsReader(a.bytes);
      expect(r.nextU256().toString(), v);
      expect(r.isEof, isTrue);
    });

    test('bool and u8', () {
      final a = ScArgs()
        ..addBool(true)
        ..addU8(7);
      expect(a.bytes, [1, 7]);
    });

    test('reader string/bytes roundtrip', () {
      final a = ScArgs()
        ..addString('hello')
        ..addBytes([9, 8, 7]);
      final r = ScArgsReader(a.bytes);
      expect(r.nextString(), 'hello');
      expect(r.nextBytes(), [9, 8, 7]);
      expect(r.isEof, isTrue);
    });

    test('transferArgs matches transfer(to, amount) layout', () {
      final args = Mrc20Service.transferArgs('AU1abc', BigInt.from(1000));
      // len(AU1abc)=6 | "AU1abc" | 1000 u256le
      expect(args.sublist(0, 4), [6, 0, 0, 0]);
      expect(utf8.decode(args.sublist(4, 10)), 'AU1abc');
      // 1000 = 0x3E8 → LE bytes [0xE8, 0x03, 0, ...]
      expect(args[10], 232);
      expect(args[11], 3);
      expect(args, hasLength(10 + 32));
      expect(args.sublist(12).every((b) => b == 0), isTrue);
    });

    test('negative values rejected', () {
      expect(() => (ScArgs()..addU256(BigInt.from(-1))), throwsArgumentError);
    });

    test('bigIntToLe / leToBigInt roundtrip various widths', () {
      final cases = {
        8: BigInt.from(255),
        16: BigInt.from(65535),
        32: BigInt.parse(
          '115792089237316195423570985008687907853269984665640564039457584007913129639935',
        ),
      };
      cases.forEach((width, v) {
        final le = bigIntToLe(v, width);
        expect(le, hasLength(width));
        expect(leToBigInt(le), v);
      });
      // Values that do not fit throw (2^64 needs 9 bytes).
      expect(
        () => bigIntToLe(BigInt.parse('18446744073709551616'), 8),
        throwsArgumentError,
      );
    });
  });

  group('Mrc20Service.balanceCreationCost', () {
    test('matches massa-web3 formula', () {
      // 400_000 + 100_000*(7+len) + 3_200_000
      final addr = 'AU1' + 'a' * 49; // length 52
      final cost = Mrc20Service.balanceCreationCost(addr);
      expect(cost, BigInt.from(400000 + 100000 * (7 + 52) + 3200000));
      expect(cost, BigInt.from(9500000));
    });
  });
}
