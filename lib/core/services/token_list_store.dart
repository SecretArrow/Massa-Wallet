/// Persists the user's MRC-20 token list in SharedPreferences.
///
/// Shared by the dashboard tokens section and the full tokens screen —
/// both must agree on which tokens exist per network.
library;

import 'package:shared_preferences/shared_preferences.dart';

/// Token-list persistence (per network key: 'buildnet' / 'mainnet').
class TokenListStore {
  static const _kKey = 'wallet.tokens';

  /// Loads saved custom token addresses for [networkKey].
  Future<List<String>> load(String networkKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('$_kKey.$networkKey') ?? const [];
  }

  /// Saves [addresses] for [networkKey].
  Future<void> save(String networkKey, List<String> addresses) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('$_kKey.$networkKey', addresses);
  }
}
