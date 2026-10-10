/// Address book screen: saved recipients (with MNS domain support).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api/massa_rpc.dart';
import '../../core/contracts/mns_service.dart';
import '../../core/i18n/app_i18n.dart';
import '../../core/services/address_book_service.dart';
import '../../core/services/settings_provider.dart';
import '../../ui/theme.dart';

/// Address book screen.
class AddressBookScreen extends StatefulWidget {
  /// When set, the screen acts as a picker and returns the chosen address.
  final bool pickerMode;

  /// Creates the screen.
  const AddressBookScreen({super.key, this.pickerMode = false});

  @override
  State<AddressBookScreen> createState() => _AddressBookScreenState();
}

class _AddressBookScreenState extends State<AddressBookScreen> {
  final AddressBookService _book = AddressBookService();
  List<Contact> _contacts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final contacts = await _book.load();
    if (!mounted) return;
    setState(() {
      _contacts = contacts;
      _loading = false;
    });
  }

  Future<void> _addContact() async {
    final nameCtrl = TextEditingController();
    final addrCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.t('book.addTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: InputDecoration(labelText: ctx.t('book.name')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: addrCtrl,
              decoration: InputDecoration(
                labelText: ctx.t('book.address'),
                hintText: 'AU1… atau name.massa',
                helperText: ctx.t('book.mnsHint'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.t('book.add')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    final raw = addrCtrl.text.trim();

    // MNS: allow adding via name.massa — resolve to the target address.
    var address = raw;
    var domain = '';
    final parsed = MnsService.parseInput(raw);
    if (parsed.domain != null) {
      try {
        final settings = context.read<SettingsProvider>();
        final service = MnsService(
          clientFactory: () =>
              MassaRpcClient(endpoint: settings.effectiveEndpoint),
        );
        final res = await service.resolve(
          parsed.domain!,
          mainnet: settings.network == MassaNetwork.mainnet,
        );
        address = res.target;
        domain = '${res.domain}.massa';
      } on MnsException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: const Color(0xFFF85149),
          ),
        );
        return;
      }
    }
    if (name.isEmpty ||
        !(address.startsWith('AU1') || address.startsWith('AS1'))) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.t('book.invalid'))));
      return;
    }
    await _book.save(
      Contact(
        name: name.isEmpty ? domain : name,
        address: address,
        domain: domain,
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.t(widget.pickerMode ? 'book.pickTitle' : 'book.title'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt),
            tooltip: context.t('book.add'),
            onPressed: _addContact,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _contacts.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.import_contacts_outlined,
                    size: 56,
                    color: Color(0xFF30363D),
                  ),
                  const SizedBox(height: 12),
                  Text(context.t('book.empty')),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _addContact,
                    icon: const Icon(Icons.person_add_alt),
                    label: Text(context.t('book.add')),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _contacts.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (ctx, i) {
                final c = _contacts[i];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: MassaColors.teal.withValues(alpha: 0.15),
                      child: c.domain.isNotEmpty
                          ? const Icon(
                              Icons.dns_outlined,
                              color: MassaColors.teal,
                              size: 20,
                            )
                          : Text(
                              c.name.isEmpty ? '?' : c.name[0].toUpperCase(),
                              style: const TextStyle(color: MassaColors.teal),
                            ),
                    ),
                    title: Text(c.domain.isNotEmpty ? c.domain : c.name),
                    subtitle: Text(
                      c.domain.isNotEmpty
                          ? '${c.name} · ${c.address.substring(0, 8)}…'
                          : '${c.address.substring(0, 12)}…${c.address.substring(c.address.length - 6)}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                    onTap: () async {
                      if (widget.pickerMode) {
                        Navigator.pop(context, c.address);
                        return;
                      }
                      await Clipboard.setData(ClipboardData(text: c.address));
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(context.t('receive.copied'))),
                      );
                    },
                    trailing: !widget.pickerMode
                        ? IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () async {
                              await _book.delete(c.address);
                              await _load();
                            },
                          )
                        : null,
                  ),
                );
              },
            ),
    );
  }
}
