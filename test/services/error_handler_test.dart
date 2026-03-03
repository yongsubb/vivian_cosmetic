import 'package:flutter_test/flutter_test.dart';
import 'package:vivian_cosmetic_shop_application/core/services/error_handler.dart';
import 'dart:io';

void main() {
  group('ErrorHandler Tests', () {
    late ErrorHandler errorHandler;

    setUp(() {
      errorHandler = ErrorHandler();
      errorHandler.clearLogs();
    });

    test('ErrorHandler should be singleton', () {
      final instance1 = ErrorHandler();
      final instance2 = ErrorHandler();

      expect(instance1, same(instance2));
    });

    test('logError should add error to logs', () {
      final error = Exception('Test error');

      errorHandler.logError(error, StackTrace.current, context: 'Test context');

      expect(errorHandler.logs.length, 1);
      expect(errorHandler.logs.first.context, 'Test context');
    });

    test('clearLogs should remove all logged errors', () {
      errorHandler.logError(Exception('Error 1'), StackTrace.current);
      errorHandler.logError(Exception('Error 2'), StackTrace.current);

      expect(errorHandler.logs.length, 2);

      errorHandler.clearLogs();

      expect(errorHandler.logs.length, 0);
    });

    test('getUserFriendlyMessage should convert SocketException', () {
      final error = SocketException('Network error');

      final message = ErrorHandler.getUserFriendlyMessage(error);

      expect(message, contains('internet connection'));
    });

    test('getUserFriendlyMessage should convert HttpException', () {
      final error = HttpException('HTTP error');

      final message = ErrorHandler.getUserFriendlyMessage(error);

      expect(message, contains('connect to server'));
    });

    test('getUserFriendlyMessage should handle timeout errors', () {
      final error = Exception('Connection timeout');

      final message = ErrorHandler.getUserFriendlyMessage(error);

      expect(message, contains('timed out'));
    });

    test('getUserFriendlyMessage should handle 401 unauthorized', () {
      final error = Exception('Unauthorized 401');

      final message = ErrorHandler.getUserFriendlyMessage(error);

      expect(message, contains('Session expired'));
    });

    test('getUserFriendlyMessage should handle 403 forbidden', () {
      final error = Exception('Forbidden 403');

      final message = ErrorHandler.getUserFriendlyMessage(error);

      expect(message, contains('permission'));
    });

    test('getUserFriendlyMessage should handle 404 not found', () {
      final error = Exception('Not found 404');

      final message = ErrorHandler.getUserFriendlyMessage(error);

      expect(message, contains('not found'));
    });

    test('getUserFriendlyMessage should handle 500 server error', () {
      final error = Exception('Server error 500');

      final message = ErrorHandler.getUserFriendlyMessage(error);

      expect(message, contains('Server error'));
    });

    test(
      'getUserFriendlyMessage should return generic message for unknown errors',
      () {
        final error = Exception('Unknown error type');

        final message = ErrorHandler.getUserFriendlyMessage(error);

        expect(message, 'An error occurred. Please try again.');
      },
    );

    test('ErrorLog should store error details', () {
      final error = Exception('Test error');
      final stackTrace = StackTrace.current;
      final timestamp = DateTime.now();

      errorHandler.logError(error, stackTrace, context: 'Test');

      final log = errorHandler.logs.first;

      expect(log.error, error);
      expect(log.stackTrace, stackTrace);
      expect(log.context, 'Test');
      expect(log.timestamp.difference(timestamp).inSeconds, lessThan(1));
    });

    test('ErrorLog message should return error string', () {
      final error = Exception('Test error message');

      errorHandler.logError(error, StackTrace.current);

      final log = errorHandler.logs.first;

      expect(log.message, contains('Test error message'));
    });

    test('ErrorLog shortMessage should truncate long messages', () {
      final longError = Exception('A' * 150);

      errorHandler.logError(longError, StackTrace.current);

      final log = errorHandler.logs.first;

      expect(log.shortMessage.length, lessThanOrEqualTo(103)); // 100 + '...'
    });

    test('Error logs should be limited to maxLogs', () {
      // Log more than maxLogs (100) errors
      for (int i = 0; i < 105; i++) {
        errorHandler.logError(Exception('Error $i'), StackTrace.current);
      }

      expect(errorHandler.logs.length, 100);
    });
  });
}
