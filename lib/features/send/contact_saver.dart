/// Post-send contact saving flow (shared by MAS and token send screens).
library;

import 'package:flutter/material.dart';

import '../../core/i18n/app_i18n.dart';
import '../../core/services/address_book_service.dart';

/// Offers to save [address] to the address book after a successful send.
///
/// When [resolvedDomain]/[resolvedAddress] match (an MNS send), the domain
/// is saved as the contact name without asking. Skips silently when the
/// address is already known.
Future<void> maybeSaveContact(
  BuildContext context,
  String address, {
  String? resolvedDomain,
  String? resolvedAddress,
}) async {
  final book = AddressBookService();
  final known = await book.load();
  if (known.any((c) => c.address == address)) return;
  // MNS sends save the domain as the contact name automatically.
  if (resolvedDomain != null && resolvedAddress == address) {
    await book.save(
      Contact(name: resolvedDomain, address: address, domain: resolvedDomain),
    );
    return;
  }
  if (!context.mounted) return;
  final short =
      '${address.substring(0, 10)}…${address.substring(address.length - 6)}';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.t('book.saveTitle')),
      content: Text(ctx.t('book.saveBody', args: [short])),
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
  if (ok != true || !context.mounted) return;
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
  if (nameOk == true && context.mounted) {
    final name = nameCtrl.text.trim();
    await book.save(
      Contact(name: name.isEmpty ? 'Contact' : name, address: address),
    );
  }
}
