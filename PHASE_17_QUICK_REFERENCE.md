# Phase 17: Error Handling - Quick Reference

## 🚀 Quick Start

### Import Required Files
```dart
import '../core/services/error_handler.dart';
import '../core/widgets/error_display.dart';
```

## 📱 Common Patterns

### Pattern 1: Loading/Error/Content State
```dart
class MyScreen extends StatefulWidget {
  @override
  State<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends State<MyScreen> {
  bool _isLoading = false;
  dynamic _error;
  List<Product> _data = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await ApiService().get<List>('/products');
      
      if (!mounted) return;

      if (response.success && response.data != null) {
        setState(() {
          _data = response.data!; // Parse your data
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = response.message;
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
      appBar: AppBar(title: const Text('My Screen')),
      body: LoadingOrError(
        isLoading: _isLoading,
        error: _error,
        onRetry: _loadData,
        child: ListView.builder(
          itemCount: _data.length,
          itemBuilder: (context, index) {
            return ListTile(title: Text(_data[index].name));
          },
        ),
      ),
    );
  }
}
```

### Pattern 2: Action with Snackbar Feedback
```dart
Future<void> _deleteItem(String id) async {
  try {
    final response = await ApiService().delete(
      '/items/$id',
      enableRetry: false, // Don't retry destructive actions
    );

    if (!mounted) return;

    if (response.success) {
      context.showSuccessSnackbar('Item deleted successfully');
      _loadData(); // Reload list
    } else {
      context.showErrorSnackbar(response.message);
    }
  } catch (e) {
    if (!mounted) return;
    context.showErrorSnackbar(e);
  }
}
```

### Pattern 3: Action with Error Dialog and Retry
```dart
Future<void> _processPayment(double amount) async {
  try {
    final response = await ApiService().post(
      '/transactions',
      body: {'amount': amount},
    );

    if (!mounted) return;

    if (response.success) {
      context.showSuccessSnackbar('Payment processed');
      Navigator.pop(context);
    } else {
      ErrorHandler.showErrorDialog(
        context,
        response.message ?? 'Payment failed',
        title: 'Payment Error',
        onRetry: () => _processPayment(amount),
      );
    }
  } catch (e) {
    if (!mounted) return;
    ErrorHandler.showErrorDialog(
      context,
      e,
      title: 'Payment Error',
      onRetry: () => _processPayment(amount),
    );
  }
}
```

### Pattern 4: Compact Error Display
```dart
Widget build(BuildContext context) {
  return Column(
    children: [
      if (_error != null)
        ErrorDisplay(
          error: _error,
          onRetry: _loadData,
          compact: true, // Shows inline red box
        ),
      // Rest of your content
    ],
  );
}
```

## 🎯 API Service Retry Control

### Automatic Retry (Default)
```dart
// Automatically retries on network errors
final response = await ApiService().get('/products');
```

### Disable Retry for Specific Requests
```dart
// Don't retry for: delete, create, update operations
final response = await ApiService().delete(
  '/products/$id',
  enableRetry: false,
);

final response = await ApiService().post(
  '/products',
  body: productData,
  enableRetry: false,
);
```

## 💬 Snackbar Extensions

### Error Snackbar (Red)
```dart
context.showErrorSnackbar(error);
// or with custom message
context.showErrorSnackbar(error, message: 'Failed to load data');
```

### Success Snackbar (Green)
```dart
context.showSuccessSnackbar('Product saved successfully!');
```

### Info Snackbar (Blue)
```dart
context.showInfoSnackbar('Syncing data...');
```

## 🔍 Error Dialog

### Basic Error Dialog
```dart
ErrorHandler.showErrorDialog(
  context,
  'Something went wrong',
  title: 'Error',
);
```

### Error Dialog with Retry Button
```dart
ErrorHandler.showErrorDialog(
  context,
  error,
  title: 'Connection Error',
  onRetry: _loadData,
);
```

## 📊 LoadingOrError Widget

### Basic Usage
```dart
LoadingOrError(
  isLoading: _isLoading,
  error: _error,
  onRetry: _loadData,
  child: MyContentWidget(),
)
```

### With Loading Message
```dart
LoadingOrError(
  isLoading: _isLoading,
  error: _error,
  onRetry: _loadData,
  loadingMessage: 'Loading products...',
  child: MyContentWidget(),
)
```

## 🎨 ErrorDisplay Widget

### Full Screen Error (Centered)
```dart
ErrorDisplay(
  error: _error,
  onRetry: _loadData,
)
```

### Compact Error (Inline)
```dart
ErrorDisplay(
  error: _error,
  onRetry: _loadData,
  compact: true,
)
```

### Custom Error Message
```dart
ErrorDisplay(
  message: 'Failed to load products. Please try again.',
  onRetry: _loadData,
)
```

## 🔧 User-Friendly Messages

Errors are automatically converted to user-friendly messages:

| Technical Error | Display Message |
|----------------|----------------|
| SocketException | "No internet connection. Please check your network." |
| HttpException | "Could not connect to server. Please try again." |
| TimeoutException | "Request timed out. Please check your connection." |
| 401 | "Session expired. Please login again." |
| 403 | "You do not have permission to perform this action." |
| 404 | "The requested resource was not found." |
| 500 | "Server error occurred. Please try again later." |

### Manual Conversion
```dart
String userMessage = ErrorHandler.getUserFriendlyMessage(error);
```

## ⚙️ Network Retry Configuration

### Current Default Settings
```dart
// In ApiService._executeWithRetry()
RetryConfig(
  maxAttempts: 3,              // Try 3 times total
  initialDelay: Duration(seconds: 1),    // Wait 1s before first retry
  backoffMultiplier: 2.0,      // Double delay each retry (1s, 2s, 4s)
)
```

### Custom Retry Config (Advanced)
```dart
// In network_retry.dart
await NetworkRetry.execute(
  () => myNetworkCall(),
  config: RetryConfig(
    maxAttempts: 5,
    initialDelay: Duration(milliseconds: 500),
    backoffMultiplier: 1.5,
  ),
);
```

## 📝 Error Logging

### View Logged Errors (Debug)
```dart
// Get all error logs
final logs = ErrorHandler().logs;

for (final log in logs) {
  print('${log.timestamp}: ${log.message}');
  if (log.context != null) {
    print('Context: ${log.context}');
  }
}

// Clear logs
ErrorHandler().clearLogs();
```

### Manual Error Logging
```dart
ErrorHandler().logError(
  error,
  StackTrace.current,
  context: 'Manual log from feature X',
);
```

## 🚫 Don't Do This

### ❌ Don't Catch Without Showing Error
```dart
// BAD
try {
  await ApiService().get('/products');
} catch (e) {
  // Error swallowed, user has no feedback!
}
```

### ✅ Do This Instead
```dart
// GOOD
try {
  final response = await ApiService().get('/products');
  if (!response.success) {
    context.showErrorSnackbar(response.message);
  }
} catch (e) {
  if (!mounted) return;
  context.showErrorSnackbar(e);
}
```

### ❌ Don't Show Technical Errors to Users
```dart
// BAD
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(content: Text(error.toString())), // Technical jargon
);
```

### ✅ Do This Instead
```dart
// GOOD
context.showErrorSnackbar(error); // Automatically user-friendly
```

### ❌ Don't Retry Critical Operations
```dart
// BAD - Can cause duplicate deletes/creates
await ApiService().delete('/products/$id'); // Has automatic retry!
```

### ✅ Do This Instead
```dart
// GOOD - Disable retry for destructive actions
await ApiService().delete(
  '/products/$id',
  enableRetry: false,
);
```

## 🎯 Best Practices

1. **Always check `mounted`** before `setState` in async callbacks
2. **Use `context.showErrorSnackbar()`** for quick feedback
3. **Use `ErrorHandler.showErrorDialog()`** for important errors with retry
4. **Use `LoadingOrError` widget** for screens that load data
5. **Disable retry** for create/update/delete operations
6. **Always provide retry callback** in error displays when possible
7. **Log errors** with context for debugging

## 📱 Testing Checklist

- [ ] Turn off WiFi, try loading data → See "No internet connection"
- [ ] Stop backend, try API call → See retry attempts in console
- [ ] Simulate 401 error → See "Session expired"
- [ ] Delete item → Verify no retry attempts
- [ ] Error snackbar dismisses after 4 seconds
- [ ] Success snackbar dismisses after 3 seconds
- [ ] Error dialog shows with retry button
- [ ] LoadingOrError shows spinner while loading
- [ ] LoadingOrError shows error display on failure

## 📚 More Info

- Full testing guide: `PHASE_17_ERROR_HANDLING_TESTING.md`
- Implementation details: `PHASE_17_ERROR_HANDLING_SUMMARY.md`

---

**Quick Reference Version 1.0** | Phase 17 Error Handling
