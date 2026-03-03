import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Returns true if the `mobile_scanner` plugin has a platform implementation.
///
/// `mobile_scanner` supports: Android, iOS, macOS, Web.
/// It does not support Windows/Linux desktop, so using it there throws
/// MissingPluginException.
bool get isMobileScannerSupported {
  if (kIsWeb) return true;

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return true;
    default:
      return false;
  }
}

Future<void> showScannerUnsupportedDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Scanner not supported'),
        content: Text(
          kIsWeb
              ? 'Barcode scanning should be available in the browser. If you still see this, try a hard refresh (Ctrl+F5) or rebuild your web release.'
              : 'Barcode scanning is not available on this platform.\n\nUse the Web app (Chrome/Edge), Android, iOS, or macOS to scan using the camera. On Windows desktop you can still enter the barcode manually.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}

class ScannerUnsupportedInlineMessage extends StatelessWidget {
  const ScannerUnsupportedInlineMessage({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.block_rounded, color: Colors.white),
                SizedBox(height: 12),
                Text(
                  'Camera barcode scanning is not supported on this platform.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
                SizedBox(height: 8),
                Text(
                  'Use Web/Android/iOS/macOS or enter the barcode manually.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
