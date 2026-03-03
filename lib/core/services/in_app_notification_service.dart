import 'package:flutter/material.dart';

/// Lightweight, app-wide notifications using a single [ScaffoldMessenger].
///
/// This avoids per-screen popup logic and makes it easy to show a notification
/// from anywhere (including services) without needing a [BuildContext].
class InAppNotificationService {
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static void hideCurrent() {
    messengerKey.currentState?.hideCurrentSnackBar();
  }

  static void showInfo(
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _show(
      message,
      duration: duration,
      backgroundColor: const Color(0xFF2D2D2D),
    );
  }

  static void showSuccess(
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _show(
      message,
      duration: duration,
      backgroundColor: const Color(0xFF1B5E20),
    );
  }

  static void showError(
    String message, {
    Duration duration = const Duration(seconds: 4),
  }) {
    _show(
      message,
      duration: duration,
      backgroundColor: const Color(0xFFB71C1C),
    );
  }

  static void _show(
    String message, {
    required Color backgroundColor,
    required Duration duration,
  }) {
    final messenger = messengerKey.currentState;
    if (messenger == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: duration,
          behavior: SnackBarBehavior.floating,
          backgroundColor: backgroundColor,
        ),
      );
  }
}
