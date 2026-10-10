/// Staking screen: buy/sell rolls, cycle info, auto-compound.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/massa_amount.dart';
import '../../core/i18n/app_i18n.dart';
import '../../ui/theme.dart';
import '../../core/services/auto_compound_service.dart';
import '../../core/services/settings_provider.dart';
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
  String? _acStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAcStatus());
  }

  Future<void> _loadAcStatus() async {
    // Reads last auto-compound record for the status line.
    try {
      final wallet = context.read<WalletProvider>();
      final outcome = await wallet.runAutoCompound();
      if (!mounted) return;
      setState(() {
        _acStatus = _describeOutcome(outcome);
      });
    } on Exception {
      // Status line is best-effort.
    }
  }

  String _describeOutcome(AutoCompoundOutcome o) {
    switch (o.action) {
      case AutoCompoundAction.disabled:
        return context.t('ac.status.disabled');
      case AutoCompoundAction.sameCycle:
        return context.t('ac.status.waiting', args: ['${o.cycle ?? '—'}']);
      case AutoCompoundAction.nothingToReinvest:
        return context.t('ac.status.nothing');
      case AutoCompoundAction.bought:
        return context.t(
          'ac.status.bought',
          args: ['${o.rollsBought}', '${o.cycle ?? '—'}'],
        );
      case AutoCompoundAction.failed:
        return context.t('ac.status.failed', args: [o.detail ?? '?']);
    }
  }

  Future<void> _toggleAutoCompound(bool v) async {
    final wallet = context.read<WalletProvider>();
    final account = wallet.activeAccount;
    if (v && account != null && account.isWatchOnly) {
      setState(() {
        _isError = true;
        _message = context.t('wallet.watchOnly');
      });
      return;
    }
    await context.read<SettingsProvider>().setAutoCompound(v);
    if (v) {
      // Evaluate immediately so the user sees the current decision.
      try {
        final outcome = await wallet.runAutoCompound();
        if (mounted) setState(() => _acStatus = _describeOutcome(outcome));
      } on Exception {
        // best-effort
      }
    }
    if (mounted) setState(() {});
  }

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

  /// Reserved balance (1 MAS) used as the auto-compound fee buffer.
  static final BigInt _acReserve = BigInt.from(1000000000);

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    final settings = context.watch<SettingsProvider>();
    final account = wallet.activeAccount;
    final balance = account == null ? null : wallet.balanceOf(account.address);
    final rolls = balance?.rolls ?? BigInt.zero;

    // Whole rolls the auto-compound would buy right now.
    final acSurplus = (balance?.finalBalance ?? BigInt.zero) - _acReserve;
    final acPotential = acSurplus > BigInt.zero
        ? acSurplus ~/ BigInt.from(rollPriceNano)
        : BigInt.zero;

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
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
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
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                    const Icon(Icons.info_outline, color: PyramidsColors.brand),
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

            // ── Auto-compound ──────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.autorenew, color: Color(0xFF3FB950)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.t('ac.title'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Switch(
                          value: settings.autoCompoundEnabled,
                          onChanged: _toggleAutoCompound,
                          activeThumbColor: const Color(0xFF3FB950),
                        ),
                      ],
                    ),
                    Text(
                      context.t('ac.body'),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.t(
                        'ac.potential',
                        args: ['$acPotential', nanoToMas(_acReserve)],
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (_acStatus != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _acStatus!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: PyramidsColors.brand,
                        ),
                      ),
                    ],
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
