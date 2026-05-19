import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Glass presets aligned with the package Apple Music iOS 26 demo
/// (`apple_music_demo.dart`): tinted body, minimal blur, refraction — not a
/// high-alpha white wash.
abstract final class ShellGlassSettings {
  /// Tab + search pills — same physics as the demo's `_barGlassSettings`.
  static LiquidGlassSettings bottomBarGlass(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return LiquidGlassSettings(
      glassColor: isDark
          ? const Color(0xAA1C1C1E)
          : const Color(0xB3F2F2F7), // iOS grouped fill on light lists
      thickness: 30,
      blur: 2,
      chromaticAberration: 0.01,
      lightAngle: GlassDefaults.lightAngle,
      lightIntensity: 0.5,
      ambientStrength: 0,
      refractiveIndex: 1.2,
      saturation: 1.2,
      visibility: 1,
      specularSharpness: GlassSpecularSharpness.medium,
    );
  }

  /// Sliding selection lens — low tint + refraction so icons show through.
  ///
  /// Must stay much more transparent than [bottomBarGlass]; the bar body uses
  /// a heavier fill, but the indicator samples and refracts the icon layer.
  static LiquidGlassSettings indicatorLens(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return LiquidGlassSettings(
      // Refraction-only during morph — blur stacks on the shader and reads muddy.
      glassColor: isDark
          ? const Color(0x28FFFFFF)
          : const Color(0x35FFFFFF),
      thickness: 12,
      blur: 0,
      chromaticAberration: 0.015,
      lightAngle: GlassDefaults.lightAngle,
      lightIntensity: isDark ? 0.55 : 0.85,
      ambientStrength: 0.12,
      refractiveIndex: 1.3,
      saturation: 1.0,
      visibility: 1,
      specularSharpness: GlassSpecularSharpness.medium,
    );
  }

  /// Solid pill behind the selected tab (visible at rest on the frosted bar).
  static Color indicatorFill(Brightness brightness, ColorScheme colors) {
    return brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.22)
        : Colors.black.withValues(alpha: 0.14);
  }

  /// Strips Material focus rings from the package search [TextField].
  static ThemeData searchFieldTheme(ThemeData base) {
    const none = InputBorder.none;
    return base.copyWith(
      inputDecorationTheme: const InputDecorationTheme(
        filled: false,
        border: none,
        enabledBorder: none,
        focusedBorder: none,
        disabledBorder: none,
        errorBorder: none,
        focusedErrorBorder: none,
        contentPadding: EdgeInsets.zero,
        isDense: true,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: base.colorScheme.onSurface,
        selectionColor: base.colorScheme.primary.withValues(alpha: 0.25),
      ),
    );
  }
}
