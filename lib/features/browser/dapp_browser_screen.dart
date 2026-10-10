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
import '../../core/i18n/app_i18n.dart';
import '../../core/services/settings_provider.dart';
import '../../core/services/wallet_provider.dart';
import '../../ui/theme.dart';

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

  @override
  void initState() {
    super.initState();
    _settings = context.read<SettingsProvider>();
    _mns = MnsService(
      clientFactory: () => MassaRpcClient(endpoint: _settings!.effectiveEndpoint),
    );
    _deweb = DeWebService(
      clientFactory: () => MassaRpcClient(endpoint: _settings!.effectiveEndpoint),
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
              content: Text(
                context.t('browser.notSite', args: [res.target]),
              ),
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
      await _controller.loadRequest(Uri.parse(localUrl));
      setState(() => _currentUrl = _resolvedDomain != null
          ? '$_resolvedDomain.massa'
          : sc);
    } on MnsException catch (e) {
      _showError(e.message);
    } on DeWebException catch (e) {
      _showError(e.message);
    } on Exception catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _loadHome() async {
    setState(() {
      _loading = false;
      _currentUrl = '';
      _currentTitle = '';
      _resolvedSite = null;
      _resolvedDomain = null;
    });
    setState(() => _loading = false);
    await _controller.loadHtmlString(_homeHtml());
  }

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
    if (parsed.domain != null &&
        !url.startsWith('http') ||
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
      final result = await _handleWeb3(req, wallet, settings, account?.address ?? '');
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
          {'address': a.address, 'name': a.nickname.isEmpty ? 'Massa Wallet' : a.nickname},
        ];
      case 'accounts':
        final a = wallet.activeAccount;
        if (a == null) return [];
        return [
          {'address': a.address, 'name': a.nickname.isEmpty ? 'Massa Wallet' : a.nickname},
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
        final ok = await _confirmSign(
          title: context.t('web3.signOpTitle'),
          body: data,
        );
        if (!ok) throw Exception(context.t('web3.rejected'));
        return _signMessage(data);
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
            req.method == 'buyRolls' ? 'web3.buyRollsTitle' : 'web3.sellRollsTitle',
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
    const alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
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

  String _originLabel() =>
      _resolvedDomain != null ? '${_resolvedDomain!}.massa' : (_currentTitle.isEmpty ? _currentUrl : _currentTitle);

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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _homeHtml() {
    final featured = kFeaturedSites
        .map(
          (s) => '<button onclick="location.href=\'massa://${s.$1}\'">'
              '<b>${s.$1}</b><span>${s.$2}</span></button>',
        )
        .join();
    final t = (String k, [List<String> a = const []]) => context.t(k, args: a);
    return '''<!DOCTYPE html>
<html><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>${t('browser.homeTitle')}</title>
<style>
  body{background:#0d1117;color:#e6edf3;font-family:-apple-system,sans-serif;padding:24px;margin:0}
  h1{font-size:22px;margin:0 0 4px}
  p.sub{color:#8b949e;margin:0 0 20px;font-size:13px}
  button{display:block;width:100%;text-align:left;background:#161b22;color:#e6edf3;
    border:1px solid #21262d;border-radius:14px;padding:14px 16px;margin-bottom:10px;cursor:pointer}
  button b{display:block;color:#18c8c8;font-size:15px;margin-bottom:2px}
  button span{color:#8b949e;font-size:12px}
  .hint{background:#161b22;border:1px solid #21262d;border-radius:14px;padding:14px;
    font-size:12px;color:#8b949e;margin-top:16px;line-height:1.5}
  code{color:#18c8c8}
</style></head><body>
<h1>${t('browser.homeTitle')}</h1>
<p class="sub">${t('browser.homeSub')}</p>
$featured
<div class="hint">${t('browser.homeHint')}<br/><code>window.massa.enable()</code></div>
</body></html>''';
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
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
          Expanded(child: WebViewWidget(controller: _controller)),
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
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 12),
              Text(
                '${ctx.t('browser.domain')}: ${_resolvedDomain ?? '-'}',
              ),
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
                style: const TextStyle(fontSize: 12, color: MassaColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
