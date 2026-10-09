/// Receive screen: address + QR.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/i18n/app_i18n.dart';
import '../../core/services/wallet_provider.dart';
import '../../ui/widgets.dart';

/// Receive screen.
class ReceiveScreen extends StatelessWidget {
  /// Creates the screen.
  const ReceiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    final account = wallet.activeAccount;

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
                style: const TextStyle(color: Color(0xFF8B949E)),
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
            ],
          ],
        ),
      ),
    );
  }
}
