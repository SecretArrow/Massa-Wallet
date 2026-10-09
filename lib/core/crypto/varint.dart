/// Massa varint encoding utilities.
///
/// Massa uses LEB128-style unsigned varints for:
/// - version bytes attached to keys/addresses/signatures (`VarintVersioner`)
/// - operation type / expire-period / string lengths inside operations.
///
/// Semantics are ported 1:1 from `massa-web3` (`varint` + `big-varint`),
/// which are byte-compatible for unsigned values.
library;

/// Encodes [value] as an unsigned LEB128 varint.
///
/// Throws [ArgumentError] for negative values.
List<int> varintEncode(BigInt value) {
  if (value.isNegative) {
    throw ArgumentError('value must be unsigned, got $value');
  }
  final out = <int>[];
  var v = value;
  final limit = BigInt.from(0x7f);
  while (v > limit) {
    out.add((v & limit).toInt() | 0x80);
    v >>= 7;
  }
  out.add(v.toInt());
  return out;
}

/// Encodes a non-negative [int] as unsigned LEB128 varint.
List<int> varintEncodeInt(int value) => varintEncode(BigInt.from(value));

/// Decodes an unsigned LEB128 varint starting at [offset].
///
/// Returns the decoded value and the number of bytes consumed.
({BigInt value, int bytes}) varintDecode(List<int> data, [int offset = 0]) {
  var result = BigInt.zero;
  var shift = 0;
  var n = 0;
  while (true) {
    final idx = offset + n;
    if (idx >= data.length) {
      throw const FormatException('varint: offset out of range');
    }
    final b = data[idx];
    result += BigInt.from(b & 0x7f) << shift;
    n++;
    if (b < 0x80) break;
    shift += 7;
  }
  return (value: result, bytes: n);
}

/// Decodes an unsigned LEB128 varint starting at [offset] as [int].
///
/// Throws [FormatException] if the value does not fit into 64 bits.
int varintDecodeInt(List<int> data, [int offset = 0]) {
  final r = varintDecode(data, offset);
  if (r.value > BigInt.parse('18446744073709551615')) {
    throw const FormatException('varint: value exceeds 64 bits');
  }
  return r.value.toInt();
}
