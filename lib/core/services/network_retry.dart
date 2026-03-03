import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' show ClientException;
import 'package:http/http.dart' as http;

/// Network retry configuration
class RetryConfig {
  final int maxAttempts;
  final Duration initialDelay;
  final double backoffMultiplier;
  final Duration maxDelay;
  final bool retryOnTimeout;

  const RetryConfig({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(seconds: 1),
    this.backoffMultiplier = 2.0,
    this.maxDelay = const Duration(seconds: 10),
    this.retryOnTimeout = true,
  });

  static const defaultConfig = RetryConfig();
  static const quickRetry = RetryConfig(
    maxAttempts: 2,
    initialDelay: Duration(milliseconds: 500),
  );
  static const noRetry = RetryConfig(maxAttempts: 1);
}

/// Network retry helper for handling transient network errors
class NetworkRetry {
  /// Execute an async function with automatic retry on network errors
  static Future<T> execute<T>(
    Future<T> Function() action, {
    RetryConfig config = RetryConfig.defaultConfig,
    bool Function(dynamic error)? shouldRetry,
  }) async {
    int attempt = 0;
    Duration delay = config.initialDelay;

    while (true) {
      attempt++;

      try {
        return await action();
      } catch (error) {
        // Check if we should retry
        final shouldRetryError =
            shouldRetry?.call(error) ?? _defaultShouldRetry(error, config);

        // Don't retry if max attempts reached or error is not retryable
        if (attempt >= config.maxAttempts || !shouldRetryError) {
          rethrow;
        }

        // Log retry attempt
        if (kDebugMode) {
          debugPrint(
            '🔄 Retry attempt $attempt/${config.maxAttempts} after error: ${error.toString().substring(0, 100)}',
          );
        }

        // Wait before retrying with exponential backoff
        await Future.delayed(delay);

        // Increase delay for next attempt
        delay = Duration(
          milliseconds: (delay.inMilliseconds * config.backoffMultiplier)
              .round(),
        );

        // Cap at max delay
        if (delay > config.maxDelay) {
          delay = config.maxDelay;
        }
      }
    }
  }

  /// Default logic for determining if an error should trigger a retry
  static bool _defaultShouldRetry(dynamic error, RetryConfig config) {
    // Network errors that should be retried
    if (error is ClientException) return true;
    if (error is TimeoutException && config.retryOnTimeout) return true;

    // Check error message for network-related issues
    final errorStr = error.toString().toLowerCase();
    if (errorStr.contains('network')) return true;
    if (errorStr.contains('connection')) return true;
    if (errorStr.contains('timeout') && config.retryOnTimeout) return true;
    if (errorStr.contains('failed host lookup')) return true;

    // Don't retry other errors
    return false;
  }

  /// Check if error is a network error
  static bool isNetworkError(dynamic error) {
    if (error is ClientException) return true;
    if (error is TimeoutException) return true;

    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('network') ||
        errorStr.contains('connection') ||
        errorStr.contains('socket') ||
        errorStr.contains('timeout') ||
        errorStr.contains('failed host lookup');
  }

  /// Check if device has network connectivity (basic check)
  static Future<bool> checkConnectivity() async {
    // Web has browser-managed connectivity and may block probes via CORS.
    if (kIsWeb) return true;

    // Best-effort check without using `dart:io`.
    try {
      final res = await http
          .get(Uri.parse('https://example.com'))
          .timeout(const Duration(seconds: 5));
      return res.statusCode > 0;
    } catch (_) {
      return false;
    }
  }
}

/// Extension to easily add retry logic to futures
extension FutureRetryExtension<T> on Future<T> Function() {
  Future<T> withRetry([RetryConfig config = RetryConfig.defaultConfig]) {
    return NetworkRetry.execute(this, config: config);
  }
}
