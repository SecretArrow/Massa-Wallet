import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/services/embedded_node_service.dart';
import 'core/services/security_service.dart';
import 'core/services/settings_provider.dart';
import 'core/services/wallet_provider.dart';
import 'core/services/wallet_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Edge-to-edge: draw behind the status bar (top) and the gesture
  // navigation bar (bottom). Screens use SafeArea so content never
  // collides with system UI.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final settings = SettingsProvider();
  final security = SecurityService(settings: settings);
  final embedded = EmbeddedNodeService(settings: settings);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<SecurityService>.value(value: security),
        ChangeNotifierProvider<EmbeddedNodeService>.value(value: embedded),
        ChangeNotifierProvider<WalletProvider>(
          create: (_) => WalletProvider(
            repository: WalletRepository(),
            settings: settings,
          ),
        ),
      ],
      child: const MassaWalletApp(),
    ),
  );
}
