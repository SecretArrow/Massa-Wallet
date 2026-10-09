/// Main dashboard: balance, quick actions, account switcher.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/massa_rpc.dart' show MassaNetwork;
import '../../core/i18n/app_i18n.dart';
import '../../core/services/settings_provider.dart';
import '../../core/services/wallet_provider.dart';
import '../../ui/widgets.dart';

/// Dashboard screen.
class DashboardScreen extends StatefulWidget {
  /// Creates the screen.
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WalletProvider>().refreshBalances();
    });
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
              const Icon(
                Icons.account_balance_wallet,
                size: 64,
                color: Color(0xFF30363D),
              ),
              const SizedBox(height: 16),
              Text(
                context.t('wallet.empty.title'),
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                context.t('wallet.empty.body'),
                style: const TextStyle(color: Color(0xFF8B949E)),
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
              Text(
                account.nickname.isEmpty
                    ? _shortAddr(account.address)
                    : account.nickname,
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
          IconButton(
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
            icon: const Icon(Icons.settings_outlined),
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
                        ? const Color(0xFFF0883E)
                        : const Color(0xFF1C2330),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    settings.network.name,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
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
                  icon: Icons.code,
                  label: context.t('wallet.contracts'),
                  onTap: () => Navigator.of(context).pushNamed('/contracts'),
                  color: const Color(0xFFA371F7),
                ),
              ],
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
                    a.isActive
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: a.isActive
                        ? const Color(0xFF18C8C8)
                        : const Color(0xFF8B949E),
                  ),
                  title: Text(
                    a.nickname.isEmpty ? _shortAddr(a.address) : a.nickname,
                  ),
                  subtitle: Text(
                    _shortAddr(a.address),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  trailing: Text(
                    wallet.balanceOf(a.address) == null
                        ? '—'
                        : '${wallet.formatBalance(a.address, decimals: 2)} MAS',
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
      backgroundColor: const Color(0xFF1C2330),
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
                  color: Color(0xFF18C8C8),
                ),
                title: Text(
                  a.nickname.isEmpty ? _shortAddr(a.address) : a.nickname,
                ),
                subtitle: Text(_shortAddr(a.address)),
                trailing: a.isActive
                    ? Chip(
                        label: Text(sheetCtx.t('wallet.active')),
                        backgroundColor: const Color(
                          0xFF18C8C8,
                        ).withValues(alpha: 0.15),
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
