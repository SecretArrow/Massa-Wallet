/// Central wallet state: accounts, balances, transactions and sending.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/massa_amount.dart';
import '../api/massa_models.dart';
import '../api/massa_rpc.dart';
import '../crypto/massa_keys.dart';
import '../crypto/operation_serializer.dart';
import 'activity_history_service.dart';
import 'settings_provider.dart';
import 'wallet_repository.dart';

/// Balance snapshot for one account.
class AccountBalance {
  /// Final balance in nanoMAS.
  final BigInt finalBalance;

  /// Candidate balance in nanoMAS.
  final BigInt candidateBalance;

  /// Rolls (final).
  final BigInt rolls;

  /// When the snapshot was taken.
  final DateTime fetchedAt;

  /// Creates the snapshot.
  AccountBalance({
    required this.finalBalance,
    required this.candidateBalance,
    required this.rolls,
    required this.fetchedAt,
  });
}

/// Result of sending an operation.
class SendResult {
  /// Operation id (`OP...`).
  final String operationId;

  /// Creates the result.
  const SendResult(this.operationId);
}

/// Main wallet state provider.
class WalletProvider extends ChangeNotifier {
  final WalletRepository repository;
  final SettingsProvider settings;

  /// Local activity log (outgoing operations).
  final ActivityHistoryService history = ActivityHistoryService();

  List<StoredAccount> _accounts = [];
  final Map<String, AccountBalance> _balances = {};
  bool _loading = false;
  String? _lastError;

  /// Creates the provider.
  WalletProvider({required this.repository, required this.settings});

  /// Stored accounts.
  List<StoredAccount> get accounts => List.unmodifiable(_accounts);

  /// The active account.
  StoredAccount? get activeAccount {
    for (final a in _accounts) {
      if (a.isActive) return a;
    }
    return _accounts.isEmpty ? null : _accounts.first;
  }

  /// Balance of an address (null if never fetched).
  AccountBalance? balanceOf(String address) => _balances[address];

  /// Whether a refresh is in-flight.
  bool get loading => _loading;

  /// Last error message.
  String? get lastError => _lastError;

  /// Loads accounts from storage.
  Future<void> loadAccounts() async {
    _accounts = await repository.listAccounts();
    notifyListeners();
  }

  /// Creates a new wallet.
  Future<StoredAccount> createWallet({String nickname = ''}) async {
    final account = await repository.createWallet(nickname: nickname);
    await loadAccounts();
    return account;
  }

  /// Imports a secret key (`S...`).
  Future<StoredAccount> importSecretKey(
    String sk, {
    String nickname = '',
  }) async {
    final account = await repository.importSecretKey(sk, nickname: nickname);
    await loadAccounts();
    return account;
  }

  /// Imports a Massa Standard keystore file.
  Future<StoredAccount> importKeyStore(
    String contents,
    String password, {
    String nickname = '',
  }) async {
    final account = await repository.importKeyStore(
      contents,
      password,
      nickname: nickname,
    );
    await loadAccounts();
    return account;
  }

  /// Exports a keystore file content.
  Future<String> exportKeyStore(String address, String password) =>
      repository.exportKeyStore(address, password);

  /// Reveals the secret key (caller must enforce auth).
  Future<String> revealSecretKey(String address) =>
      repository.revealSecretKey(address);

  /// Removes an account.
  Future<void> deleteAccount(String address) async {
    await repository.deleteAccount(address);
    await loadAccounts();
  }

  /// Sets the active account.
  Future<void> setActive(String address) async {
    _accounts = _accounts
        .map((a) => a.copyWith(isActive: a.address == address))
        .toList();
    await repository.saveAccounts(_accounts);
    notifyListeners();
  }

  /// Renames an account.
  Future<void> rename(String address, String nickname) async {
    _accounts = _accounts
        .map((a) => a.address == address ? a.copyWith(nickname: nickname) : a)
        .toList();
    await repository.saveAccounts(_accounts);
    notifyListeners();
  }

  /// Fetches balances for all accounts.
  Future<void> refreshBalances() async {
    if (_accounts.isEmpty) return;
    _loading = true;
    _lastError = null;
    notifyListeners();
    try {
      final client = MassaRpcClient(endpoint: settings.effectiveEndpoint);
      try {
        final addresses = _accounts.map((a) => a.address).toList();
        final infos = await client.getAddresses(addresses);
        for (final info in infos) {
          _balances[info.address] = AccountBalance(
            finalBalance: info.finalBalance,
            candidateBalance: info.candidateBalance,
            rolls: info.finalRollCount,
            fetchedAt: DateTime.now(),
          );
        }
      } finally {
        client.dispose();
      }
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Builds, signs and broadcasts a transfer.
  Future<SendResult> sendTransfer({
    required String fromAddress,
    required String recipient,
    required BigInt amountNano,
    BigInt? feeNano,
    int periodToLive = 9,
    String? note,
  }) async {
    return _sendOperation(
      fromAddress,
      (period, fee) {
        return MassaOperation.transfer(
          fee: fee,
          expirePeriod: period,
          data: TransferOperationData(
            recipientAddress: recipient,
            amount: amountNano,
          ),
        );
      },
      feeNano: feeNano,
      periodToLive: periodToLive,
      activityKind: ActivityKind.send,
      activityCounterparty: recipient,
      activityAmount: amountNano,
      note: note,
    );
  }

  /// Buys staking rolls.
  Future<SendResult> buyRolls({
    required String fromAddress,
    required int rollCount,
    BigInt? feeNano,
  }) async {
    return _sendOperation(fromAddress, (period, fee) {
      return MassaOperation.rollBuy(
        fee: fee,
        expirePeriod: period,
        data: RollOperationData(amount: BigInt.from(rollCount)),
      );
    }, feeNano: feeNano, activityKind: ActivityKind.rollBuy);
  }

  /// Sells staking rolls.
  Future<SendResult> sellRolls({
    required String fromAddress,
    required int rollCount,
    BigInt? feeNano,
  }) async {
    return _sendOperation(fromAddress, (period, fee) {
      return MassaOperation.rollSell(
        fee: fee,
        expirePeriod: period,
        data: RollOperationData(amount: BigInt.from(rollCount)),
      );
    }, feeNano: feeNano, activityKind: ActivityKind.rollSell);
  }

  /// Calls a smart-contract function.
  Future<SendResult> callSmartContract({
    required String fromAddress,
    required String target,
    required String function,
    required List<int> parameter,
    required BigInt maxGas,
    BigInt? coinsNano,
    BigInt? feeNano,
    ActivityKind activityKind = ActivityKind.callSC,
    String? tokenSymbol,
    String? tokenAmount,
    String? note,
  }) async {
    return _sendOperation(fromAddress, (period, fee) {
      return MassaOperation.callSC(
        fee: fee,
        expirePeriod: period,
        data: CallOperationData(
          targetAddress: target,
          functionName: function,
          parameter: parameter,
          maxGas: maxGas,
          coins: coinsNano,
        ),
      );
    },
    feeNano: feeNano,
    activityKind: activityKind,
    activityCounterparty: target,
    activityAmount: coinsNano ?? BigInt.zero,
    tokenSymbol: tokenSymbol,
    tokenAmount: tokenAmount,
    note: note);
  }

  /// Executes a read-only call against a contract (no fee).
  Future<ReadOnlyCallResult> readOnlyCall({
    required String target,
    required String function,
    List<int> parameter = const [],
    int maxGas = 1000000,
  }) async {
    final client = MassaRpcClient(endpoint: settings.effectiveEndpoint);
    try {
      return await client.executeReadOnlyCall(
        ReadOnlyCallInput(
          targetAddress: target,
          targetFunction: function,
          parameter: parameter,
          maxGas: maxGas,
        ),
      );
    } finally {
      client.dispose();
    }
  }

  /// Fetches a single operation status.
  Future<OperationInfo?> getOperation(String opId) async {
    final client = MassaRpcClient(endpoint: settings.effectiveEndpoint);
    try {
      final infos = await client.getOperations([opId]);
      return infos.isEmpty ? null : infos.first;
    } finally {
      client.dispose();
    }
  }

  /// Signs an arbitrary message for a dApp (BLAKE3-hashed, ed25519).
  /// Returns the prefix-less Massa signature string.
  Future<String> signMessageForDapp(String address, String data) async {
    final versioned = await repository.readVersionedSecretKey(address);
    final priv = MassaPrivateKey.fromBytes(versioned.sublist(1));
    final sig = priv.signMessage(utf8.encode(data));
    return sig.encoded;
  }

  Future<SendResult> _sendOperation(
    String fromAddress,
    MassaOperation Function(int period, BigInt fee) build, {
    BigInt? feeNano,
    int periodToLive = 9,
    ActivityKind activityKind = ActivityKind.callSC,
    String? activityCounterparty,
    BigInt? activityAmount,
    String? tokenSymbol,
    String? tokenAmount,
    String? note,
  }) async {
    final client = MassaRpcClient(endpoint: settings.effectiveEndpoint);
    try {
      final status = await client.getStatus();
      final chainId = BigInt.from(
        status.chainId == 0 ? settings.network.chainId : status.chainId,
      );
      final fee =
          feeNano ??
          (status.minimalFee == BigInt.zero
              ? BigInt.from(1000000)
              : status.minimalFee);
      final expirePeriod = status.currentPeriod + periodToLive;
      final op = build(expirePeriod, fee);

      final versioned = await repository.readVersionedSecretKey(fromAddress);
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
      if (ids.isEmpty) {
        throw const RpcException('node returned no operation id');
      }
      final opId = ids.first;
      // Record in the local activity log (best-effort).
      try {
        await history.add(
          Activity(
            id: '${DateTime.now().microsecondsSinceEpoch}-$opId',
            kind: activityKind,
            accountAddress: fromAddress,
            amountNano: activityAmount ?? BigInt.zero,
            counterparty: activityCounterparty ?? '',
            createdAt: DateTime.now().toUtc(),
            status: ActivityStatus.submitted,
            tokenSymbol: tokenSymbol,
            tokenAmount: tokenAmount,
            function: op.call?.functionName,
            operationId: opId,
            note: note,
          ),
        );
      } on Exception {
        // History is best-effort.
      }
      // Optimistic balance refresh shortly after send.
      Future.delayed(
        const Duration(seconds: 3),
        () => refreshBalances().ignore(),
      );
      return SendResult(opId);
    } finally {
      client.dispose();
    }
  }

  /// Formatted balance string for display.
  String formatBalance(String address, {int decimals = 9}) {
    final b = _balances[address];
    if (b == null) return '—';
    return formatNano(b.finalBalance, decimals: decimals);
  }
}
