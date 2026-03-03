import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Helper extension for theme-aware colors
/// Use these instead of hardcoded AppColors for proper dark mode support
extension ThemeHelper on BuildContext {
  /// Whether the app is in dark mode
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  /// Background color - use for scaffold/page backgrounds
  Color get backgroundColor =>
      isDarkMode ? AppColors.darkBackground : AppColors.background;

  /// Surface color - use for cards, dialogs, bottom sheets
  Color get surfaceColor =>
      isDarkMode ? AppColors.darkSurface : AppColors.surface;

  /// Card background color
  Color get cardColor =>
      isDarkMode ? AppColors.darkCardBackground : AppColors.cardBackground;

  /// Primary text color
  Color get textPrimaryColor =>
      isDarkMode ? AppColors.darkTextPrimary : AppColors.textPrimary;

  /// Secondary text color
  Color get textSecondaryColor =>
      isDarkMode ? AppColors.darkTextSecondary : AppColors.textSecondary;

  /// Light text color
  Color get textLightColor =>
      isDarkMode ? AppColors.darkTextLight : AppColors.textLight;

  /// Divider color
  Color get dividerColor =>
      isDarkMode ? AppColors.darkDivider : AppColors.divider;

  /// Elevated surface (for modals, dropdowns)
  Color get elevatedSurfaceColor =>
      isDarkMode ? AppColors.darkSurfaceVariant : AppColors.white;

  /// White that adapts to dark mode (stays white for accents on primary colors)
  Color get adaptiveWhite => AppColors.white;

  /// Input field fill color
  Color get inputFillColor =>
      isDarkMode ? AppColors.darkSurfaceVariant : AppColors.white;

  /// Icon color for secondary icons
  Color get iconSecondaryColor =>
      isDarkMode ? AppColors.darkTextSecondary : AppColors.textSecondary;
}

/// Static helper for when context is not available
class ThemeColors {
  static Color textPrimary(BuildContext context) => context.textPrimaryColor;
  static Color textSecondary(BuildContext context) =>
      context.textSecondaryColor;
  static Color surface(BuildContext context) => context.surfaceColor;
  static Color background(BuildContext context) => context.backgroundColor;
  static Color card(BuildContext context) => context.cardColor;
  static Color divider(BuildContext context) => context.dividerColor;
}
