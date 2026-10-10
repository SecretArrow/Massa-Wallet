/// MAS price ticker via CoinGecko (best-effort, offline-tolerant).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Price snapshot for MAS.
class MasPrice {
  /// USD price.
  final double usd;

  /// IDR price.
  final double idr;

  /// 24h change in percent (USD).
  final double change24h;

  /// Fetch time.
  final DateTime fetchedAt;

  /// Creates the snapshot.
  const MasPrice({
    required this.usd,
    required this.idr,
    required this.change24h,
    required this.fetchedAt,
  });
}

/// Fetches and caches the MAS price.
class PriceService {
  static const _kUrl =
      'https://api.coingecko.com/api/v3/simple/price'
      '?ids=massa&vs_currencies=usd,idr&include_24hr_change=true';

  /// Cache TTL.
  static const Duration ttl = Duration(minutes: 5);

  MasPrice? _last;
  DateTime _lastFetch = DateTime.fromMillisecondsSinceEpoch(0);
  bool _loading = false;

  /// Cached price (null when never fetched).
  MasPrice? get cached => _last;

  /// Whether a fetch is in-flight.
  bool get loading => _loading;

  /// Fetches the current price; returns the cached value when fresh or when
  /// the network is unavailable (best-effort, never throws).
  Future<MasPrice?> fetch({http.Client? httpClient}) async {
    if (_loading) return _last;
    if (_last != null && DateTime.now().difference(_lastFetch) < ttl) {
      return _last;
    }
    _loading = true;
    final client = httpClient ?? http.Client();
    try {
      final res = await client
          .get(Uri.parse(_kUrl), headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = json.decode(res.body) as Map<String, dynamic>;
        final massa = body['massa'] as Map<String, dynamic>?;
        if (massa != null) {
          _last = MasPrice(
            usd: (massa['usd'] as num?)?.toDouble() ?? 0,
            idr: (massa['idr'] as num?)?.toDouble() ?? 0,
            change24h: (massa['usd_24h_change'] as num?)?.toDouble() ?? 0,
            fetchedAt: DateTime.now(),
          );
          _lastFetch = DateTime.now();
        }
      }
    } on Exception {
      // Keep the previous value (may be null) — offline tolerant.
    } finally {
      _loading = false;
      try {
        if (httpClient == null) client.close();
      } catch (_) {}
    }
    return _last;
  }
}
