/// Embedded massa-node manager (experimental).
///
/// Ships the official `massa-node` binaries (cross-compiled with the NDK
/// by the release workflow) inside the APK as
/// `jniLibs/<abi>/libmassa_node.so` (buildnet build) and
/// `jniLibs/<abi>/libmassa_node_mainnet.so` (mainnet build). Android
/// extracts bundled native libraries into
/// `applicationInfo.nativeLibraryDir`, which is the one location where
/// app-owned executables may be exec()'d on modern Android (W^X policy).
/// The node therefore runs **inside the app sandbox** — same UID, no
/// root, no Termux — managed as a child process of the app.
///
/// One binary per network: the Massa chain id is baked into the binary
/// at compile time, so a buildnet binary can never serve mainnet (and
/// vice versa). [binaryNameFor] / [dataDirNameFor] pick the right pair.
///
/// Lifecycle:
/// 1. `start()` — copies the bundled base config for the ACTIVE network
///    into a per-network app-support directory, patches binds to
///    loopback, then spawns the matching binary with `MASSA_CONFIG_PATH`
///    pointing at the generated config.
/// 2. RPC on `http://127.0.0.1:33036/api/v2` is polled until the node
///    answers `get_status`; on success the wallet's endpoint resolution
///    switches to the loopback (via `SettingsProvider.embeddedNodeHealthy`).
/// 3. If the process dies at the dynamic-linker stage (the classic
///    "cannot link executable" failure), [diagnoseStartFailure] turns
///    the raw stderr into a structured failure so the UI can explain it
///    and offer a one-tap switch back to the public RPC — the wallet is
///    NEVER left pointing at a dead node.
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

/// Bundled buildnet massa source revision the assets were taken from.
const bundledNodeVersion = 'DEVN.30.2';

/// Bundled mainnet massa source revision marker (bumped when the CI
/// bundles a newer mainnet profile under assets/node/mainnet/).
const bundledMainnetVersion = 'MAIN.1';

/// Structured cause of an embedded-node start failure.
enum EmbeddedFailureKind {
  /// No failure (or not started yet).
  none,

  /// The Android dynamic linker could not load the binary — typically a
  /// missing shared library such as `libc++_shared.so`.
  missingLib,

  /// The OS refused to execute the binary.
  permissionDenied,

  /// Wrong architecture / corrupted ELF (e.g. arm64 binary on x86_64).
  execFormat,

  /// The process ran but the RPC never answered.
  rpcTimeout,

  /// Anything else.
  generic,
}

/// Extracts a structured [EmbeddedFailureKind] (and the missing library
/// name, when applicable) from the captured node logs.
///
/// Pure function (unit-tested). Bionic's dynamic linker prints lines
/// like:
///   `CANNOT LINK EXECUTABLE "/path": library "libc++_shared.so" not found`
///   `CANNOT LINK EXECUTABLE "...": cannot locate symbol ...`
({EmbeddedFailureKind kind, String? missingLib}) diagnoseStartFailure(
  List<String> logs, {
  int scan = 40,
}) {
  final tail = logs.length > scan ? logs.sublist(logs.length - scan) : logs;
  for (final raw in tail.reversed) {
    final line = raw.toLowerCase();
    if (line.contains('cannot link executable') ||
        line.contains('cannot locate symbol')) {
      final m = RegExp(
        r'library "([^"]+)"',
        caseSensitive: false,
      ).firstMatch(raw);
      return (kind: EmbeddedFailureKind.missingLib, missingLib: m?.group(1));
    }
    if (line.contains('permission denied')) {
      return (kind: EmbeddedFailureKind.permissionDenied, missingLib: null);
    }
    if (line.contains('exec format error') ||
        line.contains('not executable') ||
        line.contains('no such file or directory') && line.contains('exec')) {
      return (kind: EmbeddedFailureKind.execFormat, missingLib: null);
    }
  }
  return (kind: EmbeddedFailureKind.generic, missingLib: null);
}

/// SharedPreferences key: epoch-millis until which the background
/// keepalive must NOT respawn the node (set after a deterministic
/// start failure such as a missing dynamic library). A manual "Start
/// node" tap always clears it by succeeding (or re-arms it on failure).
const kAutoRestartBlockPref = 'node.autoRestartBlockedUntil';

/// How long a deterministic start failure pauses background respawn.
const nodeRestartCooldown = Duration(minutes: 10);

/// Whether the background keepalive respawn is blocked at [now].
/// Pure function (unit-tested).
bool nodeRestartBlocked(int? blockedUntilMs, DateTime now) =>
    blockedUntilMs != null &&
    DateTime.fromMillisecondsSinceEpoch(blockedUntilMs).isAfter(now);

/// Builds the child-process environment for the embedded node.
///
/// `Process.start(environment: …)` REPLACES the inherited environment —
/// it does not merge. Shipping only `MASSA_CONFIG_PATH` stripped
/// `LD_LIBRARY_PATH`, so the Bionic linker could not resolve
/// `libc++_shared.so` sitting in the SAME directory as the executable
/// (unlike glibc, Bionic does not search the executable's own
/// directory) — the classic
/// "CANNOT LINK EXECUTABLE: library libc++_shared.so not found"
/// crash loop on every released build. This helper merges the
/// caller-provided base (defaults to the current process environment)
/// and puts [libDir] at the FRONT of `LD_LIBRARY_PATH` so app-bundled
/// runtime libraries always win. Pure function (unit-tested).
Map<String, String> buildNodeEnv(
  String libDir,
  String configPath, {
  Map<String, String>? base,
}) {
  final env = Map<String, String>.from(base ?? Platform.environment);
  final current = env['LD_LIBRARY_PATH'];
  final rest = (current == null || current.isEmpty)
      ? <String>[]
      : current
            .split(':')
            .where((p) => p.isNotEmpty && p != libDir)
            .toList();
  env['LD_LIBRARY_PATH'] = [libDir, ...rest].join(':');
  env['MASSA_CONFIG_PATH'] = configPath;
  return env;
}

/// ELF executable shipped in jniLibs for [network].
String binaryNameFor(MassaNetwork network) => network == MassaNetwork.mainnet
    ? 'libmassa_node_mainnet.so'
    : 'libmassa_node.so';

/// Per-network data directory under the app-support root.
///
/// Buildnet keeps the legacy `massa-node` name so existing installs do
/// not re-bootstrap after the update.
String dataDirNameFor(MassaNetwork network) =>
    network == MassaNetwork.mainnet ? 'massa-node-mainnet' : 'massa-node';

/// Bundled asset prefix holding the base config for [network].
String configAssetDirFor(MassaNetwork network) =>
    network == MassaNetwork.mainnet ? 'assets/node/mainnet' : 'assets/node';

/// Config revision marker for [network].
String configVersionFor(MassaNetwork network) => network == MassaNetwork.mainnet
    ? bundledMainnetVersion
    : bundledNodeVersion;

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

/// Manages the embedded massa-node child process.
class EmbeddedNodeService extends ChangeNotifier {
  final SettingsProvider settings;

  EmbeddedNodeState _state = EmbeddedNodeState.stopped;
  String? _lastError;
  EmbeddedFailureKind _failureKind = EmbeddedFailureKind.none;
  String? _missingLib;
  DateTime? _startedAt;
  Process? _process;
  final List<String> _logs = <String>[];
  bool _binaryAvailable = false;
  String? _libDir;
  MassaNetwork _detectedFor = MassaNetwork.buildnet;

  /// Creates the service (UI isolate).
  EmbeddedNodeService({required this.settings});

  /// Current lifecycle state.
  EmbeddedNodeState get state => _state;

  /// Last error message, if any.
  String? get lastError => _lastError;

  /// Structured failure classification for the last failed start.
  EmbeddedFailureKind get failureKind => _failureKind;

  /// The shared library the dynamic linker could not resolve, when
  /// [failureKind] is [EmbeddedFailureKind.missingLib].
  String? get missingLib => _missingLib;

  /// When the node was started.
  DateTime? get startedAt => _startedAt;

  /// Whether the bundled binary for the ACTIVE network was detected.
  bool get binaryAvailable => _binaryAvailable;

  /// Network the last detection ran for.
  MassaNetwork get detectedFor => _detectedFor;

  /// Resolved native library directory (null before first detection).
  String? get libDir => _libDir;

  /// Recent node logs (oldest first, capped at 1000 lines).
  List<String> get logs => List.unmodifiable(_logs);

  /// Clears the in-memory log buffer (viewer "clear" action).
  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  /// Test hook — appends a line exactly like the process pipes do.
  @visibleForTesting
  void appendLogLine(String line) => _log(line);

  /// Loopback endpoint the embedded node serves.
  String get endpoint => settings.embeddedEndpoint;

  /// Detects the bundled binary for the active network and refreshes
  /// availability.
  Future<bool> detectBinary() async {
    _detectedFor = settings.network;
    _libDir = await _resolveLibDir();
    final bin = _binaryPath();
    _binaryAvailable =
        _libDir != null &&
        bin != null &&
        File(bin).existsSync() &&
        _hasBundledAssets(_detectedFor);
    if (_binaryAvailable) {
      if (_state == EmbeddedNodeState.unsupported) {
        _state = EmbeddedNodeState.stopped;
      }
    } else {
      if (_state == EmbeddedNodeState.stopped ||
          _state == EmbeddedNodeState.unsupported) {
        _state = EmbeddedNodeState.unsupported;
      }
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
    return '$dir/${binaryNameFor(_detectedFor)}';
  }

  bool _hasBundledAssets(MassaNetwork network) {
    // If the asset is missing rootBundle.load throws synchronously via
    // the future — treat as unavailable.
    try {
      rootBundle.load('${configAssetDirFor(network)}/config.toml');
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
    _failureKind = EmbeddedFailureKind.none;
    _missingLib = null;
    await detectBinary();
    if (!_binaryAvailable) {
      _lastError = 'embedded node binary not available in this build';
      _failureKind = EmbeddedFailureKind.generic;
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

      // Belt-and-braces preflight: the binary needs libc++_shared.so
      // next to it; warn early in the log stream when it is missing.
      if (!File('$_libDir/libc++_shared.so').existsSync()) {
        _log('WARN: libc++_shared.so not found in $_libDir — the node '
            'binary may fail to link on this device');
      }

      final process = await Process.start(
        _binaryPath()!,
        ['-p', pwd, '--accept-community-charter'],
        workingDirectory: dataDir.path,
        // MUST merge the full environment (incl. LD_LIBRARY_PATH) —
        // a bare {MASSA_CONFIG_PATH} map makes the Bionic linker fail
        // with "CANNOT LINK EXECUTABLE: library libc++_shared.so not
        // found" even though the library sits right next to the binary.
        environment: buildNodeEnv(
          _libDir!,
          '${dataDir.path}/base_config/config.toml',
        ),
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
            final diag = diagnoseStartFailure(_logs);
            _failureKind = diag.kind;
            _missingLib = diag.missingLib;
            _lastError = _failureKind == EmbeddedFailureKind.generic
                ? 'node exited with code $code'
                : 'node exited with code $code '
                      '(linker/runtime failure)';
            _process = null;
            _state = EmbeddedNodeState.failed;
            // Deterministic failures (missing lib, exec format, no exec
            // permission) can NEVER succeed by retrying — pause the
            // background keepalive so it cannot turn one bad binary
            // into a device-hammering crash loop. A manual "Start"
            // tap still works and clears the block on success.
            if (_failureKind == EmbeddedFailureKind.missingLib ||
                _failureKind == EmbeddedFailureKind.permissionDenied ||
                _failureKind == EmbeddedFailureKind.execFormat) {
              unawaited(_setRestartBlocked(true));
              _log('auto-restart paused for '
                  '${nodeRestartCooldown.inMinutes} min '
                  '(deterministic failure — press Start to retry)');
            }
            unawaited(settings.setEmbeddedNodeHealthy(false));
            notifyListeners();
          }
        }),
      );

      final ok = await _waitForRpc();
      if (!ok) {
        if (_state != EmbeddedNodeState.failed) {
          // RPC timeout with a live process — classify from the logs.
          final diag = diagnoseStartFailure(_logs);
          _failureKind = diag.kind;
          _missingLib = diag.missingLib;
          _lastError = _logs.isEmpty
              ? 'node RPC did not answer in time'
              : _logs.last;
        }
        _state = EmbeddedNodeState.failed;
        _kill();
        unawaited(settings.setEmbeddedNodeHealthy(false));
      } else {
        _state = EmbeddedNodeState.running;
        _failureKind = EmbeddedFailureKind.none;
        _missingLib = null;
        unawaited(_setRestartBlocked(false));
        unawaited(settings.setEmbeddedNodeHealthy(true));
      }
    } on Exception catch (e) {
      _state = EmbeddedNodeState.failed;
      final diag = diagnoseStartFailure(_logs);
      _failureKind = diag.kind;
      _missingLib = diag.missingLib;
      _lastError = e.toString();
      unawaited(settings.setEmbeddedNodeHealthy(false));
    }
    notifyListeners();
  }

  /// Stops the node.
  Future<void> stop() async {
    final p = _process;
    _state = EmbeddedNodeState.stopped;
    _process = null;
    _startedAt = null;
    unawaited(settings.setEmbeddedNodeHealthy(false));
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

  /// Stops the node and wipes all node data (ledger, rocksdb, logs) for
  /// the ACTIVE network.
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
    return Directory('${support.path}/${dataDirNameFor(_detectedFor)}');
  }

  /// Copies the bundled base config for the ACTIVE network into the
  /// per-network app-support dir, patches binds to loopback and creates
  /// the auxiliary directories the node expects.
  Future<Directory> _prepareDataDir() async {
    final network = _detectedFor;
    final assetDir = configAssetDirFor(network);
    final root = await _dataRoot();
    final baseConfig = Directory('${root.path}/base_config');
    root.createSync(recursive: true);
    Directory('${root.path}/config').createSync(recursive: true);

    final marker = File('${root.path}/$_kVersionMarker');
    final version = configVersionFor(network);
    final needsCopy =
        !marker.existsSync() || marker.readAsStringSync() != version;
    if (needsCopy) {
      baseConfig.createSync(recursive: true);
      final gasDir = Directory('${baseConfig.path}/gas_costs');
      if (!gasDir.existsSync()) gasDir.createSync(recursive: true);

      final files = <String, String>{
        '$assetDir/config.toml': '${baseConfig.path}/config.toml',
        '$assetDir/initial_ledger.json':
            '${baseConfig.path}/initial_ledger.json',
        '$assetDir/initial_rolls.json': '${baseConfig.path}/initial_rolls.json',
        '$assetDir/initial_peers.json': '${baseConfig.path}/initial_peers.json',
        '$assetDir/deferred_credits.json':
            '${baseConfig.path}/deferred_credits.json',
        '$assetDir/gas_costs/abi_gas_costs.json':
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
        '// Generated for Pine Wallet embedded node '
        '($version · ${network.name}) — binds forced to loopback.\n'
        '${patchNodeConfig(raw)}',
      );
      marker.writeAsStringSync(version);
      _log('base config installed ($version · ${network.name})');
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

  /// Persists/clears the background-keepalive cooldown marker.
  Future<void> _setRestartBlocked(bool blocked) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (blocked) {
        await prefs.setInt(
          kAutoRestartBlockPref,
          DateTime.now().add(nodeRestartCooldown).millisecondsSinceEpoch,
        );
      } else {
        await prefs.remove(kAutoRestartBlockPref);
      }
    } on Exception {
      // Best-effort — a failed write must not break the state machine.
    }
  }

  void _log(String line) {
    _logs.add('${DateTime.now().toIso8601String().substring(11, 19)} $line');
    if (_logs.length > 1000) {
      _logs.removeRange(0, _logs.length - 1000);
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
      final isMainnet = prefs.getString('settings.network') == 'mainnet';
      final network = isMainnet ? MassaNetwork.mainnet : MassaNetwork.buildnet;
      final libDir = prefs.getString(kNativeLibDirPref);
      if (libDir == null || libDir.isEmpty) return;
      final bin = File('$libDir/${binaryNameFor(network)}');
      if (!bin.existsSync()) return;
      // Honor the crash-loop cooldown: a deterministic failure (e.g.
      // missing libc++_shared.so) must not be retried every tick.
      if (nodeRestartBlocked(
        prefs.getInt(kAutoRestartBlockPref),
        DateTime.now(),
      )) {
        return;
      }

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
      final root = Directory('${support.path}/${dataDirNameFor(network)}');
      if (!File('${root.path}/base_config/config.toml').existsSync()) {
        return; // first start must happen from the UI (assets install)
      }
      var pwd = prefs.getString(_kStakingPwdPref);
      pwd ??= 'massa-wallet-local';
      await Process.start(
        bin.path,
        ['-p', pwd, '--accept-community-charter'],
        workingDirectory: root.path,
        // Merge (not replace) the environment — see [buildNodeEnv].
        environment: buildNodeEnv(
          libDir,
          '${root.path}/base_config/config.toml',
        ),
        mode: ProcessStartMode.detached,
      );
    } on Exception {
      // Best-effort keepalive — never break the background tick.
    }
  }
}
