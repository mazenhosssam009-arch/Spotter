# Applying the Spotter design

1. `pubspec.yaml`: add `google_fonts: ^6.2.1` (Space Grotesk, IBM Plex Sans, Cairo for Arabic).
   For offline gyms, download the fonts once and bundle them as assets
   (google_fonts picks bundled files automatically, see its docs).
2. The theme is `lib/core/theme/app_theme.dart` (`AppTheme`), the `Sp.*` tokens are in
   `lib/core/theme/spotter_theme.dart` and the shared widgets are `lib/core/widgets/spot_widgets.dart`.
3. In `main.dart`:
   ```dart
   MaterialApp(theme: AppTheme.light, darkTheme: AppTheme.dark, themeMode: ThemeMode.dark, ...)
   ```
4. For every other screen use the kit instead of default widgets:
   `SpotCard`, `SpotChip`, `SpotMetric`, `SpotButton` (primary / secondary / destructive / link),
   `SpotDialog`, and the `Sp.*` colours and text styles. Bottom tabs get the Spotter look from
   `NavigationBar` automatically.

## What changed in trainer_page.dart
- All counting / form / rest logic is unchanged.
- Text that used to be drawn onto the camera picture (reps, %, form score, warnings, set info)
  moved into a panel under the camera: status chips, feedback card, REPS DONE card with depth
  progress, FORM SCORE ring, +/- rep buttons and the mint FINISH SET button.
  The depth bar and squat ticks stay on the picture (now mint / amber / red).
- Rest screen, 3-2-1 countdown and all dialogs use the Spotter style.
- `Finish` moved from the app bar to the bottom button (as in the mockup).

## Not covered (files I did not receive)
`camera_view.dart` (its app bar picks up the theme but I could not restyle its internals),
the exercise menu / home screen, and any other pages.
