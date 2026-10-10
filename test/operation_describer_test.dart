import 'package:flutter_test/flutter_test.dart';
import 'package:massa_wallet/core/api/massa_amount.dart' show parseUserAmount;
import 'package:massa_wallet/core/crypto/massa_keys.dart';
import 'package:massa_wallet/core/crypto/operation_describer.dart';
import 'package:massa_wallet/core/crypto/operation_serializer.dart';

void main() {
  group('describeSerializedOperation', () {
    test('decodes a transfer (recipient, amount, fee)', () {
      final priv = MassaPrivateKey.generate();
      final recipient = priv.publicKey.address;
      final op = MassaOperation.transfer(
        fee: BigInt.from(1000000),
        expirePeriod: 1234,
        data: TransferOperationData(
          recipientAddress: recipient.encoded,
          amount: parseUserAmount('2.5'),
        ),
      );
      final bytes = OperationSerializer.serialize(op);
      final desc = describeSerializedOperation(bytes);

      expect(desc.parsedOk, isTrue);
      expect(desc.type, OperationType.transaction);
      expect(desc.fee, BigInt.from(1000000));
      expect(desc.expirePeriod, 1234);
      expect(desc.targetAddress, recipient.encoded);
      expect(desc.amount, parseUserAmount('2.5'));
    });

    test('decodes roll buy/sell', () {
      final op = MassaOperation.rollBuy(
        fee: BigInt.zero,
        expirePeriod: 10,
        data: RollOperationData(amount: BigInt.from(3)),
      );
      final desc = describeSerializedOperation(
        OperationSerializer.serialize(op),
      );
      expect(desc.parsedOk, isTrue);
      expect(desc.type, OperationType.rollBuy);
      expect(desc.amount, BigInt.from(3));

      final sell = MassaOperation.rollSell(
        fee: BigInt.zero,
        expirePeriod: 10,
        data: RollOperationData(amount: BigInt.one),
      );
      final desc2 = describeSerializedOperation(
        OperationSerializer.serialize(sell),
      );
      expect(desc2.type, OperationType.rollSell);
    });

    test('decodes callSC (target, function, coins)', () {
      final priv = MassaPrivateKey.generate();
      final contract = priv.publicKey.address;
      final op = MassaOperation.callSC(
        fee: BigInt.from(500),
        expirePeriod: 99,
        data: CallOperationData(
          targetAddress: contract.encoded,
          functionName: 'transfer',
          parameter: [1, 2, 3],
          maxGas: BigInt.from(300000),
          coins: BigInt.from(42),
        ),
      );
      final desc = describeSerializedOperation(
        OperationSerializer.serialize(op),
      );
      expect(desc.parsedOk, isTrue);
      expect(desc.type, OperationType.callSC);
      expect(desc.targetAddress, contract.encoded);
      expect(desc.functionName, 'transfer');
      expect(desc.maxGas, BigInt.from(300000));
      expect(desc.coins, BigInt.from(42));
    });

    test('garbage bytes parse without throwing', () {
      final desc = describeSerializedOperation([0xff, 0xff, 0xff, 0x05]);
      expect(desc.parsedOk, isFalse);
      expect(desc.byteLength, 4);
    });

    test('empty bytes parse without throwing', () {
      final desc = describeSerializedOperation(const []);
      expect(desc.parsedOk, isFalse);
    });
  });
}
