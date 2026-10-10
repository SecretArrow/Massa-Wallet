/// Massa JSON-RPC v2 client.
///
/// Byte/semantics-compatible with `@massalabs/massa-web3` `JsonRpcProvider`:
/// `POST {jsonrpc: "2.0", method, params: [...], id}` to
/// `https://buildnet.massa.net/api/v2` / `https://mainnet.massa.net/api/v2`.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'massa_models.dart';

/// Well-known Massa networks.
enum MassaNetwork {
  /// Mainnet — chainId 77658377.
  mainnet(
    name: 'Mainnet',
    chainId: 77658377,
    apiUrl: 'https://mainnet.massa.net/api/v2',
  ),

  /// Buildnet (testnet) — chainId 77658366, has a faucet.
  buildnet(
    name: 'Buildnet',
    chainId: 77658366,
    apiUrl: 'https://buildnet.massa.net/api/v2',
  );

  const MassaNetwork({
    required this.name,
    required this.chainId,
    required this.apiUrl,
  });

  /// Human network name.
  final String name;

  /// Chain identifier (u64) used for operation signing.
  final int chainId;

  /// Public JSON-RPC endpoint.
  final String apiUrl;
}

/// A Massa JSON-RPC v2 client.
class MassaRpcClient {
  /// RPC endpoint URL (public API or a custom/local node).
  final String endpoint;

  /// HTTP client (injectable for tests).
  final http.Client httpClient;

  int _id = 0;

  /// Creates a client for [endpoint].
  MassaRpcClient({required this.endpoint, http.Client? httpClient})
    : httpClient = httpClient ?? http.Client();

  /// Client for one of the known [network]s.
  factory MassaRpcClient.forNetwork(
    MassaNetwork network, {
    http.Client? httpClient,
  }) => MassaRpcClient(endpoint: network.apiUrl, httpClient: httpClient);

  /// Issues a JSON-RPC request. [params] is wrapped into the params array
  /// exactly like massa-web3 does.
  Future<dynamic> call(String method, [Object? params]) async {
    _id++;
    final body = json.encode({
      'jsonrpc': '2.0',
      'method': method,
      'params': params == null ? [] : [params],
      'id': _id,
    });
    final res = await httpClient.post(
      Uri.parse(endpoint),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    if (res.statusCode != 200) {
      throw RpcException('HTTP ${res.statusCode}: ${res.body}');
    }
    final decoded = json.decode(res.body) as Map<String, dynamic>;
    final error = decoded['error'];
    if (error != null) {
      final message = error is Map ? error['message'] ?? '$error' : '$error';
      throw RpcException(message.toString());
    }
    return decoded['result'];
  }

  /// Node status (chain id, minimal fee, current period...).
  Future<NodeStatus> getStatus() async {
    final r = await call('get_status');
    return NodeStatus.fromJson(r as Map<String, dynamic>);
  }

  /// Address info for a list of addresses.
  Future<List<AddressInfo>> getAddresses(List<String> addresses) async {
    final r = await call('get_addresses', addresses);
    return (r as List)
        .map((e) => AddressInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Fetches address info for a single address.
  Future<AddressInfo> getAddressInfo(String address) async =>
      (await getAddresses([address])).first;

  /// Sends serialized & signed operations; returns operation ids.
  Future<List<String>> sendOperations(List<SendOperationInput> ops) async {
    final r = await call(
      'send_operations',
      ops
          .map(
            (op) => {
              'serialized_content': op.serializedContent,
              'creator_public_key': op.creatorPublicKey,
              'signature': op.signature,
            },
          )
          .toList(),
    );
    return (r as List).cast<String>();
  }

  /// Executes a read-only smart-contract call (no state change, no fee).
  Future<ReadOnlyCallResult> executeReadOnlyCall(
    ReadOnlyCallInput input,
  ) async {
    final r = await call('execute_read_only_call', [
      {
        'max_gas': input.maxGas,
        'target_address': input.targetAddress,
        'target_function': input.targetFunction,
        'parameter': input.parameter,
        'caller_address': input.callerAddress,
        'coins': input.coins,
        'fee': input.fee,
      },
    ]);
    final list = r as List;
    if (list.isEmpty) {
      throw const RpcException('execute_read_only_call: empty result');
    }
    return ReadOnlyCallResult.fromJson(list.first as Map<String, dynamic>);
  }

  /// Fetches operation info by ids.
  Future<List<OperationInfo>> getOperations(List<String> ids) async {
    final r = await call('get_operations', ids);
    return (r as List)
        .map((e) => OperationInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Datastore entries for [requests].
  Future<List<DatastoreEntry>> getDatastoreEntries(
    List<DatastoreEntryInput> requests,
  ) async {
    final r = await call(
      'get_datastore_entries',
      requests.map((e) => {'address': e.address, 'key': e.key}).toList(),
    );
    return (r as List)
        .map((e) => DatastoreEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Stakers with roll counts (paginated).
  Future<List<StakerEntry>> getStakers({int offset = 0, int limit = 20}) async {
    final r = await call('get_stakers', {'offset': offset, 'limit': limit});
    return (r as List).map((e) => StakerEntry.fromList(e as List)).toList();
  }

  /// Booking quotes for deferred calls at the given slots.
  ///
  /// Node API: `get_deferred_call_quote` takes a single argument: an array
  /// of `{target_slot, max_gas_request, params_size}` requests.
  Future<List<DeferredCallQuote>> getDeferredCallQuote(
    List<DeferredCallQuoteInput> requests,
  ) async {
    final r = await call(
      'get_deferred_call_quote',
      requests
          .map(
            (e) => {
              'target_slot': e.targetSlot.toJson(),
              'max_gas_request': e.maxGasRequest,
              'params_size': e.paramsSize,
            },
          )
          .toList(),
    );
    return (r as List)
        .map((e) => DeferredCallQuote.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Registered deferred calls by ids (`D…`).
  Future<List<DeferredCallInfo>> getDeferredCallInfo(List<String> ids) async {
    final r = await call('get_deferred_call_info', ids);
    return (r as List)
        .map((e) => DeferredCallInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Deferred call ids scheduled at the given slots.
  Future<List<DeferredCallsSlotResponse>> getDeferredCallIdsBySlot(
    List<MassaSlot> slots,
  ) async {
    final r = await call(
      'get_deferred_call_ids_by_slot',
      slots.map((s) => s.toJson()).toList(),
    );
    return (r as List)
        .map(
          (e) => DeferredCallsSlotResponse.fromJson(e as Map<String, dynamic>),
        )
        .toList();
  }

  void dispose() => httpClient.close();
}

/// JSON-RPC error.
class RpcException implements Exception {
  /// Error message.
  final String message;

  /// Creates an RPC exception.
  const RpcException(this.message);

  @override
  String toString() => 'RpcException: $message';
}

/// Input for `get_deferred_call_quote`.
class DeferredCallQuoteInput {
  /// Slot to book.
  final MassaSlot targetSlot;

  /// Maximum gas the deferred execution may consume.
  final int maxGasRequest;

  /// Size of the serialized parameters, in bytes.
  final int paramsSize;

  /// Creates a quote request.
  const DeferredCallQuoteInput({
    required this.targetSlot,
    required this.maxGasRequest,
    this.paramsSize = 0,
  });
}

/// `get_deferred_call_ids_by_slot` response item.
class DeferredCallsSlotResponse {
  /// Queried slot.
  final MassaSlot slot;

  /// Deferred call ids scheduled at [slot].
  final List<String> callIds;

  /// Creates a slot response.
  const DeferredCallsSlotResponse({required this.slot, required this.callIds});

  /// Parses from the JSON-RPC result item.
  factory DeferredCallsSlotResponse.fromJson(Map<String, dynamic> json) =>
      DeferredCallsSlotResponse(
        slot: MassaSlot.fromJson(json['slot'] as Map<String, dynamic>),
        callIds: ((json['call_ids'] as List?) ?? const []).cast<String>(),
      );
}
