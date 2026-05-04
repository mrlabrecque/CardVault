import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppFonts {
  static String get fontFamily => GoogleFonts.oswald().fontFamily ?? 'Oswald';

  static TextStyle get appBarTitle => GoogleFonts.oswald(
    fontSize: 22,
    fontWeight: FontWeight.w600,
  );
}
