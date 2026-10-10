/// MRC-20 fungible token support (massa-standards FT).
///
/// Metadata is read from the contract datastore (`NAME`, `SYMBOL`,
/// `DECIMALS`, `TOTAL_SUPPLY`) exactly like massa-web3's `MRC20` wrapper;
/// balances come from the `BALANCE<address>` entry (u256 LE), with a
/// read-only `balanceOf` call as fallback. Transfers issue a `transfer(to,
/// amount)` CallSC operation, adding the balance-creation storage cost when
/// the recipient has no entry yet.
library;

import 'dart:convert';

import '../api/massa_models.dart';
import '../api/massa_rpc.dart';
import '../crypto/sc_args.dart';

/// Official known tokens (massa-web3 `TOKENS_CONTRACTS`).
abstract final class KnownTokens {
  /// Buildnet token registry.
  static const buildnet = <String, String>{
    'WMAS': 'AS12FW5Rs5YN2zdpEnqwj4iHUUPt9R4Eqjq2qtpJFNKW3mn33RuLU',
    'USDC': 'AS12k8viVmqPtRuXzCm6rKXjLgpQWqbuMjc37YHhB452KSUUb9FgL',
    'DAI': 'AS12LpYyAjYRJfYhyu7fkrS224gMdvFHVEeVWoeHZzMdhis7UZ3Eb',
    'WETH': 'AS1gt69gqYD92dqPyE6DBRJ7KjpnQHqFzFs2YCkBcSnuxX5bGhBC',
    'USDT': 'AS12ix1Qfpue7BB8q6mWVtjNdNE9UV3x4MaUo7WhdUubov8sJ3CuP',
    'WETHb': 'AS12RmCXTA9NZaTBUBnRJuH66AGNmtEfEoqXKxLdmrTybS6GFJPFs',
    'WBTC': 'AS1ZXy3nvqXAMm2w6viAg7frte6cZfJM8hoMvWf4KoKDzvLzYKqE',
  };

  /// Mainnet token registry.
  static const mainnet = <String, String>{
    'WMAS': 'AS12U4TZfNK7qoLyEERBBRDMu8nm5MKoRzPXDXans4v9wdATZedz9',
    'USDCe': 'AS1hCJXjndR4c9vekLWsXGnrdigp4AaZ7uYG3UKFzzKnWVsrNLPJ',
    'USDTb': 'AS12LKs9txoSSy8JgFJgV96m8k5z9pgzjYMYSshwN67mFVuj3bdUV',
    'DAIe': 'AS1ZGF1upwp9kPRvDKLxFAKRebgg7b3RWDnhgV7VvdZkZsUL7Nuv',
    'WETHe': 'AS124vf3YfAJCSCQVYKczzuWWpXrximFpbTmX4rheLs5uNSftiiRY',
    'WETHb': 'AS125oPLYRTtfVjpWisPZVTLjBhCFfQ1jDsi75XNtRm1NZux54eCj',
    'PUR': 'AS133eqPPaPttJ6hJnk3sfoG5cjFFqBDi1VGxdo2wzWkq8AfZnan',
    'POM': 'AS1nqHKXpnFXqhDExTskXmBbbVpVpUbCQVtNSXLCqUDSUXihdWRq',
    'WBTCe': 'AS12fr54YtBY575Dfhtt7yftpT8KXgXb1ia5Pn1LofoLFLf9WcjGL',
  };
}

/// Snapshot of an MRC-20 token.
class Mrc20Token {
  /// Contract address (AS1…).
  final String address;

  /// Token name.
  final String name;

  /// Token symbol.
  final String symbol;

  /// Decimals.
  final int decimals;

  /// Total supply (raw units).
  final BigInt? totalSupply;

  /// Creates the token.
  const Mrc20Token({
    required this.address,
    required this.name,
    required this.symbol,
    required this.decimals,
    this.totalSupply,
  });

  /// Converts a raw balance into display units.
  String formatAmount(BigInt raw) {
    final div = BigInt.from(10).pow(decimals);
    final whole = raw ~/ div;
    final frac = raw % div;
    if (frac == BigInt.zero) return '$whole';
    final fracStr = frac.toString().padLeft(decimals, '0');
    final trimmed = fracStr.replaceAll(RegExp(r'0+$'), '');
    return '$whole.$trimmed';
  }
}

/// Datastore keys used by the MRC-20 standard.
abstract final class Mrc20Keys {
  /// `NAME` key.
  static List<int> get name => utf8.encode('NAME');

  /// `SYMBOL` key.
  static List<int> get symbol => utf8.encode('SYMBOL');

  /// `DECIMALS` key.
  static List<int> get decimals => utf8.encode('DECIMALS');

  /// `TOTAL_SUPPLY` key.
  static List<int> get totalSupply => utf8.encode('TOTAL_SUPPLY');

  /// `BALANCE<addr>` key.
  static List<int> balance(String address) =>
      utf8.encode('BALANCE$address');
}

/// Reads MRC-20 state from the chain.
class Mrc20Service {
  final MassaRpcClient Function() _clientFactory;

  /// Creates the service.
  Mrc20Service({required MassaRpcClient Function() clientFactory})
    : _clientFactory = clientFactory;

  Future<DatastoreEntry> _entry(String address, List<int> key) async {
    final client = _clientFactory();
    try {
      final entries = await client.getDatastoreEntries([
        DatastoreEntryInput(address: address, key: key),
      ]);
      return entries.isEmpty ? DatastoreEntry() : entries.first;
    } finally {
      client.dispose();
    }
  }


  /// Loads token metadata; throws if the address is not an MRC-20 contract.
  Future<Mrc20Token> loadToken(String address) async {
    final client = _clientFactory();
    try {
      final entries = await client.getDatastoreEntries([
        DatastoreEntryInput(address: address, key: Mrc20Keys.name),
        DatastoreEntryInput(address: address, key: Mrc20Keys.symbol),
        DatastoreEntryInput(address: address, key: Mrc20Keys.decimals),
        DatastoreEntryInput(address: address, key: Mrc20Keys.totalSupply),
      ]);
      final name = entries.isNotEmpty ? entries[0].value : const <int>[];
      final symbol = entries.length > 1 ? entries[1].value : const <int>[];
      final dec = entries.length > 2 ? entries[2].value : const <int>[];
      final supply = entries.length > 3 ? entries[3].value : const <int>[];
      if (name.isEmpty || symbol.isEmpty || dec.isEmpty) {
        throw RpcException(
          'not an MRC-20 contract (missing NAME/SYMBOL/DECIMALS)',
        );
      }
      return Mrc20Token(
        address: address,
        name: utf8.decode(name, allowMalformed: true),
        symbol: utf8.decode(symbol, allowMalformed: true),
        decimals: dec.first,
        totalSupply: supply.length >= 32 ? leToBigInt(supply.sublist(0, 32)) : null,
      );
    } finally {
      client.dispose();
    }
  }

  /// Reads the balance of [owner] via the `BALANCE<owner>` datastore entry,
  /// falling back to a read-only `balanceOf` call.
  Future<BigInt> balanceOf(String tokenAddress, String owner) async {
    final e = await _entry(tokenAddress, Mrc20Keys.balance(owner));
    if (e.value.length >= 32) {
      return leToBigInt(e.value.sublist(0, 32));
    }
    if (e.value.isNotEmpty) return leToBigInt(e.value);

    // Fallback: read-only call.
    final client = _clientFactory();
    try {
      final args = ScArgs()..addString(owner);
      final res = await client.executeReadOnlyCall(
        ReadOnlyCallInput(
          targetAddress: tokenAddress,
          targetFunction: 'balanceOf',
          parameter: args.bytes.toList(),
          maxGas: 8000000,
        ),
      );
      if (res.ok && res.returnValue.length >= 32) {
        return leToBigInt(res.returnValue.sublist(0, 32));
      }
      return BigInt.zero;
    } finally {
      client.dispose();
    }
  }

  /// Whether the recipient already has a balance entry (affects storage cost).
  Future<bool> hasBalanceEntry(String tokenAddress, String owner) async {
    final e = await _entry(tokenAddress, Mrc20Keys.balance(owner));
    return e.value.isNotEmpty;
  }

  /// Storage cost (nanoMAS) charged as `coins` when creating the recipient's
  /// balance entry: 400_000 + 100_000*(7+len(addr)) + 3_200_000.
  static BigInt balanceCreationCost(String recipient) {
    return BigInt.from(
      400000 + 100000 * (7 + recipient.length) + 3200000,
    );
  }

  /// Builds the `transfer(to, amount)` argument payload.
  static List<int> transferArgs(String to, BigInt rawAmount) {
    return (ScArgs()..addString(to)..addU256(rawAmount)).bytes.toList();
  }
}
