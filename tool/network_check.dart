/// Manual network check against buildnet: wallet creation → faucet →
/// transfer → finalization. Run with:
///   dart run tool/network_check.dart
///
/// Not part of `flutter test` (pure Dart, no bindings needed).
// ignore_for_file: avoid_print
library;

import 'dart:async';

import 'package:massa_wallet/core/api/faucet_client.dart';
import 'package:massa_wallet/core/api/massa_models.dart'
    show SendOperationInput;
import 'package:massa_wallet/core/api/massa_rpc.dart';
import 'package:massa_wallet/core/crypto/massa_keys.dart';
import 'package:massa_wallet/core/crypto/operation_serializer.dart';

Future<void> main() async {
  // 1. Create two accounts.
  final privA = MassaPrivateKey.generate();
  final privB = MassaPrivateKey.generate();
  final addrA = privA.publicKey.address.encoded;
  final addrB = privB.publicKey.address.encoded;
  print('account A: $addrA');
  print('account B: $addrB');

  // 2. Faucet.
  final faucet = FaucetClient();
  final res = await faucet.fund(addrA);
  print('faucet: ${res.status} — ${res.message}');
  if (res.status != FaucetStatus.accepted) {
    print('FAUCET UNAVAILABLE — stopping here (transfer test skipped)');
    return;
  }

  // 3. Poll balance.
  final client = MassaRpcClient.forNetwork(MassaNetwork.buildnet);
  BigInt balanceA = BigInt.zero;
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(const Duration(seconds: 3));
    final info = await client.getAddressInfo(addrA);
    balanceA = info.finalBalance;
    print('balance A (final): ${info.finalBalance}');
    if (balanceA > BigInt.zero) break;
  }
  if (balanceA == BigInt.zero) {
    print('FUNDS DID NOT ARRIVE');
    return;
  }

  // 4. Build + sign + send transfer A → B (0.1 MAS).
  final status = await client.getStatus();
  final fee = status.minimalFee == BigInt.zero
      ? BigInt.from(1000000)
      : status.minimalFee;
  final op = MassaOperation.transfer(
    fee: fee,
    expirePeriod: status.currentPeriod + 9,
    data: TransferOperationData(
      recipientAddress: addrB,
      amount: BigInt.from(100000000),
    ),
  );
  final sig = OperationSerializer.sign(
    BigInt.from(MassaNetwork.buildnet.chainId),
    op,
    privA,
  );
  final serialized = OperationSerializer.serialize(op);
  final ids = await client.sendOperations([
    SendOperationInput(
      serializedContent: serialized.toList(),
      creatorPublicKey: privA.publicKey.encoded,
      signature: sig.encoded,
    ),
  ]);
  final opId = ids.first;
  print('sent op: $opId');

  // 5. Poll finality.
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(const Duration(seconds: 3));
    final infos = await client.getOperations([opId]);
    if (infos.isEmpty) continue;
    final info = infos.first;
    print(
      'op status: final=${info.inFinalBlock} pool=${info.inPool} '
      'error=${info.error}',
    );
    if (info.inFinalBlock ?? false) {
      final infoB = await client.getAddressInfo(addrB);
      print('balance B (final): ${infoB.finalBalance}');
      print('E2E NETWORK FLOW OK');
      client.dispose();
      return;
    }
  }
  print('TRANSFER DID NOT FINALIZE IN TIME');
  client.dispose();
}
