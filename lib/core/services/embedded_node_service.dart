/// Embedded massa-node manager (experimental).
///
/// Ships the official `massa-node` binary (pinned to the DEVN.30.2 tag —
/// the version buildnet currently runs) inside the APK as
/// `jniLibs/<abi>/libmassa_node.so`. Android extracts bundled native
/// libraries into `applicationInfo.nativeLibraryDir`, which is the one
/// location where app-owned executables may be exec()'d on modern
/// Android (W^X policy). The node therefore runs **inside the app
/// sandbox** — same UID, no root, no Termux — managed as a child
/// process of the app and kept alive by the existing foreground service.
///
/// Lifecycle:
/// 1. `start()` — copies the bundled base config (buildnet profile) into
///    app support, patches binds to loopback, then spawns the binary
///    with `MASSA_CONFIG_PATH` pointing at the generated config.
/// 2. RPC on `http://127.0.0.1:33036/api/v2` is polled until the node
///    answers `get_status`; the wallet switches to the embedded endpoint
///    via [SettingsProvider.connectionMode].
/// 3. The background service isolate re-spawns the node if it dies
///    (see [ensureRunningFromPrefs]), so the node survives app restarts
///    as long as the foreground service lives.
///
/// Scope note: the binary is built from buildnet constants (chain id
/// 77658366 baked into the DEVN version line), so embedded mode applies
/// to buildnet only. Mainnet stays on public/custom RPC.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/massa_rpc.dart';
import 'node_mode_service.dart' show NodeHealth;
import 'settings_provider.dart';

/// Method channel to MainActivity for platform paths.
const _embeddedChannel = MethodChannel('site.massawallet.app/embedded');

/// SharedPreferences key storing the resolved native lib dir.
const kNativeLibDirPref = 'node.nativeLibDir';

/// SharedPreferences key for the auto-generated staking wallet password.
const _kStakingPwdPref = 'node.stakingPwd';

/// Marker file name storing the bundled config revision.
const _kVersionMarker = 'node.version';

/// Bundled massa source revision the assets were taken from.
const bundledNodeVersion = 'DEVN.30.2';

/// Lifecycle state of the embedded node.
enum EmbeddedNodeState {
  /// Binary or assets missing in this build.
  unsupported,

  /// Not running.
  stopped,

  /// Process spawned, waiting for the RPC to answer.
  starting,

  /// RPC reachable, node serving requests (ledger may still sync).
  running,

  /// Process exited unexpectedly.
  failed,
}

/// Rewrites the bundled upstream `config.toml` for in-app use.
///
/// Pure function (unit-tested): every listener that upstream binds to
/// `0.0.0.0`/`[::]` is forced onto loopback so the node exposes nothing
/// to the LAN. The API v2 port is configurable and defaults to
/// [SettingsProvider.embeddedApiPort].
String patchNodeConfig(
  String src, {
  int apiPort = SettingsProvider.embeddedApiPort,
}) {
  return src
      .replaceAll(
        'bind_public = "0.0.0.0:33035"',
        'bind_public = "127.0.0.1:33035"',
      )
      .replaceAll(
        'bind_api = "0.0.0.0:33036"',
        'bind_api = "127.0.0.1:$apiPort"',
      )
      .replaceAll('bind = "0.0.0.0:33037"', 'bind = "127.0.0.1:33037"')
      .replaceAll('bind = "[::]:31248"', 'bind = "127.0.0.1:31248"');
}

/// Manages the embedded massa-node child process.
class EmbeddedNodeService extends ChangeNotifier {
  final SettingsProvider settings;

  EmbeddedNodeState _state = EmbeddedNodeState.stopped;
  String? _lastError;
  DateTime? _startedAt;
  Process? _process;
  final List<String> _logs = <String>[];
  bool _binaryAvailable = false;
  String? _libDir;

  /// Creates the service (UI isolate).
  EmbeddedNodeService({required this.settings});

  /// Current lifecycle state.
  EmbeddedNodeState get state => _state;

  /// Last error message, if any.
  String? get lastError => _lastError;

  /// When the node was started.
  DateTime? get startedAt => _startedAt;

  /// Whether the bundled binary was detected on this device/ABI.
  bool get binaryAvailable => _binaryAvailable;

  /// Resolved native library directory (null before first detection).
  String? get libDir => _libDir;

  /// Recent node logs (oldest first, capped).
  List<String> get logs => List.unmodifiable(_logs);

  /// Loopback endpoint the embedded node serves.
  String get endpoint => settings.embeddedEndpoint;

  /// Detects the bundled binary and refreshes availability.
  Future<bool> detectBinary() async {
    _libDir = await _resolveLibDir();
    final bin = _binaryPath();
    _binaryAvailable =
        _libDir != null &&
        bin != null &&
        File(bin).existsSync() &&
        _hasBundledAssets();
    if (_binaryAvailable) {
      _state = EmbeddedNodeState.stopped;
    } else {
      _state = EmbeddedNodeState.unsupported;
    }
    notifyListeners();
    return _binaryAvailable;
  }

  /// Resolves the native lib dir via the platform channel, falling back
  /// to the persisted value (background isolate has no activity).
  Future<String?> _resolveLibDir() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final dir = await _embeddedChannel.invokeMethod<String>(
        'getNativeLibDir',
      );
      if (dir != null && dir.isNotEmpty) {
        await prefs.setString(kNativeLibDirPref, dir);
        return dir;
      }
    } on Exception {
      // Background isolate or channel missing — use the persisted value.
    }
    return prefs.getString(kNativeLibDirPref);
  }

  String? _binaryPath() {
    final dir = _libDir;
    if (dir == null) return null;
    return '$dir/libmassa_node.so';
  }

  bool _hasBundledAssets() {
    // If the asset is missing rootBundle.load throws synchronously via
    // the future — treat as unavailable.
    try {
      rootBundle.load('assets/node/config.toml');
      return true;
    } on Exception {
      return false;
    }
  }

  /// Starts the node (idempotent).
  Future<void> start() async {
    if (_state == EmbeddedNodeState.running ||
        _state == EmbeddedNodeState.starting) {
      return;
    }
    _lastError = null;
    await detectBinary();
    if (!_binaryAvailable) {
      _lastError = 'embedded node binary not available in this build';
      notifyListeners();
      return;
    }

    _state = EmbeddedNodeState.starting;
    notifyListeners();

    try {
      final dataDir = await _prepareDataDir();
      final prefs = await SharedPreferences.getInstance();
      var pwd = prefs.getString(_kStakingPwdPref);
      if (pwd == null || pwd.isEmpty) {
        pwd = _randomPassword();
        await prefs.setString(_kStakingPwdPref, pwd);
      }

      final process = await Process.start(
        _binaryPath()!,
        ['-p', pwd, '--accept-community-charter'],
        workingDirectory: dataDir.path,
        environment: {
          'MASSA_CONFIG_PATH': '${dataDir.path}/base_config/config.toml',
        },
      );
      _process = process;
      _startedAt = DateTime.now();
      _log('node started (pid ${process.pid})');

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_log, onError: (Object _) {});
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_log, onError: (Object _) {});
      unawaited(
        process.exitCode.then((code) {
          if (_state != EmbeddedNodeState.stopped) {
            _state = EmbeddedNodeState.failed;
            _lastError = 'node exited with code $code';
            _process = null;
            notifyListeners();
          }
        }),
      );

      final ok = await _waitForRpc();
      if (!ok) {
        _lastError = _logs.isEmpty
            ? 'node RPC did not answer in time'
            : _logs.last;
        _state = EmbeddedNodeState.failed;
        _kill();
      } else {
        _state = EmbeddedNodeState.running;
      }
    } on Exception catch (e) {
      _state = EmbeddedNodeState.failed;
      _lastError = e.toString();
    }
    notifyListeners();
  }

  /// Stops the node.
  Future<void> stop() async {
    final p = _process;
    _state = EmbeddedNodeState.stopped;
    _process = null;
    _startedAt = null;
    notifyListeners();
    if (p == null) return;
    p.kill();
    try {
      await p.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      Process.killPid(p.pid, ProcessSignal.sigkill);
    }
    _log('node stopped');
  }

  /// Stops the node and wipes all node data (ledger, rocksdb, logs).
  Future<void> resetData() async {
    await stop();
    final dir = await _dataRoot();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
    _logs.clear();
    _log('node data wiped');
    notifyListeners();
  }

  /// Probes the loopback RPC directly.
  Future<NodeHealth> probe() async {
    final client = MassaRpcClient(endpoint: endpoint);
    final sw = Stopwatch()..start();
    try {
      final status = await client.getStatus().timeout(
        const Duration(seconds: 4),
      );
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

  // ── Internals ────────────────────────────────────────────────────────

  Future<Directory> _dataRoot() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/massa-node');
  }

  /// Copies bundled base config into the app support dir, patches binds
  /// to loopback and creates the auxiliary directories the node expects.
  Future<Directory> _prepareDataDir() async {
    final root = await _dataRoot();
    final baseConfig = Directory('${root.path}/base_config');
    root.createSync(recursive: true);
    Directory('${root.path}/config').createSync(recursive: true);

    final marker = File('${root.path}/$_kVersionMarker');
    final needsCopy =
        !marker.existsSync() || marker.readAsStringSync() != bundledNodeVersion;
    if (needsCopy) {
      baseConfig.createSync(recursive: true);
      final gasDir = Directory('${baseConfig.path}/gas_costs');
      if (!gasDir.existsSync()) gasDir.createSync(recursive: true);

      final files = <String, String>{
        'assets/node/config.toml': '${baseConfig.path}/config.toml',
        'assets/node/initial_ledger.json':
            '${baseConfig.path}/initial_ledger.json',
        'assets/node/initial_rolls.json':
            '${baseConfig.path}/initial_rolls.json',
        'assets/node/initial_peers.json':
            '${baseConfig.path}/initial_peers.json',
        'assets/node/deferred_credits.json':
            '${baseConfig.path}/deferred_credits.json',
        'assets/node/gas_costs/abi_gas_costs.json':
            '${baseConfig.path}/gas_costs/abi_gas_costs.json',
      };
      for (final entry in files.entries) {
        final data = await rootBundle.load(entry.key);
        File(entry.value).writeAsBytesSync(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      }
      // Optional files referenced by the config — write empty JSON lists.
      File(
        '${baseConfig.path}/bootstrap_whitelist.json',
      ).writeAsStringSync('[]');
      File(
        '${baseConfig.path}/bootstrap_blacklist.json',
      ).writeAsStringSync('[]');

      final raw = File('${baseConfig.path}/config.toml').readAsStringSync();
      File('${baseConfig.path}/config.toml').writeAsStringSync(
        '// Generated for Massa Wallet embedded node '
        '($bundledNodeVersion) — binds forced to loopback.\n'
        '${patchNodeConfig(raw)}',
      );
      marker.writeAsStringSync(bundledNodeVersion);
      _log('base config installed ($bundledNodeVersion)');
    }
    return root;
  }

  Future<bool> _waitForRpc() async {
    final client = MassaRpcClient(endpoint: endpoint);
    try {
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      while (DateTime.now().isBefore(deadline)) {
        if (_process == null) return false; // process died while waiting
        try {
          await client.getStatus().timeout(const Duration(seconds: 3));
          return true;
        } on Exception {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
      return false;
    } finally {
      client.dispose();
    }
  }

  void _kill() {
    final p = _process;
    if (p == null) return;
    p.kill();
    _process = null;
  }

  void _log(String line) {
    _logs.add('${DateTime.now().toIso8601String().substring(11, 19)} $line');
    if (_logs.length > 400) {
      _logs.removeRange(0, _logs.length - 400);
    }
    // Notify only when someone is listening — logs arrive in bursts.
    notifyListeners();
  }

  static String _randomPassword() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = Random.secure();
    return List.generate(24, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  /// Background-isolate keepalive: reads persisted prefs, checks the
  /// loopback RPC and (re)spawns the node when the embedded mode is
  /// active but the node is down. Never throws.
  static Future<void> ensureRunningFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString('settings.connectionMode') != 'embedded') return;
      if (prefs.getString('settings.network') == 'mainnet') return;
      final libDir = prefs.getString(kNativeLibDirPref);
      if (libDir == null || libDir.isEmpty) return;
      final bin = File('$libDir/libmassa_node.so');
      if (!bin.existsSync()) return;

      final endpoint =
          'http://127.0.0.1:${SettingsProvider.embeddedApiPort}/api/v2';
      final client = MassaRpcClient(endpoint: endpoint);
      var alive = false;
      try {
        await client.getStatus().timeout(const Duration(seconds: 3));
        alive = true;
      } on Exception {
        alive = false;
      } finally {
        client.dispose();
      }
      if (alive) return;

      final support = await getApplicationSupportDirectory();
      final root = Directory('${support.path}/massa-node');
      if (!File('${root.path}/base_config/config.toml').existsSync()) {
        return; // first start must happen from the UI (assets install)
      }
      var pwd = prefs.getString(_kStakingPwdPref);
      pwd ??= 'massa-wallet-local';
      await Process.start(
        bin.path,
        ['-p', pwd, '--accept-community-charter'],
        workingDirectory: root.path,
        environment: {
          'MASSA_CONFIG_PATH': '${root.path}/base_config/config.toml',
        },
        mode: ProcessStartMode.detached,
      );
    } on Exception {
      // Best-effort keepalive — never break the background tick.
    }
  }
}
