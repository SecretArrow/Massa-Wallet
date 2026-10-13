/// Send MAS screen with QR scanning.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/massa_amount.dart';
import '../../core/api/fee_policy.dart';
import '../../core/api/massa_rpc.dart';
import '../../core/contracts/mns_service.dart';
import '../../core/crypto/massa_keys.dart';
import '../../core/i18n/app_i18n.dart';
import '../../core/services/settings_provider.dart';
import '../../core/services/wallet_provider.dart';
import '../history/address_book_screen.dart';
import 'contact_saver.dart';
import 'qr_scan_page.dart';

/// Send screen.
class SendScreen extends StatefulWidget {
  /// Creates the screen.
  const SendScreen({super.key});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final _recipient = TextEditingController();
  final _amount = TextEditingController();
  bool _busy = false;
  String? _opId;
  String? _error;
  String? _resolvedDomain;
  String? _resolvedAddress;
  bool _resolving = false;

  // Fee selection (defaults to standard = 2x minimal).
  FeePreset _feePreset = FeePreset.standard;
  final _customFee = TextEditingController();
  BigInt _minimalFee = FeePolicy.fallbackMinimalFee;

  /// Currently selected effective fee in nanoMAS.
  BigInt get _effectiveFee {
    BigInt? custom;
    if (_feePreset == FeePreset.custom) {
      try {
        custom = parseUserAmount(_customFee.text);
      } on FormatException {
        custom = null; // half-typed input -> clamp to minimal
      }
    }
    return FeePolicy.feeFor(_feePreset, _minimalFee, customNano: custom);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final wallet = context.read<WalletProvider>();
      final f = await wallet.nodeMinimalFee();
      if (mounted) setState(() => _minimalFee = f);
    });
  }

  @override
  void dispose() {
    _recipient.dispose();
    _amount.dispose();
    _customFee.dispose();
    super.dispose();
  }

  bool _isValidAddress(String s) {
    try {
      MassaAddress.fromString(s.trim());
      return true;
    } on FormatException {
      return false;
    }
  }

  bool _looksLikeDomain(String s) {
    final parsed = MnsService.parseInput(s);
    return parsed.domain != null;
  }

  /// Resolves an MNS domain in the recipient field (name.massa).
  Future<void> _resolveMns() async {
    final raw = _recipient.text.trim();
    if (raw.isEmpty) return;
    final parsed = MnsService.parseInput(raw);
    if (parsed.domain == null) {
      setState(() {
        _resolvedDomain = null;
        _resolvedAddress = null;
      });
      return;
    }
    setState(() => _resolving = true);
    try {
      final settings = context.read<SettingsProvider>();
      final service = MnsService(
        clientFactory: () => MassaRpcClient(
          endpoint: context.read<SettingsProvider>().effectiveEndpoint,
        ),
      );
      final res = await service.resolve(
        parsed.domain!,
        mainnet: settings.network == MassaNetwork.mainnet,
      );
      setState(() {
        _resolvedDomain = '${res.domain}.massa';
        _resolvedAddress = res.target;
        _recipient.text = res.target;
      });
    } catch (e) {
      setState(() {
        _resolvedDomain = null;
        _resolvedAddress = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: const Color(0xFFF85149),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<void> _send() async {
    final wallet = context.read<WalletProvider>();
    final account = wallet.activeAccount;
    if (account == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _opId = null;
    });
    try {
      var recipient = _recipient.text.trim();
      // MNS: resolve name.massa (or a bare domain) before sending.
      if (_looksLikeDomain(recipient)) {
        final parsed = MnsService.parseInput(recipient);
        final settings = context.read<SettingsProvider>();
        final service = MnsService(
          clientFactory: () =>
              MassaRpcClient(endpoint: settings.effectiveEndpoint),
        );
        final res = await service.resolve(
          parsed.domain!,
          mainnet: settings.network == MassaNetwork.mainnet,
        );
        setState(() {
          _resolvedDomain = '${res.domain}.massa';
          _resolvedAddress = res.target;
        });
        recipient = res.target;
      }
      if (!_isValidAddress(recipient)) {
        throw Exception(context.t('send.invalidRecipient'));
      }
      final amount = parseUserAmount(_amount.text);
      if (amount <= BigInt.zero) {
        throw Exception(context.t('send.invalidAmount'));
      }
      final result = await wallet.sendTransfer(
        fromAddress: account.address,
        recipient: recipient,
        amountNano: amount,
        feeNano: _effectiveFee,
        note: _resolvedDomain,
      );
      setState(() => _opId = result.operationId);
      await wallet.refreshBalances();
      await maybeSaveContact(
        context,
        recipient,
        resolvedDomain: _resolvedDomain,
        resolvedAddress: _resolvedAddress,
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openScanner() async {
    final code = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const QrScanPage()));
    if (code != null && code.isNotEmpty) {
      setState(() => _recipient.text = code);
    }
  }

  void _pickContact() async {
    final address = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const AddressBookScreen(pickerMode: true),
      ),
    );
    if (address != null && address.isNotEmpty) {
      setState(() => _recipient.text = address);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    final account = wallet.activeAccount;

    return Scaffold(
      appBar: AppBar(title: Text(context.t('send.title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (_opId != null) ...[
              Card(
                color: const Color(0xFF12261A),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Color(0xFF3FB950),
                        size: 48,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        context.t('send.success'),
                        style: const TextStyle(
                          color: Color(0xFF3FB950),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        '${context.t('send.opId')}: $_opId',
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            TextField(
              controller: _recipient,
              decoration: InputDecoration(
                labelText: context.t('send.recipient'),
                helperText: context.t('send.mnsHint'),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_looksLikeDomain(_recipient.text))
                      IconButton(
                        icon: _resolving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.dns_outlined),
                        onPressed: _resolving ? null : _resolveMns,
                        tooltip: context.t('send.resolveMns'),
                      ),
                    IconButton(
                      icon: const Icon(Icons.import_contacts_outlined),
                      onPressed: _pickContact,
                      tooltip: context.t('book.pickTitle'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      onPressed: _openScanner,
                      tooltip: context.t('send.scan'),
                    ),
                  ],
                ),
              ),
            ),
            if (_resolvedDomain != null && _resolvedAddress != null) ...[
              const SizedBox(height: 8),
              Card(
                color: const Color(0xFF12261A),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.dns_outlined,
                        size: 16,
                        color: Color(0xFF3FB950),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$_resolvedDomain → $_resolvedAddress',
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: Color(0xFF3FB950),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: context.t('send.amount'),
                suffixText: 'MAS',
              ),
            ),
            if (account != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    final b = wallet.balanceOf(account.address);
                    if (b != null) {
                      setState(() => _amount.text = nanoToMas(b.finalBalance));
                    }
                  },
                  child: Text(context.t('send.max')),
                ),
              ),
            ],
            const SizedBox(height: 8),

            // ── Fee selection ─────────────────────────────────────────
            Text(
              context.t('send.fee'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in FeePreset.values)
                  ChoiceChip(
                    label: Text(
                      switch (preset) {
                        FeePreset.economy => context.t('send.fee.economy'),
                        FeePreset.standard => context.t('send.fee.standard'),
                        FeePreset.fast => context.t('send.fee.fast'),
                        FeePreset.custom => context.t('send.fee.custom'),
                      },
                    ),
                    selected: _feePreset == preset,
                    onSelected: (_) => setState(() => _feePreset = preset),
                  ),
              ],
            ),
            if (_feePreset == FeePreset.custom) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _customFee,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: context.t('send.fee.custom'),
                  helperText: context.t('send.fee.customHint'),
                  suffixText: 'MAS',
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '${context.t('send.fee')}: ${nanoToMas(_effectiveFee)} MAS',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Card(
                color: const Color(0xFF2D1215),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '${context.t('send.failed')}: $_error',
                    style: const TextStyle(
                      color: Color(0xFFF85149),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _send,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.t('send.confirm')),
            ),
          ],
        ),
      ),
    );
  }
}
