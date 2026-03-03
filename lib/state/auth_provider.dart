import 'package:flutter/foundation.dart';

import '../core/services/app_lifecycle_service.dart';
import '../core/services/inactivity_service.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  bool _initializing = true;
  Map<String, dynamic>? _user;

  bool get initializing => _initializing;
  bool get isLoggedIn => _api.isLoggedIn;

  Map<String, dynamic>? get user => _user ?? _api.currentUser;

  String get role => (user?['role'] ?? '').toString();

  String get displayName {
    final u = user;
    final name =
        (u?['display_name'] ??
                u?['nickname'] ??
                u?['full_name'] ??
                u?['username'])
            ?.toString();
    if (name != null && name.trim().isNotEmpty) return name.trim();
    return 'User';
  }

  Future<void> initialize() async {
    // ApiService.init() is already called in main(), but calling it again is safe.
    await _api.init();

    _user = _api.currentUser;

    if (_api.isLoggedIn) {
      // Validate/refresh session
      final ok = await _fetchMeWithRefreshFallback();
      if (!ok) {
        await _api.logout();
        _user = null;
      } else {
        // Best effort: flush queued offline transactions when we know we're online+authenticated.
        // ignore: unawaited_futures
        _api.syncOfflineTransactions();
      }
    }

    _initializing = false;
    notifyListeners();
  }

  Future<ApiResponse<AuthData>> login({
    required String username,
    String? password,
    String? pin,
    String? role,
  }) async {
    ApiResponse<AuthData> res;

    if (pin != null) {
      res = await _api.loginWithPin(username: username, pin: pin, role: role);
    } else {
      res = await _api.login(
        username: username,
        password: password ?? '',
        role: role,
      );
    }

    if (res.success && res.data != null) {
      _user = res.data!.user;
      // Best effort to sync with /auth/me (and also validates refresh flow).
      await _fetchMeWithRefreshFallback();
      notifyListeners();
      return res;
    }

    return res;
  }

  Future<void> logout() async {
    InactivityService().dispose();
    AppLifecycleService().dispose();
    await _api.logout();
    _user = null;
    notifyListeners();
  }

  Future<bool> _fetchMeWithRefreshFallback() async {
    final me = await _api.getCurrentUser();
    if (me.success && me.data != null) {
      _user = me.data;
      return true;
    }

    if (me.statusCode == 401) {
      final refreshed = await _api.refreshToken();
      if (refreshed) {
        final me2 = await _api.getCurrentUser();
        if (me2.success && me2.data != null) {
          _user = me2.data;
          return true;
        }
      }
    }

    return false;
  }
}
