// Spotter design system ("Kinetic Monochrome" + mint accent) taken from the
// ANANA design kit (DESIGN.md + the 4 screens). Use it for EVERY screen:
//
//   MaterialApp(theme: spotterTheme(), themeMode: ThemeMode.dark, ...)
//
// Needs the `google_fonts` package (Space Grotesk, IBM Plex Sans, Cairo for Arabic).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
  static const mintDim = Color(0xFF83D7B1);
  static const white = Color(0xFFFFFFFF);
  static const onSurface = Color(0xFFE5E2E1);
  static const muted = Color(0xFFC4C7C8);
  static const outline = Color(0xFF8E9192);

  // semantic status colours (only for real feedback)
  static const warn = Color(0xFFF59E0B);
  static const fault = Color(0xFFEF4444);
  static const faultSoft = Color(0xFFFFB4AB);
  static const faultContainer = Color(0xFF93000A);

  // radii
  static const rCard = 16.0;
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

ThemeData spotterTheme() {
  const scheme = ColorScheme.dark(
    primary: Sp.mint,
    onPrimary: Sp.canvas,
    secondary: Sp.mintDim,
    onSecondary: Sp.canvas,
    error: Sp.faultSoft,
    onError: Color(0xFF690005),
    errorContainer: Sp.faultContainer,
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Sp.canvas,
    onSurface: Sp.onSurface,
    onSurfaceVariant: Sp.muted,
    outline: Sp.outline,
    outlineVariant: Sp.line,
    surfaceContainerLowest: Sp.canvas,
    surfaceContainerLow: Sp.canvas,
    surfaceContainer: Sp.card,
    surfaceContainerHigh: Sp.cardHigh,
    surfaceContainerHighest: Sp.cardHigh,
  );
  RoundedRectangleBorder rr(double r, {Color side = Sp.line}) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(r), side: BorderSide(color: side));

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: Sp.canvas,
    canvasColor: Sp.canvas,
    dividerColor: Sp.line,
    iconTheme: const IconThemeData(color: Sp.onSurface),
    textTheme: TextTheme(
      displayLarge: Sp.displayMetric,
      headlineLarge: Sp.headlineLg,
      headlineMedium: Sp.headlineMd,
      headlineSmall: Sp.headlineSm,
      titleLarge: Sp.headlineSm,
      titleMedium: Sp.bodyLg,
      titleSmall: Sp.labelLg,
      bodyLarge: Sp.bodyLg,
      bodyMedium: Sp.bodyMd,
      bodySmall: Sp.bodySm,
      labelLarge: Sp.labelLg,
      labelMedium: Sp.labelMd,
      labelSmall: Sp.labelSm,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Sp.canvas,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Sp.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      shape: const Border(bottom: BorderSide(color: Sp.line)),
      titleTextStyle: Sp.headlineSm.copyWith(fontWeight: FontWeight.w700, color: Sp.white),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Sp.mint,
        foregroundColor: Sp.canvas,
        minimumSize: const Size(0, 52),
        shape: rr(Sp.rButton, side: Colors.transparent),
        textStyle: Sp.labelLg,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Sp.white,
        backgroundColor: Sp.card,
        minimumSize: const Size(0, 52),
        side: const BorderSide(color: Sp.line),
        shape: rr(Sp.rButton),
        textStyle: Sp.labelLg,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Sp.onSurface,
        minimumSize: const Size(44, 44),
        textStyle: Sp.labelLg,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Sp.canvas,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: Sp.bodyMd.copyWith(color: Sp.muted),
      helperStyle: Sp.bodySm.copyWith(color: Sp.muted),
      errorStyle: Sp.bodySm.copyWith(color: Sp.faultSoft),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Sp.rButton), borderSide: const BorderSide(color: Sp.line)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Sp.rButton), borderSide: const BorderSide(color: Sp.line)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Sp.rButton), borderSide: const BorderSide(color: Sp.white)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Sp.rButton), borderSide: const BorderSide(color: Sp.faultSoft)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Sp.rButton), borderSide: const BorderSide(color: Sp.faultSoft)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Sp.card,
      side: const BorderSide(color: Sp.line),
      shape: rr(Sp.rChip),
      labelStyle: Sp.labelMd.copyWith(color: Sp.white),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Sp.cardHigh,
      surfaceTintColor: Colors.transparent,
      shape: rr(Sp.rButton),
      textStyle: Sp.bodyMd,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Sp.cardHigh,
      contentTextStyle: Sp.bodyMd,
      behavior: SnackBarBehavior.floating,
      shape: rr(Sp.rButton),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Sp.mint : Sp.card),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Sp.canvas : Sp.white),
        side: const WidgetStatePropertyAll(BorderSide(color: Sp.line)),
        shape: WidgetStatePropertyAll(rr(Sp.rButton)),
        textStyle: WidgetStatePropertyAll(Sp.labelMd),
      ),
    ),
    // bottom tabs (Home / Workout / Nutrition / Coach / Profile)
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Sp.canvas,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith((s) =>
          Sp.labelSm.copyWith(color: s.contains(WidgetState.selected) ? Sp.mint : Sp.outline)),
      iconTheme: WidgetStateProperty.resolveWith((s) =>
          IconThemeData(color: s.contains(WidgetState.selected) ? Sp.mint : Sp.outline)),
    ),
  );
}

// ============================ shared widgets ============================

/// Level-2 card: tonal fill + 1px hairline, 16px radius, no shadow.
class SpotCard extends StatelessWidget {
  const SpotCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = Sp.card,
    this.borderColor = Sp.line,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(Sp.rCard),
          border: Border.all(color: borderColor),
        ),
        child: child,
      );
}

/// Status chip: neutral dark fill, 6px colour dot, high-contrast label.
class SpotChip extends StatelessWidget {
  const SpotChip(this.text, {super.key, this.dot, this.textColor = Sp.white});
  final String text;
  final Color? dot;
  final Color textColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Sp.card,
          borderRadius: BorderRadius.circular(Sp.rChip),
          border: Border.all(color: Sp.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot != null) ...[
            Container(width: 6, height: 6, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(text.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Sp.labelSm.copyWith(fontSize: 11, color: textColor)),
          ),
        ]),
      );
}

/// Metric card: small uppercase label, big tabular value, optional unit.
class SpotMetric extends StatelessWidget {
  const SpotMetric(this.label, this.value, {super.key, this.unit, this.valueColor = Sp.white});
  final String label;
  final String value;
  final String? unit;
  final Color valueColor;

  @override
  Widget build(BuildContext context) => SpotCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label.toUpperCase(), style: Sp.labelSm.copyWith(color: Sp.muted)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(value, style: Sp.headlineLg.copyWith(color: valueColor)),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(unit!.toUpperCase(), style: Sp.labelSm.copyWith(color: Sp.muted)),
              ],
            ]),
          ),
        ]),
      );
}

enum SpotKind { primary, secondary, destructive, link }

/// Buttons: primary = solid mint, secondary = outlined, destructive = dark with red
/// border (never solid red), link = underlined text. 12px radius, 56px tall by default.
/// Inside a Row wrap it in Expanded.
class SpotButton extends StatelessWidget {
  const SpotButton(this.label,
      {super.key, this.onPressed, this.icon, this.kind = SpotKind.primary, this.height = 56});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final SpotKind kind;
  final double height;

  @override
  Widget build(BuildContext context) {
    final child = Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
      if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
      Flexible(child: Text(label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis)),
    ]);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Sp.rButton));
    switch (kind) {
      case SpotKind.primary:
        return FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(minimumSize: Size.fromHeight(height)),
          child: child,
        );
      case SpotKind.secondary:
        return OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(minimumSize: Size.fromHeight(height)),
          child: child,
        );
      case SpotKind.destructive:
        return OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: Size.fromHeight(height),
            backgroundColor: Sp.neutral,
            foregroundColor: Sp.fault,
            side: const BorderSide(color: Sp.fault),
            shape: shape,
          ),
          child: child,
        );
      case SpotKind.link:
        return TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            minimumSize: const Size(44, 44),
            foregroundColor: Sp.onSurface,
            textStyle: Sp.bodyMd.copyWith(decoration: TextDecoration.underline),
          ),
          child: Text(label),
        );
    }
  }
}

/// Dialog in the Spotter style; actions are stacked full width (gym-glove friendly).
class SpotDialog extends StatelessWidget {
  const SpotDialog({super.key, required this.title, required this.content, required this.actions});
  final String title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: Sp.cardHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Sp.rCard), side: const BorderSide(color: Sp.line)),
        title: Text(title, style: Sp.headlineSm.copyWith(color: Sp.white)),
        content: DefaultTextStyle(style: Sp.bodyMd, child: content),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          SizedBox(
            width: double.infinity,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                actions[i],
              ],
            ]),
          ),
        ],
      );
}
