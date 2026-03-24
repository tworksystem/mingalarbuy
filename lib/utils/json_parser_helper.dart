/// Professional JSON Parsing Helper
/// 
/// Safely parses JSON values that may come as String or num from APIs
/// Handles type coercion and provides safe defaults
class JsonParserHelper {
  /// Safely parse an integer from JSON
  /// Handles both String and num types
  static int safeParseInt(dynamic value, {int defaultValue = 0}) {
    if (value == null) return defaultValue;
    
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      return parsed ?? defaultValue;
    }
    
    return defaultValue;
  }

  /// Safely parse a double from JSON
  /// Handles both String and num types
  static double safeParseDouble(dynamic value, {double defaultValue = 0.0}) {
    if (value == null) return defaultValue;
    
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      return parsed ?? defaultValue;
    }
    
    return defaultValue;
  }

  /// Safely parse a String from JSON
  /// Handles null and converts other types to String
  static String safeParseString(dynamic value, {String defaultValue = ''}) {
    if (value == null) return defaultValue;
    if (value is String) return value;
    return value.toString();
  }

  /// Safely parse a boolean from JSON
  /// Handles String "true"/"false", int 0/1, and bool
  static bool safeParseBool(dynamic value, {bool defaultValue = false}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is int) return value != 0;
    if (value is String) {
      final lower = value.toLowerCase().trim();
      if (lower == 'true' || lower == '1' || lower == 'yes') return true;
      if (lower == 'false' || lower == '0' || lower == 'no') return false;
    }
    return defaultValue;
  }

  /// Safely parse a list of integers from JSON
  /// Handles mixed types and filters invalid values
  static List<int> safeParseIntList(dynamic value, {List<int>? defaultValue}) {
    if (value == null) return defaultValue ?? [];
    if (value is! List) return defaultValue ?? [];
    
    final result = <int>[];
    for (final item in value) {
      final parsed = safeParseInt(item);
      if (parsed != 0 || item == 0) {
        result.add(parsed);
      }
    }
    return result;
  }

  /// Safely parse a nullable integer from JSON
  static int? safeParseIntNullable(dynamic value) {
    if (value == null) return null;
    
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      return parsed;
    }
    
    return null;
  }
}

