import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/services/security_service.dart';
import 'core/services/settings_provider.dart';
import 'core/services/wallet_provider.dart';
import 'core/services/wallet_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsProvider();
  final security = SecurityService(settings: settings);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<SecurityService>.value(value: security),
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
