import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:mobile_scanner/mobile_scanner.dart';

String? customerQrCodeFromBarcodes(Iterable<Barcode> barcodes) {
  for (final barcode in barcodes) {
    if (barcode.format != BarcodeFormat.qrCode) continue;
    final value = barcode.rawValue?.trim();
    if (value != null && value.isNotEmpty && value.length <= 200) return value;
  }
  return null;
}

class CustomerQrScannerScreen extends StatefulWidget {
  const CustomerQrScannerScreen({super.key});
  @override
  State<CustomerQrScannerScreen> createState() =>
      _CustomerQrScannerScreenState();
}

class _CustomerQrScannerScreenState extends State<CustomerQrScannerScreen> {
  late final MobileScannerController _controller;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (_completed) return;
    final code = customerQrCodeFromBarcodes(capture.barcodes);
    if (code == null) return;
    _completed = true;
    Navigator.of(context).pop(code);
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Escanear QR del Cliente')),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Centra el QR de identidad del Cliente dentro del marco. El QR solo identifica la cuenta; el Cliente debe autorizar cualquier pago con puntos desde su propia app.',
          ),
        ),
        Expanded(
          child: MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(CupertinoIcons.camera, size: 48),
                    const SizedBox(height: 12),
                    const Text(
                      'No se pudo iniciar la cámara. Revisa el permiso y vuelve al campo para introducir el código manualmente.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(CupertinoIcons.pencil),
                      label: const Text('Usar código manual'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(CupertinoIcons.xmark),
              label: const Text('Cancelar'),
            ),
          ),
        ),
      ],
    ),
  );
}
