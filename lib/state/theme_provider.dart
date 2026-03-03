import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Theme provider to manage app theme (light/dark mode)
class ThemeProvider extends ChangeNotifier {
  static const String _themePreferenceKey = 'isDarkMode';

  ThemeMode _themeMode = ThemeMode.light;
  bool _isInitialized = false;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  bool get isInitialized => _isInitialized;

  /// Initialize theme from saved preferences
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final isDark = prefs.getBool(_themePreferenceKey) ?? false;
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading theme preference: $e');
      _isInitialized = true;
    }
  }

  /// Toggle between light and dark theme
  Future<void> toggleTheme() async {
    _themeMode = _themeMode == ThemeMode.light
        ? ThemeMode.dark
        : ThemeMode.light;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_themePreferenceKey, isDarkMode);
    } catch (e) {
      debugPrint('Error saving theme preference: $e');
    }
  }

  /// Set theme explicitly
  Future<void> setTheme(ThemeMode mode) async {
    if (_themeMode == mode) return;

    _themeMode = mode;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_themePreferenceKey, isDarkMode);
    } catch (e) {
      debugPrint('Error saving theme preference: $e');
    }
  }

  /// Set dark theme
  Future<void> setDarkTheme() async {
    await setTheme(ThemeMode.dark);
  }

  /// Set light theme
  Future<void> setLightTheme() async {
    await setTheme(ThemeMode.light);
  }
}
