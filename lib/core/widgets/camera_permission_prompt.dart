import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_typography.dart';

Future<void> showEnableCameraDialog({
  required BuildContext context,
  Future<void> Function()? onRetry,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.camera_alt_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('Enable Camera', style: AppTypography.heading4),
          ],
        ),
        content: Text(
          kIsWeb
              ? 'Camera access is required to scan barcodes.\n\nTo enable it: click the lock icon near the address bar → Site settings → Camera → Allow. Then press Retry.\n\nNote: most browsers only allow camera on HTTPS or localhost.'
              : 'Camera access is required to scan barcodes.\n\nTo enable it: open your device Settings → App permissions → Camera → Allow. Then return and press Retry.',
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          if (onRetry != null)
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await onRetry();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.white,
              ),
              child: const Text('Retry'),
            ),
        ],
      );
    },
  );
}

class CameraPermissionInlineMessage extends StatelessWidget {
  final VoidCallback? onEnable;

  const CameraPermissionInlineMessage({super.key, this.onEnable});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_off_rounded, color: Colors.white),
                const SizedBox(height: 12),
                Text(
                  'Camera access is needed to scan.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 12),
                if (onEnable != null)
                  ElevatedButton.icon(
                    onPressed: onEnable,
                    icon: const Icon(Icons.settings_rounded),
                    label: const Text('Enable camera'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.white,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
