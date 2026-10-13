/// Seed-phrase → Massa key derivation (Pyramids Wallet standard).
///
/// Documented, deterministic scheme so the phrase can be replayed in
/// any compatible tool:
///
/// 1. BIP-39 mnemonic (English wordlist, 12 or 24 words)
/// 2. `seed = PBKDF2-HMAC-SHA512(mnemonic, "mnemonic" + passphrase, 2048)`
/// 3. SLIP-0010 ed25519 hardened path **`m/44'/4478'/0'/0'/0'`**
///    (SLIP-44 coin type 4478 = MASSA)
/// 4. the 32-byte SLIP-10 key IS the Massa ed25519 seed
///    (`S + base58check(varint(0) + key)` wire format).
library;

import 'bip39.dart';
import 'massa_keys.dart';
import 'slip10.dart';

/// Pyramids Wallet derivation path (SLIP-44 MASSA = 4478).
const String pyramidsDerivationPath = "m/44'/4478'/0'/0'/0'";

const List<int> _pyramidsPath = [44, 4478, 0, 0, 0];

/// Derives the Massa private key for [mnemonic].
///
/// Throws [FormatException] for an invalid phrase (see [mnemonicToEntropy]
/// for the error codes) and [ArgumentError] for unsupported lengths.
MassaPrivateKey privateKeyFromMnemonic(
  String mnemonic, {
  String passphrase = '',
}) {
  final seed = mnemonicToSeed(mnemonic, passphrase: passphrase);
  final key = slip10DeriveEd25519(seed, _pyramidsPath);
  return MassaPrivateKey.fromBytes(key);
}
