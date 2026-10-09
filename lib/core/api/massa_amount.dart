/// MAS amount handling.
///
/// The Massa JSON-RPC v2 API returns amounts as decimal strings in **MAS
/// units** (9 decimals), e.g. `"1012462541.490508428"`, while operations
/// (fee / amount / coins) are expressed in **nanoMAS** (u64, 1 MAS =
/// 1e9 nanoMAS). This module converts between both representations
/// losslessly using BigInt arithmetic.
library;

const int masDecimals = 9;

/// Converts a decimal MAS string to nanoMAS (BigInt).
///
/// Accepts `"123"`, `"123.456"`, `".5"`, `"1."`, optional leading `+`.
/// Throws [FormatException] for malformed or >9-decimal inputs.
BigInt masToNano(String mas) {
  final s = mas.trim();
  if (s.isEmpty) throw const FormatException('empty amount');
  final negative = s.startsWith('-');
  final body = negative
      ? s.substring(1)
      : (s.startsWith('+') ? s.substring(1) : s);
  final dot = body.indexOf('.');
  String intPart;
  String fracPart;
  if (dot == -1) {
    intPart = body;
    fracPart = '';
  } else {
    intPart = body.substring(0, dot);
    fracPart = body.substring(dot + 1);
  }
  if (intPart.isEmpty) intPart = '0';
  if (intPart.contains(RegExp(r'[^0-9]')) ||
      fracPart.contains(RegExp(r'[^0-9]'))) {
    throw FormatException('invalid MAS amount: $mas');
  }
  if (fracPart.length > masDecimals) {
    throw FormatException('too many decimals (max 9): $mas');
  }
  fracPart = fracPart.padRight(masDecimals, '0');
  final combined = '$intPart$fracPart'.replaceAll(RegExp(r'^0+(?=\d)'), '');
  final value = combined.isEmpty ? BigInt.zero : BigInt.parse(combined);
  return negative ? -value : value;
}

/// Converts nanoMAS to a decimal MAS string (up to 9 decimals, trimmed).
String nanoToMas(BigInt nano) {
  final negative = nano.isNegative;
  final abs = negative ? -nano : nano;
  final s = abs.toString().padLeft(masDecimals + 1, '0');
  final intPart = s.substring(0, s.length - masDecimals);
  final fracPart = s
      .substring(s.length - masDecimals)
      .replaceAll(RegExp(r'0+$'), '');
  final sign = negative && abs != BigInt.zero ? '-' : '';
  return fracPart.isEmpty ? '$sign$intPart' : '$sign$intPart.$fracPart';
}

/// Formats a nanoMAS amount with [decimals] fraction digits (for display).
String formatNano(BigInt nano, {int decimals = 9}) {
  final full = nanoToMas(nano);
  final dot = full.indexOf('.');
  if (dot == -1) return full;
  final frac = full.substring(dot + 1);
  if (frac.length <= decimals) return full;
  return '${full.substring(0, dot)}.${frac.substring(0, decimals)}';
}

/// Parses user input (e.g. "12.5") into nanoMAS, allowing comma separator.
BigInt parseUserAmount(String input) =>
    masToNano(input.trim().replaceAll(',', '.'));
