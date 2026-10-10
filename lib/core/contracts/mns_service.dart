/// Massa Name System (MNS) resolution.
///
/// Resolves `name.massa` domains to their target address through the official
/// MNS smart contracts (`dnsResolve` read-only call), with the legacy DNS
/// contracts as a fallback. Verified live on buildnet:
/// `dnsResolve('massa') -> AU1wN8rn...` (gas >= 2.1M required).
library;

import '../api/massa_models.dart';
import '../api/massa_rpc.dart';
import '../crypto/sc_args.dart';

/// MNS / DNS contract addresses per network.
abstract final class MnsContracts {
  /// MNS contract on mainnet (massa-web3 `MNS_CONTRACTS.mainnet`).
  static const mainnet = 'AS1q5hUfxLXNXLKsYQVXZLK7MPUZcWaNZZsK7e9QzqhGdAgLpUGT';

  /// MNS contract on buildnet (massa-web3 `MNS_CONTRACTS.buildnet`).
  static const buildnet = 'AS12qKAVjU1nr66JSkQ6N4Lqu4iwuVc6rAbRTrxFoynPrPdP1sj3G';

  /// Legacy DNS contract fallback (massa-web3 `DNSAddress`).
  static const legacyMainnet =
      'AS12B8JLmcrGsMFNo4BcMfmGyXLpqWovie8CKAPSorXRg4scEzbL';
  static const legacyBuildnet =
      'AS12U4F6yBQehi6rrZK3Qj4JSEhAAAqLQKK8KDPQKvvnBxyz1uMJ';
}

/// Result of resolving a Massa domain.
class MnsResolution {
  /// The bare domain name (without `.massa`).
  final String domain;

  /// The resolved target address (AU1… EOA or AS1… smart contract).
  final String target;

  /// Whether the target is a smart contract (AS1…).
  bool get isSmartContract => target.startsWith('AS1');

  /// Creates a resolution.
  const MnsResolution({required this.domain, required this.target});

  @override
  String toString() => '$domain.massa -> $target';
}

/// Exception thrown when a domain cannot be resolved.
class MnsException implements Exception {
  /// Error message.
  final String message;

  /// Creates the exception.
  const MnsException(this.message);

  @override
  String toString() => 'MnsException: $message';
}

/// Resolves Massa domains via the MNS contracts.
class MnsService {
  final MassaRpcClient Function() _clientFactory;

  final Map<String, MnsResolution?> _cache = {};

  /// Creates the service with an RPC client factory.
  MnsService({required MassaRpcClient Function() clientFactory})
    : _clientFactory = clientFactory;

  /// Normalizes user input into `(domain, suffix)`.
  ///
  /// Accepts `name.massa`, `name`, `http(s)://name.massa/path`,
  /// `massa://name` or a raw `AS1…`/`AU1…` address.
  static ({String? domain, String? address, String path}) parseInput(
    String input,
  ) {
    var raw = input.trim();
    if (raw.isEmpty) return (domain: null, address: null, path: '');

    String path = '';
    // Strip scheme.
    for (final prefix in ['massa://', 'https://', 'http://']) {
      if (raw.startsWith(prefix)) {
        raw = raw.substring(prefix.length);
        break;
      }
    }
    // Split path.
    final slash = raw.indexOf('/');
    if (slash >= 0) {
      path = raw.substring(slash + 1);
      raw = raw.substring(0, slash);
    }
    // Strip port if any.
    final colon = raw.indexOf(':');
    if (colon >= 0) raw = raw.substring(0, colon);

    // Raw address?
    if (raw.startsWith('AS1') || raw.startsWith('AU1')) {
      return (domain: null, address: raw, path: path);
    }
    var domain = raw;
    if (domain.toLowerCase().endsWith('.massa')) {
      domain = domain.substring(0, domain.length - '.massa'.length);
    }
    if (domain.isEmpty) return (domain: null, address: null, path: path);
    return (domain: domain, address: null, path: path);
  }

  /// Resolves a bare domain (no `.massa` suffix) to its target address.
  Future<MnsResolution> resolve(String domain, {required bool mainnet}) async {
    final key = '${mainnet ? 'm' : 'b'}:$domain';
    if (_cache.containsKey(key)) {
      final cached = _cache[key];
      if (cached == null) {
        throw const MnsException('domain not found (cached)');
      }
      return cached;
    }

    final primary = mainnet ? MnsContracts.mainnet : MnsContracts.buildnet;
    final legacy =
        mainnet ? MnsContracts.legacyMainnet : MnsContracts.legacyBuildnet;
    for (final contract in [primary, legacy]) {
      final target = await _dnsResolve(contract, domain);
      if (target != null && target.isNotEmpty) {
        final res = MnsResolution(domain: domain, target: target);
        _cache[key] = res;
        return res;
      }
    }
    _cache[key] = null;
    throw MnsException('domain "$domain" not found');
  }

  /// Issues a `dnsResolve` read-only call; returns null on any failure.
  Future<String?> _dnsResolve(String contract, String domain) async {
    final client = _clientFactory();
    try {
      final args = ScArgs()..addString(domain);
      final res = await client.executeReadOnlyCall(
        ReadOnlyCallInput(
          targetAddress: contract,
          targetFunction: 'dnsResolve',
          parameter: args.bytes.toList(),
          maxGas: 8000000,
        ),
      );
      if (!res.ok || res.returnValue.isEmpty) return null;
      // Result value is the raw target string bytes.
      return String.fromCharCodes(res.returnValue).trim();
    } on Exception {
      return null;
    } finally {
      client.dispose();
    }
  }
}
