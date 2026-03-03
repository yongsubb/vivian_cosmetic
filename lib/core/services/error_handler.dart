import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' show ClientException;

/// Global error handler service for catching and logging errors
class ErrorHandler {
  static final ErrorHandler _instance = ErrorHandler._();
  factory ErrorHandler() => _instance;
  ErrorHandler._();

  final List<ErrorLog> _errorLogs = [];
  final int _maxLogs = 100;

  /// Initialize the global error handler
  static void initialize() {
    // Catch Flutter framework errors
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      ErrorHandler().logError(
        details.exception,
        details.stack,
        context: 'Flutter Framework Error',
      );
    };

    // Catch errors outside of Flutter (async errors, etc)
    PlatformDispatcher.instance.onError = (error, stack) {
      ErrorHandler().logError(error, stack, context: 'Platform Error');
      return true; // Handled
    };
  }

  /// Log an error
  void logError(dynamic error, StackTrace? stackTrace, {String? context}) {
    final errorLog = ErrorLog(
      error: error,
      stackTrace: stackTrace,
      timestamp: DateTime.now(),
      context: context,
    );

    _errorLogs.add(errorLog);

    // Keep only the last N logs
    if (_errorLogs.length > _maxLogs) {
      _errorLogs.removeAt(0);
    }

    // Log to console in debug mode
    if (kDebugMode) {
      debugPrint('🔴 ERROR: ${errorLog.message}');
      if (context != null) {
        debugPrint('📍 Context: $context');
      }
      if (stackTrace != null) {
        debugPrint(
          '📚 Stack: ${stackTrace.toString().split('\n').take(5).join('\n')}',
        );
      }
    }

    // TODO: In production, send to error tracking service (e.g., Sentry, Firebase Crashlytics)
  }

  /// Get all logged errors
  List<ErrorLog> get logs => List.unmodifiable(_errorLogs);

  /// Clear all logs
  void clearLogs() {
    _errorLogs.clear();
  }

  /// Get user-friendly error message
  static String getUserFriendlyMessage(dynamic error) {
    if (error == null) return 'An unknown error occurred';

    final errorStr = error.toString().toLowerCase();

    // Network errors
    if (errorStr.contains('socketexception') ||
        errorStr.contains('failed host lookup') ||
        errorStr.contains('name or service not known') ||
        errorStr.contains('network is unreachable') ||
        errorStr.contains('no address associated with hostname')) {
      return 'No internet connection. Please check your network.';
    }
    if (error is ClientException ||
        errorStr.contains('clientexception') ||
        errorStr.contains('xmlhttprequest error') ||
        errorStr.contains('connection refused') ||
        errorStr.contains('connection reset') ||
        errorStr.contains('connection closed') ||
        errorStr.contains('http')) {
      return 'Could not connect to server. Please try again.';
    }
    if (errorStr.contains('timeout')) {
      return 'Request timed out. Please check your connection.';
    }
    if (errorStr.contains('connection refused')) {
      return 'Server is not available. Please try again later.';
    }

    // Authentication errors
    if (errorStr.contains('unauthorized') || errorStr.contains('401')) {
      return 'Session expired. Please login again.';
    }
    if (errorStr.contains('forbidden') || errorStr.contains('403')) {
      return 'You do not have permission to perform this action.';
    }

    // Data errors
    if (errorStr.contains('not found') || errorStr.contains('404')) {
      return 'The requested resource was not found.';
    }
    if (errorStr.contains('parse') || errorStr.contains('format')) {
      return 'Invalid data format. Please try again.';
    }

    // Server errors
    if (errorStr.contains('500') || errorStr.contains('server error')) {
      return 'Server error occurred. Please try again later.';
    }

    // Default message
    return 'An error occurred. Please try again.';
  }

  /// Show error dialog to user
  static void showErrorDialog(
    BuildContext context,
    dynamic error, {
    String? title,
    VoidCallback? onRetry,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title ?? 'Error'),
        content: Text(getUserFriendlyMessage(error)),
        actions: [
          if (onRetry != null)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                onRetry();
              },
              child: const Text('Retry'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Show error snackbar to user
  static void showErrorSnackbar(
    BuildContext context,
    dynamic error, {
    String? message,
    Duration? duration,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message ?? getUserFriendlyMessage(error)),
        backgroundColor: Colors.red,
        duration: duration ?? const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }
}

/// Error log entry
class ErrorLog {
  final dynamic error;
  final StackTrace? stackTrace;
  final DateTime timestamp;
  final String? context;

  ErrorLog({
    required this.error,
    this.stackTrace,
    required this.timestamp,
    this.context,
  });

  String get message {
    if (error == null) return 'Unknown error';
    return error.toString();
  }

  String get shortMessage {
    final msg = message;
    if (msg.length > 100) {
      return '${msg.substring(0, 100)}...';
    }
    return msg;
  }
}
