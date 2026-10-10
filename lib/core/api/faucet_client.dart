/// Massa buildnet faucet client.
///
/// The public buildnet faucet lives at `https://faucet.buildnet.massa.net`
/// and exposes `POST /api/v1/fund` with `{"address": "AU12…"}`. A 2xx
/// response means the request was accepted; funds are credited in the
/// next few seconds/minutes. 4xx responses carry a JSON error message
/// (rate limiting, invalid address, …).
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Outcome of a faucet request.
enum FaucetStatus {
  /// Request accepted — funds will arrive shortly.
  accepted,

  /// Rate limited / rejected — try again later.
  rejected,

  /// Network or server failure.
  failed,
}

/// Result of a faucet request.
class FaucetResult {
  /// Outcome.
  final FaucetStatus status;

  /// Human-readable message from the faucet (or our own summary).
  final String message;

  /// Creates the result.
  const FaucetResult({required this.status, required this.message});
}

/// Client for the public buildnet faucet.
class FaucetClient {
  /// Faucet base endpoint.
  final String endpoint;

  /// HTTP client (injectable for tests).
  final http.Client httpClient;

  /// Request timeout.
  final Duration timeout;

  /// Creates a faucet client.
  FaucetClient({
    this.endpoint = 'https://faucet.buildnet.massa.net/api/v1/fund',
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
  }) : httpClient = httpClient ?? http.Client();

  /// Requests funds for [address].
  Future<FaucetResult> fund(String address) async {
    if (address.isEmpty) {
      return const FaucetResult(
        status: FaucetStatus.rejected,
        message: 'empty address',
      );
    }
    try {
      final res = await httpClient
          .post(
            Uri.parse(endpoint),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'address': address}),
          )
          .timeout(timeout);
      final body = res.body;
      String? message;
      try {
        final decoded = json.decode(body);
        if (decoded is Map<String, dynamic>) {
          message =
              (decoded['message'] ?? decoded['error'] ?? decoded['detail'])
                  ?.toString();
        }
      } on FormatException {
        // Non-JSON body — fall through with null message.
      }
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return FaucetResult(
          status: FaucetStatus.accepted,
          message: message ?? 'accepted (${res.statusCode})',
        );
      }
      if (res.statusCode == 429 ||
          (message?.toLowerCase().contains('rate') ?? false)) {
        return FaucetResult(
          status: FaucetStatus.rejected,
          message: message ?? 'rate limited (${res.statusCode})',
        );
      }
      return FaucetResult(
        status: FaucetStatus.rejected,
        message: message ?? 'HTTP ${res.statusCode}',
      );
    } on TimeoutException {
      return const FaucetResult(
        status: FaucetStatus.failed,
        message: 'faucet timeout',
      );
    } catch (e) {
      return FaucetResult(status: FaucetStatus.failed, message: e.toString());
    }
  }

  void dispose() => httpClient.close();
}
