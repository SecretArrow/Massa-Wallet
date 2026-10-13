/// Roll auto-compound: reinvest staking rewards into new rolls.
///
/// Massa pays staking rewards at the end of every cycle via *deferred
/// credits* — balance shows up at cycle rollover. This service watches the
/// cycle clock (`get_status.currentCycle`) and, when a new cycle starts and
/// the balance grew, converts the harvestable surplus (balance minus a fee
/// reserve) into **whole rolls** through a regular `RollBuy` operation.
///
/// The decision logic is pure and unit-tested; execution works both from
/// the staking screen (foreground) and the background-sync isolate, using
/// only `SharedPreferences` + the secure store (no UI dependency).
///
/// Defaults: reserve 1 MAS (fees), min reinvest 1 roll (100 MAS).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/massa_amount.dart';
import '../api/massa_models.dart';
import '../api/massa_rpc.dart';
import '../crypto/massa_keys.dart';
import '../crypto/operation_serializer.dart';
import 'wallet_repository.dart';

/// Price of one roll in nanoMAS (100 MAS — mainnet & buildnet).
const int rollPriceNano = 100000000000;

/// Pure decision: how many whole rolls can be bought?
///
/// [finalBalanceNano] — current spendable balance.
/// [reserveNano] — kept for fees / daily use (never reinvested).
/// [priceNano] — current roll price.
/// [lastRolls] — rolls already owned (kept for context in results).
int computeReinvestRolls({
  required BigInt finalBalanceNano,
  required BigInt reserveNano,
  required BigInt priceNano,
  BigInt? lastRolls,
}) {
  if (priceNano <= BigInt.zero) return 0;
  final surplus = finalBalanceNano - reserveNano;
  if (surplus <= BigInt.zero) return 0;
  return (surplus ~/ priceNano).toInt();
}

/// Result of one auto-compound tick.
class AutoCompoundOutcome {
  /// What the tick decided.
  final AutoCompoundAction action;

  /// Cycle the decision was made in.
  final int? cycle;

  /// Rolls bought (when action == bought).
  final int rollsBought;

  /// Operation id when bought.
  final String? operationId;

  /// Human-readable detail (error / skip reason).
  final String? detail;

  /// Balance snapshot in nanoMAS at decision time (when known).
  final BigInt? balanceNano;

  /// Creates the outcome.
  const AutoCompoundOutcome({
    required this.action,
    this.cycle,
    this.rollsBought = 0,
    this.operationId,
    this.detail,
    this.balanceNano,
  });
}

/// One persisted auto-compound action (history entry).
class AutoCompoundRecord {
  /// When the action happened (UTC).
  final DateTime at;

  /// Cycle the action was taken in (null = never reached a node).
  final int? cycle;

  /// What happened.
  final AutoCompoundAction action;

  /// Rolls bought (when bought).
  final int rolls;

  /// Operation id (when bought).
  final String? operationId;

  /// Skip reason / error detail.
  final String? detail;

  /// Balance snapshot in nanoMAS (when known).
  final BigInt? balanceNano;

  /// Account the action was taken for.
  final String? address;

  /// Creates the record.
  const AutoCompoundRecord({
    required this.at,
    required this.action,
    this.cycle,
    this.rolls = 0,
    this.operationId,
    this.detail,
    this.balanceNano,
    this.address,
  });

  /// Restores a record from its persisted map form.
  factory AutoCompoundRecord.fromMap(Map<String, dynamic> m) {
    return AutoCompoundRecord(
      at:
          DateTime.tryParse(m['at'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      cycle: m['cycle'] as int?,
      action: AutoCompoundAction.values.firstWhere(
        (a) => a.name == (m['action'] as String? ?? ''),
        orElse: () => AutoCompoundAction.failed,
      ),
      rolls: (m['rolls'] as num?)?.toInt() ?? 0,
      operationId: m['opId'] as String?,
      detail: m['detail'] as String?,
      balanceNano: m['balance'] == null
          ? null
          : BigInt.tryParse(m['balance'].toString()),
      address: m['address'] as String?,
    );
  }

  /// Serializes the record for persistence.
  Map<String, dynamic> toMap() => {
    'at': at.toIso8601String(),
    'cycle': cycle,
    'action': action.name,
    'rolls': rolls,
    'opId': operationId,
    'detail': detail,
    'balance': balanceNano?.toString(),
    'address': address,
  };
}

/// Possible tick outcomes.
enum AutoCompoundAction {
  /// Feature disabled.
  disabled,

  /// Still the same cycle as the last processed one.
  sameCycle,

  /// Balance below reserve + one roll price.
  nothingToReinvest,

  /// Bought rolls successfully.
  bought,

  /// Attempted but the broadcast failed.
  failed,
}

/// Persisted state + executor for auto-compound.
class AutoCompoundService {
  /// SharedPreferences store (injected for tests).
  final SharedPreferences prefs;

  /// Wallet repository providing signing keys.
  final WalletRepository repository;

  static const _kEnabled = 'ac.enabled';
  static const _kReserveNano = 'ac.reserveNano';
  static const _kLastCycle = 'ac.lastCycle';
  static const _kLastAction = 'ac.lastAction';
  static const _kHistory = 'ac.history';

  /// History capacity (newest kept).
  static const int historyCap = 10;

  /// Creates the service.
  AutoCompoundService({required this.prefs, required this.repository});

  /// Whether auto-compound is enabled.
  bool get enabled => prefs.getBool(_kEnabled) ?? false;

  /// Enables/disables auto-compound.
  Future<void> setEnabled(bool v) => prefs.setBool(_kEnabled, v);

  /// Fee reserve in nanoMAS (default 1 MAS).
  BigInt get reserveNano =>
      BigInt.from(prefs.getInt(_kReserveNano) ?? 1000000000);

  /// Sets the fee reserve (nanoMAS).
  Future<void> setReserveNano(BigInt nano) =>
      prefs.setInt(_kReserveNano, nano.toInt());

  /// Last processed cycle (null = never ran).
  int? get lastCycle {
    final v = prefs.getInt(_kLastCycle);
    return v;
  }

  /// Last action record (JSON: {at, cycle, action, rolls, detail}).
  Map<String, dynamic>? get lastAction {
    final raw = prefs.getString(_kLastAction);
    if (raw == null || raw.isEmpty) return null;
    try {
      return json.decode(raw) as Map<String, dynamic>;
    } on FormatException {
      return null;
    }
  }

  /// Recent auto-compound activity, newest first (capped at [historyCap]).
  List<AutoCompoundRecord> get history {
    final raw = prefs.getString(_kHistory);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = json.decode(raw) as List;
      return list
          .map((e) => AutoCompoundRecord.fromMap(e as Map<String, dynamic>))
          .toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  Future<void> _appendHistory(AutoCompoundRecord r) async {
    final next = <AutoCompoundRecord>[r, ...history];
    if (next.length > historyCap) {
      next.removeRange(historyCap, next.length);
    }
    await prefs.setString(
      _kHistory,
      json.encode(next.map((e) => e.toMap()).toList()),
    );
  }

  Future<void> _record(AutoCompoundOutcome o, {String? address}) async {
    final record = AutoCompoundRecord(
      at: DateTime.now().toUtc(),
      cycle: o.cycle,
      action: o.action,
      rolls: o.rollsBought,
      operationId: o.operationId,
      detail: o.detail,
      balanceNano: o.balanceNano,
      address: address,
    );
    await prefs.setString(_kLastAction, json.encode(record.toMap()));
    await _appendHistory(record);
    if (o.cycle != null && o.action != AutoCompoundAction.failed) {
      await prefs.setInt(_kLastCycle, o.cycle!);
    }
  }

  /// Evaluates (and executes) auto-compound for [address].
  ///
  /// [broadcast] signs & sends the RollBuy through [WalletRepository];
  /// injected so tests can stub it. Returns the outcome and records it.
  ///
  /// By default the tick only acts once per staking cycle (the
  /// `lastCycle` watermark). [force] bypasses that gate — used by the
  /// manual "Compound now" button so users can reinvest mid-cycle.
  Future<AutoCompoundOutcome> tick({
    required String address,
    required String endpoint,
    BigInt? rollPriceNanoOverride,
    Future<String?> Function(int rolls)? broadcast,
    bool force = false,
    http.Client? httpClient,
  }) async {
    if (!enabled) {
      return const AutoCompoundOutcome(action: AutoCompoundAction.disabled);
    }
    final client = MassaRpcClient(endpoint: endpoint, httpClient: httpClient);
    try {
      final status = await client.getStatus();
      final cycle = status.currentCycle ?? 0;
      if (!force && lastCycle != null && cycle <= lastCycle!) {
        return AutoCompoundOutcome(
          action: AutoCompoundAction.sameCycle,
          cycle: cycle,
          detail: 'waiting for cycle ${lastCycle! + 1}',
        );
      }
      final infos = await client.getAddresses([address]);
      if (infos.isEmpty) {
        return AutoCompoundOutcome(
          action: AutoCompoundAction.nothingToReinvest,
          cycle: cycle,
          detail: 'address not found',
        );
      }
      final balance = infos.first.finalBalance;
      final price = rollPriceNanoOverride ?? BigInt.from(rollPriceNano);
      final rolls = computeReinvestRolls(
        finalBalanceNano: balance,
        reserveNano: reserveNano,
        priceNano: price,
      );
      if (rolls < 1) {
        final outcome = AutoCompoundOutcome(
          action: AutoCompoundAction.nothingToReinvest,
          cycle: cycle,
          balanceNano: balance,
          detail:
              'surplus below roll price (balance ${formatNano(balance)} MAS)',
        );
        await _record(outcome, address: address);
        return outcome;
      }
      if (broadcast == null) {
        final opId = await _broadcastRollBuy(
          address: address,
          rolls: rolls,
          status: status,
          client: client,
        );
        final outcome = AutoCompoundOutcome(
          action: opId != null
              ? AutoCompoundAction.bought
              : AutoCompoundAction.failed,
          cycle: cycle,
          rollsBought: opId != null ? rolls : 0,
          operationId: opId,
          balanceNano: balance,
          detail: opId != null
              ? null
              : 'broadcast failed (check fee reserve / connection)',
        );
        await _record(outcome, address: address);
        return outcome;
      }
      try {
        final opId = await broadcast(rolls);
        final outcome = AutoCompoundOutcome(
          action: opId != null
              ? AutoCompoundAction.bought
              : AutoCompoundAction.failed,
          cycle: cycle,
          rollsBought: opId != null ? rolls : 0,
          operationId: opId,
          balanceNano: balance,
        );
        await _record(outcome, address: address);
        return outcome;
      } on Exception catch (e) {
        final outcome = AutoCompoundOutcome(
          action: AutoCompoundAction.failed,
          cycle: cycle,
          detail: e.toString(),
          balanceNano: balance,
        );
        await _record(outcome, address: address);
        return outcome;
      }
    } on Exception catch (e) {
      // Network-level failure: do not advance the cycle watermark.
      return AutoCompoundOutcome(
        action: AutoCompoundAction.failed,
        detail: e.toString(),
      );
    } finally {
      client.dispose();
    }
  }

  Future<String?> _broadcastRollBuy({
    required String address,
    required int rolls,
    required NodeStatus status,
    required MassaRpcClient client,
  }) async {
    try {
      final chainId = BigInt.from(status.chainId == 0 ? 0 : status.chainId);
      final fee = status.minimalFee == BigInt.zero
          ? BigInt.from(1000000)
          : status.minimalFee;
      final op = MassaOperation.rollBuy(
        fee: fee,
        expirePeriod: status.currentPeriod + 9,
        data: RollOperationData(amount: BigInt.from(rolls)),
      );
      final versioned = await repository.readVersionedSecretKey(address);
      final priv = MassaPrivateKey.fromBytes(versioned.sublist(1));
      final sig = OperationSerializer.sign(chainId, op, priv);
      final serialized = OperationSerializer.serialize(op);
      final ids = await client.sendOperations([
        SendOperationInput(
          serializedContent: serialized.toList(),
          creatorPublicKey: priv.publicKey.encoded,
          signature: sig.encoded,
        ),
      ]);
      return ids.isEmpty ? null : ids.first;
    } on Exception {
      return null;
    }
  }
}
