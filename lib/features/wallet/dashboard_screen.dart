/// Main dashboard: balance, quick actions, account switcher.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/massa_amount.dart' show formatNano;
import '../../core/api/massa_rpc.dart' show MassaNetwork;
import '../../core/i18n/app_i18n.dart';
import '../../core/services/activity_history_service.dart';
import '../../core/services/embedded_node_service.dart';
import '../../core/services/price_service.dart';
import '../../core/services/settings_provider.dart';
import '../../core/services/wallet_provider.dart';
import '../../ui/home_shell.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Dashboard screen.
class DashboardScreen extends StatefulWidget {
  /// Creates the screen.
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final PriceService _price = PriceService();
  List<Activity> _recent = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WalletProvider>().refreshBalances();
      _loadPrice();
      _loadRecent();
    });
  }

  Future<void> _loadPrice() async {
    await _price.fetch();
    if (mounted) setState(() {});
  }

  Future<void> _loadRecent() async {
    final wallet = context.read<WalletProvider>();
    final account = wallet.activeAccount;
    final items = await wallet.history.load(accountAddress: account?.address);
    if (!mounted) return;
    setState(() => _recent = items.take(3).toList());
  }

  /// Jumps to the History tab inside the shell (falls back to a pushed
  /// route when the dashboard is displayed outside the shell).
  void _openHistory(BuildContext context) {
    HomeTabs.maybeOf(context)?.goTo(1);
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    final settings = context.watch<SettingsProvider>();
    final account = wallet.activeAccount;

    if (account == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.account_balance_wallet,
                size: 64,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              const SizedBox(height: 16),
              Text(
                context.t('wallet.empty.title'),
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                context.t('wallet.empty.body'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pushNamed('/onboarding'),
                child: Text(context.t('onboarding.create')),
              ),
            ],
          ),
        ),
      );
    }

    final balance = wallet.balanceOf(account.address);
    final rolls = balance?.rolls ?? BigInt.zero;

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => _showAccountSheet(context, wallet),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  account.nickname.isEmpty
                      ? _shortAddr(account.address)
                      : account.nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.keyboard_arrow_down),
            ],
          ),
        ),
        actions: [
          IconButton(
            onPressed: wallet.loading
                ? null
                : () => context.read<WalletProvider>().refreshBalances(),
            icon: wallet.loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
        backgroundColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<WalletProvider>().refreshBalances(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            // Embedded-node offline banner (only in embedded mode).
            _EmbeddedNodeBanner(settings: settings),
            BalanceCard(
              balance: wallet.formatBalance(account.address),
              hidden: settings.hideBalances,
              candidateBalance: balance == null
                  ? null
                  : '${context.t('wallet.candidate')}: '
                        '${wallet.formatBalance(account.address)}',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                AddressChip(address: account.address),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: settings.network == MassaNetwork.mainnet
                        ? PyramidsColors.orange
                        : Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    settings.network.name,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                if (account.isWatchOnly) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: PyramidsColors.brand.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.visibility,
                          size: 12,
                          color: PyramidsColors.brand,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          context.t('wallet.watchOnly.short'),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            _PriceTicker(price: _price.cached, onRetry: _loadPrice),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 0.82,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                ActionTile(
                  icon: Icons.north_east,
                  label: context.t('wallet.send'),
                  onTap: () => Navigator.of(context).pushNamed('/send'),
                ),
                ActionTile(
                  icon: Icons.south_west,
                  label: context.t('wallet.receive'),
                  onTap: () => Navigator.of(context).pushNamed('/receive'),
                  color: const Color(0xFF3FB950),
                ),
                ActionTile(
                  icon: Icons.stacked_bar_chart,
                  label: context.t('wallet.staking'),
                  onTap: () => Navigator.of(context).pushNamed('/staking'),
                  color: const Color(0xFFF0883E),
                ),
                ActionTile(
                  icon: Icons.token,
                  label: context.t('wallet.tokens'),
                  onTap: () => Navigator.of(context).pushNamed('/tokens'),
                ),
              ],
            ),
            // Recent activity preview → full list lives in the History tab.
            _RecentActivitySection(
              items: _recent,
              onViewAll: () => _openHistory(context),
            ),
            SectionHeader(title: context.t('wallet.rolls')),
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.stacked_bar_chart,
                  color: Color(0xFFF0883E),
                ),
                title: Text('$rolls'),
                subtitle: Text(context.t('staking.rollCost')),
                trailing: TextButton(
                  onPressed: () => Navigator.of(context).pushNamed('/staking'),
                  child: Text(context.t('wallet.staking')),
                ),
              ),
            ),
            SectionHeader(title: context.t('wallet.accounts')),
            ...wallet.accounts.map(
              (a) => Card(
                child: ListTile(
                  leading: Icon(
                    a.isWatchOnly
                        ? Icons.visibility
                        : a.isActive
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: a.isActive
                        ? PyramidsColors.brand
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  title: Text(
                    a.nickname.isEmpty ? _shortAddr(a.address) : a.nickname,
                  ),
                  subtitle: Text(
                    _shortAddr(a.address),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (a.isWatchOnly)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(
                            Icons.remove_red_eye_outlined,
                            size: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      Text(
                        wallet.balanceOf(a.address) == null
                            ? '—'
                            : '${wallet.formatBalance(a.address, decimals: 2)} MAS',
                      ),
                    ],
                  ),
                  onTap: () {
                    context
                        .read<WalletProvider>()
                        .setActive(a.address)
                        .then(
                          (_) =>
                              context.read<WalletProvider>().refreshBalances(),
                        );
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pushNamed('/import'),
              icon: const Icon(Icons.add),
              label: Text(context.t('wallet.addAccount')),
            ),
            if (wallet.lastError != null) ...[
              const SizedBox(height: 16),
              Card(
                color: const Color(0xFF2D1215),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFF85149)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          wallet.lastError!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFF85149),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _shortAddr(String a) =>
      '${a.substring(0, 8)}…${a.substring(a.length - 6)}';

  void _showAccountSheet(BuildContext context, WalletProvider wallet) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              sheetCtx.t('wallet.accounts'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ...wallet.accounts.map(
              (a) => ListTile(
                leading: const Icon(
                  Icons.account_circle,
                  color: PyramidsColors.brand,
                ),
                title: Text(
                  a.nickname.isEmpty ? _shortAddr(a.address) : a.nickname,
                ),
                subtitle: Text(_shortAddr(a.address)),
                trailing: a.isActive
                    ? Chip(
                        label: Text(sheetCtx.t('wallet.active')),
                        backgroundColor: PyramidsColors.brand.withValues(
                          alpha: 0.15,
                        ),
                      )
                    : null,
                onTap: () {
                  sheetCtx
                      .read<WalletProvider>()
                      .setActive(a.address)
                      .then(
                        (_) =>
                            sheetCtx.read<WalletProvider>().refreshBalances(),
                      );
                  Navigator.of(sheetCtx).pop();
                },
              ),
            ),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(sheetCtx).pop();
                Navigator.of(context).pushNamed('/import');
              },
              icon: const Icon(Icons.add),
              label: Text(sheetCtx.t('wallet.addAccount')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact last-3-activity preview on the dashboard.
class _RecentActivitySection extends StatelessWidget {
  final List<Activity> items;
  final VoidCallback onViewAll;

  const _RecentActivitySection({required this.items, required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.t('wallet.recentActivity'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onViewAll,
                child: Text(
                  context.t('wallet.viewAll'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (items.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.t('history.empty'),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...items.map((a) => _RecentTile(item: a)),
      ],
    );
  }
}

/// One compact activity row in the dashboard preview.
class _RecentTile extends StatelessWidget {
  final Activity item;

  const _RecentTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = _kindInfo(context);
    final amount = _amountLabel();
    return Card(
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, size: 16, color: color),
        ),
        title: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Text(
          _timeLabel(),
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: amount.isEmpty
            ? null
            : Text(
                amount,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: item.status == ActivityStatus.failed
                      ? PyramidsColors.error
                      : null,
                ),
              ),
      ),
    );
  }

  (IconData, Color, String) _kindInfo(BuildContext context) =>
      switch (item.kind) {
        ActivityKind.send => (
          Icons.north_east,
          PyramidsColors.orange,
          context.t('history.sent'),
        ),
        ActivityKind.receive => (
          Icons.south_west,
          PyramidsColors.green,
          context.t('history.received'),
        ),
        ActivityKind.rollBuy => (
          Icons.stacked_bar_chart,
          PyramidsColors.brand,
          context.t('history.rollBuy'),
        ),
        ActivityKind.rollSell => (
          Icons.south,
          PyramidsColors.brand,
          context.t('history.rollSell'),
        ),
        ActivityKind.callSC => (
          Icons.code,
          PyramidsColors.deepBrand,
          context.t('history.call'),
        ),
        ActivityKind.tokenTransfer => (
          Icons.token,
          PyramidsColors.deepBrand,
          context.t('history.token'),
        ),
        ActivityKind.dapp => (
          Icons.public,
          PyramidsColors.deepBrand,
          context.t('history.dapp'),
        ),
      };

  String _amountLabel() {
    switch (item.kind) {
      case ActivityKind.tokenTransfer:
        return item.tokenAmount == null
            ? ''
            : '${item.tokenAmount} ${item.tokenSymbol ?? ''}';
      case ActivityKind.rollBuy:
      case ActivityKind.rollSell:
        return '';
      default:
        if (item.amountNano == BigInt.zero) return '';
        return '${formatNano(item.amountNano, decimals: 4)} MAS';
    }
  }

  String _timeLabel() {
    final local = item.createdAt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

/// Compact MAS price ticker (CoinGecko, offline-tolerant).
class _PriceTicker extends StatelessWidget {
  final MasPrice? price;
  final VoidCallback onRetry;

  const _PriceTicker({required this.price, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    if (!settings.showFiat || price == null) {
      return const SizedBox.shrink();
    }
    final isId = settings.language.code == 'id';
    final value = isId ? price!.idr : price!.usd;
    final symbol = isId ? 'Rp' : '\$';
    final change = price!.change24h;
    final changeColor = change >= 0
        ? const Color(0xFF3FB950)
        : const Color(0xFFF85149);
    final changeSign = change >= 0 ? '+' : '';
    final currencyLabel = isId ? 'IDR' : 'USD';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Card(
        child: ListTile(
          dense: true,
          leading: const Icon(
            Icons.currency_exchange,
            color: PyramidsColors.brand,
          ),
          title: Text(
            '$symbol${_formatNumber(value)} $currencyLabel',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${context.t('price.masPrice')} · '
            '$changeSign${change.toStringAsFixed(2)}% 24h',
            style: const TextStyle(fontSize: 11),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                change >= 0 ? Icons.trending_up : Icons.trending_down,
                color: changeColor,
                size: 16,
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 16),
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatNumber(double v) {
    if (v >= 1000) return v.toStringAsFixed(0);
    if (v >= 1) return v.toStringAsFixed(2);
    return v.toStringAsFixed(v < 0.01 ? 6 : 4);
  }
}

/// Amber banner shown when the wallet is in embedded-node mode but the
/// in-app node is not running. Tapping it opens the node screen.
class _EmbeddedNodeBanner extends StatelessWidget {
  final SettingsProvider settings;
  const _EmbeddedNodeBanner({required this.settings});

  @override
  Widget build(BuildContext context) {
    if (settings.connectionMode != NodeConnectionMode.embedded) {
      return const SizedBox.shrink();
    }
    final node = context.watch<EmbeddedNodeService>();
    final ok =
        node.state == EmbeddedNodeState.running && settings.embeddedUsable;
    if (ok) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).pushNamed('/node'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Icons.dns_outlined,
                  color: Theme.of(context).colorScheme.onTertiaryContainer,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.t('dashboard.nodeOffline'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
