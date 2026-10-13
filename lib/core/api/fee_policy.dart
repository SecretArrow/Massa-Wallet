/// Fee policy: user-controlled operation fees.
///
/// The node reports a minimal accepted fee (`getStatus().minimalFee`).
/// The send screen exposes presets (multiples of that minimum) plus a
/// custom amount; this module keeps the math pure and unit-testable.
library;

/// How quickly the user wants an operation included in a block.
enum FeePreset {
  /// Minimal fee — cheapest, potentially slower inclusion.
  economy,

  /// 2x minimal fee — default.
  standard,

  /// 5x minimal fee — priority inclusion.
  fast,

  /// User-entered amount (clamped up to the minimal fee).
  custom,
}

/// Fee math for operation fees in nanoMAS.
abstract final class FeePolicy {
  /// Offline fallback when the node reports no minimal fee (0.001 MAS).
  static const BigInt fallbackMinimalFee = BigInt.from(1000000);

  /// Multiplier applied to the minimal fee per non-custom preset.
  static const Map<FeePreset, int> multipliers = {
    FeePreset.economy: 1,
    FeePreset.standard: 2,
    FeePreset.fast: 5,
  };

  /// Effective fee in nanoMAS for [preset].
  ///
  /// * non-custom presets: `max(minimalFee, fallback) * multiplier`;
  /// * custom: the user amount clamped up to the node minimum (a fee
  ///   below the minimum would be rejected outright).
  static BigInt feeFor(
    FeePreset preset,
    BigInt minimalFee, {
    BigInt? customNano,
  }) {
    final base = minimalFee > BigInt.zero ? minimalFee : fallbackMinimalFee;
    if (preset == FeePreset.custom) {
      final c = customNano ?? BigInt.zero;
      return c > base ? c : base;
    }
    return base * BigInt.from(multipliers[preset]!);
  }
}
