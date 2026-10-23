import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:ai_trainer/core/route/routing.dart';
import 'package:ai_trainer/features/face_detection/presentation/screens/face_detection_screen.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/bloc/exercise_menu_cubit/exercise_menu_cubit.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/screens/chrome_support_screen.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/screens/pose_estimation_screen.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/screens/trainer_screen.dart';
import 'package:ai_trainer/injection_container.dart';

/// Main.py: choose your training
class TrainingMenuScreen extends StatelessWidget {
  const TrainingMenuScreen({super.key});

  void _open(BuildContext context, Widget page, String feature) {
    Routing.routePush(kIsWeb ? ChromeSupportScreen(feature: feature) : page, context);
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<ExerciseMenuCubit>()..load(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Spotter')),
        body: BlocBuilder<ExerciseMenuCubit, ExerciseMenuState>(
          builder: (context, state) => ListView(
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
              if (state is ExerciseMenuLoading) const Center(child: CircularProgressIndicator()),
              if (state is ExerciseMenuError) Text(state.message),
              if (state is ExerciseMenuLoaded)
                for (var i = 0; i < state.exercises.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                      onPressed: () => _open(
                        context,
                        TrainerScreen(exercise: state.exercises[i]),
                        'Workout tracking',
                      ),
                      child: Text(
                        '${i + 1} - ${state.exercises[i].name}',
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
                    _open(context, const PoseEstimationScreen(), 'Pose estimation'),
                child: const Text('Pose Estimation (PoseModule)'),
              ),
              OutlinedButton(
                onPressed: () =>
                    _open(context, const FaceDetectionScreen(), 'Face detection'),
                child: const Text('Face Detection (FaceDetectionModule)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
