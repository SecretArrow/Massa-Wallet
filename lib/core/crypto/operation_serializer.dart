/// Massa operation serialization, canonicalization and signing.
///
/// Byte-compatible with `massa-web3` `OperationManager` (verified against
/// the official unit-test vectors):
///
/// ```text
/// serialized(op)   = LEB128(fee) | LEB128(expirePeriod) | LEB128(type) | payload
/// canonical(chainId, op, pub) = u64BE(chainId) | versionedPublicKey | serialized(op)
/// signature = ed25519_sign(rawPrivateKey, BLAKE3(canonical))
/// ```
library;

import 'dart:convert';
import 'dart:typed_data';

import 'massa_keys.dart';
import 'varint.dart';

/// Operation types as fixed by the Massa node.
enum OperationType {
  /// Plain MAS transfer.
  transaction(0),

  /// Buy staking rolls.
  rollBuy(1),

  /// Sell staking rolls.
  rollSell(2),

  /// Deploy / execute smart-contract bytecode.
  executeSC(3),

  /// Call a smart-contract function.
  callSC(4);

  const OperationType(this.value);

  /// Wire value of the operation type.
  final int value;

  static OperationType fromValue(int v) => OperationType.values.firstWhere(
    (t) => t.value == v,
    orElse: () => throw ArgumentError('operation type not supported: $v'),
  );
}

/// A transfer operation.
class TransferOperationData {
  /// Recipient address (`AU...`/`AS...`).
  final String recipientAddress;

  /// Amount in nanoMAS (1 MAS = 1e9 nanoMAS).
  final BigInt amount;

  TransferOperationData({required this.recipientAddress, required this.amount});
}

/// Buy/sell rolls operation.
class RollOperationData {
  /// Number of rolls.
  final BigInt amount;

  RollOperationData({required this.amount});
}

/// Call smart-contract function operation.
class CallOperationData {
  /// Target smart-contract address.
  final String targetAddress;

  /// Function name.
  final String functionName;

  /// Raw serialized parameter bytes (Massa `Args` compatible).
  final List<int> parameter;

  /// Maximum gas for the execution.
  final BigInt maxGas;

  /// Coins sent with the call, in nanoMAS.
  final BigInt coins;

  CallOperationData({
    required this.targetAddress,
    required this.functionName,
    required this.parameter,
    required this.maxGas,
    BigInt? coins,
  }) : coins = coins ?? BigInt.zero;
}

/// Execute smart-contract bytecode operation.
class ExecuteOperationData {
  /// Compiled AssemblyScript bytecode.
  final List<int> contractDataBinary;

  /// Maximum gas.
  final BigInt maxGas;

  /// Maximum coins, in nanoMAS.
  final BigInt maxCoins;

  /// Optional datastore entries.
  final Map<List<int>, List<int>> datastore;

  ExecuteOperationData({
    required this.contractDataBinary,
    required this.maxGas,
    BigInt? maxCoins,
    this.datastore = const {},
  }) : maxCoins = maxCoins ?? BigInt.zero;
}

/// Fully-specified operation ready for serialization.
class MassaOperation {
  /// Operation fee in nanoMAS.
  final BigInt fee;

  /// Absolute slot period after which the operation expires.
  final int expirePeriod;

  /// Operation type.
  final OperationType type;

  final TransferOperationData? transfer;
  final RollOperationData? roll;
  final CallOperationData? call;
  final ExecuteOperationData? execute;

  MassaOperation._({
    required this.fee,
    required this.expirePeriod,
    required this.type,
    this.transfer,
    this.roll,
    this.call,
    this.execute,
  });

  /// Builds a transaction operation.
  factory MassaOperation.transfer({
    required BigInt fee,
    required int expirePeriod,
    required TransferOperationData data,
  }) => MassaOperation._(
    fee: fee,
    expirePeriod: expirePeriod,
    type: OperationType.transaction,
    transfer: data,
  );

  /// Builds a buy-rolls operation.
  factory MassaOperation.rollBuy({
    required BigInt fee,
    required int expirePeriod,
    required RollOperationData data,
  }) => MassaOperation._(
    fee: fee,
    expirePeriod: expirePeriod,
    type: OperationType.rollBuy,
    roll: data,
  );

  /// Builds a sell-rolls operation.
  factory MassaOperation.rollSell({
    required BigInt fee,
    required int expirePeriod,
    required RollOperationData data,
  }) => MassaOperation._(
    fee: fee,
    expirePeriod: expirePeriod,
    type: OperationType.rollSell,
    roll: data,
  );

  /// Builds a smart-contract call operation.
  factory MassaOperation.callSC({
    required BigInt fee,
    required int expirePeriod,
    required CallOperationData data,
  }) => MassaOperation._(
    fee: fee,
    expirePeriod: expirePeriod,
    type: OperationType.callSC,
    call: data,
  );

  /// Builds an execute-bytecode operation.
  factory MassaOperation.executeSC({
    required BigInt fee,
    required int expirePeriod,
    required ExecuteOperationData data,
  }) => MassaOperation._(
    fee: fee,
    expirePeriod: expirePeriod,
    type: OperationType.executeSC,
    execute: data,
  );
}

/// Serializes, canonicalizes and signs Massa operations.
class OperationSerializer {
  /// Serializes [operation] following the Massa protocol.
  static Uint8List serialize(MassaOperation operation) {
    final components = <int>[
      ...varintEncode(operation.fee),
      ...varintEncodeInt(operation.expirePeriod),
      ...varintEncodeInt(operation.type.value),
    ];

    switch (operation.type) {
      case OperationType.transaction:
        final t = operation.transfer!;
        components
          ..addAll(MassaAddress.fromString(t.recipientAddress).operationBytes)
          ..addAll(varintEncode(t.amount));
        break;
      case OperationType.rollBuy:
      case OperationType.rollSell:
        components.addAll(varintEncode(operation.roll!.amount));
        break;
      case OperationType.callSC:
        final c = operation.call!;
        components
          ..addAll(varintEncode(c.maxGas))
          ..addAll(varintEncode(c.coins))
          ..addAll(MassaAddress.fromString(c.targetAddress).operationBytes)
          ..addAll(varintEncodeInt(utf8.encode(c.functionName).length))
          ..addAll(utf8.encode(c.functionName))
          ..addAll(varintEncodeInt(c.parameter.length))
          ..addAll(c.parameter);
        break;
      case OperationType.executeSC:
        final e = operation.execute!;
        components
          ..addAll(varintEncode(e.maxGas))
          ..addAll(varintEncode(e.maxCoins))
          ..addAll(varintEncode(BigInt.from(e.contractDataBinary.length)))
          ..addAll(e.contractDataBinary)
          ..addAll(varintEncode(BigInt.from(e.datastore.length)));
        e.datastore.forEach((key, value) {
          components
            ..addAll(varintEncode(BigInt.from(key.length)))
            ..addAll(key)
            ..addAll(varintEncode(BigInt.from(value.length)))
            ..addAll(value);
        });
        break;
    }

    return Uint8List.fromList(components);
  }

  /// Builds the canonical bytes that get signed:
  /// `u64BE(chainId) | versionedPublicKey | serializedOperation`.
  static Uint8List canonicalize(
    BigInt chainId,
    MassaOperation operation,
    MassaPublicKey publicKey,
  ) {
    final networkId = Uint8List(8);
    var v = chainId;
    for (var i = 7; i >= 0; i--) {
      networkId[i] = (v & BigInt.from(0xff)).toInt();
      v >>= 8;
    }
    final data = serialize(operation);
    return Uint8List.fromList([
      ...networkId,
      ...publicKey.versionedBytes,
      ...data,
    ]);
  }

  /// Signs [operation] for the network identified by [chainId].
  ///
  /// Equivalent to massa-web3 `OperationManager.sign` — the canonical bytes
  /// are BLAKE3-hashed once, inside [MassaPrivateKey.signMessage].
  static MassaSignature sign(
    BigInt chainId,
    MassaOperation operation,
    MassaPrivateKey privateKey,
  ) {
    final canonical = canonicalize(chainId, operation, privateKey.publicKey);
    return privateKey.signMessage(canonical);
  }
}
