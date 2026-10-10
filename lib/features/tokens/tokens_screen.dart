/// MRC-20 tokens: list, add custom tokens, balances and transfers.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/massa_rpc.dart';
import '../../core/contracts/mrc20_service.dart';
import '../../core/i18n/app_i18n.dart';
import '../../core/services/activity_history_service.dart';
import '../../core/services/settings_provider.dart';
import '../../core/services/wallet_provider.dart';
import '../../ui/theme.dart';

/// Persists the user's token list in SharedPreferences.
class TokenListStore {
  static const _kKey = 'wallet.tokens';

  /// Loads saved custom token addresses for [networkKey].
  Future<List<String>> load(String networkKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('$_kKey.$networkKey') ?? const [];
  }

  /// Saves [addresses] for [networkKey].
  Future<void> save(String networkKey, List<String> addresses) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('$_kKey.$networkKey', addresses);
  }
}

/// A row in the tokens list.
class _TokenRow {
  final Mrc20Token token;
  final BigInt balance;
  _TokenRow(this.token, this.balance);
}

/// Tokens screen.
class TokensScreen extends StatefulWidget {
  /// Creates the tokens screen.
  const TokensScreen({super.key});

  @override
  State<TokensScreen> createState() => _TokensScreenState();
}

class _TokensScreenState extends State<TokensScreen> {
  late final Mrc20Service _mrc20;
  final TokenListStore _store = TokenListStore();
  List<_TokenRow> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _mrc20 = Mrc20Service(
      clientFactory: () => MassaRpcClient(
        endpoint: context.read<SettingsProvider>().effectiveEndpoint,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final wallet = context.read<WalletProvider>();
    final settings = context.read<SettingsProvider>();
    final account = wallet.activeAccount;
    if (account == null) {
      setState(() {
        _loading = false;
        _rows = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final networkKey = settings.network == MassaNetwork.mainnet
          ? 'mainnet'
          : 'buildnet';
      final custom = await _store.load(networkKey);
      final registry = KnownTokens.mainnet.entries
          .where((e) => networkKey == 'mainnet')
          .map((e) => e.value)
          .toList();
      final known = KnownTokens.buildnet.entries
          .where((e) => networkKey == 'buildnet')
          .map((e) => e.value)
          .toList();
      final addresses = <String>{
        ...(networkKey == 'mainnet' ? registry : known),
        ...custom,
      }.toList();

      final rows = <_TokenRow>[];
      for (final addr in addresses) {
        try {
          final token = await _mrc20.loadToken(addr);
          final balance = await _mrc20.balanceOf(addr, account.address);
          rows.add(_TokenRow(token, balance));
        } on Exception {
          // Skip non-MRC20/broken entries.
        }
      }
      if (!mounted) return;
      setState(() => _rows = rows);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addToken() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.t('tokens.addTitle')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: ctx.t('tokens.addressLabel'),
            hintText: 'AS1…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.t('tokens.add')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final address = controller.text.trim();
    if (!address.startsWith('AS1')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t('tokens.invalidAddress'))),
      );
      return;
    }
    final settings = context.read<SettingsProvider>();
    final networkKey = settings.network == MassaNetwork.mainnet
        ? 'mainnet'
        : 'buildnet';
    try {
      // Validate by loading metadata.
      await _mrc20.loadToken(address);
      final saved = await _store.load(networkKey);
      if (!saved.contains(address)) {
        await _store.save(networkKey, [...saved, address]);
      }
      await _refresh();
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.t('tokens.loadFailed')}: $e')),
      );
    }
  }

  Future<void> _sendToken(_TokenRow row) async {
    final wallet = context.read<WalletProvider>();
    final account = wallet.activeAccount;
    if (account == null) return;

    final toCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${ctx.t('tokens.send')} ${row.token.symbol}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: toCtrl,
              decoration: InputDecoration(
                labelText: ctx.t('send.to'),
                hintText: 'AU1…',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: ctx.t('send.amount'),
                suffixText: row.token.symbol,
                helperText:
                    '${ctx.t('tokens.balance')}: ${row.token.formatAmount(row.balance)}',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.t('tokens.send')),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final to = toCtrl.text.trim();
    final amountStr = amountCtrl.text.trim().replaceAll(',', '.');
    final amountRaw = _parseTokenAmount(amountStr, row.token.decimals);
    if (!to.startsWith('AU1') && !to.startsWith('AS1')) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.t('send.invalidAddress'))));
      return;
    }
    if (amountRaw == null || amountRaw <= BigInt.zero) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.t('send.invalidAmount'))));
      return;
    }

    // Storage cost when the recipient has no balance entry yet.
    BigInt? coins;
    try {
      final hasEntry = await _mrc20.hasBalanceEntry(row.token.address, to);
      if (!hasEntry) {
        coins = Mrc20Service.balanceCreationCost(to);
      }
    } on Exception {
      // Keep coins null on lookup failure.
    }

    try {
      final res = await wallet.callSmartContract(
        fromAddress: account.address,
        target: row.token.address,
        function: 'transfer',
        parameter: Mrc20Service.transferArgs(to, amountRaw),
        maxGas: BigInt.from(10000000),
        coinsNano: coins,
        activityKind: ActivityKind.tokenTransfer,
        tokenSymbol: row.token.symbol,
        tokenAmount: row.token.formatAmount(amountRaw),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${context.t('send.success')}: ${row.token.symbol} · OP ${res.operationId.substring(0, 12)}…',
          ),
        ),
      );
      unawaited(_refresh());
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.t('send.failed')}: $e')),
      );
    }
  }

  BigInt? _parseTokenAmount(String input, int decimals) {
    final cleaned = input.trim();
    if (cleaned.isEmpty) return null;
    final parts = cleaned.split('.');
    if (parts.length > 2) return null;
    final intPart = parts[0].isEmpty ? '0' : parts[0];
    var fracPart = parts.length > 1 ? parts[1] : '';
    if (intPart.contains(RegExp(r'[^0-9]')) ||
        fracPart.contains(RegExp(r'[^0-9]'))) {
      return null;
    }
    if (fracPart.length > decimals) return null;
    fracPart = fracPart.padRight(decimals, '0');
    final combined = '$intPart$fracPart';
    return BigInt.tryParse(combined);
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    final account = wallet.activeAccount;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('tokens.title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: context.t('tokens.add'),
            onPressed: _addToken,
          ),
          IconButton(
            icon: wallet.loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: _buildBody(account?.address ?? ''),
    );
  }

  Widget _buildBody(String account) {
    if (account.isEmpty) {
      return Center(child: Text(context.t('wallet.empty.title')));
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.token_outlined,
              size: 56,
              color: Color(0xFF30363D),
            ),
            const SizedBox(height: 12),
            Text(context.t('tokens.empty')),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _addToken,
              icon: const Icon(Icons.add),
              label: Text(context.t('tokens.add')),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Card(
              color: const Color(0xFF2D1215),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFF85149),
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ..._rows.map(
            (r) => Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: MassaColors.teal.withValues(alpha: 0.15),
                  child: Text(
                    r.token.symbol.isNotEmpty
                        ? r.token.symbol.substring(0, 1)
                        : '?',
                    style: const TextStyle(color: MassaColors.teal),
                  ),
                ),
                title: Text(r.token.name),
                subtitle: Text(
                  '${r.token.symbol} · ${r.token.address.substring(0, 12)}…',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Text(
                  r.token.formatAmount(r.balance),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                onTap: () => _showTokenDetail(r),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.t('tokens.registryNote'),
            style: const TextStyle(
              fontSize: 11,
              color: MassaColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showTokenDetail(_TokenRow r) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${r.token.name} (${r.token.symbol})',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${ctx.t('tokens.balance')}: '
                '${r.token.formatAmount(r.balance)} ${r.token.symbol}',
              ),
              if (r.token.totalSupply != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${ctx.t('tokens.totalSupply')}: '
                  '${r.token.formatAmount(r.token.totalSupply!)}',
                ),
              ],
              const SizedBox(height: 4),
              Text('${ctx.t('tokens.decimals')}: ${r.token.decimals}'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      r.token.address,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: MassaColors.textSecondary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: r.token.address));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(content: Text(ctx.t('receive.copied'))),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _sendToken(r);
                },
                icon: const Icon(Icons.north_east),
                label: Text(ctx.t('tokens.send')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
