import 'package:intl/intl.dart';

/// Helpers to consistently display timestamps in Philippine time (Asia/Manila, UTC+8).
///
/// Backend timestamps are now generated using `datetime.now()` (local time) and serialized via
/// `isoformat()` without a timezone suffix.
class PhTime {
  static const Duration _phOffset = Duration(hours: 8);

  /// Current time in Philippine time.
  static DateTime now() => DateTime.now().toUtc().add(_phOffset);

  /// Parse a backend ISO timestamp and convert it to Philippine time.
  ///
  /// Rules:
  /// - If [raw] contains a timezone (ends with `Z` or has +/-HH:MM), respect it.
  /// - Otherwise, assume it is local Philippine time (backend uses `datetime.now()`).
  static DateTime? parseToPh(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final parsed = DateTime.tryParse(trimmed);
    if (parsed == null) return null;

    final hasExplicitTz =
        trimmed.endsWith('Z') || RegExp(r'([+-]\d\d:\d\d)$').hasMatch(trimmed);

    // If it has explicit timezone, convert to UTC then add PH offset
    if (parsed.isUtc || hasExplicitTz) {
      return parsed.toUtc().add(_phOffset);
    }

    // If it's naive (no timezone), treat it as already Philippine time
    // since backend now uses datetime.now() which returns local time
    return parsed;
  }

  /// Parse [raw] to Philippine time, or return [fallback] (defaults to PH `now`).
  static DateTime parseToPhOrNow(String? raw, {DateTime? fallback}) {
    return parseToPh(raw) ?? (fallback ?? now());
  }

  static String formatPh(DateTime dt, String pattern) {
    return DateFormat(pattern).format(dt);
  }

  static String formatIsoToPh(
    String? raw,
    String pattern, {
    String fallback = '',
  }) {
    final dt = parseToPh(raw);
    if (dt == null) return fallback;
    return formatPh(dt, pattern);
  }
}
