import 'package:intl/intl.dart';

/// Centralized helpers for rendering prices in Myanmar Kyat (Ks) with
/// consistent thousand separators and optional fractional precision.
class PriceFormatter {
  PriceFormatter._();

  static final NumberFormat _noDecimalFormatter =
      NumberFormat('#,##0', 'en_US');
  static final NumberFormat _twoDecimalFormatter =
      NumberFormat('#,##0.00', 'en_US');

  /// Formats a numeric [value] into a human readable Kyat string such as
  /// `12,996 Ks`. If the value contains a fractional component, it preserves
  /// two decimal places; otherwise decimals are omitted.
  static String format(double value) {
    if (value.isNaN || value.isInfinite || value <= 0) {
      return 'Price not available';
    }

    final bool hasFractional = value % 1 != 0;
    final NumberFormat formatter =
        hasFractional ? _twoDecimalFormatter : _noDecimalFormatter;

    final formatted = formatter.format(value);
    return '$formatted Ks';
  }

  /// Convenience method to format a numeric string. Handles commas and empty
  /// values gracefully.
  static String formatFromString(String raw) {
    final normalized = raw.replaceAll(',', '').trim();
    final parsed = double.tryParse(normalized);
    if (parsed == null) {
      return 'Price not available';
    }
    return format(parsed);
  }
}
