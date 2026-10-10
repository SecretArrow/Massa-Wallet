/// Node connectivity health checks.
///
/// Covers all three connection modes:
/// 1. *Public RPC* — official endpoints (default light client).
/// 2. *Custom RPC* — a user-operated node (LAN/VPS/Termux).
/// 3. *Embedded* — the in-app massa-node binary on loopback.
library;

import '../api/massa_rpc.dart';
import 'settings_provider.dart';

/// Node-mode health snapshot.
class NodeHealth {
  /// Whether the last probe succeeded.
  final bool reachable;

  /// Node version reported by `get_status` (null when unreachable).
  final String? version;

  /// Chain id reported by the node.
  final int? chainId;

  /// Error message when unreachable.
  final String? error;

  /// Latency of the probe.
  final Duration? latency;

  /// Creates the snapshot.
  const NodeHealth({
    required this.reachable,
    this.version,
    this.chainId,
    this.error,
    this.latency,
  });
}

/// Manages node connectivity health.
class NodeModeService {
  final SettingsProvider settings;

  /// Creates the service.
  NodeModeService({required this.settings});

  /// Probes the endpoint the wallet would actually use for the active
  /// mode (custom URL, embedded loopback, or the public RPC).
  Future<NodeHealth> probe() async {
    final client = MassaRpcClient(endpoint: settings.effectiveEndpoint);
    final sw = Stopwatch()..start();
    try {
      final status = await client.getStatus();
      sw.stop();
      return NodeHealth(
        reachable: true,
        version: status.version,
        chainId: status.chainId,
        latency: sw.elapsed,
      );
    } catch (e) {
      return NodeHealth(reachable: false, error: e.toString());
    } finally {
      client.dispose();
    }
  }

  /// True when the wallet deviates from the default public RPC.
  bool get isEnabled => settings.connectionMode != NodeConnectionMode.publicRpc;

  /// Warn-level check: a node on a different chain id than the
  /// selected network would produce signatures that nodes reject.
  Future<String?> validateChainId() async {
    final health = await probe();
    if (!health.reachable) return health.error;
    if (health.chainId != settings.network.chainId) {
      return 'node chainId ${health.chainId} != ${settings.network.name} '
          '(${settings.network.chainId})';
    }
    return null;
  }
}
