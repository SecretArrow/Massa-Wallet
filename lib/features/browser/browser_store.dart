/// Browser persistence + curated Massa dApp catalog.
library;

import 'package:shared_preferences/shared_preferences.dart';

/// A curated / bookmarked dApp entry.
class DappEntry {
  /// Display name.
  final String name;

  /// URL.
  final String url;

  /// One-line description (start page).
  final String? description;

  /// Creates the entry.
  const DappEntry({required this.name, required this.url, this.description});
}

/// Curated starting points — official Massa web properties first,
/// well-known ecosystem dApps below. Users extend via bookmarks.
const List<DappEntry> kCuratedDapps = [
  DappEntry(
    name: 'Massa Explorer',
    url: 'https://explorer.massa.net',
    description: 'Mainnet block & operation explorer',
  ),
  DappEntry(
    name: 'Buildnet Explorer',
    url: 'https://buildnet-explorer.massa.net',
    description: 'Buildnet explorer',
  ),
  DappEntry(
    name: 'Networks & Faucets',
    url: 'https://docs.massa.net/docs/build/networks-faucets/public-networks',
    description: 'Get buildnet test MAS (Discord faucet)',
  ),
  DappEntry(
    name: 'Massa Docs',
    url: 'https://docs.massa.net',
    description: 'Official documentation',
  ),
  DappEntry(
    name: 'massa.net',
    url: 'https://massa.net',
    description: 'Official site & ecosystem',
  ),
  DappEntry(
    name: 'Massa Station dApps',
    url:
        'https://docs.massa.net/docs/massaStation/browse-decentralized-application',
    description: 'How decentralized apps work on Massa',
  ),
];

/// Max remembered history entries.
const int kHistoryCap = 30;

/// Bookmarks + history backed by SharedPreferences.
class BrowserStore {
  /// Preferences (injectable for tests).
  final SharedPreferences prefs;

  /// Creates the store.
  BrowserStore(this.prefs);

  static const _kBookmarks = 'browser.bookmarks';
  static const _kHistory = 'browser.history';

  List<String> _read(String key) =>
      List<String>.from(prefs.getStringList(key) ?? const <String>[]);

  void _write(String key, List<String> values) =>
      prefs.setStringList(key, values);

  /// Bookmarked URLs (encoded `name|url` lines).
  List<DappEntry> bookmarks() => _read(_kBookmarks).map(_parseLine).toList();

  /// Adds a bookmark; returns the updated list.
  List<DappEntry> addBookmark(String name, String url) {
    final line = _encodeLine(name, url);
    final current = _read(_kBookmarks)..remove(line);
    _write(_kBookmarks, [line, ...current]);
    return bookmarks();
  }

  /// Removes a bookmark by URL.
  List<DappEntry> removeBookmark(String url) {
    final current = _read(_kBookmarks)
        .where((line) => !_parseLine(line).url.startsWith(_normalize(url)))
        .toList();
    _write(_kBookmarks, current);
    return bookmarks();
  }

  /// Whether [url] is bookmarked.
  bool isBookmarked(String url) =>
      bookmarks().any((b) => b.url.startsWith(_normalize(url)));

  /// Recent history, most recent first.
  List<DappEntry> history() => _read(_kHistory).map(_parseLine).toList();

  /// Records a visit (dedupes consecutive, caps length).
  List<DappEntry> recordVisit(String name, String url) {
    if (url.isEmpty || !url.startsWith('http')) return history();
    final line = _encodeLine(name, url);
    final current = _read(_kHistory);
    if (current.isNotEmpty && current.first.startsWith(_normalize(url))) {
      return history();
    }
    current
      ..removeWhere((l) => l.startsWith(_normalize(url)))
      ..insert(0, line);
    if (current.length > kHistoryCap) {
      current.removeRange(kHistoryCap, current.length);
    }
    _write(_kHistory, current);
    return history();
  }

  /// Clears history.
  void clearHistory() => _write(_kHistory, []);

  static String _encodeLine(String name, String url) =>
      '${name.replaceAll('|', ' ')}|$url';

  static DappEntry _parseLine(String line) {
    final i = line.indexOf('|');
    if (i <= 0) return DappEntry(name: line, url: line);
    return DappEntry(name: line.substring(0, i), url: line.substring(i + 1));
  }

  static String _normalize(String url) {
    final u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty) return url;
    return '${u.scheme}://${u.host}${u.path.isEmpty ? '' : u.path}';
  }
}
