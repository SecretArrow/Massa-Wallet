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

  /// Current thread of [currentPeriod].
  final int currentThread;

  /// Current cycle (nullable on some nodes).
  final int? currentCycle;

  /// Unix-ms timestamp of the next cycle start (nullable).
  final int? nextCycleTimeMs;

  /// Node-reported unix-ms time (nullable).
  final int? currentTimeMs;

  /// Creates a node status.
  NodeStatus({
    required this.version,
    required this.chainId,
    required this.minimalFee,
    required this.currentPeriod,
    this.currentThread = 0,
    this.currentCycle,
    this.nextCycleTimeMs,
    this.currentTimeMs,
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
    currentThread:
        ((json['last_slot'] as Map<String, dynamic>?)?['thread'] as num?)
            ?.toInt() ??
        0,
    currentCycle: (json['current_cycle'] as num?)?.toInt(),
    nextCycleTimeMs: (json['next_cycle_time'] as num?)?.toInt(),
    currentTimeMs: (json['current_time'] as num?)?.toInt(),
  );
}

/// A Massa execution slot: [period] × [thread] (32 threads of 500 ms,
/// i.e. 16 s per period — fixed by the node, `massa-models` constants).
class MassaSlot {
  /// Slot period.
  final int period;

  /// Slot thread (0..31).
  final int thread;

  /// Creates a slot.
  const MassaSlot({required this.period, required this.thread});

  /// Parses `{period, thread}` JSON.
  factory MassaSlot.fromJson(Map<String, dynamic> json) => MassaSlot(
    period: (json['period'] as num).toInt(),
    thread: (json['thread'] as num).toInt(),
  );

  /// JSON representation for RPC requests.
  Map<String, dynamic> toJson() => {'period': period, 'thread': thread};

  @override
  bool operator ==(Object other) =>
      other is MassaSlot && other.period == period && other.thread == thread;

  @override
  int get hashCode => Object.hash(period, thread);

  @override
  String toString() => '($period, $thread)';
}

/// Booking quote for a deferred call (from `get_deferred_call_quote`).
class DeferredCallQuote {
  /// Target slot of the quote.
  final MassaSlot targetSlot;

  /// Gas the node will actually reserve (may be bumped over the request).
  final BigInt maxGas;

  /// Whether the slot can still be booked.
  final bool available;

  /// Booking price in nanoMAS (network fee paid at registration time).
  final BigInt priceNano;

  /// Creates a quote.
  const DeferredCallQuote({
    required this.targetSlot,
    required this.maxGas,
    required this.available,
    required this.priceNano,
  });

  /// Parses from the JSON-RPC result item.
  factory DeferredCallQuote.fromJson(Map<String, dynamic> json) {
    final price = json['price'];
    final priceNano = price == null
        ? BigInt.zero
        : price is num
        ? BigInt.from(price.toInt())
        : masToNano(price.toString());
    final maxGas = json['max_gas_request'] ?? json['max_gas'];
    return DeferredCallQuote(
      targetSlot: MassaSlot.fromJson(
        json['target_slot'] as Map<String, dynamic>,
      ),
      maxGas: maxGas == null
          ? BigInt.zero
          : BigInt.from((maxGas as num).toInt()),
      available: (json['available'] as bool?) ?? false,
      priceNano: priceNano,
    );
  }
}

/// A registered deferred call (from `get_deferred_call_info`).
class DeferredCallInfo {
  /// Deferred call id (`D…` base58check).
  final String callId;

  /// Address that registered the call.
  final String senderAddress;

  /// Slot at which the call executes.
  final MassaSlot targetSlot;

  /// Target smart-contract address.
  final String targetAddress;

  /// Target function name.
  final String targetFunction;

  /// Serialized parameters (raw bytes).
  final List<int> parameters;

  /// Coins sent along, in nanoMAS.
  final BigInt coinsNano;

  /// Maximum gas of the execution.
  final BigInt maxGas;

  /// Booking fee paid, in nanoMAS.
  final BigInt feeNano;

  /// Whether the call was cancelled by its creator.
  final bool cancelled;

  /// Creates deferred call info.
  const DeferredCallInfo({
    required this.callId,
    required this.senderAddress,
    required this.targetSlot,
    required this.targetAddress,
    required this.targetFunction,
    required this.parameters,
    required this.coinsNano,
    required this.maxGas,
    required this.feeNano,
    required this.cancelled,
  });

  static BigInt _amount(dynamic v) {
    if (v == null) return BigInt.zero;
    if (v is num) return BigInt.from(v.toInt());
    return masToNano(v.toString());
  }

  /// Parses from the JSON-RPC result item.
  factory DeferredCallInfo.fromJson(Map<String, dynamic> json) {
    final call = (json['call'] as Map<String, dynamic>?) ?? json;
    return DeferredCallInfo(
      callId: (json['call_id'] ?? call['call_id'] ?? '') as String,
      senderAddress: (call['sender_address'] ?? '') as String,
      targetSlot: MassaSlot.fromJson(
        call['target_slot'] as Map<String, dynamic>,
      ),
      targetAddress: (call['target_address'] ?? '') as String,
      targetFunction: (call['target_function'] ?? '') as String,
      parameters: ((call['parameters'] as List?) ?? const [])
          .map((e) => (e as num).toInt())
          .toList(),
      coinsNano: _amount(call['coins']),
      maxGas: BigInt.from(((call['max_gas'] as num?) ?? 0).toInt()),
      feeNano: _amount(call['fee']),
      cancelled: (call['cancelled'] as bool?) ?? false,
    );
  }
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

  /// Final datastore keys (raw bytes), capped by the node (typically 500).
  final List<List<int>> finalDatastoreKeys;

  /// Candidate datastore keys (raw bytes), capped by the node.
  final List<List<int>> candidateDatastoreKeys;

  /// Creates address info.
  AddressInfo({
    required this.address,
    required this.finalBalance,
    required this.candidateBalance,
    required this.finalRollCount,
    required this.candidateRollCount,
    this.cycleInfos = const [],
    this.finalDatastoreKeys = const [],
    this.candidateDatastoreKeys = const [],
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
    finalDatastoreKeys: ((json['final_datastore_keys'] as List?) ?? const [])
        .map((e) => (e as List).cast<int>())
        .toList(),
    candidateDatastoreKeys:
        ((json['candidate_datastore_keys'] as List?) ?? const [])
            .map((e) => (e as List).cast<int>())
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
  ///
  /// Handles both the live node format `{result: {Ok: [bytes]}}` and the
  /// legacy massa-web3 format `{result: {Ok: {return_value: ...}}}`.
  factory ReadOnlyCallResult.fromJson(Map<String, dynamic> json) {
    final res = json['result'];
    dynamic okValue;
    String? err;
    if (res is Map) {
      okValue = res['Ok'];
      if (okValue == null) {
        final e = res['Error'] ?? res['Err'];
        err = e is Map
            ? (e['Execute_error']?['error']?.toString() ?? '$e')
            : e?.toString();
      }
    } else if (json['Ok'] != null) {
      okValue = json['Ok'];
    } else if (json['Err'] != null) {
      err = json['Err'].toString();
    }
    List<int> ret = const [];
    if (okValue != null) {
      ret = switch (okValue) {
        final String s => base64Decode(s),
        final Map m => switch (m['return_value']) {
          final String s => base64Decode(s),
          final List l => l.cast<int>(),
          _ => const <int>[],
        },
        final List l => l.cast<int>(),
        _ => const <int>[],
      };
    }
    return ReadOnlyCallResult(
      ok: okValue != null,
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

  /// Raw value bytes (final state preferred, falls back to candidate).
  final List<int> value;

  /// Raw value from the final state (may be empty).
  final List<int> finalValue;

  /// Raw value from the candidate state (may be empty).
  final List<int> candidateValue;

  /// Creates the entry.
  DatastoreEntry({
    this.address,
    this.value = const [],
    this.finalValue = const [],
    this.candidateValue = const [],
  });

  static List<int> _bytes(Object? v) => switch (v) {
    final String s => List<int>.from(base64Decode(s)),
    final List l => l.cast<int>(),
    _ => const <int>[],
  };

  /// Parses from JSON.
  ///
  /// Live nodes return `{final_value: [...], candidate_value: [...]}` while
  /// some proxies return a single `value` field — handle both.
  factory DatastoreEntry.fromJson(Map<String, dynamic> json) {
    final fin = _bytes(json['final_value']);
    final cand = _bytes(json['candidate_value']);
    final single = _bytes(json['value']);
    return DatastoreEntry(
      address: json['address'] as String?,
      finalValue: fin,
      candidateValue: cand,
      value: fin.isNotEmpty ? fin : (single.isNotEmpty ? single : cand),
    );
  }
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
