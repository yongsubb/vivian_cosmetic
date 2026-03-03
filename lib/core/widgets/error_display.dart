import 'package:flutter/material.dart';

import '../services/error_handler.dart';

/// Reusable error display widget with retry option
class ErrorDisplay extends StatelessWidget {
  final String? message;
  final dynamic error;
  final VoidCallback? onRetry;
  final bool compact;

  const ErrorDisplay({
    super.key,
    this.message,
    this.error,
    this.onRetry,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final displayMessage =
        message ?? ErrorHandler.getUserFriendlyMessage(error);

    if (compact) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                displayMessage,
                style: TextStyle(color: Colors.red.shade900, fontSize: 13),
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(width: 8),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(
              'Oops!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              displayMessage,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Loading state with error fallback
class LoadingOrError extends StatelessWidget {
  final bool isLoading;
  final dynamic error;
  final VoidCallback? onRetry;
  final Widget child;
  final String? loadingMessage;

  const LoadingOrError({
    super.key,
    required this.isLoading,
    this.error,
    this.onRetry,
    required this.child,
    this.loadingMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return ErrorDisplay(error: error, onRetry: onRetry);
    }

    if (isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            if (loadingMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                loadingMessage!,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
            ],
          ],
        ),
      );
    }

    return child;
  }
}

/// Snackbar helper extensions
extension ErrorSnackbarExtension on BuildContext {
  /// Show error snackbar
  void showErrorSnackbar(dynamic error, {String? message}) {
    ErrorHandler.showErrorSnackbar(this, error, message: message);
  }

  /// Show success snackbar
  void showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(this).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  /// Show info snackbar
  void showInfoSnackbar(String message) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
