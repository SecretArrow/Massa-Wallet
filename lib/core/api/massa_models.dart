/// Typed models for the Massa JSON-RPC v2 API.
library;

import 'dart:convert';

import 'massa_amount.dart';

/// Node status (from `get_status`).
class NodeStatus {
  /// Node version string.
  final String version;

  /// Current chain id.
  final int chainId;

  /// Minimal accepted fee, in nanoMAS.
  final BigInt minimalFee;

  /// Current slot period.
  final int currentPeriod;

  /// Current cycle (nullable on some nodes).
  final int? currentCycle;

  /// Creates a node status.
  NodeStatus({
    required this.version,
    required this.chainId,
    required this.minimalFee,
    required this.currentPeriod,
    this.currentCycle,
  });

  /// Parses from the JSON-RPC result.
  factory NodeStatus.fromJson(Map<String, dynamic> json) => NodeStatus(
    version: (json['version'] ?? '') as String,
    chainId: (json['chain_id'] as num?)?.toInt() ?? 0,
    minimalFee: json['minimal_fee'] == null
        ? BigInt.from(1000000) // 0.001 MAS fallback
        : masToNano(json['minimal_fee'].toString()),
    currentPeriod:
        ((json['last_slot'] as Map<String, dynamic>?)?['period'] as num?)
            ?.toInt() ??
        0,
    currentCycle: (json['current_cycle'] as num?)?.toInt(),
  );
}

/// Address info (from `get_addresses`).
class AddressInfo {
  /// The address string.
  final String address;

  /// Final balance in nanoMAS.
  final BigInt finalBalance;

  /// Candidate (speculative) balance in nanoMAS.
  final BigInt candidateBalance;

  /// Final roll count.
  final BigInt finalRollCount;

  /// Candidate roll count.
  final BigInt candidateRollCount;

  /// Cycle information (roll drawing / production counts).
  final List<CycleInfo> cycleInfos;

  /// Creates address info.
  AddressInfo({
    required this.address,
    required this.finalBalance,
    required this.candidateBalance,
    required this.finalRollCount,
    required this.candidateRollCount,
    this.cycleInfos = const [],
  });

  /// Parses from the JSON-RPC result.
  factory AddressInfo.fromJson(Map<String, dynamic> json) => AddressInfo(
    address: json['address'] as String,
    finalBalance: masToNano(json['final_balance'].toString()),
    candidateBalance: masToNano(json['candidate_balance'].toString()),
    finalRollCount: BigInt.from(
      (json['final_roll_count'] as num?)?.toInt() ?? 0,
    ),
    candidateRollCount: BigInt.from(
      (json['candidate_roll_count'] as num?)?.toInt() ?? 0,
    ),
    cycleInfos: ((json['cycle_infos'] as List?) ?? const [])
        .map((e) => CycleInfo.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  /// Active rolls across cycles (sum of active_roll_count).
  BigInt get activeRolls =>
      cycleInfos.fold(BigInt.zero, (acc, c) => acc + c.activeRollCount);
}

/// Per-cycle staking info.
class CycleInfo {
  /// Cycle number.
  final int cycle;

  /// Active roll count in this cycle.
  final BigInt activeRollCount;

  /// Produced blocks in this cycle.
  final int producedBlocks;

  /// Created a cycle with this many rolls.
  final BigInt? rollCount;

  /// Creates cycle info.
  CycleInfo({
    required this.cycle,
    required this.activeRollCount,
    required this.producedBlocks,
    this.rollCount,
  });

  /// Parses from JSON.
  factory CycleInfo.fromJson(Map<String, dynamic> json) => CycleInfo(
    cycle: (json['cycle'] as num?)?.toInt() ?? 0,
    activeRollCount: BigInt.from(
      (json['active_roll_count'] as num?)?.toInt() ?? 0,
    ),
    producedBlocks: ((json['produced_blocks'] as List?) ?? const []).length,
    rollCount: json['roll_count'] == null
        ? null
        : BigInt.from((json['roll_count'] as num).toInt()),
  );
}

/// Input for `send_operations`.
class SendOperationInput {
  /// Serialized operation bytes (as list of ints).
  final List<int> serializedContent;

  /// Creator public key string (`P...`).
  final String creatorPublicKey;

  /// Signature string (base58check, no prefix).
  final String signature;

  /// Creates the input.
  SendOperationInput({
    required this.serializedContent,
    required this.creatorPublicKey,
    required this.signature,
  });
}

/// Input for `execute_read_only_call`.
class ReadOnlyCallInput {
  /// Target smart-contract address.
  final String targetAddress;

  /// Target function name (empty to run `main`).
  final String targetFunction;

  /// Raw parameter bytes.
  final List<int> parameter;

  /// Max gas.
  final int maxGas;

  /// Caller address or null.
  final String? callerAddress;

  /// Coins string or null.
  final String? coins;

  /// Fee string or null.
  final String? fee;

  /// Creates the input.
  ReadOnlyCallInput({
    required this.targetAddress,
    required this.targetFunction,
    this.parameter = const [],
    this.maxGas = 1000000,
    this.callerAddress,
    this.coins,
    this.fee,
  });
}

/// Result of a read-only call.
class ReadOnlyCallResult {
  /// Whether execution succeeded.
  final bool ok;

  /// Returned bytes (base64 decoded by the API layer when available).
  final List<int> returnValue;

  /// Error message when [ok] is false.
  final String? error;

  /// Gas cost.
  final BigInt gasCost;

  /// Creates the result.
  ReadOnlyCallResult({
    required this.ok,
    this.returnValue = const [],
    this.error,
    BigInt? gasCost,
  }) : gasCost = gasCost ?? BigInt.zero;

  /// Parses from the JSON-RPC result.
  factory ReadOnlyCallResult.fromJson(Map<String, dynamic> json) {
    final res = json['result'];
    final ok = res is Map ? res['Ok'] != null : json['Ok'] != null;
    dynamic okValue;
    if (res is Map && res['Ok'] != null) {
      okValue = res['Ok'];
    } else if (json['Ok'] != null) {
      okValue = json['Ok'];
    }
    String? err;
    if (!ok) {
      final e = (res is Map ? res['Err'] ?? json['Err'] : json['Err']);
      err = e is Map
          ? (e['Execute_error']?['error']?.toString() ?? '$e')
          : '$e';
    }
    List<int> ret = const [];
    if (ok && okValue is Map && okValue['return_value'] != null) {
      ret = switch (okValue['return_value']) {
        final String s => base64Decode(s),
        final List l => l.cast<int>(),
        _ => const [],
      };
    }
    return ReadOnlyCallResult(
      ok: ok,
      returnValue: ret,
      error: err,
      gasCost: BigInt.from((json['gas_cost'] as num?)?.toInt() ?? 0),
    );
  }
}

/// Operation info (from `get_operations`).
class OperationInfo {
  /// Operation id (`OP...`).
  final String id;

  /// Whether the op is in a final block.
  final bool? inFinalBlock;

  /// Whether the op is in a pool.
  final bool? inPool;

  /// Whether the op is speculative success.
  final bool? speculative;

  /// Error string, if execution failed.
  final String? error;

  /// Creates operation info.
  OperationInfo({
    required this.id,
    this.inFinalBlock,
    this.inPool,
    this.speculative,
    this.error,
  });

  /// Parses from the JSON-RPC result.
  factory OperationInfo.fromJson(Map<String, dynamic> json) {
    dynamic op = json['operation'];
    if (op is! Map<String, dynamic>) op = json;
    return OperationInfo(
      id: json['id'] as String? ?? '',
      inFinalBlock: op['in_final_block'] as bool?,
      inPool: op['in_pool'] as bool?,
      speculative: op['speculative'] as bool?,
      error: (op['error'] ?? json['error'])?.toString(),
    );
  }
}

/// A datastore key/value entry.
class DatastoreEntry {
  /// Address owning the entry.
  final String? address;

  /// Raw value bytes.
  final List<int> value;

  /// Creates the entry.
  DatastoreEntry({this.address, this.value = const []});

  /// Parses from JSON.
  factory DatastoreEntry.fromJson(Map<String, dynamic> json) => DatastoreEntry(
    address: json['address'] as String?,
    value: switch (json['value']) {
      final String s => List<int>.from(base64Decode(s)),
      final List l => l.cast<int>(),
      _ => const <int>[],
    },
  );
}

/// Datastore entry request.
class DatastoreEntryInput {
  /// Address to query.
  final String address;

  /// Raw key bytes.
  final List<int> key;

  /// Creates the request.
  DatastoreEntryInput({required this.address, required this.key});
}

/// Staker entry (address + roll count).
class StakerEntry {
  /// Staker address.
  final String address;

  /// Roll count.
  final BigInt rolls;

  /// Creates the entry.
  StakerEntry({required this.address, required this.rolls});

  /// Parses from the `[address, rolls]` array.
  factory StakerEntry.fromList(List e) => StakerEntry(
    address: e[0] as String,
    rolls: BigInt.from((e[1] as num).toInt()),
  );
}
