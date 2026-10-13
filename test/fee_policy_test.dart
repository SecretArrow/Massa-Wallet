/// Tests for the fee policy (presets + custom clamping).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:massa_wallet/core/api/fee_policy.dart';

void main() {
  final minimal = BigInt.from(1000000); // 0.001 MAS node minimum

  group('FeePolicy.feeFor', () {
    test('economy = 1x minimal fee', () {
      expect(FeePolicy.feeFor(FeePreset.economy, minimal), minimal);
    });

    test('standard = 2x minimal fee', () {
      expect(FeePolicy.feeFor(FeePreset.standard, minimal), minimal * BigInt.two);
    });

    test('fast = 5x minimal fee', () {
      expect(FeePolicy.feeFor(FeePreset.fast, minimal), minimal * BigInt.from(5));
    });

    test('custom above minimal is honored', () {
      expect(
        FeePolicy.feeFor(
          FeePreset.custom,
          minimal,
          customNano: BigInt.from(7000000),
        ),
        BigInt.from(7000000),
      );
    });

    test('custom below minimal is clamped up to minimal', () {
      expect(
        FeePolicy.feeFor(
          FeePreset.custom,
          minimal,
          customNano: BigInt.from(10),
        ),
        minimal,
      );
    });

    test('custom without input falls back to minimal', () {
      expect(FeePolicy.feeFor(FeePreset.custom, minimal), minimal);
    });

    test('zero minimal fee from node falls back to 0.001 MAS base', () {
      expect(FeePolicy.feeFor(FeePreset.economy, BigInt.zero),
          FeePolicy.fallbackMinimalFee);
      expect(FeePolicy.feeFor(FeePreset.fast, BigInt.zero),
          FeePolicy.fallbackMinimalFee * BigInt.from(5));
    });

    test('multipliers table matches presets', () {
      expect(FeePolicy.multipliers.length, 3);
      expect(FeePolicy.multipliers.containsKey(FeePreset.custom), isFalse);
    });
  });
}
