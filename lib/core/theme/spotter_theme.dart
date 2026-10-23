// Spotter design system ("Kinetic Monochrome" + mint accent). The theme itself is the
// app's shared theme in app_theme.dart (AppTheme.dark / AppTheme.light); the tokens and
// widgets below use the same colours, type scale and radii so custom screens match it.
//
// Needs the `google_fonts` package (Space Grotesk, IBM Plex Sans, Cairo for Arabic).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ai_trainer/core/theme/app_theme.dart';

/// colour + type tokens (values read from the mockups' code.html)
class Sp {
  Sp._();

  // surfaces (dark green-black, tonal layers, no shadows)
  static const canvas = Color(0xFF0B1715); // level 0: app background
  static const card = Color(0xFF112420); // level 2: cards, chips
  static const cardHigh = Color(0xFF162F29); // level 3: dialogs, menus
  static const line = Color(0xFF1A3830); // 1px hairline borders / tracks
  static const neutral = Color(0xFF201F1F); // neutral dark (destructive button)
  static const neutralHigh = Color(0xFF2A2A2A); // icon wells

  // accent + text
  static const mint = Color(0xFF59EBAB); // primary accent / "good"
  static const mintDim = Color(0xFF56A986); // secondary (app_theme)
  static const white = Color(0xFFFFFFFF);
  static const onSurface = Color(0xFFFFFFFF); // app_theme onSurface
  static const muted = Color(0xFFC4C7C8);
  static const outline = Color(0xFF8E9192);

  // semantic status colours (only for real feedback)
  static const warn = Color(0xFFF59E0B);
  static const fault = Color(0xFFEF4444);
  static const faultSoft = Color(0xFFFFB4AB);
  static const faultContainer = Color(0xFF93000A);

  // radii (app_theme: 12 for cards, dialogs, buttons and inputs)
  static const rCard = 12.0;
  static const rButton = 12.0;
  static const rChip = 8.0;

  static final _ar = GoogleFonts.cairo().fontFamily!; // Arabic glyph fallback

  static TextStyle _head(double size, FontWeight w, double lsEm, double lh) =>
      GoogleFonts.spaceGrotesk(
        fontSize: size,
        fontWeight: w,
        letterSpacing: size * lsEm,
        height: lh / size,
        color: onSurface,
      ).copyWith(fontFamilyFallback: [_ar], fontFeatures: const [FontFeature.tabularFigures()]);

  static TextStyle _body(double size, FontWeight w, double lh, [double ls = 0]) =>
      GoogleFonts.ibmPlexSans(
        fontSize: size,
        fontWeight: w,
        letterSpacing: ls,
        height: lh / size,
        color: onSurface,
      ).copyWith(fontFamilyFallback: [_ar]);

  static final displayMetric = _head(56, FontWeight.w700, -0.04, 60);
  static final headlineLg = _head(32, FontWeight.w700, -0.02, 38);
  static final headlineMd = _head(24, FontWeight.w600, -0.01, 30);
  static final headlineSm = _head(18, FontWeight.w600, 0, 24);
  static final bodyLg = _body(16, FontWeight.w500, 24);
  static final bodyMd = _body(14, FontWeight.w400, 20);
  static final bodySm = _body(12, FontWeight.w400, 16, 0.12);
  static final labelLg = _head(14, FontWeight.w600, 0.04, 18);
  static final labelMd = _head(12, FontWeight.w600, 0.05, 16);
  static final labelSm = _head(10, FontWeight.w700, 0.08, 14);
}

/// The Spotter theme is the app's shared theme (app_theme.dart), so every screen matches.
ThemeData spotterTheme() => AppTheme.dark;

