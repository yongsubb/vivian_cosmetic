import 'package:flutter/material.dart';

/// Vivian Cosmetic Shop Color Scheme
/// A cosmetic-themed color palette with soft, elegant tones
class AppColors {
  // Primary Colors
  static const Color primary = Color(0xFFE91E63); // Soft Rose Pink
  static const Color primaryLight = Color(0xFFF8BBD9);
  static const Color primaryDark = Color(0xFFC2185B);

  // Secondary Colors
  static const Color secondary = Color(0xFFF5E6DA); // Nude Beige
  static const Color secondaryLight = Color(0xFFFFF8F5);
  static const Color secondaryDark = Color(0xFFE8D5C9);

  // Accent Colors
  static const Color accent = Color(0xFFC9A24D); // Gold
  static const Color accentLight = Color(0xFFD4B86A);
  static const Color accentDark = Color(0xFFB8923D);

  // Neutral Colors
  static const Color white = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFFFFBFA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF333333); // Dark Gray
  static const Color textSecondary = Color(0xFF666666);
  static const Color textLight = Color(0xFF999999);
  static const Color divider = Color(0xFFE0E0E0);

  // Status Colors
  static const Color success = Color(0xFF4CAF50);
  static const Color successLight = Color(0xFFE8F5E9);
  static const Color warning = Color(0xFFFF9800);
  static const Color warningLight = Color(0xFFFFF3E0);
  static const Color error = Color(0xFFF44336);
  static const Color errorLight = Color(0xFFFFEBEE);
  static const Color info = Color(0xFF2196F3);
  static const Color infoLight = Color(0xFFE3F2FD);

  // Card & Shadow Colors
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color shadow = Color(0x1A000000);

  // Gradient for buttons and headers
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [accentLight, accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Dark Theme Colors - Deep black with pink accent style
  static const Color darkBackground = Color(0xFF0A0A0A); // Very deep black
  static const Color darkSurface = Color(
    0xFF141414,
  ); // Slightly lighter for cards
  static const Color darkSurfaceVariant = Color(
    0xFF1C1C1C,
  ); // For elevated surfaces
  static const Color darkTextPrimary = Color(0xFFF5F5F5); // Bright white text
  static const Color darkTextSecondary = Color(0xFFAAAAAA); // Muted gray
  static const Color darkTextLight = Color(0xFF707070);
  static const Color darkDivider = Color(0xFF2A2A2A);
  static const Color darkCardBackground = Color(0xFF141414);

  // Dark theme accent glow effect color
  static const Color darkAccentGlow = Color(
    0x33E91E63,
  ); // Pink glow with transparency
}
