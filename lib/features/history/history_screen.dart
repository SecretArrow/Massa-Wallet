/// Activity history screen (local operation log with on-chain status sync).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/massa_amount.dart';
import '../../core/api/massa_rpc.dart';
import '../../core/i18n/app_i18n.dart';
import '../../core/services/activity_history_service.dart';
import '../../core/services/settings_provider.dart';
import '../../core/services/wallet_provider.dart';
import '../../ui/theme.dart';

/// History screen.
class HistoryScreen extends StatefulWidget {
  /// Creates the screen.
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Activity> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final wallet = context.read<WalletProvider>();
    final account = wallet.activeAccount;
    final items = await wallet.history.load(accountAddress: account?.address);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
    // Best-effort status refresh for submitted ops.
    unawaited(_refreshStatuses());
  }

  Future<void> _refreshStatuses() async {
    final settings = context.read<SettingsProvider>();
    final pending = _items
        .where((a) => a.status == ActivityStatus.submitted && a.operationId != null)
        .toList();
    if (pending.isEmpty) return;
    final client = MassaRpcClient(endpoint: settings.effectiveEndpoint);
    final wallet = context.read<WalletProvider>();
    try {
      for (final a in pending) {
        try {
          final infos = await client.getOperations([a.operationId!]);
          if (infos.isEmpty) continue;
          final info = infos.first;
          if (info.error != null && info.error!.isNotEmpty) {
            await wallet.history.updateStatus(a.id, ActivityStatus.failed);
          } else if (info.inFinalBlock == true) {
            await wallet.history.updateStatus(a.id, ActivityStatus.final_);
          }
        } on Exception {
          // Skip this op.
        }
      }
      if (!mounted) return;
      final account = context.read<WalletProvider>().activeAccount;
      final items = await wallet.history.load(accountAddress: account?.address);
      if (mounted) setState(() => _items = items);
    } finally {
      client.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('history.title')),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: context.t('history.clear'),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(ctx.t('history.clear')),
                    content: Text(ctx.t('history.clearBody')),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(ctx.t('common.cancel')),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(ctx.t('history.clear')),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await context.read<WalletProvider>().history.clear();
                  await _load();
                }
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.receipt_long_outlined,
                        size: 56,
                        color: Color(0xFF30363D),
                      ),
                      const SizedBox(height: 12),
                      Text(context.t('history.empty')),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          context.t('history.emptyNote'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: MassaColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (ctx, i) => _ActivityCard(item: _items[i]),
                  ),
                ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final Activity item;

  const _ActivityCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = _kindInfo(context);
    final amount = _amountLabel();
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(label, style: const TextStyle(fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.counterparty.isNotEmpty)
              Text(
                _short(item.counterparty),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            Text(
              _timeLabel(context),
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (amount.isNotEmpty)
              Text(
                amount,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: item.kind == ActivityKind.rollBuy ||
                          item.kind == ActivityKind.send
                      ? color
                      : null,
                ),
              ),
            _statusChip(context),
          ],
        ),
      ),
    );
  }

  (IconData, Color, String) _kindInfo(BuildContext context) {
    switch (item.kind) {
      case ActivityKind.send:
        return (Icons.north_east, MassaColors.orange, context.t('history.sent'));
      case ActivityKind.receive:
        return (
          Icons.south_west,
          MassaColors.green,
          context.t('history.received')
        );
      case ActivityKind.rollBuy:
        return (
          Icons.stacked_bar_chart,
          MassaColors.teal,
          context.t('history.rollBuy')
        );
      case ActivityKind.rollSell:
        return (
          Icons.south,
          MassaColors.teal,
          context.t('history.rollSell')
        );
      case ActivityKind.callSC:
        return (
          Icons.code,
          MassaColors.deepTeal,
          item.function?.isNotEmpty == true
              ? '${context.t('history.call')}: ${item.function}'
              : context.t('history.call')
        );
      case ActivityKind.tokenTransfer:
        return (
          Icons.token,
          MassaColors.deepTeal,
          '${context.t('history.token')} ${item.tokenSymbol ?? ''}'
        );
      case ActivityKind.dapp:
        return (
          Icons.public,
          MassaColors.deepTeal,
          context.t('history.dapp')
        );
    }
  }

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

  Widget _statusChip(BuildContext context) {
    final (label, color) = switch (item.status) {
      ActivityStatus.submitted => (context.t('history.pending'), MassaColors.orange),
      ActivityStatus.final_ => (context.t('history.final'), MassaColors.green),
      ActivityStatus.failed => (context.t('history.failed'), MassaColors.red),
    };
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: color),
      ),
    );
  }

  String _timeLabel(BuildContext context) {
    final local = item.createdAt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String _short(String s) =>
      s.length <= 16 ? s : '${s.substring(0, 10)}…${s.substring(s.length - 6)}';
}
