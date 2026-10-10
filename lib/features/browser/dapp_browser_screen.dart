/// DApp browser: browses on-chain `.massa` sites (DeWeb) and normal
/// websites, injecting the `window.massa` provider with user-confirmed
/// signing and transaction dialogs.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/api/massa_amount.dart';
import '../../core/api/massa_rpc.dart';
import '../../core/contracts/deweb_service.dart';
import '../../core/contracts/local_site_server.dart';
import '../../core/contracts/mns_service.dart';
import '../../core/contracts/web3_provider.dart';
import '../../core/crypto/operation_describer.dart';
import '../../core/crypto/operation_serializer.dart' show OperationType;
import '../../core/i18n/app_i18n.dart';
import '../../core/services/settings_provider.dart';
import '../../core/services/wallet_provider.dart';
import '../../ui/theme.dart';
import 'browser_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Curated starter sites (on-chain, buildnet-friendly).
const List<(String, String)> kFeaturedSites = [
  ('helloworld.massa', '👋 Hello World — the classic first DeWeb site'),
  ('docs.massa', '📚 Massa docs mirror on-chain'),
  ('explorer.massa', '🔎 On-chain explorer site'),
  ('deweb.massa', '🌐 DeWeb portal'),
];

/// In-app DApp browser screen.
class DappBrowserScreen extends StatefulWidget {
  /// Optional initial URL (`name.massa`, `AS1…`, or https://…).
  final String? initialUrl;

  /// Creates the browser screen.
  const DappBrowserScreen({super.key, this.initialUrl});

  @override
  State<DappBrowserScreen> createState() => _DappBrowserScreenState();
}

class _DappBrowserScreenState extends State<DappBrowserScreen> {
  late final WebViewController _controller;
  final TextEditingController _urlInput = TextEditingController();

  late final MnsService _mns;
  late final DeWebService _deweb;
  late final LocalSiteServer _server;

  SettingsProvider? _settings;

  bool _loading = true;
  String _currentUrl = '';
  String _currentTitle = '';
  String? _resolvedSite; // SC address currently served
  String? _resolvedDomain;
  double _progress = 0;
  final List<String> _history = [];

  // Start page + persisted browser data.
  BrowserStore? _store;
  List<DappEntry> _bookmarks = const [];
  List<DappEntry> _storeHistory = const [];
  bool _showStartPage = true;

  @override
  void initState() {
    super.initState();
    _settings = context.read<SettingsProvider>();
    _mns = MnsService(
      clientFactory: () =>
          MassaRpcClient(endpoint: _settings!.effectiveEndpoint),
    );
    _deweb = DeWebService(
      clientFactory: () =>
          MassaRpcClient(endpoint: _settings!.effectiveEndpoint),
    );
    _server = LocalSiteServer(deweb: _deweb);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) => setState(() => _progress = p / 100),
          onPageStarted: (url) => setState(() {
            _loading = true;
            _currentUrl = url;
          }),
          onPageFinished: _onPageFinished,
          onNavigationRequest: _onNavigationRequest,
        ),
      )
      ..addJavaScriptChannel(
        'MassaMobile',
        onMessageReceived: (msg) => _onWeb3Message(msg.message),
      );
    _start(widget.initialUrl ?? 'home');
    // Load persisted bookmarks/history (start page data).
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() {
        _store = BrowserStore(prefs);
        _bookmarks = _store!.bookmarks();
        _storeHistory = _store!.history();
      });
    });
  }

  @override
  void dispose() {
    _server.stop();
    _urlInput.dispose();
    super.dispose();
  }

  Future<void> _start(String input) async {
    final settings = _settings!;
    setState(() => _loading = true);
    try {
      final parsed = MnsService.parseInput(input);
      final isMassa = parsed.domain != null || parsed.address != null;
      if (input == 'home') {
        await _loadHome();
        return;
      }
      if (!isMassa) {
        final url = input.startsWith('http') ? input : 'https://$input';
        if (mounted) {
          setState(() => _showStartPage = false);
        }
        _recordVisit(_hostOf(url), url);
        await _controller.loadRequest(Uri.parse(url));
        return;
      }

      // Resolve .massa domain / AS address → SC address.
      String sc;
      if (parsed.address != null) {
        sc = parsed.address!;
        _resolvedDomain = null;
      } else {
        final res = await _mns.resolve(
          parsed.domain!,
          mainnet: settings.network == MassaNetwork.mainnet,
        );
        if (!res.isSmartContract) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.t('browser.notSite', args: [res.target])),
            ),
          );
          setState(() => _loading = false);
          return;
        }
        sc = res.target;
        _resolvedDomain = res.domain;
      }

      await _server.start();
      _server.serveSite(sc);
      _resolvedSite = sc;
      final path = parsed.path.isEmpty ? '' : '/${parsed.path}';
      final localUrl = '${_server.baseUrl}/$path';
      _pushHistory(_resolvedDomain != null ? '${_resolvedDomain!}.massa' : sc);
      if (mounted) {
        setState(() {
          _showStartPage = false;
          _currentUrl = _resolvedDomain != null
              ? '${_resolvedDomain!}.massa'
              : sc;
        });
      }
      _recordVisit(
        _resolvedDomain != null ? '${_resolvedDomain!}.massa' : sc,
        _resolvedDomain != null ? 'https://${_resolvedDomain!}.massa' : sc,
      );
      await _controller.loadRequest(Uri.parse(localUrl));
    } on MnsException catch (e) {
      _showError(e.message);
    } on DeWebException catch (e) {
      _showError(e.message);
    } on Exception catch (e) {
      _showError(e.toString());
    }
  }

  /// Shows the Flutter start page (curated dApps, DeWeb sites,
  /// bookmarks, history) instead of a WebView HTML page.
  Future<void> _loadHome() async {
    setState(() {
      _loading = false;
      _currentUrl = '';
      _currentTitle = '';
      _resolvedSite = null;
      _resolvedDomain = null;
      _showStartPage = true;
    });
  }

  void _recordVisit(String name, String url) {
    final store = _store;
    if (store == null || !url.startsWith('http')) return;
    store.recordVisit(name, url);
    if (mounted) {
      setState(() => _storeHistory = store.history());
    }
  }

  String _hostOf(String url) => Uri.tryParse(url)?.host ?? url;

  void _pushHistory(String url) {
    if (url.isEmpty) return;
    setState(() => _history.insert(0, url));
    if (_history.length > 50) _history.removeLast();
  }

  NavigationDecision _onNavigationRequest(NavigationRequest req) {
    final url = req.url;
    // Local server & about/data URLs pass through.
    if (url.startsWith(_server.baseUrl ?? 'http://127.0.0.1:0') ||
        url.startsWith('data:') ||
        url.startsWith('about:')) {
      return NavigationDecision.navigate;
    }
    // Internal .massa links handled by our resolver.
    final parsed = MnsService.parseInput(url);
    if (parsed.domain != null && !url.startsWith('http') ||
        url.endsWith('.massa') ||
        url.contains('.massa/')) {
      unawaited(_start(url));
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  Future<void> _onPageFinished(String url) async {
    final wallet = context.read<WalletProvider>();
    final settings = _settings!;
    final account = wallet.activeAccount;
    final script = massaProviderScript(
      address: account?.address ?? '',
      nickname: account?.nickname ?? '',
      chainId: settings.network.chainId,
      networkName: settings.network.name,
    );
    try {
      await _controller.runJavaScript(script);
    } on Exception {
      // Page may have navigated mid-injection.
    }
    if (mounted) {
      setState(() => _loading = false);
    }
    // Read <title> best-effort.
    try {
      final title = await _controller.runJavaScriptReturningResult(
        'document.title',
      );
      if (mounted) {
        setState(() => _currentTitle = '$title'.replaceAll("'", ''));
      }
    } on Exception {
      // ignore
    }
  }

  Future<void> _onWeb3Message(String message) async {
    final req = Web3Request.tryParse(message);
    if (req == null) return;
    final wallet = context.read<WalletProvider>();
    final settings = _settings!;
    final account = wallet.activeAccount;
    try {
      final result = await _handleWeb3(
        req,
        wallet,
        settings,
        account?.address ?? '',
      );
      if (!mounted) return;
      await _controller.runJavaScript(req.resolveJs(result));
    } on Exception catch (e) {
      if (!mounted) return;
      await _controller.runJavaScript(req.rejectJs(e.toString()));
    }
  }

  Future<Object?> _handleWeb3(
    Web3Request req,
    WalletProvider wallet,
    SettingsProvider settings,
    String account,
  ) async {
    switch (req.method) {
      case 'enable':
        final ok = await _confirm(
          title: context.t('web3.connectTitle'),
          body: context.t('web3.connectBody', args: [_originLabel()]),
          confirm: context.t('web3.connect'),
        );
        if (!ok) throw Exception(context.t('web3.rejected'));
        final a = wallet.activeAccount;
        if (a == null) throw Exception(context.t('web3.noAccount'));
        return [
          {
            'address': a.address,
            'name': a.nickname.isEmpty ? 'Pyramids Wallet' : a.nickname,
          },
        ];
      case 'accounts':
        final a = wallet.activeAccount;
        if (a == null) return [];
        return [
          {
            'address': a.address,
            'name': a.nickname.isEmpty ? 'Pyramids Wallet' : a.nickname,
          },
        ];
      case 'network':
        return {
          'chainId': '${settings.network.chainId}',
          'name': settings.network.name,
        };
      case 'balance':
        final target = (req.params['address'] as String?) ?? account;
        final client = MassaRpcClient(endpoint: settings.effectiveEndpoint);
        try {
          final info = await client.getAddressInfo(target);
          return formatNano(info.finalBalance);
        } finally {
          client.dispose();
        }
      case 'sign':
        final data = (req.params['data'] ?? '') as String;
        final ok = await _confirmSign(
          title: context.t('web3.signTitle'),
          body: data,
        );
        if (!ok) throw Exception(context.t('web3.rejected'));
        final sig = await _signMessage(data);
        return sig;
      case 'signOperation':
        final data = (req.params['data'] ?? '') as String;
        // Defensive decode: base58 / base64 / comma-separated ints.
        final opBytes = _decodeArgs(data);
        final desc = describeSerializedOperation(opBytes);
        final rows = <String, String>{
          context.t('browser.opDetails'): desc.type == null || !desc.parsedOk
              ? context.t('browser.opUnknown')
              : (desc.functionName == null
                    ? desc.type!.name
                    : '${desc.type!.name} → ${desc.functionName}'),
          if (desc.parsedOk && desc.targetAddress != null)
            '→': desc.targetAddress!,
          if (desc.parsedOk &&
              desc.amount != null &&
              desc.type == OperationType.transaction)
            context.t('send.amount'): '${formatNano(desc.amount!)} MAS',
          if (desc.parsedOk && desc.fee != null)
            context.t('send.fee'): '${formatNano(desc.fee!)} MAS',
          context.t('web3.raw'): data,
        };
        final okOp = await _confirmTx(
          title: context.t('web3.signOpTitle'),
          rows: rows,
        );
        if (!okOp) throw Exception(context.t('web3.rejected'));
        // Canonical signing: u64BE(chainId) | versionedPub | serializedOp.
        final signed = await wallet.signSerializedOperationForDapp(
          account,
          opBytes,
        );
        return signed.signature;
      case 'sendTransaction':
        final to = (req.params['to'] ?? '') as String;
        final amountStr = (req.params['amount'] ?? '0').toString();
        final amountNano = parseUserAmount(amountStr);
        final ok = await _confirmTx(
          title: context.t('web3.sendTitle'),
          rows: {
            context.t('web3.to'): to,
            context.t('web3.amount'): '$amountStr MAS',
            context.t('web3.from'): account,
          },
        );
        if (!ok) throw Exception(context.t('web3.rejected'));
        final res = await wallet.sendTransfer(
          fromAddress: account,
          recipient: to,
          amountNano: amountNano,
          note: 'dApp: $_currentTitle',
        );
        return res.operationId;
      case 'buyRolls':
      case 'sellRolls':
        final amount = int.tryParse('${req.params['amount']}') ?? 0;
        final ok = await _confirmTx(
          title: context.t(
            req.method == 'buyRolls'
                ? 'web3.buyRollsTitle'
                : 'web3.sellRollsTitle',
          ),
          rows: {
            context.t('staking.rolls'): '$amount',
            context.t('web3.from'): account,
          },
        );
        if (!ok) throw Exception(context.t('web3.rejected'));
        final res = req.method == 'buyRolls'
            ? await wallet.buyRolls(fromAddress: account, rollCount: amount)
            : await wallet.sellRolls(fromAddress: account, rollCount: amount);
        return res.operationId;
      case 'callSC':
        final target = (req.params['target'] ?? '') as String;
        final func = (req.params['func'] ?? '') as String;
        final argsBase58 = (req.params['argsBase58'] ?? '') as String;
        final coinsStr = (req.params['coins'] ?? '0').toString();
        final coinsNano = parseUserAmount(coinsStr);
        final ok = await _confirmTx(
          title: context.t('web3.callTitle'),
          rows: {
            context.t('web3.contract'): target,
            context.t('web3.function'): func,
            if (coinsNano > BigInt.zero)
              context.t('web3.coins'): '$coinsStr MAS',
            context.t('web3.from'): account,
          },
        );
        if (!ok) throw Exception(context.t('web3.rejected'));
        final res = await wallet.callSmartContract(
          fromAddress: account,
          target: target,
          function: func,
          parameter: _decodeArgs(argsBase58),
          maxGas: BigInt.from(10000000),
          coinsNano: coinsNano == BigInt.zero ? null : coinsNano,
          note: 'dApp: $_currentTitle',
        );
        return res.operationId;
      default:
        throw Exception('unsupported method: ${req.method}');
    }
  }

  /// Decodes the dApp-provided Args payload. Accepts raw base58-of-bytes is
  /// not standard — dApps using window.massa.callSC usually pass the raw
  /// serialized Args as base58 of the bytes; we accept base58, base64 or
  /// comma-separated ints defensively.
  List<int> _decodeArgs(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return const [];
    // comma separated ints
    if (trimmed.contains(',')) {
      final parts = trimmed.split(',');
      final ints = parts.map((p) => int.tryParse(p.trim())).toList();
      if (ints.every((i) => i != null && i >= 0 && i <= 255)) {
        return ints.cast<int>();
      }
    }
    // base64
    if (RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(trimmed) &&
        trimmed.length % 4 == 0) {
      try {
        return base64Decode(trimmed);
      } on FormatException {
        // fallthrough
      }
    }
    // base58 (uses Massa base58 alphabet, no checksum for raw args)
    const alphabet =
        '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    var num = BigInt.zero;
    for (final ch in trimmed.runes) {
      final idx = alphabet.indexOf(String.fromCharCode(ch));
      if (idx < 0) return utf8.encode(trimmed); // plain string fallback
      num = num * BigInt.from(58) + BigInt.from(idx);
    }
    final out = <int>[];
    var v = num;
    while (v > BigInt.zero) {
      out.insert(0, (v & BigInt.from(0xFF)).toInt());
      v = v >> 8;
    }
    return out;
  }

  Future<String> _signMessage(String data) async {
    final wallet = context.read<WalletProvider>();
    final account = wallet.activeAccount;
    if (account == null) throw Exception(context.t('web3.noAccount'));
    return wallet.signMessageForDapp(account.address, data);
  }

  String _originLabel() => _resolvedDomain != null
      ? '${_resolvedDomain!}.massa'
      : (_currentTitle.isEmpty ? _currentUrl : _currentTitle);

  Future<bool> _confirm({
    required String title,
    required String body,
    String confirm = 'OK',
  }) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirm),
          ),
        ],
      ),
    );
    return res == true;
  }

  Future<bool> _confirmSign({required String title, required String body}) =>
      _confirm(
        title: title,
        body: body.length > 400 ? '${body.substring(0, 400)}…' : body,
        confirm: context.t('web3.sign'),
      );

  Future<bool> _confirmTx({
    required String title,
    required Map<String, String> rows,
  }) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in rows.entries) ...[
              Text(
                e.key,
                style: const TextStyle(
                  fontSize: 12,
                  color: MassaColors.textSecondary,
                ),
              ),
              SelectableText(
                e.value,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.t('web3.confirm')),
          ),
        ],
      ),
    );
    return res == true;
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _loading = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _toggleBookmark() {
    final store = _store;
    final url = _currentUrl;
    if (store == null || !url.startsWith('http')) return;
    if (store.isBookmarked(url)) {
      store.removeBookmark(url);
    } else {
      store.addBookmark(_hostOf(url), url);
    }
    setState(() => _bookmarks = store.bookmarks());
  }

  void _clearStoreHistory() {
    _store?.clearHistory();
    setState(() => _storeHistory = const []);
  }

  @override
  Widget build(BuildContext context) {
    final inputIsMassa = _resolvedDomain != null;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: TextField(
            controller: _urlInput,
            textInputAction: TextInputAction.go,
            decoration: InputDecoration(
              hintText: 'name.massa · AS1… · https://…',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              prefixIcon: const Icon(Icons.public, size: 18),
              suffixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : const Icon(Icons.search, size: 18),
            ),
            onSubmitted: (v) {
              if (v.trim().isEmpty) return;
              _start(v.trim());
            },
          ),
        ),
        actions: [
          if (_currentUrl.startsWith('http'))
            IconButton(
              tooltip: (_store?.isBookmarked(_currentUrl) ?? false)
                  ? context.t('browser.removeBookmark')
                  : context.t('browser.addBookmark'),
              icon: Icon(
                (_store?.isBookmarked(_currentUrl) ?? false)
                    ? Icons.star
                    : Icons.star_border,
                size: 20,
              ),
              onPressed: _toggleBookmark,
            ),
          if (inputIsMassa)
            IconButton(
              tooltip: context.t('browser.siteInfo'),
              icon: const Icon(Icons.info_outline, size: 20),
              onPressed: _showSiteInfo,
            ),
        ],
        bottom: _loading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _progress == 0 ? null : _progress,
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  color: MassaColors.teal,
                ),
              )
            : null,
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Offstage(
                  offstage: _showStartPage,
                  child: WebViewWidget(controller: _controller),
                ),
                if (_showStartPage)
                  _StartPage(
                    bookmarks: _bookmarks,
                    history: _storeHistory,
                    onOpen: _start,
                    onClearHistory: _clearStoreHistory,
                  ),
              ],
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF21262D))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              icon: const Icon(Icons.home_outlined),
              tooltip: context.t('browser.home'),
              onPressed: () => _start('home'),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: context.t('browser.back'),
              onPressed: () async {
                if (await _controller.canGoBack()) {
                  await _controller.goBack();
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: context.t('browser.reload'),
              onPressed: () => _controller.reload(),
            ),
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: context.t('browser.history'),
              onPressed: _showHistorySheet,
            ),
          ],
        ),
      ),
    );
  }

  void _showHistorySheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              ctx.t('browser.history'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (_history.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(ctx.t('browser.historyEmpty')),
              )
            else
              ..._history.map(
                (u) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.public, size: 18),
                  title: Text(u),
                  onTap: () {
                    Navigator.pop(ctx);
                    _start(u);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showSiteInfo() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ctx.t('browser.siteInfo'),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              Text('${ctx.t('browser.domain')}: ${_resolvedDomain ?? '-'}'),
              const SizedBox(height: 4),
              Text(
                '${ctx.t('browser.contract')}: ',
                style: const TextStyle(fontSize: 13),
              ),
              SelectableText(
                _resolvedSite ?? '-',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: MassaColors.teal,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${ctx.t('browser.servedLocally')}',
                style: const TextStyle(
                  fontSize: 12,
                  color: MassaColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Flutter start page: curated https dApps, on-chain DeWeb sites,
/// bookmarks and persistent history.
class _StartPage extends StatelessWidget {
  final List<DappEntry> bookmarks;
  final List<DappEntry> history;
  final ValueChanged<String> onOpen;
  final VoidCallback onClearHistory;

  const _StartPage({
    required this.bookmarks,
    required this.history,
    required this.onOpen,
    required this.onClearHistory,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          Center(
            child: Text(
              '▲',
              style: TextStyle(
                fontSize: 34,
                color: Theme.of(context).colorScheme.primary,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              context.t('app.title'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              context.t('browser.homeSub'),
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
          _section(context, context.t('browser.dappsHttp')),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.95,
            children: kCuratedDapps
                .map((d) => _DappTile(entry: d, onTap: () => onOpen(d.url)))
                .toList(),
          ),
          _section(context, context.t('browser.dappsDeweb')),
          ...kFeaturedSites.map(
            (s) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.dns),
                title: Text(s.$1),
                subtitle: Text(
                  s.$2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => onOpen(s.$1),
              ),
            ),
          ),
          _section(context, context.t('browser.bookmarks')),
          if (bookmarks.isEmpty)
            Text(
              context.t('browser.noBookmarks'),
              style: const TextStyle(fontSize: 12),
            )
          else
            ...bookmarks.map(
              (b) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.star),
                  title: Text(b.name),
                  subtitle: Text(
                    b.url,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => onOpen(b.url),
                ),
              ),
            ),
          Row(
            children: [
              Expanded(child: _section(context, context.t('browser.history'))),
              if (history.isNotEmpty)
                TextButton.icon(
                  onPressed: onClearHistory,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: Text(
                    context.t('browser.clearHistory'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
          if (history.isEmpty)
            Text(
              context.t('browser.noHistory'),
              style: const TextStyle(fontSize: 12),
            )
          else
            ...history.map(
              (h) => ListTile(
                dense: true,
                leading: const Icon(Icons.history),
                title: Text(
                  h.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  h.url,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => onOpen(h.url),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            context.t('browser.securityHint'),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontSize: 11),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 0.5,
      ),
    ),
  );
}

/// Grid tile for a curated dApp.
class _DappTile extends StatelessWidget {
  final DappEntry entry;
  final VoidCallback onTap;

  const _DappTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Text(
                entry.name.isEmpty ? '?' : entry.name[0].toUpperCase(),
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
