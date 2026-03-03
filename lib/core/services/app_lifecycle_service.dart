import 'dart:async';

import 'package:flutter/material.dart';

/// Service to detect when app is resumed from background and show PIN lock if needed
class AppLifecycleService with WidgetsBindingObserver {
  AppLifecycleService._();

  static final AppLifecycleService _instance = AppLifecycleService._();
  factory AppLifecycleService() => _instance;

  DateTime? _lastPausedAt;
  Duration _lockThreshold = const Duration(minutes: 5);
  bool _isEnabled = false;
  Future<bool> Function()? _onResumeLocked;

  /// Initialize the app lifecycle service
  void init({
    required Future<bool> Function() onResumeLocked,
    Duration? lockThreshold,
  }) {
    _onResumeLocked = onResumeLocked;
    _lockThreshold = lockThreshold ?? const Duration(minutes: 5);
    _isEnabled = true;
    WidgetsBinding.instance.addObserver(this);
  }

  /// Disable the app lifecycle service
  void dispose() {
    _isEnabled = false;
    WidgetsBinding.instance.removeObserver(this);
    _onResumeLocked = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isEnabled || _onResumeLocked == null) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _lastPausedAt = DateTime.now();
      debugPrint('📴 App paused at $_lastPausedAt');
    } else if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      debugPrint('📱 App resumed at $now');

      if (_lastPausedAt != null) {
        final elapsed = now.difference(_lastPausedAt!);
        debugPrint('⏱️ App was in background for ${elapsed.inSeconds}s');

        if (elapsed >= _lockThreshold) {
          debugPrint('🔒 Showing PIN lock screen...');
          _onResumeLocked!();
        }
      }
    }
  }
}
