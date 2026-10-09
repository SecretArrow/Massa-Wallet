/// Staking screen: buy/sell rolls, cycle info.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/app_i18n.dart';
import '../../core/services/wallet_provider.dart';

/// Staking screen.
class StakingScreen extends StatefulWidget {
  /// Creates the screen.
  const StakingScreen({super.key});

  @override
  State<StakingScreen> createState() => _StakingScreenState();
}

class _StakingScreenState extends State<StakingScreen> {
  final _rollCount = TextEditingController(text: '1');
  bool _busy = false;
  String? _message;
  bool _isError = false;

  @override
  void dispose() {
    _rollCount.dispose();
    super.dispose();
  }

  Future<void> _submit(bool buy) async {
    final wallet = context.read<WalletProvider>();
    final account = wallet.activeAccount;
    if (account == null) return;
    final count = int.tryParse(_rollCount.text) ?? 0;
    if (count <= 0) {
      setState(() {
        _isError = true;
        _message = context.t('send.invalidAmount');
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = buy
          ? await wallet.buyRolls(
              fromAddress: account.address,
              rollCount: count,
            )
          : await wallet.sellRolls(
              fromAddress: account.address,
              rollCount: count,
            );
      setState(() {
        _message = '${context.t('send.success')} · ${result.operationId}';
        _isError = false;
      });
      await wallet.refreshBalances();
    } catch (e) {
      setState(() {
        _message = e.toString();
        _isError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    final account = wallet.activeAccount;
    final balance = account == null ? null : wallet.balanceOf(account.address);
    final rolls = balance?.rolls ?? BigInt.zero;

    return Scaffold(
      appBar: AppBar(title: Text(context.t('staking.title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      context.t('staking.activeRolls'),
                      style: const TextStyle(color: Color(0xFF8B949E)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$rolls',
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.t('staking.rollCost'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8B949E),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFF18C8C8)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.t('staking.info'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _rollCount,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.t('staking.rollCount'),
                suffixText: context.t('staking.rolls'),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : () => _submit(true),
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.t('staking.buy')),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy ? null : () => _submit(false),
              child: Text(context.t('staking.sell')),
            ),
            if (_message != null) ...[
              const SizedBox(height: 16),
              Card(
                color: _isError
                    ? const Color(0xFF2D1215)
                    : const Color(0xFF12261A),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    _message!,
                    style: TextStyle(
                      fontSize: 12,
                      color: _isError
                          ? const Color(0xFFF85149)
                          : const Color(0xFF3FB950),
                    ),
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
