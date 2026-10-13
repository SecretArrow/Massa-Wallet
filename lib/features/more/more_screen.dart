/// "More" tab: staking, tokens, contracts, node, settings — grouped.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/massa_rpc.dart' show MassaNetwork;
import '../../core/i18n/app_i18n.dart';
import '../../core/services/settings_provider.dart';
import '../../core/services/wallet_provider.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// More screen — the fourth tab of the bottom navigation.
class MoreScreen extends StatelessWidget {
  /// Creates the screen.
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    final settings = context.watch<SettingsProvider>();
    final account = wallet.activeAccount;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('more.title')),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (account != null) _AccountHeader(wallet: wallet),
          SectionHeader(title: context.t('more.section.earn')),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _MoreItem(
                  icon: Icons.stacked_bar_chart,
                  color: PyramidsColors.orange,
                  title: context.t('wallet.staking'),
                  subtitle: context.t('more.staking.sub'),
                  route: '/staking',
                ),
                const _Divider(),
                _MoreItem(
                  icon: Icons.schedule,
                  color: const Color(0xFFA371F7),
                  title: context.t('deferred.title'),
                  subtitle: context.t('more.deferred.sub'),
                  route: '/deferred',
                ),
              ],
            ),
          ),
          SectionHeader(title: context.t('more.section.assets')),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _MoreItem(
                  icon: Icons.token,
                  color: PyramidsColors.brand,
                  title: context.t('wallet.tokens'),
                  subtitle: context.t('more.tokens.sub'),
                  route: '/tokens',
                ),
                const _Divider(),
                _MoreItem(
                  icon: Icons.code,
                  color: const Color(0xFF58A6FF),
                  title: context.t('wallet.contracts'),
                  subtitle: context.t('more.contracts.sub'),
                  route: '/contracts',
                ),
                const _Divider(),
                _MoreItem(
                  icon: Icons.import_contacts,
                  color: PyramidsColors.green,
                  title: context.t('wallet.addressBook'),
                  subtitle: context.t('more.contacts.sub'),
                  route: '/addressBook',
                ),
              ],
            ),
          ),
          SectionHeader(title: context.t('more.section.system')),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _MoreItem(
                  icon: Icons.dns_outlined,
                  color: const Color(0xFF58A6FF),
                  title: context.t('node.title'),
                  subtitle: context.t('more.node.sub'),
                  route: '/node',
                ),
                const _Divider(),
                _MoreItem(
                  icon: Icons.settings_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  title: context.t('wallet.settings'),
                  subtitle: context.t('more.settings.sub'),
                  route: '/settings',
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _NetworkFooter(settings: settings),
        ],
      ),
    );
  }
}

/// Gradient header card showing the active account at a glance.
class _AccountHeader extends StatelessWidget {
  final WalletProvider wallet;

  const _AccountHeader({required this.wallet});

  @override
  Widget build(BuildContext context) {
    final account = wallet.activeAccount!;
    final name = account.nickname.isEmpty
        ? '${account.address.substring(0, 8)}…'
              '${account.address.substring(account.address.length - 6)}'
        : account.nickname;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(20)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [PyramidsColors.deepBrand, PyramidsColors.brandLight],
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            child: const Icon(
              Icons.account_balance_wallet,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${account.address.substring(0, 10)}…',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                wallet.balanceOf(account.address) == null
                    ? '—'
                    : wallet.formatBalance(account.address, decimals: 2),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              Text(
                'MAS',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One row of a More section card.
class _MoreItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String route;

  const _MoreItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(icon, size: 20, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        size: 20,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onTap: () => Navigator.of(context).pushNamed(route),
    );
  }
}

/// Hairline between rows inside a section card.
class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    indent: 68,
    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
  );
}

/// Small version + network footer at the bottom of the More tab.
class _NetworkFooter extends StatelessWidget {
  final SettingsProvider settings;

  const _NetworkFooter({required this.settings});

  @override
  Widget build(BuildContext context) {
    final isMainnet = settings.network == MassaNetwork.mainnet;
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.shield_outlined,
            size: 14,
            color: PyramidsColors.brand,
          ),
          const SizedBox(width: 6),
          Text(
            'Pyramids Wallet · ${settings.network.name.toUpperCase()}',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (isMainnet) ...[
            const SizedBox(width: 6),
            const Icon(
              Icons.verified_outlined,
              size: 14,
              color: PyramidsColors.green,
            ),
          ],
        ],
      ),
    );
  }
}
