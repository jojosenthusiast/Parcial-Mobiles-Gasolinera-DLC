import 'package:dlc_operations/customer_qr_scanner_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  test('only non-empty QR payloads are accepted as customer identities', () {
    const barcode = Barcode(
      format: BarcodeFormat.qrCode,
      rawValue: '  public-code-123  ',
    );
    expect(customerQrCodeFromBarcodes([barcode]), 'public-code-123');
  });

  test('other barcode formats and empty QR values are ignored', () {
    const code128 = Barcode(format: BarcodeFormat.code128, rawValue: 'other');
    const emptyQr = Barcode(format: BarcodeFormat.qrCode, rawValue: '  ');
    expect(customerQrCodeFromBarcodes([code128, emptyQr]), isNull);
  });

  test('QR payloads above the API input limit are ignored', () {
    final longQr = Barcode(
      format: BarcodeFormat.qrCode,
      rawValue: List.filled(201, 'x').join(),
    );
    expect(customerQrCodeFromBarcodes([longQr]), isNull);
  });
}
