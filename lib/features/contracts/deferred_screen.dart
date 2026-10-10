/// Deferred calls (ASC) planner: slot clock, booking quotes, lookups and
/// guided booking through a scheduler contract.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/massa_amount.dart';
import '../../core/api/massa_models.dart';
import '../../core/api/massa_rpc.dart';
import '../../core/i18n/app_i18n.dart';
import '../../core/services/deferred_calls_service.dart';
import '../../core/services/wallet_provider.dart';

enum _Preset { manager, generic, raw }

String _fmt(DateTime t, {bool seconds = false}) {
  String p(int v, [int w = 2]) => v.toString().padLeft(w, '0');
  final base =
      '${t.year.toString().padLeft(4, '0')}-${p(t.month)}-${p(t.day)} '
      '${p(t.hour)}:${p(t.minute)}';
  return seconds ? '$base:${p(t.second)}' : base;
}

/// Deferred-calls screen.
class DeferredCallsScreen extends StatefulWidget {
  /// Creates the screen.
  const DeferredCallsScreen({super.key});

  @override
  State<DeferredCallsScreen> createState() => _DeferredCallsScreenState();
}

class _DeferredCallsScreenState extends State<DeferredCallsScreen> {
  DateTime _when = DateTime.now().toUtc().add(const Duration(hours: 1));
  int? _genesisMs;
  DeferredCallQuote? _quote;
  String? _quoteError;
  bool _busy = false;

  final _idCtrl = TextEditingController();
  DeferredCallInfo? _info;
  bool _infoNotFound = false;

  final _schedulerCtrl = TextEditingController();
  final _schedulerFnCtrl = TextEditingController(text: 'register');
  _Preset _preset = _Preset.manager;
  final _periodsCtrl = TextEditingController(text: '192');
  final _targetAddrCtrl = TextEditingController();
  final _targetFnCtrl = TextEditingController();
  final _targetParamsCtrl = TextEditingController();
  final _coinsCtrl = TextEditingController(text: '0');
  final _maxGasCtrl = TextEditingController(text: '20000000');
  String? _sendError;
  String? _sentOpId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadGenesis());
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _schedulerCtrl.dispose();
    _schedulerFnCtrl.dispose();
    _periodsCtrl.dispose();
    _targetAddrCtrl.dispose();
    _targetFnCtrl.dispose();
    _targetParamsCtrl.dispose();
    _coinsCtrl.dispose();
    _maxGasCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadGenesis() async {
    final settings = context.read<WalletProvider>().settings;
    try {
      final g = await DeferredCallsService(
        endpoint: settings.effectiveEndpoint,
      ).fetchGenesisMs();
      if (mounted) setState(() => _genesisMs = g);
    } on Exception {
      // The planner stays usable offline: user can still type raw slots.
    }
  }

  MassaSlot get _targetSlot {
    if (_genesisMs == null) return const MassaSlot(period: 0, thread: 0);
    return DeferredCallsService.dateTimeToSlot(_when, _genesisMs!);
  }

  Future<void> _pickTime() async {
    final now = DateTime.now().toUtc();
    final date = await showDatePicker(
      context: context,
      initialDate: _when.isBefore(now) ? now : _when,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    if (time == null) return;
    setState(() {
      _when = DateTime.utc(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _quote = null;
      _quoteError = null;
    });
  }

  Future<void> _getQuote() async {
    if (_genesisMs == null) return;
    setState(() {
      _busy = true;
      _quote = null;
      _quoteError = null;
    });
    try {
      final settings = context.read<WalletProvider>().settings;
      final svc = DeferredCallsService(endpoint: settings.effectiveEndpoint);
      final paramsHex = _targetParamsCtrl.text.trim();
      final paramsSize = paramsHex.isEmpty
          ? 0
          : (paramsHex.startsWith('0x')
                    ? (paramsHex.length - 2)
                    : paramsHex.length) ~/
                2;
      final quotes = await svc.quote([
        DeferredCallQuoteInput(
          targetSlot: _targetSlot,
          maxGasRequest: int.tryParse(_maxGasCtrl.text.trim()) ?? 20000000,
          paramsSize: paramsSize,
        ),
      ]);
      if (mounted)
        setState(() => _quote = quotes.isEmpty ? null : quotes.first);
    } catch (e) {
      if (mounted) setState(() => _quoteError = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _lookup() async {
    final id = _idCtrl.text.trim();
    if (id.isEmpty) return;
    setState(() {
      _busy = true;
      _info = null;
      _infoNotFound = false;
    });
    try {
      final settings = context.read<WalletProvider>().settings;
      final infos = await DeferredCallsService(
        endpoint: settings.effectiveEndpoint,
      ).info([id]);
      if (mounted) {
        setState(() {
          _info = infos.isEmpty ? null : infos.first;
          _infoNotFound = infos.isEmpty;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _infoNotFound = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<int> _hexToBytes(String raw) {
    final t = raw.trim().toLowerCase().replaceFirst('0x', '');
    if (t.isEmpty) return const [];
    final out = <int>[];
    for (var i = 0; i + 1 < t.length; i += 2) {
      out.add(int.parse(t.substring(i, i + 2), radix: 16));
    }
    return out;
  }

  Future<void> _book() async {
    final wallet = context.read<WalletProvider>();
    final account = wallet.activeAccount;
    if (account == null || _genesisMs == null) return;
    setState(() {
      _busy = true;
      _sendError = null;
      _sentOpId = null;
    });
    try {
      List<int> args;
      switch (_preset) {
        case _Preset.manager:
          final periods = int.tryParse(_periodsCtrl.text.trim()) ?? 0;
          args = DeferredCallsService.managerRegisterCallArgs(periods);
        case _Preset.generic:
          args = DeferredCallsService.genericRegisterArgs(
            targetAddress: _targetAddrCtrl.text.trim(),
            targetFunction: _targetFnCtrl.text.trim(),
            slot: _targetSlot,
            maxGas: BigInt.tryParse(_maxGasCtrl.text.trim()) ?? BigInt.zero,
            params: _hexToBytes(_targetParamsCtrl.text),
            coinsNano: parseUserAmount(_coinsCtrl.text),
          );
        case _Preset.raw:
          args = _hexToBytes(_targetParamsCtrl.text);
      }
      final res = await wallet.callSmartContract(
        fromAddress: account.address,
        target: _schedulerCtrl.text.trim(),
        function: _schedulerFnCtrl.text.trim(),
        parameter: args,
        maxGas:
            BigInt.tryParse(_maxGasCtrl.text.trim()) ?? BigInt.from(1000000),
        note: 'deferred-call-booking',
      );
      if (mounted) setState(() => _sentOpId = res.operationId);
    } catch (e) {
      if (mounted) setState(() => _sendError = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final slot = _targetSlot;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('deferred.title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              context.t('deferred.explain'),
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 24),
            _Section(
              title: context.t('deferred.planner'),
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.t('deferred.pickTime')),
                  subtitle: Text('${_fmt(_when)} UTC'),
                  trailing: const Icon(Icons.schedule),
                  onTap: _busy ? null : _pickTime,
                ),
                if (_genesisMs != null) ...[
                  const SizedBox(height: 8),
                  _KV(
                    label: context.t('deferred.slot'),
                    value: slot.toString(),
                  ),
                  _KV(
                    label: context.t('deferred.slotTime'),
                    value: _fmt(
                      DeferredCallsService.slotToDateTime(slot, _genesisMs!),
                      seconds: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: _busy ? null : _getQuote,
                    child: Text(context.t('deferred.getQuote')),
                  ),
                  if (_quote != null) ...[
                    const SizedBox(height: 12),
                    _KV(
                      label: context.t('deferred.quotePrice'),
                      value: DeferredCallsService.formatPrice(
                        _quote!.priceNano,
                      ),
                    ),
                    _KV(
                      label: context.t('deferred.quoteGas'),
                      value: _quote!.maxGas.toString(),
                    ),
                    Text(
                      _quote!.available
                          ? context.t('deferred.quoteOk')
                          : context.t('deferred.quoteBusy'),
                      style: TextStyle(
                        color: _quote!.available
                            ? const Color(0xFF3FB950)
                            : const Color(0xFFF85149),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (_quoteError != null)
                    Text(
                      _quoteError!,
                      style: const TextStyle(color: Color(0xFFF85149)),
                    ),
                ] else
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            _Section(
              title: context.t('deferred.lookup'),
              children: [
                TextField(
                  controller: _idCtrl,
                  decoration: InputDecoration(
                    labelText: context.t('deferred.lookupHint'),
                    hintText: 'D...',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: _busy ? null : _lookup,
                  child: Text(context.t('deferred.lookupBtn')),
                ),
                if (_infoNotFound)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      context.t('deferred.notFound'),
                      style: const TextStyle(color: Color(0xFFF85149)),
                    ),
                  ),
                if (_info != null) ...[
                  const SizedBox(height: 12),
                  _KV(
                    label: context.t('deferred.infoSender'),
                    value: _info!.senderAddress,
                  ),
                  _KV(
                    label: context.t('deferred.infoTarget'),
                    value: _info!.targetAddress,
                  ),
                  _KV(
                    label: context.t('deferred.infoFunction'),
                    value: _info!.targetFunction,
                  ),
                  _KV(
                    label: context.t('deferred.slot'),
                    value: _info!.targetSlot.toString(),
                  ),
                  _KV(
                    label: context.t('deferred.infoParams'),
                    value: '${_info!.parameters.length} B',
                  ),
                  _KV(
                    label: context.t('deferred.infoCoins'),
                    value: formatNano(_info!.coinsNano),
                  ),
                  _KV(
                    label: context.t('deferred.infoFee'),
                    value: formatNano(_info!.feeNano),
                  ),
                  _KV(
                    label: context.t('deferred.infoCancelled'),
                    value: _info!.cancelled
                        ? context.t('deferred.infoCancelled')
                        : context.t('deferred.infoActive'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),
            _Section(
              title: context.t('deferred.book'),
              children: [
                Text(
                  context.t('deferred.bookHint'),
                  style: const TextStyle(fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _schedulerCtrl,
                  decoration: InputDecoration(
                    labelText: context.t('deferred.bookContract'),
                    hintText: 'AS1...',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _schedulerFnCtrl,
                  decoration: InputDecoration(
                    labelText: context.t('deferred.bookFunction'),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<_Preset>(
                  initialValue: _preset,
                  decoration: InputDecoration(
                    labelText: context.t('deferred.bookPreset'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: _Preset.manager,
                      child: Text(
                        context.t('deferred.presetManager'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: _Preset.generic,
                      child: Text(
                        context.t('deferred.presetGeneric'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: _Preset.raw,
                      child: Text(
                        context.t('deferred.presetRaw'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _preset = v ?? _Preset.manager),
                ),
                const SizedBox(height: 12),
                if (_preset == _Preset.manager)
                  TextField(
                    controller: _periodsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.t('deferred.periodsFromNow'),
                      helperText: '1 period = 16 s (128 ≈ 34 min)',
                    ),
                  )
                else ...[
                  if (_preset == _Preset.generic) ...[
                    TextField(
                      controller: _targetAddrCtrl,
                      decoration: InputDecoration(
                        labelText: context.t('deferred.targetAddress'),
                        hintText: 'AS1...',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _targetFnCtrl,
                      decoration: InputDecoration(
                        labelText: context.t('deferred.targetFunction'),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _targetParamsCtrl,
                    decoration: InputDecoration(
                      labelText: _preset == _Preset.generic
                          ? context.t('deferred.targetParams')
                          : context.t('deferred.presetRaw'),
                      hintText: '0x0102...',
                    ),
                  ),
                  if (_preset == _Preset.generic) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _coinsCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: context.t('deferred.targetCoins'),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _maxGasCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.t('deferred.maxGas'),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy || _genesisMs == null ? null : _book,
                  child: Text(context.t('deferred.sign')),
                ),
                if (_sendError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _sendError!,
                      style: const TextStyle(color: Color(0xFFF85149)),
                    ),
                  ),
                if (_sentOpId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SelectableText(
                      '${context.t('deferred.sent')}: $_sentOpId',
                      style: const TextStyle(color: Color(0xFF3FB950)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _KV extends StatelessWidget {
  final String label;
  final String value;

  const _KV({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}
