import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const primary       = Color(0xFF800020);
  static const primaryDark   = Color(0xFF5C0017);
  static const primaryLight  = Color(0xFFA0002A);
  static const surface       = Color(0xFFFFFFFF);
  static const surfaceElev   = Color(0xFFF8F9FA);
  static const border        = Color(0xFFE0E0E0);
  static const textMain      = Color(0xFF1F2937);
  static const textMuted     = Color(0xFF6B7280);

  static ThemeData light() {
    final base = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      primary: primary,
      onPrimary: Colors.white,
      surface: surface,
      onSurface: textMain,
      surfaceContainerHighest: surfaceElev,
      outline: border,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      fontFamily: GoogleFonts.oswald().fontFamily,
      textTheme: GoogleFonts.oswaldTextTheme(),
      scaffoldBackgroundColor: const Color(0xFFF9FAFB),

      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textMain,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: primary,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textMain,
        ),
        shape: Border(bottom: BorderSide(color: border)),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: primary,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        indicatorColor: Colors.white.withValues(alpha: 0.18),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? Colors.white
                : Colors.white.withValues(alpha: 0.55),
            size: 22,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
            color: states.contains(WidgetState.selected)
                ? Colors.white
                : Colors.white.withValues(alpha: 0.55),
          );
        }),
        height: 72,
      ),

      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: border),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: const TextStyle(color: textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: primary.withValues(alpha: 0.12),
        labelStyle: const TextStyle(fontSize: 13, color: textMain),
        side: const BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      dividerTheme: const DividerThemeData(color: border, space: 1),
    );
  }

  static ThemeData dark() {
    final base = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
      primary: primaryLight,
      onPrimary: Colors.white,
      surface: const Color(0xFF111827),
      onSurface: Colors.white,
      surfaceContainerHighest: const Color(0xFF1F2937),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      fontFamily: GoogleFonts.oswald().fontFamily,
      textTheme: GoogleFonts.oswaldTextTheme(ThemeData.dark().textTheme),
      scaffoldBackgroundColor: const Color(0xFF111827),

      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF111827),
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
        shape: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: primaryDark,
        indicatorColor: Colors.white.withValues(alpha: 0.18),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? Colors.white : Colors.white.withValues(alpha: 0.5),
          size: 22,
        )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
          fontSize: 10, fontWeight: FontWeight.w500,
          color: states.contains(WidgetState.selected) ? Colors.white : Colors.white.withValues(alpha: 0.5),
        )),
        height: 72,
      ),

      cardTheme: CardThemeData(
        color: const Color(0xFF1F2937),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryLight,
          side: BorderSide(color: primaryLight, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
