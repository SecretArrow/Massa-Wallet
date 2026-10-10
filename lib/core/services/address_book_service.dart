/// Address book: saved recipients for transfers and token sends.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One saved contact.
class Contact {
  /// Display name.
  final String name;

  /// Massa address (AU1…).
  final String address;

  /// Creates a contact.
  const Contact({required this.name, required this.address});

  Map<String, String> _toJson() => {'name': name, 'address': address};

  static Contact _fromJson(Map<String, dynamic> j) =>
      Contact(name: (j['name'] ?? '') as String, address: (j['address'] ?? '') as String);

  @override
  bool operator ==(Object other) =>
      other is Contact && other.address == address;

  @override
  int get hashCode => address.hashCode;
}

/// Persists the address book.
class AddressBookService {
  static const _kKey = 'wallet.addressBook';

  /// Creates the service.
  AddressBookService();

  /// Loads all contacts (sorted by name).
  Future<List<Contact>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kKey) ?? const [];
    final list = raw
        .map((s) {
          try {
            return Contact._fromJson(json.decode(s) as Map<String, dynamic>);
          } on FormatException {
            return null;
          }
        })
        .whereType<Contact>()
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Adds or updates a contact (by address). Returns the new list.
  Future<List<Contact>> save(Contact contact) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kKey) ?? const [];
    final list = raw
        .map((s) {
          try {
            return Contact._fromJson(json.decode(s) as Map<String, dynamic>);
          } on FormatException {
            return null;
          }
        })
        .whereType<Contact>()
        .where((c) => c.address != contact.address)
        .toList();
    list.add(contact);
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    await prefs.setStringList(
      _kKey,
      list.map((c) => json.encode(c._toJson())).toList(),
    );
    return list;
  }

  /// Deletes a contact by address.
  Future<void> delete(String address) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kKey) ?? const [];
    final kept = <String>[];
    for (final item in raw) {
      try {
        final c = Contact._fromJson(json.decode(item) as Map<String, dynamic>);
        if (c.address != address) kept.add(item);
      } on FormatException {
        // ignore malformed entries
      }
    }
    await prefs.setStringList(_kKey, kept);
  }
}
