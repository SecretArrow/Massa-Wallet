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

  /// Creates the outcome.
  const AutoCompoundOutcome({
    required this.action,
    this.cycle,
    this.rollsBought = 0,
    this.operationId,
    this.detail,
  });
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

  /// Creates the service.
  AutoCompoundService({required this.prefs, required this.repository});

  /// Whether auto-compound is enabled.
  bool get enabled => prefs.getBool(_kEnabled) ?? false;

  /// Enables/disables auto-compound.
  Future<void> setEnabled(bool v) => prefs.setBool(_kEnabled, v);

  /// Fee reserve in nanoMAS (default 1 MAS).
  BigInt get reserveNano => BigInt.from(prefs.getInt(_kReserveNano) ?? 1000000000);

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

  Future<void> _record(
    AutoCompoundOutcome o, {
    String? address,
  }) async {
    await prefs.setString(
      _kLastAction,
      json.encode({
        'at': DateTime.now().toUtc().toIso8601String(),
        'cycle': o.cycle,
        'action': o.action.name,
        'rolls': o.rollsBought,
        'opId': o.operationId,
        'detail': o.detail,
        'address': address,
      }),
    );
    if (o.cycle != null && o.action != AutoCompoundAction.failed) {
      await prefs.setInt(_kLastCycle, o.cycle!);
    }
  }

  /// Evaluates (and executes) auto-compound for [address].
  ///
  /// [broadcast] signs & sends the RollBuy through [WalletRepository];
  /// injected so tests can stub it. Returns the outcome and records it.
  Future<AutoCompoundOutcome> tick({
    required String address,
    required String endpoint,
    BigInt? rollPriceNanoOverride,
    Future<String?> Function(int rolls)? broadcast,
  }) async {
    if (!enabled) {
      return const AutoCompoundOutcome(action: AutoCompoundAction.disabled);
    }
    final client = MassaRpcClient(endpoint: endpoint);
    try {
      final status = await client.getStatus();
      final cycle = status.currentCycle ?? 0;
      if (lastCycle != null && cycle <= lastCycle!) {
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
        );
        await _record(outcome, address: address);
        return outcome;
      } on Exception catch (e) {
        final outcome = AutoCompoundOutcome(
          action: AutoCompoundAction.failed,
          cycle: cycle,
          detail: e.toString(),
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
      final chainId = BigInt.from(
        status.chainId == 0 ? 0 : status.chainId,
      );
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
