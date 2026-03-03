import 'dart:async';

import 'package:flutter/material.dart';

/// Manages inactivity timeout and automatic logout.
class InactivityService {
  InactivityService._();

  static final InactivityService _instance = InactivityService._();
  factory InactivityService() => _instance;

  /// Default inactivity timeout in minutes
  static const int defaultTimeoutMinutes = 15;

  Timer? _timer;
  int _timeoutMinutes = defaultTimeoutMinutes;
  VoidCallback? _onTimeout;
  bool _isEnabled = true;

  /// Initialize the inactivity service with a timeout callback
  void init({
    required VoidCallback onTimeout,
    int timeoutMinutes = defaultTimeoutMinutes,
    bool enabled = true,
  }) {
    _onTimeout = onTimeout;
    _timeoutMinutes = timeoutMinutes;
    _isEnabled = enabled;
    if (_isEnabled) {
      _resetTimer();
    }
  }

  /// Enable or disable the inactivity timer
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    if (!enabled) {
      _timer?.cancel();
      _timer = null;
    } else if (_onTimeout != null) {
      _resetTimer();
    }
  }

  /// Update the timeout duration
  void setTimeoutMinutes(int minutes) {
    _timeoutMinutes = minutes;
    if (_isEnabled && _timer != null) {
      _resetTimer();
    }
  }

  /// Reset the inactivity timer (called on user interaction)
  void _resetTimer() {
    _timer?.cancel();
    if (!_isEnabled || _onTimeout == null) return;

    _timer = Timer(Duration(minutes: _timeoutMinutes), () {
      debugPrint('⏰ Inactivity timeout reached. Auto-logout triggered.');
      _onTimeout?.call();
    });
  }

  /// Record user activity (resets the timer)
  void recordActivity() {
    if (_isEnabled && _onTimeout != null) {
      _resetTimer();
    }
  }

  /// Stop the inactivity timer
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _onTimeout = null;
  }
}

/// Widget wrapper that tracks user interactions and resets the inactivity timer
class InactivityDetector extends StatelessWidget {
  final Widget child;

  const InactivityDetector({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => InactivityService().recordActivity(),
      onPanDown: (_) => InactivityService().recordActivity(),
      onScaleStart: (_) => InactivityService().recordActivity(),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => InactivityService().recordActivity(),
        onPointerMove: (_) => InactivityService().recordActivity(),
        child: child,
      ),
    );
  }
}
