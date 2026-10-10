/// Deferred-calls (ASC) helper: slot clock, booking quotes and lookups.
///
/// Deferred calls are Massa's *guaranteed* async execution primitive: a
/// smart-contract function runs at a booked future slot. Registration always
/// happens **inside** a contract via the `deferred_call_register` ABI
/// (wallets cannot register directly), so this service provides:
///
/// - the slot clock: unix time ↔ `(period, thread)` with the genesis
///   timestamp derived at runtime from `get_status` (works on every network
///   and custom nodes);
/// - booking quotes (`get_deferred_call_quote`, verified live);
/// - deferred-call lookups (`get_deferred_call_info`, `…_ids_by_slot`);
/// - `Args` builders for scheduling through a *scheduler contract*
///   (e.g. the official `massa-sc-examples/deferred-call-manager`).
///
/// Wire constants are fixed by `massa-models`: `T0 = 16 000 ms` per period,
/// `THREAD_COUNT = 32` (500 ms per thread), `PERIODS_PER_CYCLE = 128`.
library;

import 'dart:typed_data';

import '../api/massa_amount.dart';
import '../api/massa_models.dart';
import '../api/massa_rpc.dart';
import '../crypto/sc_args.dart';

/// Slot clock + deferred-call RPC helpers for one endpoint.
class DeferredCallsService {
  /// RPC endpoint (public API or custom node).
  final String endpoint;

  /// Milliseconds per period (node constant `T0`).
  static const int periodMs = 16000;

  /// Threads per period (node constant `THREAD_COUNT`).
  static const int threadCount = 32;

  /// Milliseconds per thread.
  static const int threadMs = periodMs ~/ threadCount;

  /// Periods per staking cycle (node constant `PERIODS_PER_CYCLE`).
  static const int periodsPerCycle = 128;

  /// Creates the service for [endpoint].
  const DeferredCallsService({required this.endpoint});

  /// Derives the network genesis unix-ms from a node status.
  ///
  /// Preferred (exact): `next_cycle_time − (cycle+1) × 128 periods × T0`.
  /// Fallback: `current_time − slotMs(last_slot)` when cycle timing is not
  /// reported (small nodes / older versions).
  static int genesisFromStatus(NodeStatus status) {
    final cycle = status.currentCycle;
    final next = status.nextCycleTimeMs;
    if (cycle != null && next != null) {
      return next - (cycle + 1) * periodsPerCycle * periodMs;
    }
    final t = status.currentTimeMs;
    if (t != null) {
      return t -
          slotMs(
            MassaSlot(
              period: status.currentPeriod,
              thread: status.currentThread,
            ),
          );
    }
    throw const RpcException('get_status lacks timing fields');
  }

  /// Fetches the genesis timestamp (unix-ms) for this endpoint.
  Future<int> fetchGenesisMs() async {
    final client = MassaRpcClient(endpoint: endpoint);
    try {
      return genesisFromStatus(await client.getStatus());
    } finally {
      client.dispose();
    }
  }

  /// Absolute unix-ms of [slot] for a network with genesis [genesisMs].
  static int slotMs(MassaSlot slot) =>
      slot.period * periodMs + slot.thread * threadMs;

  static int _slotToMs(MassaSlot slot, int genesisMs) =>
      genesisMs + slotMs(slot);

  /// Converts [slot] to a wall-clock [DateTime] (UTC).
  static DateTime slotToDateTime(MassaSlot slot, int genesisMs) =>
      DateTime.fromMillisecondsSinceEpoch(
        _slotToMs(slot, genesisMs),
        isUtc: true,
      );

  /// Converts a wall-clock [dateTime] to the slot containing it.
  static MassaSlot dateTimeToSlot(DateTime dateTime, int genesisMs) {
    final delta = dateTime.toUtc().millisecondsSinceEpoch - genesisMs;
    if (delta < 0) {
      throw ArgumentError('datetime is before network genesis');
    }
    final period = delta ~/ periodMs;
    final thread = (delta % periodMs) ~/ threadMs;
    return MassaSlot(period: period, thread: thread);
  }

  /// The slot that is executing "now" (per [nowMs], default wall clock).
  static MassaSlot slotNow({int? nowMs, required int genesisMs}) =>
      dateTimeToSlot(
        DateTime.fromMillisecondsSinceEpoch(
          nowMs ?? DateTime.now().millisecondsSinceEpoch,
          isUtc: true,
        ),
        genesisMs,
      );

  /// Fetches booking quotes for [requests].
  Future<List<DeferredCallQuote>> quote(
    List<DeferredCallQuoteInput> requests,
  ) async {
    final client = MassaRpcClient(endpoint: endpoint);
    try {
      return await client.getDeferredCallQuote(requests);
    } finally {
      client.dispose();
    }
  }

  /// Fetches booking quotes for [slots] with a fixed [maxGas] and 0-byte
  /// parameters — the common "can I book this slot?" check.
  Future<List<DeferredCallQuote>> quoteSlots(
    List<MassaSlot> slots, {
    int maxGas = 20000000,
  }) => quote(
    slots
        .map(
          (s) => DeferredCallQuoteInput(targetSlot: s, maxGasRequest: maxGas),
        )
        .toList(),
  );

  /// Fetches deferred calls by id.
  Future<List<DeferredCallInfo>> info(List<String> ids) async {
    final client = MassaRpcClient(endpoint: endpoint);
    try {
      return await client.getDeferredCallInfo(ids);
    } finally {
      client.dispose();
    }
  }

  /// Fetches deferred-call ids scheduled at [slots].
  Future<List<DeferredCallsSlotResponse>> idsBySlot(
    List<MassaSlot> slots,
  ) async {
    final client = MassaRpcClient(endpoint: endpoint);
    try {
      return await client.getDeferredCallIdsBySlot(slots);
    } finally {
      client.dispose();
    }
  }

  /// Builds `Args` for the official `massa-sc-examples/deferred-call-manager`
  /// `registerCall(period)` entrypoint: a single `u64` = periods from now.
  static Uint8List managerRegisterCallArgs(int periodsFromNow) =>
      (ScArgs()..addU64(BigInt.from(periodsFromNow))).bytes;

  /// Builds `Args` for a *generic* scheduler contract exposing
  /// `register(targetAddress, targetFunction, period, thread, maxGas,
  /// params, coins)` — the natural full form of `deferredCallRegister`.
  /// Argument order must match the chosen scheduler contract.
  static Uint8List genericRegisterArgs({
    required String targetAddress,
    required String targetFunction,
    required MassaSlot slot,
    required BigInt maxGas,
    List<int> params = const [],
    BigInt? coinsNano,
  }) =>
      (ScArgs()
            ..addString(targetAddress)
            ..addString(targetFunction)
            ..addU64(BigInt.from(slot.period))
            ..addU8(slot.thread)
            ..addU64(maxGas)
            ..addBytes(params)
            ..addU64(coinsNano ?? BigInt.zero))
          .bytes;

  /// Formats a quote price for display (e.g. `0.2441 MAS`).
  static String formatPrice(BigInt priceNano) => '${formatNano(priceNano)} MAS';
}
