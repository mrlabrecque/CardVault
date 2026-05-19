import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Primary colors ────────────────────────────────────────────
  static const primary       = Color(0xFF800020);
  static const primaryDark   = Color(0xFF5C0017);
  static const primaryLight  = Color(0xFFA0002A);

  // ── Gray colors (light to dark) ───────────────────────────────
  static const grayLight     = Color(0xFFE5E7EB); // Light borders, backgrounds
  static const grayMedium    = Color(0xFF9CA3AF); // Secondary icons, muted text
  static const grayDark      = Color(0xFF6B7280); // Primary muted text

  // ── Other ─────────────────────────────────────────────────────
  static const surface       = Color(0xFFFFFFFF);
  static const surfaceElev   = Color(0xFFF8F9FA);
  static const border        = grayLight;
  static const textMain      = Color(0xFF1F2937);
  static const textMuted     = grayDark;

  /// Unselected segment track — same system fill as native [UISegmentedControl]
  /// (used by [AdaptiveSegmentedControl] in app-bar chrome).
  static Color segmentedTrackBackground(BuildContext context) {
    return CupertinoColors.tertiarySystemFill.resolveFrom(context);
  }

  /// Cupertino typography for widgets that read [CupertinoTheme.of] (e.g.
  /// [CupertinoTextField] inside [AdaptiveTextField]). Uses Oswald while keeping
  /// Apple default sizes/letterSpacing/colors for the current [brightness].
  ///
  /// **Limits:** [AdaptiveListTile] on iOS hardcodes `TextStyle` without consulting
  /// this theme. iOS 26+ native platform-view buttons use the system typeface.
  static CupertinoThemeData cupertinoShellTheme(Brightness brightness) {
    final base = CupertinoThemeData(brightness: brightness, primaryColor: primary);
    final t = base.textTheme;
    TextStyle oswald(TextStyle s) => GoogleFonts.oswald(textStyle: s);
    return CupertinoThemeData(
      brightness: brightness,
      primaryColor: primary,
      textTheme: CupertinoTextThemeData(
        primaryColor: primary,
        textStyle: oswald(t.textStyle),
        actionTextStyle: oswald(t.actionTextStyle),
        actionSmallTextStyle: oswald(t.actionSmallTextStyle),
        tabLabelTextStyle: oswald(t.tabLabelTextStyle),
        navTitleTextStyle: oswald(t.navTitleTextStyle),
        navLargeTitleTextStyle: oswald(t.navLargeTitleTextStyle),
        navActionTextStyle: oswald(t.navActionTextStyle),
        pickerTextStyle: oswald(t.pickerTextStyle),
        dateTimePickerTextStyle: oswald(t.dateTimePickerTextStyle),
      ),
    );
  }

  /// Solid-color bars (e.g. burgundy app bar): transparent fill + circular ink on press.
  static ButtonStyle _iconButtonOnSolidBarStyle() {
    return ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return Colors.white.withValues(alpha: 0.38);
        }
        return Colors.white;
      }),
      backgroundColor: WidgetStateProperty.all(Colors.transparent),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return Colors.white.withValues(alpha: 0.20);
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return Colors.white.withValues(alpha: 0.12);
        }
        return null;
      }),
      shape: WidgetStateProperty.all(const CircleBorder()),
      padding: WidgetStateProperty.all(const EdgeInsets.all(8)),
    );
  }

  static BoxDecoration cupertinoTextFieldDecoration(
    BuildContext context, {
    double radius = 12,
    bool enabled = true,
  }) {
    final colors = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: colors.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: colors.outline,
      ),
    );
  }

  static ThemeData light() {
    final base = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      primary: primary,
      onPrimary: Colors.white,
      surface: surface,
      onSurface: textMain,
      surfaceContainerHighest: surfaceElev,
      outline: border    
      );

    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      fontFamily: GoogleFonts.oswald().fontFamily,
      textTheme: GoogleFonts.oswaldTextTheme(),
      scaffoldBackgroundColor: Color(0xFFFDFDFD),

      appBarTheme: const AppBarTheme(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        actionsIconTheme: IconThemeData(color: Colors.white, size: 24),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
        ),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        shape: Border(bottom: BorderSide(color: primaryDark)),
      ),

      iconButtonTheme: IconButtonThemeData(style: _iconButtonOnSolidBarStyle()),

      // Shell uses [GlassShellBottomBar], not Material [NavigationBar].
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 0,
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
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        actionsIconTheme: const IconThemeData(color: Colors.white, size: 24),
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
        shape: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),

      iconButtonTheme: IconButtonThemeData(style: _iconButtonOnSolidBarStyle()),

      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 0,
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
