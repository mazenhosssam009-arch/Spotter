import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'face_detection_module.dart';
import 'pose_page.dart';
import 'trainer.dart';

/// Main.py: choose your training
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
  runApp(const AiTrainerApp());
}

class AiTrainerApp extends StatelessWidget {
  const AiTrainerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spotter',
      debugShowCheckedModeBanner: false,
      // the app's shared theme (core/theme/app_theme.dart)
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // the trainer screens are built dark: always use the dark theme, so buttons on them
      // (+/- reps, Back in the coach dialog) are not dark-on-dark when the phone is in light mode
      themeMode: ThemeMode.dark,
      home: const MenuPage(),
    );
  }
}

class MenuPage extends StatelessWidget {
  const MenuPage({super.key});

  void _open(BuildContext context, Widget page, String feature) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => kIsWeb ? ChromeSupportPage(feature: feature) : page,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Spotter')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Choose your training:',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (kIsWeb) ...[
            const SizedBox(height: 8),
            const Text(
              'Chrome supports the app interface, but live camera detection '
              'requires the Android or iOS app.',
            ),
          ],
          const SizedBox(height: 12),
          for (var i = 0; i < exercises.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                onPressed: () => _open(
                  context,
                  TrainerPage(exercise: exercises[i]),
                  'Workout tracking',
                ),
                child: Text(
                  '${i + 1} - ${exercises[i].name}',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
          const SizedBox(height: 24),
          Text(
            'Learning demos',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () =>
                _open(context, const PosePage(), 'Pose estimation'),
            child: const Text('Pose Estimation (PoseModule)'),
          ),
          OutlinedButton(
            onPressed: () =>
                _open(context, const FaceDetectionPage(), 'Face detection'),
            child: const Text('Face Detection (FaceDetectionModule)'),
          ),
        ],
      ),
    );
  }
}

class ChromeSupportPage extends StatelessWidget {
  const ChromeSupportPage({super.key, required this.feature});

  final String feature;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chrome support')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.phone_android, size: 48),
                const SizedBox(height: 16),
                Text(
                  '$feature is not available in Chrome',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'This feature uses Google ML Kit and live camera image '
                  'streaming, which are not supported by this Flutter web '
                  'build. Run Spotter on an Android or iOS device to use '
                  'camera-based detection.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back to menu'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
