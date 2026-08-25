// ============================================================
// GirlTea type scale — Playfair Display (editorial/emotional) + Inter (UI).
// ============================================================
// The mockup specifies Playfair + Inter only; Poppins is dropped.
// Playfair carries the brand + emotional headlines; Inter does all the
// working UI (titles, body, labels). Build the Material TextTheme once in
// _buildTheme via [gtTextTheme]; use the named [GtText] styles for one-offs.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class GtText {
  const GtText._();

  // --- Editorial / emotional (Playfair Display) ---
  static TextStyle display({Color? color}) => GoogleFonts.playfairDisplay(
        fontSize: 40,
        height: 1.08,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: color,
      );

  static TextStyle headline({Color? color}) => GoogleFonts.playfairDisplay(
        fontSize: 28,
        height: 1.15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: color,
      );

  static TextStyle title({Color? color}) => GoogleFonts.playfairDisplay(
        fontSize: 21,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: color,
      );

  // --- Working UI (Inter) ---
  static TextStyle titleUi({Color? color}) => GoogleFonts.inter(
        fontSize: 17,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: color,
      );

  static TextStyle body({Color? color}) => GoogleFonts.inter(
        fontSize: 15,
        height: 1.45,
        fontWeight: FontWeight.w400,
        color: color,
      );

  static TextStyle bodySm({Color? color}) => GoogleFonts.inter(
        fontSize: 13,
        height: 1.4,
        fontWeight: FontWeight.w400,
        color: color,
      );

  static TextStyle label({Color? color}) => GoogleFonts.inter(
        fontSize: 13,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: color,
      );

  static TextStyle overline({Color? color}) => GoogleFonts.inter(
        fontSize: 11,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        color: color,
      );
}

/// Build a Material [TextTheme] from the GirlTea scale.
/// Playfair → display/headline/titleLarge (editorial); Inter → the rest.
TextTheme gtTextTheme(Color onSurface, Color onSurfaceMuted) {
  final c = onSurface;
  return TextTheme(
    displayLarge: GtText.display(color: c),
    displayMedium: GtText.headline(color: c),
    displaySmall: GtText.title(color: c),
    headlineMedium: GtText.headline(color: c),
    headlineSmall: GtText.title(color: c),
    titleLarge: GtText.title(color: c),
    titleMedium: GtText.titleUi(color: c),
    titleSmall: GtText.label(color: c),
    bodyLarge: GtText.body(color: c),
    bodyMedium: GtText.body(color: c),
    bodySmall: GtText.bodySm(color: onSurfaceMuted),
    labelLarge: GtText.label(color: c),
    labelMedium: GtText.label(color: c),
    labelSmall: GtText.overline(color: onSurfaceMuted),
  );
}
