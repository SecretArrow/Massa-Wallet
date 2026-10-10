// Live end-to-end check against buildnet (run manually, not part of CI):
//   dart run tool/live_check.dart
//
// Exercises the exact production code path: MNS resolution → DeWeb file
// fetch → MRC-20 metadata + balance.
import 'package:massa_wallet/core/api/massa_rpc.dart';
import 'package:massa_wallet/core/contracts/deweb_service.dart';
import 'package:massa_wallet/core/contracts/mns_service.dart';
import 'package:massa_wallet/core/contracts/mrc20_service.dart';

Future<void> main() async {
  const endpoint = 'https://buildnet.massa.net/api/v2';
  MassaRpcClient clientFactory() => MassaRpcClient(endpoint: endpoint);

  // 1. MNS resolution
  print('── MNS resolution ──');
  final mns = MnsService(clientFactory: clientFactory);
  final site = await mns.resolve('helloworld', mainnet: false);
  print('helloworld.massa → ${site.target} (SC=${site.isSmartContract})');

  // 2. DeWeb file fetch
  print('\n── DeWeb fetch ──');
  final deweb = DeWebService(clientFactory: clientFactory);
  final index = await deweb.fetchFile(site.target, '/');
  print('index.html: ${index.bytes.length} bytes, ${index.mimeType}');
  print('first line: ${String.fromCharCodes(index.bytes.take(80))}');
  final title = await deweb.readGlobalMetadata(site.target, 'TITLE');
  print('global TITLE: $title');

  // 3. MRC-20 (WMAS buildnet)
  print('\n── MRC-20 ──');
  final mrc20 = Mrc20Service(clientFactory: clientFactory);
  final token = await mrc20.loadToken(
    'AS12FW5Rs5YN2zdpEnqwj4iHUUPt9R4Eqjq2qtpJFNKW3mn33RuLU',
  );
  print('${token.name} (${token.symbol}), decimals=${token.decimals}');

  print('\nALL LIVE CHECKS PASSED');
}
