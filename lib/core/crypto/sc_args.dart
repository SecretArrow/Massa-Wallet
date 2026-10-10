/// Massa smart-contract `Args` serialization (compatible with
/// `@massalabs/massa-sc-toolkit` `Args` and `massa-web3` `basicElements/args.ts`).
///
/// Layout is a raw concatenation (NO type tags):
/// - string  : u32 LE length + UTF-8 bytes
/// - u8..u256: little-endian fixed-width bytes
/// - bool    : 1 byte (0/1)
/// - bytes   : u32 LE length + raw bytes
library;

import 'dart:convert';
import 'dart:typed_data';

/// Serializes arguments for smart-contract function calls.
class ScArgs {
  final BytesBuilder _builder = BytesBuilder();

  /// Serialized bytes so far.
  Uint8List get bytes => _builder.toBytes();

  /// Number of bytes serialized so far.
  int get length => bytes.length;

  void _add(List<int> chunk) => _builder.add(chunk);

  /// Adds a u32 little-endian.
  ScArgs addU32(int value) {
    final b = ByteData(4)..setUint32(0, value, Endian.little);
    _add(b.buffer.asUint8List());
    return this;
  }

  /// Adds a u64 little-endian.
  ScArgs addU64(BigInt value) {
    final b = ByteData(8)
      ..setUint64(0, value.toUnsigned(64).toInt(), Endian.little);
    _add(b.buffer.asUint8List());
    return this;
  }

  /// Adds a u8.
  ScArgs addU8(int value) {
    _add([value & 0xFF]);
    return this;
  }

  /// Adds a u16 little-endian.
  ScArgs addU16(int value) {
    final b = ByteData(2)..setUint16(0, value, Endian.little);
    _add(b.buffer.asUint8List());
    return this;
  }

  /// Adds a bool (1 byte).
  ScArgs addBool(bool value) {
    _add([value ? 1 : 0]);
    return this;
  }

  /// Adds a u256 little-endian (32 bytes).
  ScArgs addU256(BigInt value) {
    final b = _toLe(value, 32);
    _add(b);
    return this;
  }

  /// Adds a u128 little-endian (16 bytes).
  ScArgs addU128(BigInt value) {
    final b = _toLe(value, 16);
    _add(b);
    return this;
  }

  /// Adds a UTF-8 string (u32 LE length + bytes).
  ScArgs addString(String value) {
    final raw = utf8.encode(value);
    addU32(raw.length);
    _add(raw);
    return this;
  }

  /// Adds raw bytes (u32 LE length + bytes), like `addUint8Array`.
  ScArgs addBytes(List<int> value) {
    addU32(value.length);
    _add(value);
    return this;
  }

  /// Chainable concatenation of another serialized args buffer.
  ScArgs concat(List<int> other) {
    _add(other);
    return this;
  }
}

/// Little-endian fixed-width conversion for big integers.
Uint8List _toLe(BigInt value, int width) {
  if (value.isNegative) {
    throw ArgumentError('negative value cannot be serialized as unsigned');
  }
  final out = Uint8List(width);
  var v = value;
  for (var i = 0; i < width; i++) {
    out[i] = (v & BigInt.from(0xFF)).toInt();
    v = v >> 8;
  }
  if (v != BigInt.zero) {
    throw ArgumentError('value too large for $width bytes');
  }
  return out;
}

/// Deserializes Massa `Args` bytes.
class ScArgsReader {
  /// Source bytes.
  final Uint8List data;

  int _offset = 0;

  /// Creates a reader.
  ScArgsReader(this.data);

  /// Current read offset.
  int get offset => _offset;

  /// Whether all bytes were consumed.
  bool get isEof => _offset >= data.length;

  /// Reads a u8.
  int nextU8() => data[_offset++];

  /// Reads a u16 LE.
  int nextU16() {
    final v = ByteData.sublistView(
      data,
      _offset,
      _offset + 2,
    ).getUint16(0, Endian.little);
    _offset += 2;
    return v;
  }

  /// Reads a u32 LE.
  int nextU32() {
    final v = ByteData.sublistView(
      data,
      _offset,
      _offset + 4,
    ).getUint32(0, Endian.little);
    _offset += 4;
    return v;
  }

  /// Reads a u64 LE.
  BigInt nextU64() => _readLe(8);

  /// Reads a u128 LE.
  BigInt nextU128() => _readLe(16);

  /// Reads a u256 LE.
  BigInt nextU256() => _readLe(32);

  /// Reads a bool.
  bool nextBool() => nextU8() != 0;

  /// Reads a UTF-8 string.
  String nextString() {
    final len = nextU32();
    final raw = data.sublist(_offset, _offset + len);
    _offset += len;
    return utf8.decode(raw);
  }

  /// Reads a byte array (u32 LE length + bytes).
  Uint8List nextBytes() {
    final len = nextU32();
    final raw = data.sublist(_offset, _offset + len);
    _offset += len;
    return raw;
  }

  BigInt _readLe(int width) {
    var v = BigInt.zero;
    for (var i = width - 1; i >= 0; i--) {
      v = (v << 8) | BigInt.from(data[_offset + i]);
    }
    _offset += width;
    return v;
  }
}

/// Converts a big integer to little-endian [width] bytes.
Uint8List bigIntToLe(BigInt value, int width) => _toLe(value, width);

/// Converts little-endian bytes to a big integer.
BigInt leToBigInt(List<int> bytes) {
  var v = BigInt.zero;
  for (var i = bytes.length - 1; i >= 0; i--) {
    v = (v << 8) | BigInt.from(bytes[i] & 0xFF);
  }
  return v;
}
