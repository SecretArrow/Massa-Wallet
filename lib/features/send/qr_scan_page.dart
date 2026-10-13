/// Full-screen QR scanner page (shared by MAS + token send flows).
library;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/i18n/app_i18n.dart';

/// Full-screen QR scanner page. Pops with the scanned string.
class QrScanPage extends StatelessWidget {
  /// Creates the scanner page.
  const QrScanPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('send.scanTitle'))),
      body: MobileScanner(
        onDetect: (capture) {
          for (final barcode in capture.barcodes) {
            final value = barcode.rawValue;
            if (value != null && value.isNotEmpty) {
              Navigator.of(context).pop(value);
              return;
            }
          }
        },
      ),
    );
  }
}
