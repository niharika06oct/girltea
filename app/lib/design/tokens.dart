// ============================================================
// GirlTea design tokens — the single source of truth for colour,
// spacing, radius, shadow, motion and breakpoints.
// ============================================================
// Nothing in the app should hardcode a hex, a radius or a raw font size.
// Colours that must adapt to light/dark live in [GtColors], a ThemeExtension
// resolved per-brightness — so dark mode is a token swap, not a rewrite.
// Brightness-independent scales (space/radius/motion/breakpoints) are plain
// const classes you can read anywhere without a BuildContext.
import 'package:flutter/material.dart';

// ------------------------------------------------------------
// Raw palette — from the mockup's "GirlTea Design System" swatches.
// Use these to *build* semantic tokens; prefer the semantic roles at
// call-sites (context.gt.accent, not GtPalette.berry).
// ------------------------------------------------------------
class GtPalette {
  const GtPalette._();
  static const berry = Color(0xFF6E294C); // primary deep tone
  static const plum = Color(0xFF7D3158); // secondary deep tone
  static const dustyRose = Color(0xFFEBB4C2); // soft rose accent
  static const peach = Color(0xFFFFD9C6); // warm peach
  static const sage = Color(0xFFA7B89F); // muted green
  static const cream = Color(0xFFFFF9F5); // warm off-white surface
  static const teaBrown = Color(0xFF8B5E3C); // tea brown
  static const lavender = Color(0xFFDCC6E8); // soft lavender
  static const butter = Color(0xFFFFF2A8); // butter yellow
  static const ink = Color(0xFF2B1F24); // near-black warm text
  static const rose = Color(0xFFE35B85); // bright rose — sparingly, on dark
}

// ------------------------------------------------------------
// Semantic colours — the roles call-sites actually use. Resolved per
// brightness; register both on ThemeData.extensions and read via context.gt.
// ------------------------------------------------------------
@immutable
class GtColors extends ThemeExtension<GtColors> {
  const GtColors({
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.onSurface,
    required this.onSurfaceMuted,
    required this.onSurfaceFaint,
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.hairline,
    required this.danger,
    required this.success,
    required this.brand,
    required this.lavender,
    required this.sage,
    required this.peach,
    required this.butter,
    required this.teaBrown,
    required this.dustyRose,
  });

  final Color surface; // app background
  final Color surfaceRaised; // cards, sheets
  final Color surfaceSunken; // rails, inset areas
  final Color onSurface; // primary text
  final Color onSurfaceMuted; // secondary text / captions
  final Color onSurfaceFaint; // hints, disabled
  final Color accent; // primary brand action
  final Color accentSoft; // soft accent fill (chips, active rows)
  final Color onAccent; // text/icon on an accent fill
  final Color hairline; // borders, dividers
  final Color danger; // errors, destructive
  final Color success; // confirmations
  final Color brand; // the wordmark
  // Expressive accents for circle identity / stickers / doodles.
  final Color lavender;
  final Color sage;
  final Color peach;
  final Color butter;
  final Color teaBrown;
  final Color dustyRose;

  static const light = GtColors(
    surface: GtPalette.cream,
    surfaceRaised: Color(0xFFFFFDFB),
    surfaceSunken: Color(0xFFF6ECE6),
    onSurface: GtPalette.ink,
    onSurfaceMuted: Color(0xFF6E5D63),
    onSurfaceFaint: Color(0xFFA2919A),
    accent: GtPalette.berry,
    accentSoft: Color(0xFFF7E4EA),
    onAccent: Colors.white,
    hairline: Color(0xFFEADBE1),
    danger: Color(0xFFB3261E),
    success: Color(0xFF4E7A57),
    brand: GtPalette.berry,
    lavender: GtPalette.lavender,
    sage: GtPalette.sage,
    peach: GtPalette.peach,
    butter: GtPalette.butter,
    teaBrown: GtPalette.teaBrown,
    dustyRose: GtPalette.dustyRose,
  );

  // "Late-night GirlTea" — deep aubergine / wine-black, warm cream text.
  // Not an inversion: warmth is preserved, accents are muted-expressive.
  static const dark = GtColors(
    surface: Color(0xFF1C1418),
    surfaceRaised: Color(0xFF271B21),
    surfaceSunken: Color(0xFF150E12),
    onSurface: Color(0xFFF3E7DD),
    onSurfaceMuted: Color(0xFFC4A9AE),
    onSurfaceFaint: Color(0xFF8A6F76),
    accent: Color(0xFFE68AA8), // brighter rose reads on dark
    accentSoft: Color(0xFF3A2530),
    onAccent: Color(0xFF1C1418),
    hairline: Color(0xFF3A2A31),
    danger: Color(0xFFF2B8B5),
    success: Color(0xFFA7C4AC),
    brand: Color(0xFFF0C9D6),
    lavender: Color(0xFFC9B2D8),
    sage: Color(0xFF97A88F),
    peach: Color(0xFFE9C3B1),
    butter: Color(0xFFE9DC93),
    teaBrown: Color(0xFFB58963),
    dustyRose: Color(0xFFD79BAC),
  );

  @override
  GtColors copyWith({
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceSunken,
    Color? onSurface,
    Color? onSurfaceMuted,
    Color? onSurfaceFaint,
    Color? accent,
    Color? accentSoft,
    Color? onAccent,
    Color? hairline,
    Color? danger,
    Color? success,
    Color? brand,
    Color? lavender,
    Color? sage,
    Color? peach,
    Color? butter,
    Color? teaBrown,
    Color? dustyRose,
  }) {
    return GtColors(
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      onSurface: onSurface ?? this.onSurface,
      onSurfaceMuted: onSurfaceMuted ?? this.onSurfaceMuted,
      onSurfaceFaint: onSurfaceFaint ?? this.onSurfaceFaint,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      onAccent: onAccent ?? this.onAccent,
      hairline: hairline ?? this.hairline,
      danger: danger ?? this.danger,
      success: success ?? this.success,
      brand: brand ?? this.brand,
      lavender: lavender ?? this.lavender,
      sage: sage ?? this.sage,
      peach: peach ?? this.peach,
      butter: butter ?? this.butter,
      teaBrown: teaBrown ?? this.teaBrown,
      dustyRose: dustyRose ?? this.dustyRose,
    );
  }

  @override
  GtColors lerp(ThemeExtension<GtColors>? other, double t) {
    if (other is! GtColors) return this;
    return GtColors(
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      onSurfaceMuted: Color.lerp(onSurfaceMuted, other.onSurfaceMuted, t)!,
      onSurfaceFaint: Color.lerp(onSurfaceFaint, other.onSurfaceFaint, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      success: Color.lerp(success, other.success, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      lavender: Color.lerp(lavender, other.lavender, t)!,
      sage: Color.lerp(sage, other.sage, t)!,
      peach: Color.lerp(peach, other.peach, t)!,
      butter: Color.lerp(butter, other.butter, t)!,
      teaBrown: Color.lerp(teaBrown, other.teaBrown, t)!,
      dustyRose: Color.lerp(dustyRose, other.dustyRose, t)!,
    );
  }
}

// ============================================================
// Named themes — "be you, here". A community member picks an app-wide
// vibe; each theme is just a full [GtColors] palette + a brightness, so the
// picker swaps the same semantic roles everything already reads via context.gt.
// Two themes (Indigo Nights, Noir Club) are dark. This is a *personal* app
// theme; a circle's own accent_color is a separate, per-room tint.
// ============================================================
enum GtThemeId {
  cottonCandy,
  queerJoy,
  indigoNights,
  sageSpace,
  sunsetDrive,
  lavenderHaze,
  cherryKiss,
  noirClub,
}

@immutable
class GtTheme {
  const GtTheme({
    required this.id,
    required this.name,
    required this.tagline,
    required this.emoji,
    required this.brightness,
    required this.colors,
    required this.swatches,
  });

  final GtThemeId id;
  final String name;
  final String tagline; // the vibe line from the mockup
  final String emoji;
  final Brightness brightness;
  final GtColors colors;
  final List<Color> swatches; // preview dots for the picker card

  bool get isDark => brightness == Brightness.dark;
}

// The default: matches GirlTea's original cream + berry look, so members
// who never open the picker see no change.
const GtThemeId kDefaultThemeId = GtThemeId.cherryKiss;

// Ordered as in the mockup's "Theme Options for Our Community".
const List<GtTheme> gtThemes = [
  GtTheme(
    id: GtThemeId.cottonCandy,
    name: 'Cotton Candy',
    tagline: 'Soft, sweet & dreamy. For the soft girls and hopeless romantics.',
    emoji: '🎀',
    brightness: Brightness.light,
    swatches: [Color(0xFFF4A9C4), Color(0xFFF7C6D6), Color(0xFFD9C7EA)],
    colors: GtColors(
      surface: Color(0xFFFFF0F6),
      surfaceRaised: Color(0xFFFFFAFC),
      surfaceSunken: Color(0xFFFBE1EC),
      onSurface: Color(0xFF4A2C3A),
      onSurfaceMuted: Color(0xFF8A6675),
      onSurfaceFaint: Color(0xFFBE9AA9),
      accent: Color(0xFFEC6BA0),
      accentSoft: Color(0xFFFBDCE8),
      onAccent: Colors.white,
      hairline: Color(0xFFF3D6E2),
      danger: Color(0xFFB3261E),
      success: Color(0xFF4E7A57),
      brand: Color(0xFFD44E86),
      lavender: GtPalette.lavender,
      sage: GtPalette.sage,
      peach: GtPalette.peach,
      butter: GtPalette.butter,
      teaBrown: GtPalette.teaBrown,
      dustyRose: GtPalette.dustyRose,
    ),
  ),
  GtTheme(
    id: GtThemeId.queerJoy,
    name: 'Queer Joy',
    tagline: 'Bold, bright & proud. For the loud, the proud and the playful.',
    emoji: '✨',
    brightness: Brightness.light,
    swatches: [
      Color(0xFFE5393B),
      Color(0xFFF5821F),
      Color(0xFFFCC419),
      Color(0xFF4CAF50),
      Color(0xFF2196F3),
      Color(0xFF8E44AD),
    ],
    colors: GtColors(
      surface: Color(0xFFFFF4EC),
      surfaceRaised: Color(0xFFFFFBF6),
      surfaceSunken: Color(0xFFFCE6D6),
      onSurface: Color(0xFF3F2A20),
      onSurfaceMuted: Color(0xFF7E5F4E),
      onSurfaceFaint: Color(0xFFB79A88),
      accent: Color(0xFFF26B3A),
      accentSoft: Color(0xFFFBDFCE),
      onAccent: Colors.white,
      hairline: Color(0xFFF3D8C6),
      danger: Color(0xFFC62828),
      success: Color(0xFF3E8E5A),
      brand: Color(0xFFE0417D),
      lavender: Color(0xFFB48CE0),
      sage: Color(0xFF7FB77E),
      peach: Color(0xFFFFC48A),
      butter: Color(0xFFFFE066),
      teaBrown: GtPalette.teaBrown,
      dustyRose: Color(0xFFF48FB1),
    ),
  ),
  GtTheme(
    id: GtThemeId.indigoNights,
    name: 'Indigo Nights',
    tagline: 'Deep, moody & magical. For late-night talks and overthinkers.',
    emoji: '🌙',
    brightness: Brightness.dark,
    swatches: [Color(0xFF3B2E7E), Color(0xFFB79BEA), Color(0xFFF4C6D9)],
    colors: GtColors(
      surface: Color(0xFF1A1640),
      surfaceRaised: Color(0xFF262051),
      surfaceSunken: Color(0xFF120F30),
      onSurface: Color(0xFFEDE7FF),
      onSurfaceMuted: Color(0xFFB3A9D9),
      onSurfaceFaint: Color(0xFF7A6FA6),
      accent: Color(0xFFB79BEA),
      accentSoft: Color(0xFF322B5C),
      onAccent: Color(0xFF1A1640),
      hairline: Color(0xFF352E63),
      danger: Color(0xFFF2B8B5),
      success: Color(0xFFA7C4AC),
      brand: Color(0xFFE6D9FF),
      lavender: Color(0xFFC9B2D8),
      sage: Color(0xFF97A88F),
      peach: Color(0xFFE9C3B1),
      butter: Color(0xFFE9DC93),
      teaBrown: Color(0xFFB58963),
      dustyRose: Color(0xFFD79BAC),
    ),
  ),
  GtTheme(
    id: GtThemeId.sageSpace,
    name: 'Sage Space',
    tagline: 'Calm, grounded & fresh. For growth minds and green-flag energy.',
    emoji: '🌿',
    brightness: Brightness.light,
    swatches: [Color(0xFF7B9A69), Color(0xFFA8BE8F), Color(0xFFE4E8D6)],
    colors: GtColors(
      surface: Color(0xFFF2F4EA),
      surfaceRaised: Color(0xFFFBFCF5),
      surfaceSunken: Color(0xFFE4E8D6),
      onSurface: Color(0xFF2E3A2A),
      onSurfaceMuted: Color(0xFF61705A),
      onSurfaceFaint: Color(0xFF9AA98F),
      accent: Color(0xFF7B9A69),
      accentSoft: Color(0xFFE1E9D5),
      onAccent: Colors.white,
      hairline: Color(0xFFDBE2CC),
      danger: Color(0xFFB3261E),
      success: Color(0xFF4E7A57),
      brand: Color(0xFF4F6B43),
      lavender: GtPalette.lavender,
      sage: Color(0xFF8CA57C),
      peach: GtPalette.peach,
      butter: GtPalette.butter,
      teaBrown: GtPalette.teaBrown,
      dustyRose: GtPalette.dustyRose,
    ),
  ),
  GtTheme(
    id: GtThemeId.sunsetDrive,
    name: 'Sunset Drive',
    tagline: 'Warm, nostalgic & free. For adventure seekers and road-trip souls.',
    emoji: '☀️',
    brightness: Brightness.light,
    swatches: [
      Color(0xFFEE7638),
      Color(0xFFF5A15C),
      Color(0xFFF4C6A0),
      Color(0xFF5B8FB0),
    ],
    colors: GtColors(
      surface: Color(0xFFFFF1E3),
      surfaceRaised: Color(0xFFFFF9F1),
      surfaceSunken: Color(0xFFFBE0CB),
      onSurface: Color(0xFF45291D),
      onSurfaceMuted: Color(0xFF855E48),
      onSurfaceFaint: Color(0xFFC09B82),
      accent: Color(0xFFEE7638),
      accentSoft: Color(0xFFFBDFC8),
      onAccent: Colors.white,
      hairline: Color(0xFFF3D7BF),
      danger: Color(0xFFC62828),
      success: Color(0xFF4E7A57),
      brand: Color(0xFFC9542A),
      lavender: GtPalette.lavender,
      sage: GtPalette.sage,
      peach: Color(0xFFFFC49A),
      butter: GtPalette.butter,
      teaBrown: GtPalette.teaBrown,
      dustyRose: GtPalette.dustyRose,
    ),
  ),
  GtTheme(
    id: GtThemeId.lavenderHaze,
    name: 'Lavender Haze',
    tagline: 'Soft, mystical & intuitive. For creatives and sensitive souls.',
    emoji: '💜',
    brightness: Brightness.light,
    swatches: [Color(0xFF9B7BC7), Color(0xFFC3ABE0), Color(0xFFEFE6F8)],
    colors: GtColors(
      surface: Color(0xFFF4EEFA),
      surfaceRaised: Color(0xFFFCF9FF),
      surfaceSunken: Color(0xFFE7DCF3),
      onSurface: Color(0xFF352A44),
      onSurfaceMuted: Color(0xFF6E6086),
      onSurfaceFaint: Color(0xFFA495BC),
      accent: Color(0xFF9B7BC7),
      accentSoft: Color(0xFFE7DCF3),
      onAccent: Colors.white,
      hairline: Color(0xFFE3D6F0),
      danger: Color(0xFFB3261E),
      success: Color(0xFF4E7A57),
      brand: Color(0xFF6E4E9E),
      lavender: Color(0xFFC3ABE0),
      sage: GtPalette.sage,
      peach: GtPalette.peach,
      butter: GtPalette.butter,
      teaBrown: GtPalette.teaBrown,
      dustyRose: GtPalette.dustyRose,
    ),
  ),
  GtTheme(
    id: GtThemeId.cherryKiss,
    name: 'Cherry Kiss',
    tagline: 'Flirty, fun & confident. For the main-character energy.',
    emoji: '💋',
    brightness: Brightness.light,
    swatches: [GtPalette.berry, Color(0xFFE83E75), Color(0xFFF4A9C4)],
    colors: GtColors.light, // GirlTea's original cream + berry
  ),
  GtTheme(
    id: GtThemeId.noirClub,
    name: 'Noir Club',
    tagline: 'Sleek, edgy & unapologetic. For the rebels and rule breakers.',
    emoji: '⚡',
    brightness: Brightness.dark,
    swatches: [
      Color(0xFF1E1C20),
      Color(0xFFE83E75),
      Color(0xFF9A9A9A),
      Color(0xFFF3F1F4),
    ],
    colors: GtColors(
      surface: Color(0xFF121114),
      surfaceRaised: Color(0xFF1E1C20),
      surfaceSunken: Color(0xFF0A0A0C),
      onSurface: Color(0xFFF3F1F4),
      onSurfaceMuted: Color(0xFFB8B2BC),
      onSurfaceFaint: Color(0xFF7A737E),
      accent: Color(0xFFE83E75),
      accentSoft: Color(0xFF33212A),
      onAccent: Colors.white,
      hairline: Color(0xFF2E2C31),
      danger: Color(0xFFF2B8B5),
      success: Color(0xFFA7C4AC),
      brand: Color(0xFFF3F1F4),
      lavender: Color(0xFFC9B2D8),
      sage: Color(0xFF97A88F),
      peach: Color(0xFFE9C3B1),
      butter: Color(0xFFE9DC93),
      teaBrown: Color(0xFFB58963),
      dustyRose: Color(0xFFE83E75),
    ),
  ),
];

/// Look up a theme by its persisted [GtThemeId.name]; falls back to the
/// default when the stored value is null or unrecognised.
GtTheme gtThemeByName(String? name) {
  for (final t in gtThemes) {
    if (t.id.name == name) return t;
  }
  return gtThemes.firstWhere((t) => t.id == kDefaultThemeId);
}

// ------------------------------------------------------------
// Spacing — 4-based scale. Use these instead of raw SizedBox/EdgeInsets ints.
// ------------------------------------------------------------
class GtSpace {
  const GtSpace._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

// ------------------------------------------------------------
// Radii. `organic` returns a gently asymmetric shape so not every card is a
// uniform rounded rectangle (brief §7 — organic containers).
// ------------------------------------------------------------
class GtRadii {
  const GtRadii._();
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 22;
  static const double pill = 100;

  static BorderRadius all(double r) => BorderRadius.circular(r);

  /// A subtly hand-made rounded rectangle — corners differ by a few px.
  static BorderRadius organic({double base = lg}) => BorderRadius.only(
        topLeft: Radius.circular(base + 4),
        topRight: Radius.circular(base - 2),
        bottomLeft: Radius.circular(base - 3),
        bottomRight: Radius.circular(base + 3),
      );
}

// ------------------------------------------------------------
// Shadows — one soft warm elevation. No heavy drop shadows (brief §26).
// ------------------------------------------------------------
class GtShadow {
  const GtShadow._();
  static List<BoxShadow> soft(Brightness b) => [
        BoxShadow(
          color: b == Brightness.light
              ? const Color(0x14000000)
              : const Color(0x33000000),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];
}

// ------------------------------------------------------------
// Motion — warm/organic, never gaming-like (brief §18).
// ------------------------------------------------------------
class GtMotion {
  const GtMotion._();
  static const Duration quick = Duration(milliseconds: 120);
  static const Duration settle = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 400);
  static const Curve organic = Curves.easeOutCubic;
  static const Curve spring = Curves.easeOutBack;
}

// ------------------------------------------------------------
// Breakpoints — mobile-first (brief §20). Reuses the app's existing 900/1180.
// ------------------------------------------------------------
class GtBreak {
  const GtBreak._();
  static const double largePhone = 600;
  static const double tablet = 900; // → desktop shell (rail | feed)
  static const double desktop = 1180; // → also show right panel
}

// ------------------------------------------------------------
// Circle accent — each circle can carry its own accent colour so switching
// circles feels like a different room. Stored as a hex string on the group.
// ------------------------------------------------------------
class GtAccents {
  const GtAccents._();

  /// Swatches offered in the circle-creation picker.
  static const List<Color> swatches = [
    GtPalette.berry,
    GtPalette.plum,
    GtPalette.teaBrown,
    GtPalette.sage,
    GtPalette.lavender,
    GtPalette.dustyRose,
    GtPalette.peach,
    GtPalette.butter,
  ];

  /// Parse a stored accent (`#RRGGBB` / `RRGGBB` / `#AARRGGBB`) to a Color,
  /// falling back to [fallback] when null or malformed.
  static Color parse(String? hex, {required Color fallback}) {
    if (hex == null) return fallback;
    var h = hex.trim().replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return fallback;
    final v = int.tryParse(h, radix: 16);
    return v == null ? fallback : Color(v);
  }

  static String toHex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

// ------------------------------------------------------------
// Convenience: read the semantic colours off any BuildContext.
// ------------------------------------------------------------
extension GtContext on BuildContext {
  GtColors get gt =>
      Theme.of(this).extension<GtColors>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? GtColors.dark
          : GtColors.light);
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
