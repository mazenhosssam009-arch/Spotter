import 'package:ai_trainer/core/theme/app_theme.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/screens/training_menu_screen.dart';
import 'package:ai_trainer/features/voice_coach/presentation/cubit/voice_settings_cubit.dart';
import 'package:ai_trainer/injection_container.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// Main.py: choose your training
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
  await init();
  runApp(const AiTrainerApp());
}

class AiTrainerApp extends StatelessWidget {
  const AiTrainerApp({super.key});

  @override
  Widget build(BuildContext context) {
    // the voice coach settings are read by the menu, the trainer and the settings screen
    return BlocProvider<VoiceSettingsCubit>.value(
      value: sl<VoiceSettingsCubit>(),
      child: MaterialApp(
        title: 'Spotter',
        debugShowCheckedModeBanner: false,
        // the app's shared theme (core/theme/app_theme.dart)
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        // the trainer screens are built dark: always use the dark theme, so buttons on them
        // (+/- reps, Back in the coach dialog) are not dark-on-dark when the phone is in light mode
        themeMode: ThemeMode.dark,
        // Pin the UI to a locale the built-in Material strings support. Without this, a
        // device set to a language/region Flutter has no Material strings for (e.g. some
        // Arabic variants) can leave the Localizations widget without MaterialLocalizations,
        // which crashes AppBar ("No MaterialLocalizations found").
        locale: const Locale('en', 'US'),
        supportedLocales: const [Locale('en', 'US')],
        home: const TrainingMenuScreen(),
      ),
    );
  }
}
