/// BIP-39 mnemonic (recovery phrase) — generate, validate, derive seed.
///
/// English wordlist only (the words are pure ASCII, so NFKD
/// normalization is a no-op and can be skipped safely — this matches
/// the common lightweight-wallet approach; the non-English BIP-39
/// wordlists are intentionally not supported).
///
/// Spec: github.com/bitcoin/bips/blob/master/bip-0039.mediawiki
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:pointycastle/export.dart';

import 'bip39_wordlist.dart';
import 'massa_keys.dart';

/// Valid mnemonic word counts (strength 128/256 are exposed; the other
/// standard lengths still validate for import compatibility).
const Set<int> bip39ValidWordCounts = {12, 15, 18, 21, 24};

/// Generates a random BIP-39 mnemonic.
///
/// [strength] is the entropy size in bits — 128 produces 12 words,
/// 256 produces 24 words.
String generateMnemonic({int strength = 128}) {
  if (strength % 32 != 0 || strength < 128 || strength > 256) {
    throw ArgumentError('strength must be 128…256 in 32-bit steps');
  }
  final entropy = randomBytes(strength ~/ 8);
  return mnemonicFromEntropy(entropy);
}

/// Encodes [entropy] (with checksum) into a BIP-39 mnemonic string.
String mnemonicFromEntropy(List<int> entropy) {
  final entropyBits = _toBits(entropy);
  final hash = c.sha256.convert(entropy).bytes;
  final checksumBits = _toBits(hash).substring(0, entropy.length * 8 ~/ 32);
  final bits = entropyBits + checksumBits;
  final words = <String>[];
  for (var i = 0; i + 11 <= bits.length; i += 11) {
    words.add(
      bip39EnglishWordlist[int.parse(bits.substring(i, i + 11), radix: 2)],
    );
  }
  return words.join(' ');
}

/// Decodes a mnemonic back to its entropy (validates checksum).
///
/// Throws [FormatException] with a stable `code:` prefix that the UI
/// maps to localized messages:
///  - `code:length` — wrong word count
///  - `code:word:{n}` — word at position n (0-based) not in the list
///  - `code:checksum` — checksum mismatch
Uint8List mnemonicToEntropy(String mnemonic) {
  final words = normalizeMnemonic(mnemonic).split(' ');
  if (!bip39ValidWordCounts.contains(words.length)) {
    throw const FormatException('code:length');
  }
  var bits = '';
  for (var i = 0; i < words.length; i++) {
    final index = bip39EnglishWordlist.indexOf(words[i]);
    if (index < 0) {
      throw FormatException('code:word:$i');
    }
    bits += index.toRadixString(2).padLeft(11, '0');
  }
  final checksumLen = bits.length * 32 ~/ 33;
  final entropyLen = bits.length - checksumLen;
  final entropyBits = bits.substring(0, entropyLen);
  final checksumBits = bits.substring(entropyLen);
  final entropy = Uint8List(entropyLen ~/ 8);
  for (var i = 0; i < entropy.length; i++) {
    entropy[i] = int.parse(entropyBits.substring(i * 8, i * 8 + 8), radix: 2);
  }
  final hash = c.sha256.convert(entropy).bytes;
  final expected = _toBits(hash).substring(0, checksumLen);
  if (checksumBits != expected) {
    throw const FormatException('code:checksum');
  }
  return entropy;
}

/// Validates a mnemonic without decoding it.
bool isValidMnemonic(String mnemonic) {
  try {
    mnemonicToEntropy(mnemonic);
    return true;
  } on FormatException {
    return false;
  }
}

/// Lowercases, trims and collapses whitespace between words.
String normalizeMnemonic(String mnemonic) => mnemonic
    .toLowerCase()
    .trim()
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .join(' ');

/// Derives the 64-byte BIP-39 seed from a mnemonic.
///
/// PBKDF2-HMAC-SHA512, 2048 iterations, salt `"mnemonic" + [passphrase]`
/// (the optional passphrase is the "25th word"; Pyramids Wallet keeps it
/// empty — an explicit empty passphrase is interoperable with all
/// standard wallets).
Uint8List mnemonicToSeed(String mnemonic, {String passphrase = ''}) {
  final normalized = normalizeMnemonic(mnemonic);
  // Cheap sanity check first (gives better errors than PBKDF2 silence).
  mnemonicToEntropy(normalized);
  final derivator = PBKDF2KeyDerivator(HMac(SHA512Digest(), 64))
    ..init(
      Pbkdf2Parameters(
        Uint8List.fromList(utf8.encode('mnemonic$passphrase')),
        2048,
        64,
      ),
    );
  return derivator.process(Uint8List.fromList(utf8.encode(normalized)));
}

/// Renders [bytes] as lowercase hex.
String bytesToHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

String _toBits(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(2).padLeft(8, '0')).join();
