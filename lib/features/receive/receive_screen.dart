/// Receive screen: address + QR + buildnet faucet helper.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/api/faucet_client.dart';
import '../../core/api/massa_rpc.dart' show MassaNetwork;
import '../../core/i18n/app_i18n.dart';
import '../../core/services/settings_provider.dart';
import '../../core/services/wallet_provider.dart';
import '../../ui/widgets.dart';
import '../browser/dapp_browser_screen.dart';

/// Receive screen.
class ReceiveScreen extends StatefulWidget {
  /// Creates the screen.
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  bool _faucetBusy = false;

  Future<void> _requestFaucet() async {
    final wallet = context.read<WalletProvider>();
    final account = wallet.activeAccount;
    if (account == null) return;
    setState(() => _faucetBusy = true);
    FaucetResult result;
    try {
      result = await FaucetClient().fund(account.address);
    } finally {
      if (mounted) setState(() => _faucetBusy = false);
    }
    if (!mounted) return;
    if (result.status == FaucetStatus.accepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t('faucet.success')),
          backgroundColor: Colors.green,
        ),
      );
      // Balance may arrive quickly — refresh shortly after.
      Future.delayed(const Duration(seconds: 15), wallet.refreshBalances);
    } else {
      // The legacy HTTP faucet is offline (official docs route faucet
      // requests through the #buildnet-faucet Discord channel) — offer
      // the current options instead.
      await _showFaucetFallback(result.message);
    }
  }

  Future<void> _showFaucetFallback(String detail) async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sheetCtx.t('faucet.unavailable.title'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${sheetCtx.t('faucet.unavailable.body')}\n\n$detail',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.forum_outlined),
                title: Text(sheetCtx.t('faucet.open.discord')),
                subtitle: const Text('discord.gg/massa'),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  Navigator.of(sheetCtx).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DappBrowserScreen(
                        initialUrl: 'https://discord.gg/massa',
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(sheetCtx.t('faucet.open.docs')),
                subtitle: const Text('docs.massa.net › networks-faucets'),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  Navigator.of(sheetCtx).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DappBrowserScreen(
                        initialUrl:
                            'https://docs.massa.net/docs/build/networks-faucets/public-networks',
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    final settings = context.watch<SettingsProvider>();
    final account = wallet.activeAccount;
    final isBuildnet = settings.network == MassaNetwork.buildnet;

    return Scaffold(
      appBar: AppBar(title: Text(context.t('receive.title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (account == null)
              Center(child: Text(context.t('wallet.noAccounts')))
            else ...[
              Text(
                context.t('receive.hint'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: QrImageView(
                    data: account.address,
                    size: 220,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF0D1117),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF0D1117),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SectionHeader(title: context.t('wallet.address')),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      SelectableText(
                        account.address,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                      const SizedBox(height: 8),
                      AddressChip(address: account.address, truncate: false),
                    ],
                  ),
                ),
              ),
              if (isBuildnet) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _faucetBusy ? null : _requestFaucet,
                  icon: _faucetBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.water_drop_outlined),
                  label: Text(context.t('receive.faucet')),
                ),
                const SizedBox(height: 8),
                Text(
                  context.t('receive.faucet.hint'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
