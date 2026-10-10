/// Address book screen: saved recipients.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n/app_i18n.dart';
import '../../core/services/address_book_service.dart';
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
              decoration: InputDecoration(
                labelText: ctx.t('book.name'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: addrCtrl,
              decoration: InputDecoration(
                labelText: ctx.t('book.address'),
                hintText: 'AU1…',
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
    final address = addrCtrl.text.trim();
    if (name.isEmpty || !(address.startsWith('AU1') || address.startsWith('AS1'))) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t('book.invalid'))),
      );
      return;
    }
    await _book.save(Contact(name: name, address: address));
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
                          backgroundColor:
                              MassaColors.teal.withValues(alpha: 0.15),
                          child: Text(
                            c.name.isEmpty ? '?' : c.name[0].toUpperCase(),
                            style: const TextStyle(color: MassaColors.teal),
                          ),
                        ),
                        title: Text(c.name),
                        subtitle: Text(
                          '${c.address.substring(0, 12)}…${c.address.substring(c.address.length - 6)}',
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
                          await Clipboard.setData(
                            ClipboardData(text: c.address),
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(context.t('receive.copied')),
                            ),
                          );
                        },
                        trailing: !widget.pickerMode
                            ? IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 20,
                                ),
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
