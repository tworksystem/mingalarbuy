import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Professional PlanetMM Theme System
///
/// Color palette extracted from PlanetMM brand image:
/// - Deep blue to purple gradient background
/// - Bright blue and purple circuit board accents
/// - Green accent for figures
/// - Gold accent for crowns and highlights
/// - White for text and contrast
class AppTheme {
  // Primary Brand Colors (from image background gradient)
  static const Color deepBlue = Color(0xFF1A237E); // Deep blue from gradient
  static const Color darkPurple =
      Color(0xFF4A148C); // Dark purple from gradient
  static const Color mediumBlue = Color(0xFF283593); // Medium blue
  static const Color mediumPurple = Color(0xFF6A1B9A); // Medium purple

  // Accent Colors (from circuit board lines and elements)
  static const Color brightBlue =
      Color(0xFF2196F3); // Bright blue circuit lines
  static const Color brightPurple =
      Color(0xFF9C27B0); // Bright purple circuit lines
  static const Color lightBlue = Color(0xFF64B5F6); // Light blue highlights
  static const Color lightPurple = Color(0xFFBA68C8); // Light purple highlights

  // Special Accent Colors (from image elements)
  static const Color planetGreen = Color(0xFF4CAF50); // Green from figures
  static const Color planetGold = Color(0xFFFFD700); // Gold from crowns
  static const Color darkGold = Color(0xFFFFC107); // Darker gold variant

  // Neutral Colors
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color darkGrey = Color(0xFF202020);
  static const Color lightGrey = Color(0xFFF5F5F5);
  static const Color mediumGrey = Color(0xFF9E9E9E);

  // Background Gradient (matching image)
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF1A237E), // Deep blue
      Color(0xFF283593), // Medium blue
      Color(0xFF4A148C), // Dark purple
      Color(0xFF6A1B9A), // Medium purple
    ],
    stops: [0.0, 0.4, 0.7, 1.0],
  );

  /// Dedicated Splash Gradient - purple focused for splash screen background
  static const LinearGradient splashPurpleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      mediumPurple, // Base purple
      brightPurple, // Brand bright purple
      lightPurple, // Softer purple highlight
    ],
    stops: [0.0, 0.5, 1.0],
  );

  // Circuit Board Gradient (for accents)
  static const LinearGradient circuitGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF2196F3), // Bright blue
      Color(0xFF64B5F6), // Light blue
      Color(0xFF9C27B0), // Bright purple
      Color(0xFFBA68C8), // Light purple
    ],
  );

  // Gold Gradient (for premium elements)
  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFFFD700), // Gold
      Color(0xFFFFC107), // Dark gold
    ],
  );

  // Text Gradients
  static const LinearGradient textGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF64B5F6), // Light blue
      Color(0xFF9C27B0), // Bright purple
    ],
  );

  /// Get the main app theme
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,

      // Color Scheme
      colorScheme: ColorScheme.light(
        primary: deepBlue,
        secondary: brightPurple,
        tertiary: planetGreen,
        surface: white,
        background: lightGrey,
        error: Colors.red,
        onPrimary: white,
        onSecondary: white,
        onTertiary: white,
        onSurface: darkGrey,
        onBackground: darkGrey,
        onError: white,
      ),

      // Primary Color Swatch
      primarySwatch: _createMaterialColor(deepBlue),

      // Scaffold
      scaffoldBackgroundColor: lightGrey,
      canvasColor: Colors.transparent,

      // App Bar Theme
      appBarTheme: AppBarTheme(
        backgroundColor: deepBlue,
        foregroundColor: white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: white),
        titleTextStyle: GoogleFonts.poppins(
          color: white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),

      // Card Theme
      cardTheme: CardThemeData(
        color: white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),

      // Button Themes
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: deepBlue,
          foregroundColor: white,
          elevation: 4,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: deepBlue,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          textStyle: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: deepBlue,
          side: const BorderSide(color: deepBlue, width: 2),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Input Decoration Theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: mediumGrey),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: mediumGrey),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: deepBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),

      // Text Theme - Using Poppins (Creative & Professional)
      textTheme: GoogleFonts.poppinsTextTheme(
        const TextTheme(
          displayLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: darkGrey,
          ),
          displayMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: darkGrey,
          ),
          displaySmall: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: darkGrey,
          ),
          headlineLarge: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: darkGrey,
          ),
          headlineMedium: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: darkGrey,
          ),
          headlineSmall: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: darkGrey,
          ),
          titleLarge: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: darkGrey,
          ),
          titleMedium: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: darkGrey,
          ),
          titleSmall: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: mediumGrey,
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.normal,
            color: darkGrey,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: darkGrey,
          ),
          bodySmall: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.normal,
            color: mediumGrey,
          ),
          labelLarge: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: darkGrey,
          ),
          labelMedium: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: mediumGrey,
          ),
          labelSmall: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: mediumGrey,
          ),
        ),
      ),

      // Icon Theme
      iconTheme: const IconThemeData(
        color: deepBlue,
        size: 24,
      ),

      // Divider Theme
      dividerTheme: const DividerThemeData(
        color: mediumGrey,
        thickness: 1,
        space: 1,
      ),

      // Floating Action Button Theme
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: brightPurple,
        foregroundColor: white,
        elevation: 4,
      ),

      // Bottom Navigation Bar Theme
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: white,
        selectedItemColor: deepBlue,
        unselectedItemColor: mediumGrey,
        selectedLabelStyle: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.normal,
        ),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),

      // Chip Theme
      chipTheme: ChipThemeData(
        backgroundColor: lightGrey,
        selectedColor: deepBlue,
        disabledColor: mediumGrey,
        labelStyle: GoogleFonts.poppins(
          color: darkGrey,
        ),
        secondaryLabelStyle: GoogleFonts.poppins(
          color: white,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),

      // Progress Indicator Theme
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: deepBlue,
        linearTrackColor: lightGrey,
        circularTrackColor: lightGrey,
      ),

      // Font Family - Poppins (Creative & Professional)
      fontFamily: GoogleFonts.poppins().fontFamily,
    );
  }

  /// Create a Material Color from a single color
  static MaterialColor _createMaterialColor(Color color) {
    List strengths = <double>[.05];
    final swatch = <int, Color>{};
    final int r = color.red, g = color.green, b = color.blue;

    for (int i = 1; i < 10; i++) {
      strengths.add(0.1 * i);
    }
    for (var strength in strengths) {
      final double ds = 0.5 - strength;
      swatch[(strength * 1000).round()] = Color.fromRGBO(
        r + ((ds < 0 ? r : (255 - r)) * ds).round(),
        g + ((ds < 0 ? g : (255 - g)) * ds).round(),
        b + ((ds < 0 ? b : (255 - b)) * ds).round(),
        1,
      );
    }
    return MaterialColor(color.value, swatch);
  }
}
