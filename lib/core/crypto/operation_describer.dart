/// Best-effort parser for serialized Massa operations.
///
/// When a dApp asks the wallet to sign raw operation bytes, showing only
/// an opaque blob would be dangerous. This decoder walks the wire format
/// (`LEB128(fee) | LEB128(expirePeriod) | LEB128(type) | payload`) and
/// extracts human-readable details for the confirmation dialog. Parsing
/// failures never throw — they yield `parsedOk: false` so the UI can
/// warn the user accordingly.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'base58_check.dart';
import 'operation_serializer.dart' show OperationType;
import 'varint.dart';

/// Decoded details of a serialized operation.
class OperationDescription {
  /// Operation type (null when parsing failed early).
  final OperationType? type;

  /// Fee in nanoMAS.
  final BigInt? fee;

  /// Expiry period.
  final int? expirePeriod;

  /// Recipient address (`AU…`/`AS…`) for transfers / callSC target.
  final String? targetAddress;

  /// Amount in nanoMAS (transfer) or roll count (rolls).
  final BigInt? amount;

  /// Coins attached to a callSC, in nanoMAS.
  final BigInt? coins;

  /// Max gas for callSC.
  final BigInt? maxGas;

  /// Called function name.
  final String? functionName;

  /// Whether the full payload parsed cleanly.
  final bool parsedOk;

  /// Raw byte length (always available).
  final int byteLength;

  /// Creates the description.
  const OperationDescription({
    this.type,
    this.fee,
    this.expirePeriod,
    this.targetAddress,
    this.amount,
    this.coins,
    this.maxGas,
    this.functionName,
    required this.parsedOk,
    required this.byteLength,
  });
}

/// Parses [bytes] into an [OperationDescription].
OperationDescription describeSerializedOperation(List<int> bytes) {
  var offset = 0;

  BigInt? readVarint() {
    try {
      final r = varintDecode(Uint8List.fromList(bytes.sublist(offset)));
      offset += r.bytes;
      return r.value;
    } catch (_) {
      return null;
    }
  }

  final fee = readVarint();
  final expire = readVarint();
  final typeRaw = readVarint();
  OperationType? type;
  if (typeRaw != null && typeRaw <= BigInt.from(OperationType.callSC.value)) {
    type = OperationType.fromValue(typeRaw.toInt());
  }
  if (fee == null || expire == null || type == null) {
    return OperationDescription(parsedOk: false, byteLength: bytes.length);
  }

  String? target;
  BigInt? amount;
  BigInt? coins;
  BigInt? maxGas;
  String? functionName;
  var ok = true;

  String? readAddress() {
    if (offset >= bytes.length) return null;
    final addrType = bytes[offset];
    offset += 1;
    final version = readVarint();
    if (version == null || offset + 32 > bytes.length) return null;
    final digest = bytes.sublist(offset, offset + 32);
    offset += 32;
    final prefix = addrType == 0 ? 'AU' : 'AS';
    try {
      return prefix +
          base58CheckEncode([...varintEncodeInt(version.toInt()), ...digest]);
    } catch (_) {
      return null;
    }
  }

  switch (type) {
    case OperationType.transaction:
      target = readAddress();
      amount = readVarint();
      ok = target != null && amount != null;
      break;
    case OperationType.rollBuy:
    case OperationType.rollSell:
      amount = readVarint();
      ok = amount != null;
      break;
    case OperationType.callSC:
      maxGas = readVarint();
      coins = readVarint();
      target = readAddress();
      final fnLen = readVarint()?.toInt();
      if (maxGas == null ||
          coins == null ||
          target == null ||
          fnLen == null ||
          offset + fnLen > bytes.length) {
        ok = false;
        break;
      }
      functionName = utf8.decode(bytes.sublist(offset, offset + fnLen));
      offset += fnLen;
      final paramLen = readVarint()?.toInt();
      if (paramLen == null || offset + paramLen > bytes.length) {
        ok = false;
        break;
      }
      offset += paramLen;
      ok = true;
      break;
    case OperationType.executeSC:
      maxGas = readVarint();
      final maxCoins = readVarint();
      final bcLen = readVarint()?.toInt();
      if (maxGas == null ||
          maxCoins == null ||
          bcLen == null ||
          offset + bcLen > bytes.length) {
        ok = false;
        break;
      }
      offset += bcLen;
      ok = true;
      break;
  }

  return OperationDescription(
    type: type,
    fee: fee,
    expirePeriod: expire.toInt(),
    targetAddress: target,
    amount: amount,
    coins: coins,
    maxGas: maxGas,
    functionName: functionName,
    parsedOk: ok && offset <= bytes.length,
    byteLength: bytes.length,
  );
}
