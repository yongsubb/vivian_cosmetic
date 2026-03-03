/// API Service for connecting to the Python backend
/// Handles HTTP requests, authentication, and token management
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/services/error_handler.dart';
import '../core/services/network_retry.dart';
import '../offline/offline_store.dart';
import 'token_storage/token_storage.dart';

/// API Configuration
class ApiConfig {
  // Change this to your backend URL
  // For Android physical device, use your PC's IP (e.g., 192.168.1.8)
  // For Android emulator use: 10.0.2.2
  // For iOS simulator use: localhost
  static String get baseUrl {
    // Web + CI/prod can override without changing code:
    // `--dart-define=API_BASE_URL=http://localhost:5000`
    const override = String.fromEnvironment('API_BASE_URL');
    if (override.trim().isNotEmpty) {
      return _normalizeBaseUrl(override);
    }

    if (kIsWeb) {
      // Use the browser host so the app works via LAN IP too.
      // Example: if opened at http://192.168.1.10/... then API defaults to http://192.168.1.10:5000
      final host = Uri.base.host;
      final scheme = Uri.base.scheme.isNotEmpty ? Uri.base.scheme : 'http';
      return _normalizeBaseUrl(
        '$scheme://${host.isNotEmpty ? host : 'localhost'}:5000',
      );
    }

    // For physical Android device via USB debugging, use your PC's local IP
    // You can find it by running: ipconfig (Windows) or ifconfig (Mac/Linux)
    if (defaultTargetPlatform == TargetPlatform.android) {
      // If using physical device (USB debugging), use your PC's IP address:
      // Current IP: 192.168.1.8 (Update this if your IP changes)
      return _normalizeBaseUrl('http://10.81.31.46:5000');

      // If using Android emulator, uncomment this line instead:
      // return 'http://10.0.2.2:5000';
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      // iOS simulator can use localhost
      return _normalizeBaseUrl('http://localhost:5000');
    } else {
      // Windows/Linux/MacOS desktop
      return _normalizeBaseUrl('http://localhost:5000');
    }
  }

  static String _normalizeBaseUrl(String raw) {
    var trimmed = raw.trim();
    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }

    // People often (accidentally) pass the full API URL here, e.g.
    // `http://localhost:5000/api`. Our code appends `/api` internally,
    // so strip a trailing `/api` to prevent `/api/api/...`.
    if (trimmed.toLowerCase().endsWith('/api')) {
      trimmed = trimmed.substring(0, trimmed.length - 4);
    }

    return trimmed;
  }

  static const String apiPrefix = '/api';

  /// Resolve media URLs returned by the backend.
  ///
  /// Supports:
  /// - Absolute URLs (http/https)
  /// - Relative paths like `/static/uploads/...` or `static/uploads/...`
  /// - Rewrites `localhost` / `127.0.0.1` host to the current [baseUrl] host
  ///   (important for Android devices, where localhost != your PC).
  static String? resolveMediaUrl(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final base = Uri.parse(baseUrl);
    final parsed = Uri.tryParse(trimmed);

    if (parsed != null && parsed.hasScheme) {
      if (parsed.host == 'localhost' || parsed.host == '127.0.0.1') {
        return parsed
            .replace(
              scheme: base.scheme,
              host: base.host,
              port: base.hasPort ? base.port : null,
            )
            .toString();
      }
      return trimmed;
    }

    var path = trimmed;
    if (path.startsWith('$apiPrefix/')) {
      path = path.substring(apiPrefix.length);
    }
    if (!path.startsWith('/')) path = '/$path';

    return base.replace(path: path).toString();
  }

  static String get apiUrl {
    return '$baseUrl$apiPrefix';
  }

  // Timeouts
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
}

/// API Response wrapper
class ApiResponse<T> {
  final bool success;
  final String? message;
  final T? data;
  final int statusCode;

  ApiResponse({
    required this.success,
    this.message,
    this.data,
    required this.statusCode,
  });

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    int statusCode, [
    T Function(dynamic)? fromJsonT,
  ]) {
    return ApiResponse(
      success: json['success'] ?? false,
      message: json['message'],
      data: fromJsonT != null && json['data'] != null
          ? fromJsonT(json['data'])
          : json['data'],
      statusCode: statusCode,
    );
  }

  factory ApiResponse.error(String message, [int statusCode = 500]) {
    return ApiResponse(
      success: false,
      message: message,
      statusCode: statusCode,
    );
  }
}

/// Authentication data
class AuthData {
  final String accessToken;
  final String refreshToken;
  final Map<String, dynamic> user;

  AuthData({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  factory AuthData.fromJson(Map<String, dynamic> json) {
    return AuthData(
      accessToken: json['access_token'] ?? '',
      refreshToken: json['refresh_token'] ?? '',
      user: json['user'] ?? {},
    );
  }
}

/// Main API Service
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final TokenStorage _tokenStorage = TokenStorage();

  Future<String?> _readTokenValue(String key) {
    return _tokenStorage.read(key);
  }

  Future<void> _writeTokenValue(String key, String? value) {
    return _tokenStorage.write(key, value);
  }

  String? _accessToken;
  String? _refreshToken;
  Map<String, dynamic>? _currentUser;

  Future<bool>? _refreshInFlight;

  // Getters
  String? get accessToken => _accessToken;
  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isLoggedIn => _accessToken != null;

  bool _isConnectivityError(ApiResponse<dynamic> response) {
    final msg = (response.message ?? '').toLowerCase();
    return msg.contains('no internet connection') ||
        msg.contains('could not connect to server');
  }

  String _currentCashierNameFallback() {
    final u = _currentUser;
    final name =
        (u?['display_name'] ??
                u?['nickname'] ??
                u?['full_name'] ??
                u?['username'])
            ?.toString();
    if (name != null && name.trim().isNotEmpty) return name.trim();
    return 'User';
  }

  Future<ApiResponse<Map<String, dynamic>>> _createTransactionOnline(
    Map<String, dynamic> payload,
  ) async {
    return await post<Map<String, dynamic>>(
      '/transactions',
      body: payload,
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Attempt to sync queued offline transactions.
  ///
  /// Best-effort: failures are swallowed and do not affect current user flow.
  Future<int> syncOfflineTransactions({int maxToSync = 25}) async {
    try {
      return await OfflineStore.syncQueuedTransactions(
        maxToSync: maxToSync,
        sendOnline: (payload) async {
          final res = await _createTransactionOnline(payload);
          if (res.success && res.data != null) return res.data;
          if (_isConnectivityError(res)) return null;
          // If it's a validation/server error, keep it in the queue for manual retry later.
          return null;
        },
      );
    } catch (e) {
      debugPrint('syncOfflineTransactions error: $e');
      return 0;
    }
  }

  bool _shouldAttemptAutoRefresh(String endpoint) {
    if (_refreshToken == null) return false;
    if (endpoint == '/auth/refresh') return false;
    if (endpoint == '/auth/login') return false;
    if (endpoint == '/auth/pin-login') return false;
    return true;
  }

  Future<bool> _refreshOnce() async {
    if (_refreshInFlight != null) return _refreshInFlight!;

    _refreshInFlight = refreshToken().whenComplete(() {
      _refreshInFlight = null;
    });

    return _refreshInFlight!;
  }

  /// Initialize service - load saved tokens
  Future<void> init() async {
    _accessToken = await _readTokenValue('access_token');
    _refreshToken = await _readTokenValue('refresh_token');
    final userJson = await _readTokenValue('current_user');
    if (userJson != null) {
      _currentUser = jsonDecode(userJson);
    }
  }

  /// Save tokens to storage
  Future<void> _saveTokens(AuthData authData) async {
    _accessToken = authData.accessToken;
    _refreshToken = authData.refreshToken;
    _currentUser = authData.user;

    debugPrint('💾 Saving token: ${authData.accessToken.substring(0, 20)}...');

    await _writeTokenValue('access_token', authData.accessToken);
    await _writeTokenValue('refresh_token', authData.refreshToken);
    await _writeTokenValue('current_user', jsonEncode(authData.user));

    debugPrint('✅ Token saved successfully');
  }

  /// Clear tokens
  Future<void> _clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    _currentUser = null;

    await _writeTokenValue('access_token', null);
    await _writeTokenValue('refresh_token', null);
    await _writeTokenValue('current_user', null);
  }

  /// Get headers for requests
  Map<String, String> get _headers {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    return headers;
  }

  Map<String, String> get _multipartHeaders {
    // Don't set Content-Type here; MultipartRequest sets the boundary.
    final headers = {'Accept': 'application/json'};

    if (_accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }

    return headers;
  }

  /// Make GET request with automatic retry on network errors
  Future<ApiResponse<T>> get<T>(
    String endpoint, {
    Map<String, String>? queryParams,
    T Function(dynamic)? fromJsonT,
    bool enableRetry = true,
  }) async {
    return await _executeWithRetry(
      () =>
          _getRaw<T>(endpoint, queryParams: queryParams, fromJsonT: fromJsonT),
      enableRetry: enableRetry,
    );
  }

  Future<ApiResponse<T>> _getRaw<T>(
    String endpoint, {
    Map<String, String>? queryParams,
    T Function(dynamic)? fromJsonT,
  }) async {
    try {
      var uri = Uri.parse('${ApiConfig.apiUrl}$endpoint');
      if (queryParams != null) {
        uri = uri.replace(queryParameters: queryParams);
      }

      var response = await http
          .get(uri, headers: _headers)
          .timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 401 && _shouldAttemptAutoRefresh(endpoint)) {
        final refreshed = await _refreshOnce();
        if (refreshed) {
          response = await http
              .get(uri, headers: _headers)
              .timeout(ApiConfig.connectionTimeout);
        }
      }

      return _handleResponse<T>(response, fromJsonT);
    } on TimeoutException catch (e) {
      ErrorHandler().logError(e, StackTrace.current, context: 'GET $endpoint');
      return ApiResponse.error(
        'Request timed out. Backend: ${ApiConfig.baseUrl}',
      );
    } catch (e, stackTrace) {
      ErrorHandler().logError(e, stackTrace, context: 'GET $endpoint');
      return ApiResponse.error(ErrorHandler.getUserFriendlyMessage(e));
    }
  }

  /// Make POST request with automatic retry on network errors
  Future<ApiResponse<T>> post<T>(
    String endpoint, {
    Map<String, dynamic>? body,
    T Function(dynamic)? fromJsonT,
    bool enableRetry = true,
  }) async {
    return await _executeWithRetry(
      () => _postRaw<T>(endpoint, body: body, fromJsonT: fromJsonT),
      enableRetry: enableRetry,
    );
  }

  Future<ApiResponse<T>> _postRaw<T>(
    String endpoint, {
    Map<String, dynamic>? body,
    T Function(dynamic)? fromJsonT,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.apiUrl}$endpoint');

      var response = await http
          .post(uri, headers: _headers, body: jsonEncode(body ?? {}))
          .timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 401 && _shouldAttemptAutoRefresh(endpoint)) {
        final refreshed = await _refreshOnce();
        if (refreshed) {
          response = await http
              .post(uri, headers: _headers, body: jsonEncode(body ?? {}))
              .timeout(ApiConfig.connectionTimeout);
        }
      }

      return _handleResponse<T>(response, fromJsonT);
    } on TimeoutException catch (e) {
      ErrorHandler().logError(e, StackTrace.current, context: 'POST $endpoint');
      return ApiResponse.error(
        'Request timed out. Backend: ${ApiConfig.baseUrl}',
      );
    } catch (e, stackTrace) {
      ErrorHandler().logError(e, stackTrace, context: 'POST $endpoint');
      return ApiResponse.error(ErrorHandler.getUserFriendlyMessage(e));
    }
  }

  /// Make PUT request with automatic retry on network errors
  Future<ApiResponse<T>> put<T>(
    String endpoint, {
    Map<String, dynamic>? body,
    T Function(dynamic)? fromJsonT,
    bool enableRetry = true,
  }) async {
    return await _executeWithRetry(
      () => _putRaw<T>(endpoint, body: body, fromJsonT: fromJsonT),
      enableRetry: enableRetry,
    );
  }

  /// Make PATCH request with automatic retry on network errors
  Future<ApiResponse<T>> patch<T>(
    String endpoint, {
    Map<String, dynamic>? body,
    T Function(dynamic)? fromJsonT,
    bool enableRetry = true,
  }) async {
    return await _executeWithRetry(
      () => _patchRaw<T>(endpoint, body: body, fromJsonT: fromJsonT),
      enableRetry: enableRetry,
    );
  }

  Future<ApiResponse<T>> _patchRaw<T>(
    String endpoint, {
    Map<String, dynamic>? body,
    T Function(dynamic)? fromJsonT,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.apiUrl}$endpoint');

      var response = await http
          .patch(uri, headers: _headers, body: jsonEncode(body ?? {}))
          .timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 401 && _shouldAttemptAutoRefresh(endpoint)) {
        final refreshed = await _refreshOnce();
        if (refreshed) {
          response = await http
              .patch(uri, headers: _headers, body: jsonEncode(body ?? {}))
              .timeout(ApiConfig.connectionTimeout);
        }
      }

      return _handleResponse<T>(response, fromJsonT);
    } on TimeoutException catch (e) {
      ErrorHandler().logError(
        e,
        StackTrace.current,
        context: 'PATCH $endpoint',
      );
      return ApiResponse.error(
        'Request timed out. Backend: ${ApiConfig.baseUrl}',
      );
    } catch (e, stackTrace) {
      ErrorHandler().logError(e, stackTrace, context: 'PATCH $endpoint');
      return ApiResponse.error(ErrorHandler.getUserFriendlyMessage(e));
    }
  }

  Future<ApiResponse<T>> _putRaw<T>(
    String endpoint, {
    Map<String, dynamic>? body,
    T Function(dynamic)? fromJsonT,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.apiUrl}$endpoint');

      var response = await http
          .put(uri, headers: _headers, body: jsonEncode(body ?? {}))
          .timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 401 && _shouldAttemptAutoRefresh(endpoint)) {
        final refreshed = await _refreshOnce();
        if (refreshed) {
          response = await http
              .put(uri, headers: _headers, body: jsonEncode(body ?? {}))
              .timeout(ApiConfig.connectionTimeout);
        }
      }

      return _handleResponse<T>(response, fromJsonT);
    } on TimeoutException catch (e) {
      ErrorHandler().logError(e, StackTrace.current, context: 'PUT $endpoint');
      return ApiResponse.error(
        'Request timed out. Backend: ${ApiConfig.baseUrl}',
      );
    } catch (e, stackTrace) {
      ErrorHandler().logError(e, stackTrace, context: 'PUT $endpoint');
      return ApiResponse.error(ErrorHandler.getUserFriendlyMessage(e));
    }
  }

  /// Make DELETE request with automatic retry on network errors
  Future<ApiResponse<T>> delete<T>(
    String endpoint, {
    Map<String, String>? queryParams,
    T Function(dynamic)? fromJsonT,
    bool enableRetry = true,
  }) async {
    return await _executeWithRetry(
      () => _deleteRaw<T>(
        endpoint,
        queryParams: queryParams,
        fromJsonT: fromJsonT,
      ),
      enableRetry: enableRetry,
    );
  }

  Future<ApiResponse<T>> _deleteRaw<T>(
    String endpoint, {
    Map<String, String>? queryParams,
    T Function(dynamic)? fromJsonT,
  }) async {
    try {
      var uri = Uri.parse('${ApiConfig.apiUrl}$endpoint');
      if (queryParams != null) {
        uri = uri.replace(queryParameters: queryParams);
      }

      var response = await http
          .delete(uri, headers: _headers)
          .timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 401 && _shouldAttemptAutoRefresh(endpoint)) {
        final refreshed = await _refreshOnce();
        if (refreshed) {
          response = await http
              .delete(uri, headers: _headers)
              .timeout(ApiConfig.connectionTimeout);
        }
      }

      return _handleResponse<T>(response, fromJsonT);
    } on TimeoutException catch (e) {
      ErrorHandler().logError(
        e,
        StackTrace.current,
        context: 'DELETE $endpoint',
      );
      return ApiResponse.error(
        'Request timed out. Backend: ${ApiConfig.baseUrl}',
      );
    } catch (e, stackTrace) {
      ErrorHandler().logError(e, stackTrace, context: 'DELETE $endpoint');
      return ApiResponse.error(ErrorHandler.getUserFriendlyMessage(e));
    }
  }

  /// Execute request with automatic retry on network errors
  Future<ApiResponse<T>> _executeWithRetry<T>(
    Future<ApiResponse<T>> Function() action, {
    required bool enableRetry,
  }) async {
    if (!enableRetry) {
      return await action();
    }

    return await NetworkRetry.execute(
      action,
      config: const RetryConfig(
        maxAttempts: 3,
        initialDelay: Duration(seconds: 1),
        backoffMultiplier: 2.0,
      ),
      shouldRetry: (error) {
        // Only retry on network errors, not API errors
        if (error is ApiResponse) {
          final msg = error.message?.toLowerCase() ?? '';
          return msg.contains('network') ||
              msg.contains('connection') ||
              msg.contains('timeout');
        }
        return NetworkRetry.isNetworkError(error);
      },
    );
  }

  /// Handle response
  ApiResponse<T> _handleResponse<T>(
    http.Response response,
    T Function(dynamic)? fromJsonT,
  ) {
    final body = response.body;
    final trimmed = body.trim();

    if (trimmed.isEmpty) {
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      return ok
          ? ApiResponse(success: true, statusCode: response.statusCode)
          : ApiResponse.error('Empty response', response.statusCode);
    }

    try {
      final decoded = jsonDecode(trimmed);

      if (decoded is Map<String, dynamic>) {
        final ok = response.statusCode >= 200 && response.statusCode < 300;

        // Most endpoints return the standard wrapper: { success, message, data }.
        // Some legacy/3rd-party endpoints may return a raw JSON object instead.
        final looksWrapped =
            decoded.containsKey('success') ||
            decoded.containsKey('data') ||
            decoded.containsKey('message');

        if (looksWrapped) {
          return ApiResponse.fromJson(decoded, response.statusCode, fromJsonT);
        }

        try {
          final parsed = fromJsonT != null ? fromJsonT(decoded) : decoded;
          return ApiResponse(
            success: ok,
            data: parsed as T?,
            statusCode: response.statusCode,
          );
        } catch (_) {
          return ApiResponse.error(
            'Failed to parse response',
            response.statusCode,
          );
        }
      }

      // Some endpoints may legitimately return a JSON array (or scalar).
      // In that case, infer success from HTTP status.
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      try {
        final parsed = fromJsonT != null ? fromJsonT(decoded) : decoded;
        return ApiResponse(
          success: ok,
          data: parsed as T?,
          statusCode: response.statusCode,
        );
      } catch (e) {
        return ApiResponse.error(
          'Failed to parse response',
          response.statusCode,
        );
      }
    } catch (e) {
      // Keep user-facing message stable, but log a small preview for debugging.
      final url = response.request?.url.toString() ?? 'unknown-url';
      final preview = trimmed.substring(
        0,
        trimmed.length > 300 ? 300 : trimmed.length,
      );
      final contentType = response.headers['content-type'];
      debugPrint(
        '❌ Non-JSON response from $url (${response.statusCode}): $preview',
      );

      final details = <String>[
        'HTTP ${response.statusCode}',
        if (contentType != null && contentType.trim().isNotEmpty)
          'content-type: ${contentType.trim()}',
      ].join(', ');
      return ApiResponse.error(
        'Failed to parse response ($details)',
        response.statusCode,
      );
    }
  }

  // ============================================================
  // Authentication Methods
  // ============================================================

  /// Login with username and password
  Future<ApiResponse<AuthData>> login({
    required String username,
    required String password,
    String? role,
  }) async {
    debugPrint('🔐 Attempting login for user: $username');
    final response = await post<AuthData>(
      '/auth/login',
      body: {'username': username, 'password': password, 'role': role},
      fromJsonT: (data) {
        debugPrint(
          '📦 Login response data: ${data.toString().substring(0, 100)}...',
        );
        return AuthData.fromJson(data);
      },
    );

    if (response.success && response.data != null) {
      debugPrint('✅ Login successful, saving tokens...');
      await _saveTokens(response.data!);
      debugPrint(
        '🎯 Current token after save: ${_accessToken?.substring(0, 30)}...',
      );
    } else {
      debugPrint('❌ Login failed: ${response.message}');
    }

    return response;
  }

  /// Login with PIN
  Future<ApiResponse<AuthData>> loginWithPin({
    required String username,
    required String pin,
    String? role,
  }) async {
    final response = await post<AuthData>(
      '/auth/login',
      body: {'username': username, 'pin': pin, 'role': role},
      fromJsonT: (data) => AuthData.fromJson(data),
    );

    if (response.success && response.data != null) {
      await _saveTokens(response.data!);
    }

    return response;
  }

  /// Request a password reset OTP sent via email.
  ///
  /// Backend endpoint: `POST /api/auth/password-reset/request`
  ///
  /// Returns an `otp_ref` when the account exists and is eligible.
  Future<ApiResponse<Map<String, dynamic>>> requestPasswordResetOtp({
    required String usernameOrEmail,
  }) async {
    return await post<Map<String, dynamic>>(
      '/auth/password-reset/request',
      body: {'username_or_email': usernameOrEmail},
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Confirm OTP and set a new password.
  ///
  /// Backend endpoint: `POST /api/auth/password-reset/confirm`
  Future<ApiResponse<Map<String, dynamic>>> confirmPasswordResetOtp({
    required String otpRef,
    required String otpCode,
    required String newPassword,
  }) async {
    return await post<Map<String, dynamic>>(
      '/auth/password-reset/confirm',
      body: {
        'otp_ref': otpRef,
        'otp_code': otpCode,
        'new_password': newPassword,
      },
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Logout
  Future<ApiResponse> logout() async {
    final response = await post('/auth/logout');
    await _clearTokens();
    return response;
  }

  /// Get current user
  Future<ApiResponse<Map<String, dynamic>>> getCurrentUser() async {
    return await get<Map<String, dynamic>>(
      '/auth/me',
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Update current user profile
  Future<ApiResponse<Map<String, dynamic>>> updateCurrentUser(
    Map<String, dynamic> userData,
  ) async {
    final response = await put<Map<String, dynamic>>(
      '/auth/me',
      body: userData,
      fromJsonT: (data) => data as Map<String, dynamic>,
    );

    if (response.success && response.data != null) {
      // Keep the cached current user in sync
      _currentUser = response.data;
      await _writeTokenValue('current_user', jsonEncode(response.data));
    }

    return response;
  }

  /// Verify token
  Future<bool> verifyToken() async {
    if (_accessToken == null) return false;

    final response = await get('/auth/verify');
    return response.success;
  }

  /// Refresh token
  Future<bool> refreshToken() async {
    if (_refreshToken == null) return false;

    try {
      final uri = Uri.parse('${ApiConfig.apiUrl}/auth/refresh');
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $_refreshToken',
      };

      final raw = await http
          .post(uri, headers: headers, body: jsonEncode({}))
          .timeout(ApiConfig.connectionTimeout);

      final parsed = _handleResponse<Map<String, dynamic>>(
        raw,
        (data) => data as Map<String, dynamic>,
      );

      if (parsed.success && parsed.data != null) {
        _accessToken = parsed.data!['access_token'];
        await _writeTokenValue('access_token', _accessToken);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // Products Methods
  // ============================================================

  /// Get all products
  Future<ApiResponse<List<Map<String, dynamic>>>> getProducts({
    String? categoryId,
    String? search,
    bool? featured,
    bool? lowStock,
    bool forceRefresh = false,
  }) async {
    final params = <String, String>{};
    if (categoryId != null) params['category_id'] = categoryId;
    if (search != null) params['search'] = search;
    if (featured == true) params['featured'] = 'true';
    if (lowStock == true) params['low_stock'] = 'true';

    // If forcing a refresh, bypass any in-memory cache and go to network.
    // Note: The current implementation doesn't have an in-memory cache layer
    // that would be bypassed here, but this parameter is kept for future-proofing
    // and to make intent clear. The main effect is triggering a new network call.

    final response = await get<List<Map<String, dynamic>>>(
      '/products',
      queryParams: params.isNotEmpty ? params : null,
      fromJsonT: (data) => List<Map<String, dynamic>>.from(data),
    );

    // If we have pending offline transactions, cached stock deltas may differ
    // from server stock (until sync completes). In that case, merge cached
    // stock_quantity over the online response so the POS immediately reflects
    // the sale/redeem stock change.
    if (response.success && response.data != null) {
      try {
        final pending = await OfflineStore.pendingTransactionCount();
        if (pending > 0) {
          final cached = await OfflineStore.getCachedAllProducts();
          if (cached.isNotEmpty) {
            final byId = <String, int>{};
            for (final p in cached) {
              final id = p['id']?.toString();
              if (id == null || id.isEmpty) continue;
              final raw = p['stock_quantity'];
              final stock = raw is num ? raw.toInt() : int.tryParse('$raw');
              if (stock != null) byId[id] = stock;
            }

            if (byId.isNotEmpty) {
              final merged = response.data!
                  .map((p) {
                    final id = p['id']?.toString();
                    final cachedStock = (id != null) ? byId[id] : null;
                    if (cachedStock == null) return p;
                    return {...p, 'stock_quantity': cachedStock};
                  })
                  .toList(growable: false);

              return ApiResponse<List<Map<String, dynamic>>>(
                success: true,
                message: response.message,
                data: merged,
                statusCode: response.statusCode,
              );
            }
          }
        }
      } catch (_) {}
    }

    // Cache full list (no filters) when online.
    if (response.success &&
        response.data != null &&
        categoryId == null &&
        search == null &&
        featured != true &&
        lowStock != true) {
      // Only update cache if it's a full, unfiltered list.
      // If forceRefresh was used, this effectively becomes a cache update.
      await OfflineStore.cacheAllProducts(response.data!);
    }

    // Offline fallback to cached products (and filter locally).
    if (!response.success && _isConnectivityError(response)) {
      final cached = await OfflineStore.getCachedAllProducts();
      if (cached.isNotEmpty) {
        Iterable<Map<String, dynamic>> filtered = cached;
        if (categoryId != null) {
          filtered = filtered.where(
            (p) => (p['category_id']?.toString() ?? '') == categoryId,
          );
        }
        if (search != null && search.trim().isNotEmpty) {
          final s = search.trim().toLowerCase();
          filtered = filtered.where(
            (p) => (p['name']?.toString().toLowerCase() ?? '').contains(s),
          );
        }
        if (lowStock == true) {
          filtered = filtered.where((p) {
            final stock = (p['stock_quantity'] as int?) ?? 0;
            return stock > 0 && stock <= 10;
          });
        }

        return ApiResponse<List<Map<String, dynamic>>>(
          success: true,
          message: 'Loaded products from offline cache',
          data: filtered.toList(),
          statusCode: 200,
        );
      }
    }

    return response;
  }

  /// Get product by barcode
  Future<ApiResponse<Map<String, dynamic>>> getProductByBarcode(
    String barcode,
  ) async {
    return await get<Map<String, dynamic>>(
      '/products/barcode/$barcode',
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Create product
  Future<ApiResponse<Map<String, dynamic>>> createProduct({
    required String name,
    required double sellingPrice,
    String? sku,
    String? barcode,
    String? description,
    double? costPrice,
    double? discountPercent,
    int? pointsCost,
    int? stockQuantity,
    int? lowStockThreshold,
    int? categoryId,
    String? imageUrl,
    bool? isFeatured,
  }) async {
    return await post<Map<String, dynamic>>(
      '/products',
      body: {
        'name': name,
        'selling_price': sellingPrice,
        if (sku != null) 'sku': sku,
        if (barcode != null) 'barcode': barcode,
        if (description != null) 'description': description,
        if (costPrice != null) 'cost_price': costPrice,
        if (discountPercent != null) 'discount_percent': discountPercent,
        if (pointsCost != null) 'points_cost': pointsCost,
        if (stockQuantity != null) 'stock_quantity': stockQuantity,
        if (lowStockThreshold != null) 'low_stock_threshold': lowStockThreshold,
        if (categoryId != null) 'category_id': categoryId,
        if (imageUrl != null) 'image_url': imageUrl,
        if (isFeatured != null) 'is_featured': isFeatured,
      },
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Update product
  Future<ApiResponse<Map<String, dynamic>>> updateProduct({
    required int productId,
    String? name,
    String? barcode,
    String? description,
    double? costPrice,
    double? sellingPrice,
    double? discountPercent,
    int? pointsCost,
    int? stockQuantity,
    int? lowStockThreshold,
    int? categoryId,
    String? imageUrl,
    bool? isActive,
    bool? isFeatured,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (barcode != null) body['barcode'] = barcode;
    if (description != null) body['description'] = description;
    if (costPrice != null) body['cost_price'] = costPrice;
    if (sellingPrice != null) body['selling_price'] = sellingPrice;
    if (discountPercent != null) body['discount_percent'] = discountPercent;
    if (pointsCost != null) body['points_cost'] = pointsCost;
    if (stockQuantity != null) body['stock_quantity'] = stockQuantity;
    if (lowStockThreshold != null) {
      body['low_stock_threshold'] = lowStockThreshold;
    }
    if (categoryId != null) body['category_id'] = categoryId;
    if (imageUrl != null) body['image_url'] = imageUrl;
    if (isActive != null) body['is_active'] = isActive;
    if (isFeatured != null) body['is_featured'] = isFeatured;

    return await put<Map<String, dynamic>>(
      '/products/$productId',
      body: body,
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Upload product image (supervisor only)
  Future<ApiResponse<Map<String, dynamic>>> uploadProductImage({
    required int productId,
    required Uint8List imageBytes,
    required String fileName,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.apiUrl}/products/$productId/image');
      http.MultipartRequest buildRequest() {
        final request = http.MultipartRequest('POST', uri);
        request.headers.addAll(_multipartHeaders);
        return request;
      }

      var request = buildRequest();
      request.files.add(
        http.MultipartFile.fromBytes('image', imageBytes, filename: fileName),
      );

      var streamedResponse = await request.send().timeout(
        ApiConfig.connectionTimeout,
      );
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 401 &&
          _shouldAttemptAutoRefresh('/products')) {
        final refreshed = await _refreshOnce();
        if (refreshed) {
          request = buildRequest();
          request.files.add(
            http.MultipartFile.fromBytes(
              'image',
              imageBytes,
              filename: fileName,
            ),
          );
          streamedResponse = await request.send().timeout(
            ApiConfig.connectionTimeout,
          );
          response = await http.Response.fromStream(streamedResponse);
        }
      }

      return _handleResponse<Map<String, dynamic>>(
        response,
        (data) => data as Map<String, dynamic>,
      );
    } on TimeoutException catch (e) {
      ErrorHandler().logError(
        e,
        StackTrace.current,
        context: 'UPLOAD product image',
      );
      return ApiResponse.error(
        'Request timed out. Please check your connection.',
      );
    } catch (e, stackTrace) {
      ErrorHandler().logError(e, stackTrace, context: 'UPLOAD product image');
      return ApiResponse.error(ErrorHandler.getUserFriendlyMessage(e));
    }
  }

  /// Delete product (soft delete)
  Future<ApiResponse<Map<String, dynamic>>> deleteProduct(int productId) async {
    return await put<Map<String, dynamic>>(
      '/products/$productId',
      body: {'is_active': false},
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Update product stock
  Future<ApiResponse<Map<String, dynamic>>> updateProductStock({
    required int productId,
    required int adjustment,
  }) async {
    return await post<Map<String, dynamic>>(
      '/products/$productId/stock',
      body: {'adjustment': adjustment},
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  // ============================================================
  // Categories Methods
  // ============================================================

  /// Get all categories
  Future<ApiResponse<List<Map<String, dynamic>>>> getCategories() async {
    return await get<List<Map<String, dynamic>>>(
      '/categories',
      fromJsonT: (data) => List<Map<String, dynamic>>.from(data),
    );
  }

  /// Create category (supervisor only)
  Future<ApiResponse<Map<String, dynamic>>> createCategory({
    required String name,
    String? description,
    String? icon,
    String? color,
  }) async {
    return await post<Map<String, dynamic>>(
      '/categories',
      body: {
        'name': name,
        'description': description,
        'icon': icon,
        'color': color,
      },
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Remove category (supervisor only)
  ///
  /// This is a soft delete on the backend (sets `is_active=false`).
  Future<ApiResponse<Map<String, dynamic>>> deleteCategory(
    int categoryId,
  ) async {
    return await delete<Map<String, dynamic>>(
      '/categories/$categoryId',
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  // ============================================================
  // Transactions Methods
  // ============================================================

  /// Create transaction
  Future<ApiResponse<Map<String, dynamic>>> createTransaction({
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double totalAmount,
    required String paymentMethod,
    required double amountReceived,
    double? discountAmount,
    double? taxAmount,
    double? changeAmount,
    String? voucherCode,
    double? voucherDiscount,
    int? customerId,
    String? notes,
  }) async {
    final payload = <String, dynamic>{
      'items': items,
      'subtotal': subtotal,
      'total_amount': totalAmount,
      'payment_method': paymentMethod,
      'amount_received': amountReceived,
      'discount_amount': discountAmount ?? 0,
      'tax_amount': taxAmount ?? 0,
      'change_amount': changeAmount ?? 0,
      'voucher_code': voucherCode,
      'voucher_discount': voucherDiscount ?? 0,
      'customer_id': customerId,
      'notes': notes,
    };

    final response = await _createTransactionOnline(payload);

    if (response.success && response.data != null) {
      // Keep offline product cache in sync with stock changes.
      try {
        final stockDeltaItems = items
            .where((i) => i['skip_stock'] != true)
            .toList(growable: false);
        await OfflineStore.applyStockDeltasToCachedProducts(
          items: stockDeltaItems,
        );
      } catch (_) {}

      // Best effort: after any successful online transaction, try flushing queued offline ones.
      // Do not await this in UI flows.
      // ignore: unawaited_futures
      syncOfflineTransactions();
      return response;
    }

    // If offline/unreachable, queue transaction locally and return receipt-compatible data.
    if (_isConnectivityError(response)) {
      final localId = await OfflineStore.enqueueTransaction(
        payload: payload,
        meta: {
          'cashier_name': _currentCashierNameFallback(),
          'payment_method': paymentMethod,
        },
      );

      // Apply the stock deltas locally so product lists reflect the sale even before sync.
      try {
        final stockDeltaItems = items
            .where((i) => i['skip_stock'] != true)
            .toList(growable: false);
        await OfflineStore.applyStockDeltasToCachedProducts(
          items: stockDeltaItems,
        );
      } catch (_) {}

      return ApiResponse<Map<String, dynamic>>(
        success: true,
        statusCode: 200,
        message: 'Saved offline. Will sync when online.',
        data: {
          'transaction_id': localId,
          'id': localId,
          'cashier_name': _currentCashierNameFallback(),
          'offline': true,
        },
      );
    }

    return response;
  }

  /// Get transactions
  Future<ApiResponse<List<Map<String, dynamic>>>> getTransactions({
    String? startDate,
    String? endDate,
    String? status,
    String? paymentMethod,
    String? search,
    int page = 1,
    int perPage = 50,
  }) async {
    final params = <String, String>{
      'page': page.toString(),
      'per_page': perPage.toString(),
    };
    if (startDate != null) params['start_date'] = startDate;
    if (endDate != null) params['end_date'] = endDate;
    if (status != null) params['status'] = status;
    if (paymentMethod != null) params['payment_method'] = paymentMethod;
    if (search != null && search.trim().isNotEmpty) params['search'] = search;

    return await get<List<Map<String, dynamic>>>(
      '/transactions',
      queryParams: params,
      fromJsonT: (data) => List<Map<String, dynamic>>.from(data),
    );
  }

  /// Get single transaction by ID
  Future<ApiResponse<Map<String, dynamic>>> getTransaction(
    int transactionId,
  ) async {
    return await get<Map<String, dynamic>>(
      '/transactions/$transactionId',
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Get single transaction by code (e.g., TXN-20250101123000)
  Future<ApiResponse<Map<String, dynamic>>> getTransactionByCode(
    String transactionCode,
  ) async {
    return await get<Map<String, dynamic>>(
      '/transactions/by-code/$transactionCode',
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  // ============================================================
  // Refunds
  // ============================================================

  /// Request a refund (cashier) or instantly refund (supervisor).
  Future<ApiResponse<Map<String, dynamic>>> requestRefund(
    int transactionId, {
    String? reason,
    String? memberCard,
  }) async {
    final body = <String, dynamic>{};
    if (reason != null && reason.trim().isNotEmpty) {
      body['reason'] = reason.trim();
    }
    if (memberCard != null && memberCard.trim().isNotEmpty) {
      body['member_card'] = memberCard.trim();
    }

    return await post<Map<String, dynamic>>(
      '/refunds/transactions/$transactionId',
      body: body.isEmpty ? null : body,
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// List pending refund requests (supervisor/admin roles).
  Future<ApiResponse<List<Map<String, dynamic>>>>
  getPendingRefundRequests() async {
    return await get<List<Map<String, dynamic>>>(
      '/refunds/pending',
      fromJsonT: (data) => List<Map<String, dynamic>>.from(data),
    );
  }

  /// List refund requests created by the current user.
  Future<ApiResponse<List<Map<String, dynamic>>>> getMyRefundRequests({
    int limit = 50,
    String? status,
  }) async {
    final params = <String, String>{'limit': limit.toString()};
    if (status != null && status.trim().isNotEmpty) {
      params['status'] = status.trim();
    }
    return await get<List<Map<String, dynamic>>>(
      '/refunds/mine',
      queryParams: params,
      fromJsonT: (data) => List<Map<String, dynamic>>.from(data),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> approveRefundRequest(
    int refundRequestId,
  ) async {
    return await post<Map<String, dynamic>>(
      '/refunds/$refundRequestId/approve',
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> rejectRefundRequest(
    int refundRequestId,
  ) async {
    return await post<Map<String, dynamic>>(
      '/refunds/$refundRequestId/reject',
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  // ============================================================
  // Reports Methods
  // ============================================================

  /// Get daily report
  Future<ApiResponse<Map<String, dynamic>>> getDailyReport([
    String? date,
  ]) async {
    return await get<Map<String, dynamic>>(
      '/reports/daily',
      queryParams: date != null ? {'date': date} : null,
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Get weekly report
  Future<ApiResponse<Map<String, dynamic>>> getWeeklyReport([
    String? date,
  ]) async {
    return await get<Map<String, dynamic>>(
      '/reports/weekly',
      queryParams: date != null ? {'date': date} : null,
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Get low stock products
  Future<ApiResponse<List<Map<String, dynamic>>>> getLowStockProducts() async {
    return await get<List<Map<String, dynamic>>>(
      '/reports/low-stock',
      fromJsonT: (data) => List<Map<String, dynamic>>.from(data),
    );
  }

  /// Get monthly report
  Future<ApiResponse<Map<String, dynamic>>> getMonthlyReport({
    int? year,
    int? month,
  }) async {
    final params = <String, String>{};
    if (year != null) params['year'] = year.toString();
    if (month != null) params['month'] = month.toString();
    return await get<Map<String, dynamic>>(
      '/reports/monthly',
      queryParams: params.isNotEmpty ? params : null,
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Get yearly report
  Future<ApiResponse<Map<String, dynamic>>> getYearlyReport({int? year}) async {
    final params = <String, String>{};
    if (year != null) params['year'] = year.toString();
    return await get<Map<String, dynamic>>(
      '/reports/yearly',
      queryParams: params.isNotEmpty ? params : null,
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Get top products
  Future<ApiResponse<List<Map<String, dynamic>>>> getTopProducts({
    int limit = 10,
    String? timeframe,
    int? year,
    int? month,
    String? date,
  }) async {
    final params = <String, String>{'limit': limit.toString()};
    if (timeframe != null && timeframe.isNotEmpty) {
      params['timeframe'] = timeframe;
    }
    if (year != null) params['year'] = year.toString();
    if (month != null) params['month'] = month.toString();
    if (date != null && date.isNotEmpty) params['date'] = date;

    return await get<List<Map<String, dynamic>>>(
      '/reports/top-products',
      queryParams: params,
      fromJsonT: (data) => List<Map<String, dynamic>>.from(data),
    );
  }

  /// Get sales breakdown by category (for dashboard charts)
  Future<ApiResponse<Map<String, dynamic>>> getCategoryBreakdown({
    String? timeframe,
    int? year,
    int? month,
    String? date,
  }) async {
    final params = <String, String>{};
    if (timeframe != null && timeframe.isNotEmpty) {
      params['timeframe'] = timeframe;
    }
    if (year != null) params['year'] = year.toString();
    if (month != null) params['month'] = month.toString();
    if (date != null && date.isNotEmpty) params['date'] = date;
    return await get<Map<String, dynamic>>(
      '/reports/category-breakdown',
      queryParams: params.isNotEmpty ? params : null,
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  // ============================================================
  // Voucher Methods
  // ============================================================

  /// Validate voucher
  Future<ApiResponse<Map<String, dynamic>>> validateVoucher(
    String code,
    double amount,
  ) async {
    return await post<Map<String, dynamic>>(
      '/vouchers/validate',
      body: {'code': code, 'amount': amount},
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  // ============================================================
  // Customer Methods
  // ============================================================

  /// Get customers
  Future<ApiResponse<List<Map<String, dynamic>>>> getCustomers({
    String? search,
  }) async {
    return await get<List<Map<String, dynamic>>>(
      '/customers',
      queryParams: search != null ? {'search': search} : null,
      fromJsonT: (data) => List<Map<String, dynamic>>.from(data),
    );
  }

  /// Create customer
  Future<ApiResponse<Map<String, dynamic>>> createCustomer(
    Map<String, dynamic> customerData,
  ) async {
    return await post<Map<String, dynamic>>(
      '/customers',
      body: customerData,
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  // ============================================================
  // Settings Methods
  // ============================================================

  /// Get all settings
  Future<ApiResponse<Map<String, dynamic>>> getSettings() async {
    return await get<Map<String, dynamic>>(
      '/settings',
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Get specific setting
  Future<ApiResponse<dynamic>> getSetting(String key) async {
    return await get<dynamic>('/settings/$key', fromJsonT: (data) => data);
  }

  /// Update settings (supervisor only)
  Future<ApiResponse<Map<String, dynamic>>> updateSettings(
    Map<String, dynamic> settings,
  ) async {
    return await put<Map<String, dynamic>>(
      '/settings',
      body: settings,
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  // ============================================================
  // Payments Methods
  // ============================================================

  /// Generate a static QRPh code (PayMongo) for e-wallet payments.
  Future<ApiResponse<Map<String, dynamic>>> generatePaymongoStaticQrph({
    double? amount,
    int? amountCentavos,
  }) async {
    return await get<Map<String, dynamic>>(
      '/payments/qrph/static',
      queryParams: {
        if (amount != null) 'amount': amount.toString(),
        if (amountCentavos != null)
          'amount_centavos': amountCentavos.toString(),
      },
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Create a PayMongo hosted checkout session for GCash with a fixed amount.
  ///
  /// Returns a `checkout_url` that can be displayed as a QR code.
  Future<ApiResponse<Map<String, dynamic>>> createPaymongoGcashCheckout({
    double? amount,
    int? amountCentavos,
  }) async {
    return await post<Map<String, dynamic>>(
      '/payments/gcash/checkout',
      body: {
        if (amount != null) 'amount': amount,
        if (amountCentavos != null) 'amount_centavos': amountCentavos,
      },
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Get status of a PayMongo GCash checkout session.
  Future<ApiResponse<Map<String, dynamic>>> getPaymongoGcashSessionStatus(
    String sessionId,
  ) async {
    return await get<Map<String, dynamic>>(
      '/payments/gcash/session/$sessionId',
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Get the status of a QRPh session (auto-complete after webhook updates it).
  Future<ApiResponse<Map<String, dynamic>>> getPaymongoQrphSessionStatus(
    String sessionId,
  ) async {
    return await get<Map<String, dynamic>>(
      '/payments/qrph/session/$sessionId',
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  // ============================================================
  // Activity Logs Methods
  // ============================================================

  /// Get recent activity logs
  Future<ApiResponse<List<Map<String, dynamic>>>> getActivityLogs({
    int limit = 50,
    bool archived = false,
  }) async {
    return await get<List<Map<String, dynamic>>>(
      '/activity-logs',
      queryParams: {
        'limit': limit.toString(),
        'archived': archived ? '1' : '0',
      },
      fromJsonT: (data) => List<Map<String, dynamic>>.from(data),
    );
  }

  /// Archive an activity log (supervisor only)
  Future<ApiResponse<void>> deleteActivityLog(int logId) async {
    return await delete<void>('/activity-logs/$logId', fromJsonT: (_) {});
  }

  /// Restore an archived activity log (supervisor only)
  Future<ApiResponse<void>> restoreActivityLog(int logId) async {
    return await patch<void>(
      '/activity-logs/$logId/restore',
      fromJsonT: (_) {},
    );
  }

  /// Permanently delete an activity log (supervisor only)
  Future<ApiResponse<void>> hardDeleteActivityLog(int logId) async {
    return await delete<void>(
      '/activity-logs/$logId',
      queryParams: {'hard': 'true'},
      fromJsonT: (_) {},
    );
  }

  // ============================================================
  // User Management Methods
  // ============================================================

  /// Get all users (supervisor only)
  Future<ApiResponse<List<Map<String, dynamic>>>> getUsers() async {
    return await get<List<Map<String, dynamic>>>(
      '/users',
      fromJsonT: (data) => List<Map<String, dynamic>>.from(data),
    );
  }

  /// Get user by ID
  Future<ApiResponse<Map<String, dynamic>>> getUser(int userId) async {
    return await get<Map<String, dynamic>>(
      '/users/$userId',
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Create user (supervisor only)
  Future<ApiResponse<Map<String, dynamic>>> createUser(
    Map<String, dynamic> userData,
  ) async {
    return await post<Map<String, dynamic>>(
      '/users',
      body: userData,
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Update user
  Future<ApiResponse<Map<String, dynamic>>> updateUser(
    int userId,
    Map<String, dynamic> userData,
  ) async {
    return await put<Map<String, dynamic>>(
      '/users/$userId',
      body: userData,
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Delete user (supervisor only)
  Future<ApiResponse<void>> deleteUser(int userId) async {
    return await delete<void>('/users/$userId', fromJsonT: (_) {});
  }

  // ============================================================================
  // LOYALTY MANAGEMENT
  // ============================================================================

  /// Get loyalty members with pagination and filters
  Future<ApiResponse<Map<String, dynamic>>> getLoyaltyMembers({
    int page = 1,
    int perPage = 20,
    String? search,
    int? tierId,
    String? status,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'per_page': perPage.toString(),
    };
    if (search != null && search.isNotEmpty) queryParams['search'] = search;
    if (tierId != null) queryParams['tier_id'] = tierId.toString();
    if (status != null && status.isNotEmpty) queryParams['status'] = status;

    return await get<Map<String, dynamic>>(
      '/loyalty/members',
      queryParams: queryParams,
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Get single loyalty member by ID
  Future<ApiResponse<Map<String, dynamic>>> getLoyaltyMember(
    int memberId,
  ) async {
    return await get<Map<String, dynamic>>(
      '/loyalty/members/$memberId',
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Scan member card barcode
  Future<ApiResponse<Map<String, dynamic>>> scanMemberCard(
    String barcode,
  ) async {
    return await get<Map<String, dynamic>>(
      '/loyalty/members/scan/$barcode',
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Search members by query
  Future<ApiResponse<List<Map<String, dynamic>>>> searchLoyaltyMembers(
    String query,
  ) async {
    return await get<List<Map<String, dynamic>>>(
      '/loyalty/members/search?q=${Uri.encodeComponent(query)}',
      fromJsonT: (data) => List<Map<String, dynamic>>.from(data),
    );
  }

  /// Register new loyalty member
  Future<ApiResponse<Map<String, dynamic>>> registerLoyaltyMember(
    Map<String, dynamic> memberData,
  ) async {
    return await post<Map<String, dynamic>>(
      '/loyalty/members',
      body: memberData,
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Update loyalty member
  Future<ApiResponse<Map<String, dynamic>>> updateLoyaltyMember(
    int memberId,
    Map<String, dynamic> data,
  ) async {
    return await put<Map<String, dynamic>>(
      '/loyalty/members/$memberId',
      body: data,
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Delete loyalty member
  Future<ApiResponse<void>> deleteLoyaltyMember(int memberId) async {
    return await delete<void>('/loyalty/members/$memberId', fromJsonT: (_) {});
  }

  /// Archive (soft-delete) a loyalty member
  Future<ApiResponse<Map<String, dynamic>>> archiveLoyaltyMember(
    int memberId,
  ) async {
    return await post<Map<String, dynamic>>(
      '/loyalty/members/$memberId/archive',
      body: {},
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Restore an archived loyalty member
  Future<ApiResponse<Map<String, dynamic>>> restoreLoyaltyMember(
    int memberId,
  ) async {
    return await post<Map<String, dynamic>>(
      '/loyalty/members/$memberId/restore',
      body: {},
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// List archived loyalty members
  Future<ApiResponse<Map<String, dynamic>>> getArchivedLoyaltyMembers({
    int page = 1,
    int perPage = 20,
    String? search,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'per_page': perPage.toString(),
    };
    if (search != null && search.isNotEmpty) queryParams['search'] = search;

    return await get<Map<String, dynamic>>(
      '/loyalty/members/archived',
      queryParams: queryParams,
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Renew loyalty membership for 1 year
  Future<ApiResponse<Map<String, dynamic>>> renewLoyaltyMembership(
    int memberId,
  ) async {
    return await post<Map<String, dynamic>>(
      '/loyalty/members/$memberId/renew',
      body: {},
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Issue physical card
  Future<ApiResponse<Map<String, dynamic>>> issueLoyaltyCard(
    int memberId,
  ) async {
    return await post<Map<String, dynamic>>(
      '/loyalty/members/$memberId/issue-card',
      body: {},
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Get card data for printing
  Future<ApiResponse<Map<String, dynamic>>> getLoyaltyCardData(
    int memberId,
  ) async {
    return await get<Map<String, dynamic>>(
      '/loyalty/members/$memberId/card-data',
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Add/deduct points manually
  Future<ApiResponse<Map<String, dynamic>>> adjustLoyaltyPoints(
    int memberId, {
    required int points,
    required String reason,
    String type = 'adjust',
  }) async {
    return await post<Map<String, dynamic>>(
      '/loyalty/members/$memberId/points',
      body: {'points': points, 'reason': reason, 'type': type},
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Get member point transactions
  Future<ApiResponse<Map<String, dynamic>>> getMemberPointTransactions(
    int memberId, {
    int page = 1,
    int perPage = 20,
  }) async {
    return await get<Map<String, dynamic>>(
      '/loyalty/members/$memberId/transactions?page=$page&per_page=$perPage',
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Redeem points for discount
  Future<ApiResponse<Map<String, dynamic>>> redeemPoints(
    int memberId,
    int points,
  ) async {
    return await post<Map<String, dynamic>>(
      '/loyalty/members/$memberId/redeem',
      body: {'points': points},
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Redeem a reward product using points (staff)
  Future<ApiResponse<Map<String, dynamic>>> redeemRewardProductForMember({
    required int memberId,
    required int productId,
    required int quantity,
  }) async {
    final response = await post<Map<String, dynamic>>(
      '/loyalty/members/$memberId/redeem-product',
      body: {'product_id': productId, 'quantity': quantity},
      fromJsonT: (data) => data as Map<String, dynamic>,
    );

    // After a successful redemption, force a refresh of the product list
    // to get the updated stock quantity.
    if (response.success) {
      // Keep offline cache consistent with redemption stock changes.
      try {
        final product = response.data?['product'];
        final stockRaw = (product is Map) ? product['stock_quantity'] : null;
        final stock = stockRaw is num
            ? stockRaw.toInt()
            : int.tryParse('$stockRaw');
        if (stock != null) {
          await OfflineStore.setCachedProductStock(
            productId: productId.toString(),
            stockQuantity: stock,
          );
        } else {
          await OfflineStore.applyStockDeltasToCachedProducts(
            items: [
              {'product_id': productId, 'quantity': quantity},
            ],
          );
        }
      } catch (_) {}

      await getProducts(forceRefresh: true);
    }

    return response;
  }

  /// Get loyalty tiers
  Future<ApiResponse<List<Map<String, dynamic>>>> getLoyaltyTiers() async {
    return await get<List<Map<String, dynamic>>>(
      '/loyalty/tiers',
      fromJsonT: (data) => List<Map<String, dynamic>>.from(data),
    );
  }

  /// Update loyalty tier
  Future<ApiResponse<Map<String, dynamic>>> updateLoyaltyTier(
    int tierId,
    Map<String, dynamic> data,
  ) async {
    return await put<Map<String, dynamic>>(
      '/loyalty/tiers/$tierId',
      body: data,
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Get loyalty settings
  Future<ApiResponse<Map<String, dynamic>>> getLoyaltySettings() async {
    return await get<Map<String, dynamic>>(
      '/loyalty/settings',
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Update loyalty settings
  Future<ApiResponse<Map<String, dynamic>>> updateLoyaltySettings(
    Map<String, dynamic> settings,
  ) async {
    return await put<Map<String, dynamic>>(
      '/loyalty/settings',
      body: settings,
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Get loyalty dashboard statistics
  Future<ApiResponse<Map<String, dynamic>>> getLoyaltyDashboard() async {
    return await get<Map<String, dynamic>>(
      '/loyalty/dashboard',
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Get recent loyalty members (joined within last [days])
  Future<ApiResponse<List<Map<String, dynamic>>>> getRecentLoyaltyMembers({
    int days = 30,
    int limit = 20,
  }) async {
    return await get<List<Map<String, dynamic>>>(
      '/loyalty/members/recent?days=$days&limit=$limit',
      fromJsonT: (data) => List<Map<String, dynamic>>.from(data),
    );
  }

  /// Earn points on purchase
  Future<ApiResponse<Map<String, dynamic>>> earnLoyaltyPoints({
    required int memberId,
    int? transactionId,
    required double amount,
  }) async {
    return await post<Map<String, dynamic>>(
      '/loyalty/earn-points',
      body: {
        'member_id': memberId,
        'transaction_id': transactionId,
        'amount': amount,
      },
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  // ============================================================================
  // PROMOTIONS
  // ============================================================================

  /// Member-facing: get all active promotions
  Future<ApiResponse<List<Map<String, dynamic>>>> getActivePromotions() async {
    return await get<List<Map<String, dynamic>>>(
      '/promotions',
      fromJsonT: (data) => List<Map<String, dynamic>>.from(data),
    );
  }

  /// Admin-facing: get all promotions (active and inactive)
  Future<ApiResponse<List<Map<String, dynamic>>>> getAllPromotions() async {
    return await get<List<Map<String, dynamic>>>(
      '/promotions/all',
      fromJsonT: (data) => List<Map<String, dynamic>>.from(data),
    );
  }

  /// Admin-facing: create a new promotion
  Future<ApiResponse<Map<String, dynamic>>> createPromotion(
    Map<String, dynamic> promotion,
  ) async {
    return await post<Map<String, dynamic>>(
      '/promotions',
      body: promotion,
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Admin-facing: update an existing promotion
  Future<ApiResponse<Map<String, dynamic>>> updatePromotion(
    int promotionId,
    Map<String, dynamic> promotion,
  ) async {
    return await put<Map<String, dynamic>>(
      '/promotions/$promotionId',
      body: promotion,
      fromJsonT: (data) => data as Map<String, dynamic>,
    );
  }

  /// Admin-facing: delete a promotion
  Future<ApiResponse<void>> deletePromotion(int promotionId) async {
    return await delete<void>('/promotions/$promotionId', fromJsonT: (_) {});
  }
}
