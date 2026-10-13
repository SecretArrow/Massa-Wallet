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
  bool _acBusy = false;

  /// Fee reserve the auto-compound keeps (loaded from the service).
  BigInt _acReserveNano = BigInt.from(1000000000);

  /// Recent auto-compound actions (newest first).
  List<AutoCompoundRecord> _acHistory = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAcStatus());
  }

  Future<void> _loadAcStatus() async {
    // Reads the last auto-compound record for the status line.
    try {
      final wallet = context.read<WalletProvider>();
      final outcome = await wallet.runAutoCompound();
      final reserve = await wallet.autoCompoundReserve();
      final history = await wallet.autoCompoundHistory();
      if (!mounted) return;
      setState(() {
        _acStatus = _describeOutcome(outcome);
        _acReserveNano = reserve;
        _acHistory = history;
      });
    } on Exception {
      // Status line is best-effort.
    }
  }

  /// Manual mid-cycle compounding (bypasses the cycle watermark).
  Future<void> _compoundNow() async {
    final wallet = context.read<WalletProvider>();
    final account = wallet.activeAccount;
    if (account == null) return;
    if (account.isWatchOnly) {
      setState(() {
        _isError = true;
        _message = context.t('wallet.watchOnly');
      });
      return;
    }
    setState(() => _acBusy = true);
    try {
      final outcome = await wallet.runAutoCompound(force: true);
      final history = await wallet.autoCompoundHistory();
      if (!mounted) return;
      setState(() {
        _acStatus = _describeOutcome(outcome);
        _acHistory = history;
      });
    } on Exception catch (e) {
      if (mounted) setState(() => _acStatus = e.toString());
    } finally {
      if (mounted) setState(() => _acBusy = false);
    }
  }

  /// Edits the auto-compound fee reserve (kept out of reinvestment).
  Future<void> _editReserve() async {
    final wallet = context.read<WalletProvider>();
    final ctrl = TextEditingController(text: nanoToMas(_acReserveNano));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.t('ac.reserve')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: ctx.t('ac.reserve'),
            helperText: ctx.t('ac.reserveHint'),
            suffixText: 'MAS',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.t('common.save')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final nano = parseUserAmount(ctrl.text);
      if (nano < BigInt.zero) throw const FormatException('negative');
      await wallet.setAutoCompoundReserve(nano);
      final history = await wallet.autoCompoundHistory();
      if (!mounted) return;
      setState(() {
        _acReserveNano = nano;
        _acHistory = history;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t('ac.reserveSaved'))),
      );
    } on FormatException {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t('send.invalidAmount'))),
      );
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

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    final settings = context.watch<SettingsProvider>();
    final account = wallet.activeAccount;
    final balance = account == null ? null : wallet.balanceOf(account.address);
    final rolls = balance?.rolls ?? BigInt.zero;

    // Whole rolls the auto-compound would buy right now.
    final acSurplus = (balance?.finalBalance ?? BigInt.zero) - _acReserveNano;
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
                    const Icon(Icons.info_outline, color: PineColors.brand),
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
                        args: ['$acPotential', nanoToMas(_acReserveNano)],
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _editReserve,
                        icon: const Icon(Icons.savings_outlined, size: 16),
                        label: Text(
                          '${context.t('ac.reserve')}: ${nanoToMas(_acReserveNano)} MAS',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    if (_acStatus != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _acStatus!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: PineColors.brand,
                        ),
                      ),
                    ],
                    if (settings.autoCompoundEnabled) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _acBusy ? null : _compoundNow,
                        icon: _acBusy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.bolt, size: 16),
                        label: Text(context.t('ac.now')),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Auto-compound history ────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.history, color: Color(0xFF3FB950)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.t('ac.history'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_acHistory.isEmpty)
                      Text(
                        context.t('ac.history.empty'),
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      ..._acHistory.take(5).map(_historyRow),
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

  /// One history entry row.
  Widget _historyRow(AutoCompoundRecord r) {
    final (icon, color, label) = switch (r.action) {
      AutoCompoundAction.bought => (
        Icons.check_circle,
        const Color(0xFF3FB950),
        context.t('ac.action.bought', args: ['${r.rolls}']),
      ),
      AutoCompoundAction.nothingToReinvest => (
        Icons.pause_circle_outline,
        const Color(0xFF8B949E),
        context.t('ac.action.nothing'),
      ),
      _ => (
        Icons.error_outline,
        const Color(0xFFF85149),
        context.t('ac.action.failed'),
      ),
    };
    final when = r.at.toLocal();
    final stamp =
        '${when.year.toString().padLeft(4, '0')}-'
        '${when.month.toString().padLeft(2, '0')}-'
        '${when.day.toString().padLeft(2, '0')} '
        '${when.hour.toString().padLeft(2, '0')}:'
        '${when.minute.toString().padLeft(2, '0')}';
    final sub = StringBuffer('cycle ${r.cycle ?? '—'} · $stamp');
    if (r.detail != null && r.detail!.isNotEmpty) {
      sub.write(' · ${r.detail}');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 13)),
                Text(
                  sub.toString(),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
