// Spotter design system ("Kinetic Monochrome" + mint accent). The theme itself is the
// app's shared theme in app_theme.dart (AppTheme.dark / AppTheme.light); the tokens and
// widgets below use the same colours, type scale and radii so custom screens match it.
//
// Needs the `google_fonts` package (Space Grotesk, IBM Plex Sans, Cairo for Arabic).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_theme.dart';

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

/// Status chip like app_theme's chips: pill shape, transparent, hairline border, 6px colour dot.
class SpotChip extends StatelessWidget {
  const SpotChip(this.text, {super.key, this.dot, this.textColor = Sp.muted});
  final String text;
  final Color? dot;
  final Color textColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(999), // StadiumBorder
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
                style: Sp.labelMd.copyWith(color: textColor)), // app_theme chip label: labelMedium
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
        backgroundColor: Sp.card, // app_theme dialog: surfaceContainerLow
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Sp.rCard), side: const BorderSide(color: Sp.line)),
        title: Text(title, style: Sp.headlineMd.copyWith(color: Sp.white)), // app_theme: headlineMedium
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
