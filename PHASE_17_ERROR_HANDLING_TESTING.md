# Phase 17: Error Handling - Testing Guide

## Overview
Phase 17 implements comprehensive error handling with:
- Global error handler
- Network error handling with automatic retry
- User-friendly error messages
- Error logging and reporting

## Components Implemented

### 1. Global Error Handler (`lib/core/services/error_handler.dart`)
- Catches all unhandled Flutter errors
- Catches async/platform errors
- Logs errors with context and stack traces
- Provides user-friendly error messages
- Shows error dialogs and snackbars

### 2. Network Retry Service (`lib/core/services/network_retry.dart`)
- Automatic retry on transient network errors
- Exponential backoff strategy
- Configurable retry attempts and delays
- Smart error detection (SocketException, HttpException, TimeoutException)

### 3. Enhanced API Service (`lib/services/api_service.dart`)
- All HTTP methods (GET, POST, PUT, DELETE) now have automatic retry
- Network errors logged to ErrorHandler
- Can disable retry on specific requests with `enableRetry: false`
- Retry config: 3 attempts, 1s initial delay, 2x backoff multiplier

### 4. Error Display Widgets (`lib/core/widgets/error_display.dart`)
- `ErrorDisplay`: Reusable error UI with retry button
- `LoadingOrError`: Combined loading/error/content state widget
- Extension methods for easy snackbar display

## Testing Scenarios

### Test 1: Global Error Handler
**Purpose**: Verify unhandled errors are caught and logged

1. **Force a Flutter Error**:
   - Temporarily add this code to any screen's build method:
   ```dart
   throw FlutterError('Test error');
   ```
   - App should catch error and show in console with 🔴 ERROR prefix
   - Error should not crash the app

2. **Force an Async Error**:
   - Temporarily add this code to any initState:
   ```dart
   Future.delayed(Duration(seconds: 1), () {
     throw Exception('Test async error');
   });
   ```
   - Error should be caught and logged with 📍 Context

3. **Check Error Logs**:
   - Errors are stored in `ErrorHandler().logs`
   - Can be displayed in a debug screen if needed

### Test 2: Network Retry Logic
**Purpose**: Verify automatic retry on network failures

1. **Test with Backend Stopped**:
   - Stop the Python backend (`Ctrl+C` in backend terminal)
   - Try to login or load any data
   - Watch console for retry messages: `🔄 Retry attempt 1/3`
   - Should see 3 retry attempts with increasing delays
   - After 3 attempts, shows error: "No internet connection"

2. **Test with Slow Network**:
   - Use Android emulator network throttling (Settings > Network > Network speed)
   - Set to "EDGE" (slow 2G)
   - Try loading products or dashboard
   - Should see retry attempts on timeout
   - Eventually succeeds or shows timeout error

3. **Test Recovery**:
   - Stop backend, try an action (should fail with retries)
   - Start backend again
   - Try the action again (should succeed immediately)

### Test 3: User-Friendly Error Messages
**Purpose**: Verify technical errors are translated to readable messages

Test these scenarios and verify the user-friendly messages:

| Technical Error | User-Friendly Message |
|----------------|----------------------|
| `SocketException` | "No internet connection. Please check your network." |
| `HttpException` | "Could not connect to server. Please try again." |
| Timeout | "Request timed out. Please check your connection." |
| 401 Unauthorized | "Session expired. Please login again." |
| 403 Forbidden | "You do not have permission to perform this action." |
| 404 Not Found | "The requested resource was not found." |
| 500 Server Error | "Server error occurred. Please try again later." |

**How to Test**:
1. **Network errors**: Turn off WiFi/mobile data
2. **401**: Wait for token to expire (or manually clear token)
3. **403**: Try accessing supervisor-only features as cashier
4. **404**: Try accessing non-existent product ID
5. **500**: Modify backend to return 500 for testing

### Test 4: Error Display Widgets
**Purpose**: Verify error UI components work correctly

1. **Compact Error Display**:
   ```dart
   ErrorDisplay(
     error: 'Test error',
     onRetry: () => print('Retry clicked'),
     compact: true,
   )
   ```
   - Shows red box with error icon, message, and retry button
   - Clicking retry executes the callback

2. **Full Error Display**:
   ```dart
   ErrorDisplay(
     error: SocketException('Network error'),
     onRetry: _loadData,
   )
   ```
   - Shows centered error UI with large icon
   - Displays user-friendly message
   - "Try Again" button triggers reload

3. **LoadingOrError Widget**:
   ```dart
   LoadingOrError(
     isLoading: _isLoading,
     error: _error,
     onRetry: _loadData,
     child: YourContentWidget(),
   )
   ```
   - Shows loading spinner when `_isLoading = true`
   - Shows error display when `_error != null`
   - Shows content when not loading and no error

### Test 5: Error Snackbars
**Purpose**: Verify quick error notifications

1. **Error Snackbar**:
   ```dart
   context.showErrorSnackbar(error);
   ```
   - Shows red snackbar at bottom
   - Displays user-friendly message
   - Has "Dismiss" button
   - Auto-dismisses after 4 seconds

2. **Success Snackbar**:
   ```dart
   context.showSuccessSnackbar('Product saved!');
   ```
   - Shows green snackbar
   - Auto-dismisses after 3 seconds

3. **Info Snackbar**:
   ```dart
   context.showInfoSnackbar('Syncing data...');
   ```
   - Shows blue snackbar
   - Auto-dismisses after 3 seconds

## Integration Examples

### Example 1: Error Handling in a Screen
```dart
class ProductListScreen extends StatefulWidget {
  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  List<Product> _products = [];
  bool _isLoading = false;
  dynamic _error;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await ApiService().get<List>(
        '/products',
        fromJsonT: (data) => data as List,
      );

      if (!mounted) return;

      if (response.success && response.data != null) {
        setState(() {
          _products = response.data!
              .map((json) => Product.fromJson(json))
              .toList();
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = response.message ?? 'Failed to load products';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Products')),
      body: LoadingOrError(
        isLoading: _isLoading,
        error: _error,
        onRetry: _loadProducts,
        child: ListView.builder(
          itemCount: _products.length,
          itemBuilder: (context, index) {
            final product = _products[index];
            return ListTile(
              title: Text(product.name),
              subtitle: Text('\$${product.price}'),
            );
          },
        ),
      ),
    );
  }
}
```

### Example 2: Quick Action with Snackbar
```dart
Future<void> _deleteProduct(int productId) async {
  try {
    final response = await ApiService().delete(
      '/products/$productId',
      enableRetry: false, // Don't retry deletes
    );

    if (!mounted) return;

    if (response.success) {
      context.showSuccessSnackbar('Product deleted successfully');
      _loadProducts(); // Reload list
    } else {
      context.showErrorSnackbar(response.message);
    }
  } catch (e) {
    if (!mounted) return;
    context.showErrorSnackbar(e);
  }
}
```

### Example 3: With Error Dialog
```dart
Future<void> _processPayment() async {
  try {
    final response = await ApiService().post(
      '/transactions',
      body: {'amount': 100.0},
    );

    if (!mounted) return;

    if (response.success) {
      // Success!
      Navigator.pop(context);
    } else {
      // Show error dialog with retry option
      ErrorHandler.showErrorDialog(
        context,
        response.message ?? 'Payment failed',
        title: 'Payment Error',
        onRetry: _processPayment,
      );
    }
  } catch (e) {
    if (!mounted) return;
    ErrorHandler.showErrorDialog(
      context,
      e,
      title: 'Payment Error',
      onRetry: _processPayment,
    );
  }
}
```

## Error Logging

### Viewing Logs in Debug Mode
All errors are logged with this format:
```
🔴 ERROR: SocketException: Network is unreachable
📍 Context: GET /products
📚 Stack: [First 5 lines of stack trace]
```

### Accessing Error Logs Programmatically
```dart
// Get all logged errors
final logs = ErrorHandler().logs;

// Display in debug screen
for (final log in logs) {
  print('${log.timestamp}: ${log.shortMessage}');
  if (log.context != null) {
    print('Context: ${log.context}');
  }
}

// Clear logs
ErrorHandler().clearLogs();
```

## Production Considerations

### Remote Error Reporting (TODO)
The error handler has a placeholder for remote error reporting:
```dart
// TODO: In production, send to error tracking service
// Options:
// - Sentry (sentry_flutter package)
// - Firebase Crashlytics (firebase_crashlytics package)
// - Custom backend endpoint
```

To implement:
1. Choose an error tracking service
2. Add package to `pubspec.yaml`
3. Initialize in `main.dart`
4. Update `ErrorHandler.logError()` to send errors

Example with Sentry:
```dart
// In main.dart
await SentryFlutter.init(
  (options) {
    options.dsn = 'YOUR_SENTRY_DSN';
  },
  appRunner: () => runApp(MyApp()),
);

// In error_handler.dart
void logError(dynamic error, StackTrace? stackTrace, {String? context}) {
  // ... existing code ...
  
  // Send to Sentry in production
  if (kReleaseMode) {
    Sentry.captureException(
      error,
      stackTrace: stackTrace,
      hint: context != null ? Hint.withMap({'context': context}) : null,
    );
  }
}
```

## Configuration

### Retry Configuration
Default retry config in `ApiService`:
- Max attempts: 3
- Initial delay: 1 second
- Backoff multiplier: 2.0 (1s, 2s, 4s)

To customize per request:
```dart
// Disable retry for specific requests
final response = await ApiService().post(
  '/transactions',
  body: data,
  enableRetry: false,
);
```

To change global retry config, modify `_executeWithRetry` in `api_service.dart`:
```dart
config: const RetryConfig(
  maxAttempts: 5,              // More attempts
  initialDelay: Duration(milliseconds: 500),  // Faster first retry
  backoffMultiplier: 1.5,      // Slower exponential growth
),
```

### Error Log Limits
Default: 100 most recent errors
To change, modify `_maxLogs` in `error_handler.dart`:
```dart
int _maxLogs = 200; // Keep more errors
```

## Troubleshooting

### Issue: Too Many Retry Attempts
**Problem**: Network requests retrying too much, slowing down the app
**Solution**: Reduce `maxAttempts` in `RetryConfig` or disable retry for specific endpoints

### Issue: Error Messages Too Technical
**Problem**: Users seeing raw error messages
**Solution**: Add more mappings in `ErrorHandler.getUserFriendlyMessage()`

### Issue: Errors Not Being Logged
**Problem**: Errors not appearing in error logs
**Solution**: Ensure `ErrorHandler.initialize()` is called in `main()` before `runApp()`

### Issue: Retry Not Working
**Problem**: Requests fail immediately without retry
**Solution**: Check that `enableRetry: true` (default) and error is a network error

## Summary

Phase 17 Error Handling provides:
- ✅ Global error catching and logging
- ✅ Automatic network retry with exponential backoff
- ✅ User-friendly error messages for all error types
- ✅ Reusable error display widgets
- ✅ Easy-to-use snackbar extensions
- ✅ Ready for production error reporting integration

All network requests now automatically retry on transient failures, and all errors are logged for debugging. Users see friendly messages instead of technical jargon.
