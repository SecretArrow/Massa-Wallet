/// Base58Check encoding/decoding (Bitcoin-style, used by Massa).
///
/// Layout: `payload || checksum` where `checksum = sha256(sha256(payload))[0:4]`.
/// Ported to match `bs58check` used by `@massalabs/massa-web3`.
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const String _alphabet =
    '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

/// Encodes [payload] with the Base58Check checksum.
String base58CheckEncode(List<int> payload) {
  final bytes = Uint8List.fromList(payload);
  final checksum = _doubleSha256(bytes);
  final full = Uint8List(bytes.length + 4)
    ..setRange(0, bytes.length, bytes)
    ..setRange(bytes.length, bytes.length + 4, checksum.sublist(0, 4));
  return _base58EncodeRaw(full);
}

/// Decodes a Base58Check string, verifying the 4-byte checksum.
///
/// Throws [FormatException] on bad characters or checksum mismatch.
Uint8List base58CheckDecode(String encoded) {
  final full = _base58DecodeRaw(encoded);
  if (full.length < 5) {
    throw const FormatException('base58check: input too short');
  }
  final payload = full.sublist(0, full.length - 4);
  final checksum = full.sublist(full.length - 4);
  final expected = _doubleSha256(payload);
  for (var i = 0; i < 4; i++) {
    if (checksum[i] != expected[i]) {
      throw const FormatException('base58check: invalid checksum');
    }
  }
  return Uint8List.fromList(payload);
}

Uint8List _doubleSha256(List<int> data) {
  final h1 = sha256.convert(data).bytes;
  return Uint8List.fromList(sha256.convert(h1).bytes);
}

String _base58EncodeRaw(Uint8List bytes) {
  // Count leading zeroes.
  var zeroes = 0;
  while (zeroes < bytes.length && bytes[zeroes] == 0) {
    zeroes++;
  }
  // Convert to big number base-58 digits (manual bignum, byte array).
  final size = (bytes.length - zeroes) * 138 ~/ 100 + 1;
  final b58 = Uint8List(size);
  var length = 0;
  for (var i = zeroes; i < bytes.length; i++) {
    var carry = bytes[i];
    var j = 0;
    for (var k = size - 1; (carry != 0 || j < length) && k >= 0; k--, j++) {
      carry += 256 * b58[k];
      b58[k] = carry % 58;
      carry ~/= 58;
    }
    length = j;
  }
  // Skip leading zeroes in the result.
  var it = size - length;
  final sb = StringBuffer();
  for (var i = 0; i < zeroes; i++) {
    sb.write('1');
  }
  while (it < size && b58[it] == 0) {
    it++;
  }
  for (; it < size; it++) {
    sb.write(_alphabet[b58[it]]);
  }
  return sb.toString();
}

Uint8List _base58DecodeRaw(String input) {
  if (input.isEmpty) return Uint8List(0);
  // Count leading '1' chars (zero bytes).
  var zeroes = 0;
  while (zeroes < input.length && input[zeroes] == '1') {
    zeroes++;
  }
  final size = (input.length - zeroes) * 733 ~/ 1000 + 1;
  final bytes = Uint8List(size);
  var length = 0;
  for (var i = zeroes; i < input.length; i++) {
    final idx = _alphabet.indexOf(input[i]);
    if (idx < 0) {
      throw FormatException('base58: invalid character "${input[i]}"');
    }
    var carry = idx;
    var j = 0;
    for (var k = size - 1; (carry != 0 || j < length) && k >= 0; k--, j++) {
      carry += 58 * bytes[k];
      bytes[k] = carry % 256;
      carry ~/= 256;
    }
    length = j;
  }
  var it = size - length;
  final out = <int>[];
  for (var i = 0; i < zeroes; i++) {
    out.add(0);
  }
  while (it < size && bytes[it] == 0) {
    it++;
  }
  for (; it < size; it++) {
    out.add(bytes[it]);
  }
  return Uint8List.fromList(out);
}
