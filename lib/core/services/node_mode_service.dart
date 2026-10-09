/// Experimental "Embedded Node" mode.
///
/// Massa full nodes require ~4 cores and ~8 GB RAM (see docs.massa.net),
/// which is beyond what most phones can sustain 24/7. This app therefore
/// ships a **hybrid architecture**:
///
/// 1. *Light client (default)* — talks to the public JSON-RPC v2 endpoint
///    (buildnet/mainnet). Zero setup, low battery.
/// 2. *Node mode (experimental)* — talks to a **local node** through a
///    user-configured endpoint (e.g. `http://127.0.0.1:33035` when a
///    massa-node runs in Termux, on the same Wi-Fi, or a self-hosted VPS).
///    When the endpoint is local the wallet effectively communicates with
///    a node embedded in the device ecosystem, including all background
///    processes (staking checks, balance sync) through the foreground
///    service.
///
/// A true in-process Rust node can be cross-compiled to Android with
/// cargo-ndk and spawned from a foreground service; the wiring in this
/// class isolates that integration point (see README roadmap).
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

/// Manages the experimental node mode.
class NodeModeService {
  final SettingsProvider settings;

  /// Creates the service.
  NodeModeService({required this.settings});

  /// Probes the configured custom node.
  Future<NodeHealth> probe() async {
    if (!settings.useCustomNode || settings.customNodeUrl.isEmpty) {
      return const NodeHealth(reachable: false, error: 'node mode disabled');
    }
    final client = MassaRpcClient(endpoint: settings.customNodeUrl);
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

  /// Returns true when the wallet should use the custom node.
  bool get isEnabled => settings.useCustomNode;

  /// Warn-level check: a custom node on a different chain id than the
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
