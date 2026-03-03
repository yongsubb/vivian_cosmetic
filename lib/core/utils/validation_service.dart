/// Input validation and sanitization utilities
class ValidationService {
  /// Validate and sanitize text input (removes dangerous characters)
  static String sanitizeText(String? input, {int? maxLength}) {
    if (input == null || input.isEmpty) return '';

    // Remove any HTML/script tags
    String cleaned = input
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'[<>]'), '');

    // Trim whitespace
    cleaned = cleaned.trim();

    // Apply max length if specified
    if (maxLength != null && cleaned.length > maxLength) {
      cleaned = cleaned.substring(0, maxLength);
    }

    return cleaned;
  }

  /// Validate email format
  static bool isValidEmail(String? email) {
    if (email == null || email.isEmpty) return false;

    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );

    return emailRegex.hasMatch(email);
  }

  /// Validate phone number (Philippine format)
  static bool isValidPhoneNumber(String? phone) {
    if (phone == null || phone.isEmpty) return false;

    // Remove common separators
    final cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    // Check for Philippine mobile format: 09XXXXXXXXX or +639XXXXXXXXX
    final phoneRegex = RegExp(r'^(\+639|09)\d{9}$');

    return phoneRegex.hasMatch(cleaned);
  }

  /// Sanitize phone number to standard format
  static String sanitizePhoneNumber(String? phone) {
    if (phone == null || phone.isEmpty) return '';

    // Remove separators
    final cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    // Convert +639XXXXXXXXX to 09XXXXXXXXX
    if (cleaned.startsWith('+639') && cleaned.length == 13) {
      return '0${cleaned.substring(3)}';
    }

    return cleaned;
  }

  /// Validate PIN (4-6 digits)
  static bool isValidPin(String? pin) {
    if (pin == null || pin.isEmpty) return false;

    final pinRegex = RegExp(r'^\d{4,6}$');
    return pinRegex.hasMatch(pin);
  }

  /// Validate username (alphanumeric, underscore, 3-30 chars)
  static bool isValidUsername(String? username) {
    if (username == null || username.isEmpty) return false;

    final usernameRegex = RegExp(r'^[a-zA-Z0-9_]{3,30}$');
    return usernameRegex.hasMatch(username);
  }

  /// Validate password strength (min 6 chars)
  static bool isValidPassword(String? password) {
    if (password == null) return false;
    return password.length >= 6;
  }

  /// Validate positive number
  static bool isValidPositiveNumber(String? value) {
    if (value == null || value.isEmpty) return false;

    final number = double.tryParse(value);
    return number != null && number > 0;
  }

  /// Validate positive integer
  static bool isValidPositiveInteger(String? value) {
    if (value == null || value.isEmpty) return false;

    final number = int.tryParse(value);
    return number != null && number > 0;
  }

  /// Validate non-negative number (0 or positive)
  static bool isValidNonNegativeNumber(String? value) {
    if (value == null || value.isEmpty) return false;

    final number = double.tryParse(value);
    return number != null && number >= 0;
  }

  /// Sanitize number input (removes non-numeric characters except decimal point)
  static String sanitizeNumber(String? input) {
    if (input == null || input.isEmpty) return '';

    // Keep only digits and decimal point
    return input.replaceAll(RegExp(r'[^\d.]'), '');
  }

  /// Sanitize integer input (removes non-numeric characters)
  static String sanitizeInteger(String? input) {
    if (input == null || input.isEmpty) return '';

    // Keep only digits
    return input.replaceAll(RegExp(r'[^\d]'), '');
  }

  /// Validate barcode/SKU format
  static bool isValidBarcode(String? barcode) {
    if (barcode == null || barcode.isEmpty) return false;

    // Allow alphanumeric and hyphens, 3-50 chars
    final barcodeRegex = RegExp(r'^[a-zA-Z0-9\-]{3,50}$');
    return barcodeRegex.hasMatch(barcode);
  }

  /// Validate date string (YYYY-MM-DD)
  static bool isValidDateString(String? date) {
    if (date == null || date.isEmpty) return false;

    final dateRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!dateRegex.hasMatch(date)) return false;

    // Try parsing to ensure it's a valid date
    try {
      DateTime.parse(date);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Sanitize SQL/NoSQL injection attempts (for extra safety)
  static String sanitizeForDatabase(String? input) {
    if (input == null || input.isEmpty) return '';

    // Remove common SQL injection patterns
    String result = input.replaceAll(';', '');
    result = result.replaceAll("'", '');
    result = result.replaceAll('"', '');
    result = result.replaceAll(r'\', '');
    result = result.replaceAll('--', '');
    result = result.replaceAll('/*', '');
    result = result.replaceAll('*/', '');
    result = result.replaceAll('xp_', '');
    result = result.replaceAll('sp_', '');
    return result.trim();
  }

  /// Validate field is not empty
  static String? validateRequired(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  /// Validate email field
  static String? validateEmailField(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }
    if (!isValidEmail(value)) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  /// Validate phone field
  static String? validatePhoneField(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required';
    }
    if (!isValidPhoneNumber(value)) {
      return 'Please enter a valid Philippine phone number';
    }
    return null;
  }

  /// Validate PIN field
  static String? validatePinField(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'PIN is required';
    }
    if (!isValidPin(value)) {
      return 'PIN must be 4-6 digits';
    }
    return null;
  }

  /// Validate username field
  static String? validateUsernameField(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Username is required';
    }
    if (!isValidUsername(value)) {
      return 'Username must be 3-30 characters (letters, numbers, underscore)';
    }
    return null;
  }

  /// Validate password field
  static String? validatePasswordField(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (!isValidPassword(value)) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  /// Validate positive number field
  static String? validatePositiveNumberField(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    if (!isValidPositiveNumber(value)) {
      return '$fieldName must be a positive number';
    }
    return null;
  }

  /// Validate positive integer field
  static String? validatePositiveIntegerField(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    if (!isValidPositiveInteger(value)) {
      return '$fieldName must be a positive whole number';
    }
    return null;
  }
}
