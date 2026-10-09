/// Smart-contract console: read-only calls.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/massa_models.dart';
import '../../core/i18n/app_i18n.dart';
import '../../core/services/wallet_provider.dart';

/// Contracts screen.
class ContractsScreen extends StatefulWidget {
  /// Creates the screen.
  const ContractsScreen({super.key});

  @override
  State<ContractsScreen> createState() => _ContractsScreenState();
}

class _ContractsScreenState extends State<ContractsScreen> {
  final _target = TextEditingController();
  final _function = TextEditingController();
  final _params = TextEditingController();
  ReadOnlyCallResult? _result;
  bool _busy = false;

  @override
  void dispose() {
    _target.dispose();
    _function.dispose();
    _params.dispose();
    super.dispose();
  }

  List<int> _parseParams(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const [];
    // Accept hex (0x...) or JSON array of ints.
    if (trimmed.toLowerCase().startsWith('0x')) {
      final hex = trimmed.substring(2);
      final out = <int>[];
      for (var i = 0; i + 1 < hex.length; i += 2) {
        out.add(int.parse(hex.substring(i, i + 2), radix: 16));
      }
      return out;
    }
    final decoded = json.decode(trimmed) as List;
    return decoded.cast<int>();
  }

  Future<void> _call() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final wallet = context.read<WalletProvider>();
      final res = await wallet.readOnlyCall(
        target: _target.text.trim(),
        function: _function.text.trim(),
        parameter: _parseParams(_params.text),
      );
      setState(() => _result = res);
    } catch (e) {
      setState(
        () => _result = ReadOnlyCallResult(ok: false, error: e.toString()),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('contracts.title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextField(
              controller: _target,
              decoration: InputDecoration(
                labelText: context.t('contracts.target'),
                hintText: 'AS1...',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _function,
              decoration: InputDecoration(
                labelText: context.t('contracts.function'),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _params,
              decoration: InputDecoration(
                labelText: context.t('contracts.params'),
                hintText: '[1,2,3] or 0x010203',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _call,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.t('contracts.readCall')),
            ),
            if (_result != null) ...[
              const SizedBox(height: 24),
              Text(
                context.t('contracts.result'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                color: _result!.ok
                    ? const Color(0xFF12261A)
                    : const Color(0xFF2D1215),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _result!.ok
                            ? context.t('contracts.resultOk')
                            : '${context.t('contracts.resultErr')}: ${_result!.error ?? ''}',
                        style: TextStyle(
                          color: _result!.ok
                              ? const Color(0xFF3FB950)
                              : const Color(0xFFF85149),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        _result!.ok
                            ? utf8.decode(
                                _result!.returnValue,
                                allowMalformed: true,
                              )
                            : '',
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${context.t('contracts.gas')}: ${_result!.gasCost}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8B949E),
                        ),
                      ),
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
