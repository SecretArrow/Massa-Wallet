/// Send MAS screen with QR scanning.
library;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../core/api/massa_amount.dart';
import '../../core/api/massa_rpc.dart';
import '../../core/contracts/mns_service.dart';
import '../../core/crypto/massa_keys.dart';
import '../../core/i18n/app_i18n.dart';
import '../../core/services/address_book_service.dart';
import '../../core/services/settings_provider.dart';
import '../../core/services/wallet_provider.dart';
import '../history/address_book_screen.dart';

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

  @override
  void dispose() {
    _recipient.dispose();
    _amount.dispose();
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
        note: _resolvedDomain,
      );
      setState(() => _opId = result.operationId);
      await wallet.refreshBalances();
      await _maybeSaveContact(recipient);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openScanner() async {
    final code = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const _QrScanPage()));
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

  Future<void> _maybeSaveContact(String address) async {
    final book = AddressBookService();
    final known = await book.load();
    if (known.any((c) => c.address == address)) return;
    // MNS sends save the domain as the contact name automatically.
    if (_resolvedDomain != null && _resolvedAddress == address) {
      await book.save(
        Contact(
          name: _resolvedDomain!,
          address: address,
          domain: _resolvedDomain!,
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.t('book.saveTitle')),
        content: Text(
          ctx.t(
            'book.saveBody',
            args: [
              '${address.substring(0, 10)}…${address.substring(address.length - 6)}',
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.t('common.no')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.t('common.yes')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final nameCtrl = TextEditingController();
    final nameOk = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.t('book.name')),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: InputDecoration(labelText: ctx.t('book.name')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.t('book.save')),
          ),
        ],
      ),
    );
    if (nameOk == true && mounted) {
      final name = nameCtrl.text.trim();
      await book.save(
        Contact(name: name.isEmpty ? 'Contact' : name, address: address),
      );
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

/// Full-screen QR scanner page.
class _QrScanPage extends StatelessWidget {
  const _QrScanPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('send.scanTitle'))),
      body: MobileScanner(
        onDetect: (capture) {
          for (final barcode in capture.barcodes) {
            final value = barcode.rawValue;
            if (value != null && value.isNotEmpty) {
              Navigator.of(context).pop(value);
              return;
            }
          }
        },
      ),
    );
  }
}
