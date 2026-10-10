/// DApp ↔ wallet bridge (`window.massa` provider).
///
/// Injects a JavaScript provider into the WebView implementing the classic
/// Massa wallet interface (`enable`, `accounts`, `sign`, …) plus a
/// `request({method, params})` JSON surface. All requests flow through a
/// JavaScriptChannel and are confirmed by the user via native dialogs.
library;

import 'dart:convert';

/// JavaScript source injected on every page.
String massaProviderScript({
  required String address,
  required String nickname,
  required int chainId,
  required String networkName,
}) {
  final account = json.encode({
    'address': address,
    'name': nickname.isEmpty ? 'Massa Wallet' : nickname,
  });
  return '''
(function () {
  if (window.__massaInjected) return;
  window.__massaInjected = true;

  var __pending = {};
  var __nextId = 1;

  function callNative(method, params) {
    return new Promise(function (resolve, reject) {
      var id = __nextId++;
      __pending[id] = { resolve: resolve, reject: reject };
      try {
        MassaMobile.postMessage(JSON.stringify({ id: id, method: method, params: params || {} }));
      } catch (e) {
        delete __pending[id];
        reject(new Error('MassaMobile channel unavailable'));
      }
      setTimeout(function () {
        if (__pending[id]) {
          delete __pending[id];
          reject(new Error('timeout: ' + method));
        }
      }, 120000);
    });
  }

  window.__massaResolve = function (id, payloadJson) {
    var p = __pending[id];
    if (!p) return;
    delete __pending[id];
    try {
      var payload = JSON.parse(payloadJson);
      if (payload.error) { p.reject(new Error(payload.error)); }
      else { p.resolve(payload.result); }
    } catch (e) { p.reject(e); }
  };

  function makeProvider() {
    var provider = {
      // --- classic window.massa interface ---
      enable: function () {
        return callNative('enable').then(function (r) { return [r.address]; });
      },
      accounts: function () {
        return callNative('accounts');
      },
      address: function () {
        return callNative('accounts').then(function (accs) {
          return (accs && accs[0] && accs[0].address) || null;
        });
      },
      network: function () {
        return callNative('network');
      },
      sign: function (data) {
        return callNative('sign', { data: String(data) });
      },
      signOperation: function (serializedOperationBase58) {
        return callNative('signOperation', { data: String(serializedOperationBase58) });
      },
      sendTransaction: function (to, amount) {
        return callNative('sendTransaction', { to: String(to), amount: String(amount) });
      },
      buyRolls: function (amount) {
        return callNative('buyRolls', { amount: String(amount) });
      },
      sellRolls: function (amount) {
        return callNative('sellRolls', { amount: String(amount) });
      },
      callSC: function (target, func, argsBase58, coins) {
        return callNative('callSC', {
          target: String(target), func: String(func),
          argsBase58: argsBase58 ? String(argsBase58) : '',
          coins: coins ? String(coins) : '0'
        });
      },
      balance: function (addr) {
        return callNative('balance', { address: addr || null });
      },
      // --- modern request surface ---
      request: function (req) {
        return callNative(req && req.method, req && req.params);
      },
      isMassa: true
    };
    return provider;
  }

  window.massa = makeProvider();
  window.massaWallet = window.massa;

  window.dispatchEvent(new Event('massa#initialized'));
  window.dispatchEvent(new CustomEvent('massa#accountChanged', { detail: $account }));

  // Announce presence (some dApps poll for it).
  console.log('[massa] in-app provider injected (chainId $chainId, $networkName)');
})();
''';
}

/// Parsed request coming from the JS bridge.
class Web3Request {
  /// Monotonic request id.
  final int id;

  /// Method name (e.g. `enable`, `sendTransaction`).
  final String method;

  /// JSON params object.
  final Map<String, dynamic> params;

  /// Creates the request.
  const Web3Request({
    required this.id,
    required this.method,
    required this.params,
  });

  /// Parses the channel payload; returns null for malformed messages.
  static Web3Request? tryParse(String message) {
    try {
      final decoded = json.decode(message);
      if (decoded is! Map<String, dynamic>) return null;
      final id = (decoded['id'] as num?)?.toInt();
      final method = decoded['method'] as String?;
      if (id == null || method == null) return null;
      final params = decoded['params'];
      return Web3Request(
        id: id,
        method: method,
        params: params is Map<String, dynamic> ? params : const {},
      );
    } on FormatException {
      return null;
    }
  }

  /// Builds the JS resolution call for this request.
  String resolveJs(Object? result) =>
      '__massaResolve($id, ${json.encode(json.encode({'result': result}))})';

  /// Builds the JS rejection call for this request.
  String rejectJs(String error) =>
      '__massaResolve($id, ${json.encode(json.encode({'error': error}))})';
}
