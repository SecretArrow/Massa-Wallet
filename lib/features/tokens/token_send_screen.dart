/// Full-screen MRC-20 token transfer.
///
/// UX parity with the native MAS send screen: recipient via address book /
/// QR / MNS domain, amount with MAX, fee presets (economy/standard/fast/
/// custom) and a live storage-cost preview when the recipient has no token
/// balance entry yet (that cost is charged as `coins` on the CallSC).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/fee_policy.dart';
import '../../core/api/massa_amount.dart';
import '../../core/api/massa_rpc.dart';
import '../../core/contracts/mns_service.dart';
import '../../core/contracts/mrc20_service.dart';
import '../../core/crypto/massa_keys.dart';
import '../../core/i18n/app_i18n.dart';
import '../../core/services/activity_history_service.dart';
import '../../core/services/settings_provider.dart';
import '../../core/services/wallet_provider.dart';
import '../history/address_book_screen.dart';
import '../send/contact_saver.dart';
import '../send/qr_scan_page.dart';

/// Token send screen.
class TokenSendScreen extends StatefulWidget {
  /// Token to transfer.
  final Mrc20Token token;

  /// Current raw balance of the active account (for MAX).
  final BigInt balance;

  /// Creates the token send screen.
  const TokenSendScreen({super.key, required this.token, required this.balance});

  @override
  State<TokenSendScreen> createState() => _TokenSendScreenState();
}

class _TokenSendScreenState extends State<TokenSendScreen> {
  late final Mrc20Service _mrc20;
  final _recipient = TextEditingController();
  final _amount = TextEditingController();
  FeePreset _feePreset = FeePreset.standard;
  final _customFee = TextEditingController();
  BigInt _minimalFee = FeePolicy.fallbackMinimalFee;
  bool _busy = false;
  String? _opId;
  String? _error;
  String? _resolvedDomain;
  String? _resolvedAddress;
  bool _resolving = false;

  // Recipient storage-entry probe (null = unknown / not an address yet).
  bool? _recipientHasEntry;
  BigInt? _storageCostNano;
  int _storageCheckSeq = 0;

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
    // Capture the endpoint eagerly (screen may be disposed while in-flight
    // RPCs re-invoke the factory — same guard as the tokens screen).
    final endpoint = context.read<SettingsProvider>().effectiveEndpoint;
    _mrc20 = Mrc20Service(
      clientFactory: () => MassaRpcClient(endpoint: endpoint),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final wallet = context.read<WalletProvider>();
      final f = await wallet.nodeMinimalFee();
      if (mounted) setState(() => _minimalFee = f);
    });
    _recipient.addListener(_onRecipientChanged);
  }

  @override
  void dispose() {
    _recipient.removeListener(_onRecipientChanged);
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

  /// Probes whether the recipient already has a token balance entry —
  /// when not, the transfer must carry the balance-creation storage cost.
  Future<void> _onRecipientChanged() async {
    if (!mounted) return;
    setState(() {}); // refresh suffix icons
    final raw = _recipient.text.trim();
    final plausible = raw.startsWith('AU1') && raw.length > 20 ||
        raw.startsWith('AS1') && raw.length > 20;
    if (!plausible) {
      _storageCheckSeq++;
      setState(() {
        _recipientHasEntry = null;
        _storageCostNano = null;
      });
      return;
    }
    final seq = ++_storageCheckSeq;
    try {
      final has = await _mrc20.hasBalanceEntry(widget.token.address, raw);
      if (seq != _storageCheckSeq || !mounted) return;
      setState(() {
        _recipientHasEntry = has;
        _storageCostNano = has ? null : Mrc20Service.balanceCreationCost(raw);
      });
    } on Exception {
      if (seq != _storageCheckSeq || !mounted) return;
      setState(() {
        _recipientHasEntry = null;
        _storageCostNano = null;
      });
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
      final amount = Mrc20Service.parseUserAmount(
        _amount.text,
        widget.token.decimals,
      );
      if (amount == null || amount <= BigInt.zero) {
        throw Exception(context.t('send.invalidAmount'));
      }
      if (amount > widget.balance) {
        throw Exception(
          context.t('tokens.insufficient', args: [widget.token.symbol]),
        );
      }
      final result = await wallet.callSmartContract(
        fromAddress: account.address,
        target: widget.token.address,
        function: 'transfer',
        parameter: Mrc20Service.transferArgs(recipient, amount),
        maxGas: BigInt.from(10000000),
        coinsNano: _storageCostNano,
        feeNano: _effectiveFee,
        activityKind: ActivityKind.tokenTransfer,
        tokenSymbol: widget.token.symbol,
        tokenAmount: widget.token.formatAmount(amount),
        note: _resolvedDomain,
      );
      setState(() => _opId = result.operationId);
      await wallet.refreshBalances();
      if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    final t = widget.token;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('tokenSend.title', args: [t.symbol])),
      ),
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
            // Recipient storage-cost preview.
            if (_storageCostNano != null) ...[
              const SizedBox(height: 8),
              Card(
                color: const Color(0xFF2A2110),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.inventory_2_outlined,
                        size: 16,
                        color: Color(0xFFD29922),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.t('tokens.storageFee', args: [
                            t.symbol,
                            nanoToMas(_storageCostNano!),
                          ]),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFD29922),
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
                suffixText: t.symbol,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  setState(() {
                    _amount.text = t.formatAmount(widget.balance);
                  });
                },
                child: Text(
                  '${context.t('send.max')} · ${t.formatAmount(widget.balance)} ${t.symbol}',
                ),
              ),
            ),
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
