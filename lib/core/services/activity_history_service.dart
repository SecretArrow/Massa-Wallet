/// Local activity history.
///
/// The public JSON-RPC v2 does not expose historical operations per address
/// (no indexer), so the wallet records every outgoing operation locally and
/// upgrades its status (submitted → final / failed) by polling
/// `get_operations` when the history screen is open.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Kind of recorded activity.
enum ActivityKind { send, receive, rollBuy, rollSell, callSC, tokenTransfer, dapp }

/// Lifecycle status of a recorded activity.
enum ActivityStatus { submitted, final_, failed }

/// One recorded wallet activity.
class Activity {
  final String id;

  /// Kind of activity.
  final ActivityKind kind;

  /// Account address that owns this record.
  final String accountAddress;

  /// Amount in nanoMAS (0 for contract calls without coins).
  final BigInt amountNano;

  /// Counterparty (recipient / contract / token contract).
  final String counterparty;

  /// Token symbol when [kind] is [ActivityKind.tokenTransfer].
  final String? tokenSymbol;

  /// Raw token amount as string when applicable.
  final String? tokenAmount;

  /// Function name for contract calls.
  final String? function;

  /// Operation id on chain (OP…).
  final String? operationId;

  /// Record creation time (UTC).
  final DateTime createdAt;

  /// Lifecycle status.
  ActivityStatus status;

  /// Short human note (e.g. dApp origin).
  final String? note;

  /// Creates an activity.
  Activity({
    required this.id,
    required this.kind,
    required this.accountAddress,
    required this.amountNano,
    required this.counterparty,
    required this.createdAt,
    required this.status,
    this.tokenSymbol,
    this.tokenAmount,
    this.function,
    this.operationId,
    this.note,
  });

  /// Creates a copy with a new status.
  Activity withStatus(ActivityStatus s) {
    status = s;
    return this;
  }

  Map<String, dynamic> _toJson() => {
    'id': id,
    'kind': kind.name,
    'account': accountAddress,
    'amount': amountNano.toString(),
    'counterparty': counterparty,
    'createdAt': createdAt.toIso8601String(),
    'status': status.name,
    if (tokenSymbol != null) 'tokenSymbol': tokenSymbol,
    if (tokenAmount != null) 'tokenAmount': tokenAmount,
    if (function != null) 'function': function,
    if (operationId != null) 'operationId': operationId,
    if (note != null) 'note': note,
  };

  static Activity _fromJson(Map<String, dynamic> j) => Activity(
    id: j['id'] as String,
    kind: ActivityKind.values.firstWhere(
      (k) => k.name == j['kind'],
      orElse: () => ActivityKind.callSC,
    ),
    accountAddress: (j['account'] ?? '') as String,
    amountNano: BigInt.tryParse((j['amount'] ?? '0').toString()) ?? BigInt.zero,
    counterparty: (j['counterparty'] ?? '') as String,
    createdAt: DateTime.tryParse((j['createdAt'] ?? '') as String) ??
        DateTime.now().toUtc(),
    status: ActivityStatus.values.firstWhere(
      (s) => s.name == (j['status'] ?? ''),
      orElse: () => ActivityStatus.submitted,
    ),
    tokenSymbol: j['tokenSymbol'] as String?,
    tokenAmount: j['tokenAmount']?.toString(),
    function: j['function'] as String?,
    operationId: j['operationId'] as String?,
    note: j['note'] as String?,
  );
}

/// Persists and queries the local activity log.
class ActivityHistoryService {
  static const _kKey = 'wallet.activityLog';
  static const _kMaxEntries = 500;

  /// Creates the service.
  ActivityHistoryService();

  /// Loads all activities (newest first).
  Future<List<Activity>> load({String? accountAddress}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kKey) ?? const [];
    final all = raw
        .map((s) {
          try {
            return Activity._fromJson(
              json.decode(s) as Map<String, dynamic>,
            );
          } on FormatException {
            return null;
          }
        })
        .whereType<Activity>()
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (accountAddress == null) return all;
    return all.where((a) => a.accountAddress == accountAddress).toList();
  }

  /// Appends a new activity.
  Future<void> add(Activity activity) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kKey) ?? const [];
    final list = [json.encode(activity._toJson()), ...raw];
    if (list.length > _kMaxEntries) {
      list.removeRange(_kMaxEntries, list.length);
    }
    await prefs.setStringList(_kKey, list);
  }

  /// Updates the status of an activity by id.
  Future<void> updateStatus(String id, ActivityStatus status) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kKey) ?? const [];
    final updated = <String>[];
    for (final item in raw) {
      try {
        final a = Activity._fromJson(json.decode(item) as Map<String, dynamic>);
        if (a.id == id) {
          a.withStatus(status);
          updated.add(json.encode(a._toJson()));
        } else {
          updated.add(item);
        }
      } on FormatException {
        updated.add(item);
      }
    }
    await prefs.setStringList(_kKey, updated);
  }

  /// Clears the whole log.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
  }
}
