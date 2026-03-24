import 'package:flutter/material.dart';

/// Professional Color Helper Utility
/// 
/// Provides utilities for converting color names to Color objects
/// and extracting color attributes from product data
class ColorHelper {
  /// Convert color name string to Color object
  /// Supports common color names and hex codes
  static Color? nameToColor(String colorName) {
    final normalized = colorName.toLowerCase().trim();
    
    // Common color name mappings
    final colorMap = <String, Color>{
      'red': Colors.red,
      'blue': Colors.blue,
      'green': Colors.green,
      'yellow': Colors.yellow,
      'orange': Colors.orange,
      'purple': Colors.purple,
      'pink': Colors.pink,
      'brown': Colors.brown,
      'black': Colors.black,
      'white': Colors.white,
      'grey': Colors.grey,
      'gray': Colors.grey,
      'cyan': Colors.cyan,
      'teal': Colors.teal,
      'indigo': Colors.indigo,
      'amber': Colors.amber,
      'lime': Colors.lime,
      'light blue': Colors.lightBlue,
      'light blue accent': Colors.lightBlueAccent,
      'blue accent': Colors.blueAccent,
      'green accent': Colors.greenAccent,
      'yellow accent': Colors.yellowAccent,
      'orange accent': Colors.orangeAccent,
      'red accent': Colors.redAccent,
      'pink accent': Colors.pinkAccent,
      'purple accent': Colors.purpleAccent,
      'deep purple': Colors.deepPurple,
      'deep purple accent': Colors.deepPurpleAccent,
      'indigo accent': Colors.indigoAccent,
      'light green': Colors.lightGreen,
      'light green accent': Colors.lightGreenAccent,
      'teal accent': Colors.tealAccent,
      'cyan accent': Colors.cyanAccent,
    };
    
    // Check direct mapping
    if (colorMap.containsKey(normalized)) {
      return colorMap[normalized];
    }
    
    // Try to parse as hex color
    if (normalized.startsWith('#') || normalized.startsWith('0x')) {
      try {
        String hex = normalized.replaceFirst('#', '').replaceFirst('0x', '');
        if (hex.length == 6) {
          hex = 'FF$hex'; // Add alpha channel
        }
        return Color(int.parse(hex, radix: 16));
      } catch (e) {
        // Invalid hex, continue to default
      }
    }
    
    // Try partial matches for common patterns
    for (final entry in colorMap.entries) {
      if (normalized.contains(entry.key) || entry.key.contains(normalized)) {
        return entry.value;
      }
    }
    
    // Default: return null if no match found
    return null;
  }
  
  /// Extract color attributes from WooCommerce product attributes
  /// Returns list of Color objects from attribute values
  static List<Color> extractColorsFromAttributes(List<dynamic> attributes) {
    final colors = <Color>[];
    
    if (attributes.isEmpty) {
      return colors;
    }
    
    // Common attribute names that might contain colors
    final colorAttributeNames = [
      'color',
      'colour',
      'pa_color',
      'pa_colour',
      'attribute_color',
      'attribute_colour',
    ];
    
    for (final attr in attributes) {
      if (attr is! Map<String, dynamic>) continue;
      
      final name = (attr['name'] ?? attr['slug'] ?? '').toString().toLowerCase();
      final slug = (attr['slug'] ?? '').toString().toLowerCase();
      
      // Check if this is a color attribute
      final isColorAttribute = colorAttributeNames.any(
        (colorName) => name.contains(colorName) || slug.contains(colorName),
      );
      
      if (isColorAttribute) {
        // Extract options/values
        final options = attr['options'];
        if (options is List) {
          for (final option in options) {
            final colorName = option.toString().trim();
            final color = nameToColor(colorName);
            if (color != null && !colors.contains(color)) {
              colors.add(color);
            }
          }
        } else if (options is String) {
          // Handle comma-separated values
          final values = options.split(',').map((v) => v.trim()).toList();
          for (final value in values) {
            final color = nameToColor(value);
            if (color != null && !colors.contains(color)) {
              colors.add(color);
            }
          }
        }
      }
    }
    
    return colors;
  }
  
  /// Extract all attribute values (not just colors)
  /// Returns list of attribute value strings
  static List<String> extractAttributeValues(List<dynamic> attributes, String attributeName) {
    final values = <String>[];
    
    if (attributes.isEmpty) {
      return values;
    }
    
    final normalizedName = attributeName.toLowerCase().trim();
    
    for (final attr in attributes) {
      if (attr is! Map<String, dynamic>) continue;
      
      final name = (attr['name'] ?? '').toString().toLowerCase();
      final slug = (attr['slug'] ?? '').toString().toLowerCase();
      
      // Check if this matches the requested attribute
      if (name.contains(normalizedName) || slug.contains(normalizedName)) {
        final options = attr['options'];
        if (options is List) {
          for (final option in options) {
            final value = option.toString().trim();
            if (value.isNotEmpty && !values.contains(value)) {
              values.add(value);
            }
          }
        } else if (options is String) {
          final optionValues = options.split(',').map((v) => v.trim()).toList();
          for (final value in optionValues) {
            if (value.isNotEmpty && !values.contains(value)) {
              values.add(value);
            }
          }
        }
      }
    }
    
    return values;
  }
}

