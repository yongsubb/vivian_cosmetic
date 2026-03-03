class PaymentQrConfig {
  /// Asset paths (optional). Put your images here:
  /// - assets/payment/gcash_qr.png
  /// - assets/payment/maya_qr.png
  static const String gcashQrAssetPath = 'assets/payment/gcash_qr.png';
  static const String mayaQrAssetPath = 'assets/payment/maya_qr.png';

  /// Configure these via build/run flags:
  ///
  /// - `--dart-define=GCASH_QR_PAYLOAD=<your merchant QR payload>`
  /// - `--dart-define=MAYA_QR_PAYLOAD=<your merchant QR payload>`
  ///
  /// The value must be the exact string payload your wallet expects.
  /// If left empty, a placeholder QR is shown.
  static String get gcashQrPayload {
    const v = String.fromEnvironment('GCASH_QR_PAYLOAD');
    final trimmed = v.trim();
    return trimmed.isNotEmpty ? trimmed : 'GCASH_QR_NOT_CONFIGURED';
  }

  static String get mayaQrPayload {
    const v = String.fromEnvironment('MAYA_QR_PAYLOAD');
    final trimmed = v.trim();
    return trimmed.isNotEmpty ? trimmed : 'MAYA_QR_NOT_CONFIGURED';
  }
}
