import 'package:flutter/material.dart';

import 'package:ai_trainer/core/theme/spotter_theme.dart';
import 'package:ai_trainer/core/widgets/spot_widgets.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/exercise.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/widgets/exercise_figures.dart';

// ===================== beginner guide =====================

/// beginner guide: the coach shows the whole movement, then each step with its explanation under him
({String camera, FigStep demo, List<(FigStep, String)> steps, List<FigMuscle> focus}) _guide(Exercise e) {
  if (e.name.contains('Curl')) {
    return (
      camera:
          'Place the phone at hip height, 2-3 m away, and film from the SIDE so your arm and hip are in view.',
      demo: FigStep(Pz.curlDown, Pz.curlUp, FigEquip.dumbbell),
      focus: const [FigMuscle.biceps],
      steps: [
        (FigStep(Pz.curlDown, null, FigEquip.dumbbell),
            'Stand tall, feet shoulder-width apart, dumbbell in hand, arm straight down.'),
        (FigStep(Pz.curlPin, null, FigEquip.dumbbell), 'Pin your elbow to your side. Only your forearm moves.'),
        (FigStep(Pz.curlDown, Pz.curlUp, FigEquip.dumbbell),
            'Curl up slowly (about 2 seconds) until the weight is near your shoulder.'),
        (FigStep(Pz.curlUp, Pz.curlDown, FigEquip.dumbbell),
            'Lower slowly (about 3 seconds) until your arm is fully straight.'),
        (FigStep(Pz.curlDown, Pz.curlSwing, FigEquip.dumbbell, true),
            'Do not swing your body or shrug your shoulders.'),
      ]
    );
  }
  if (e.name.contains('Squat')) {
    return (
      camera:
          'Place the phone 2.5-3 m away at hip height so your whole body, feet included, is in view (side or front).',
      demo: FigStep(Pz.squatStand, Pz.squatDown),
      focus: const [FigMuscle.quads, FigMuscle.glutes],
      steps: [
        (FigStep(Pz.squatStand), 'Feet shoulder-width apart, toes pointing slightly out.'),
        (FigStep(Pz.squatStand, Pz.squatQuarter), 'Chest up, tighten your stomach, look straight ahead.'),
        (FigStep(Pz.squatStand, Pz.squatDown), 'Push your hips back and down, like sitting on a chair.'),
        (FigStep(Pz.squatDown), 'Keep your knees in line with your toes. Do not let them cave in.'),
        (FigStep(Pz.squatQuarter, Pz.squatDown),
            'Go down until your thighs are parallel to the floor (the white lines on the bar show partial and deep).'),
        (FigStep(Pz.squatDown, Pz.squatStand), 'Push through your whole foot and stand up fully.'),
      ]
    );
  }
  if (e.name.contains('Deadlift')) {
    return (
      camera:
          'Film from the SIDE at hip height, far enough away that your head and feet are both in view.',
      demo: FigStep(Pz.dlStand, Pz.dlBottom, FigEquip.barbell),
      focus: const [FigMuscle.hams, FigMuscle.glutes, FigMuscle.back],
      steps: [
        (FigStep(Pz.dlBottom, null, FigEquip.barbell), 'Feet hip-width apart, the bar over the middle of your feet.'),
        (FigStep(Pz.dlStand, Pz.dlHinge, FigEquip.barbell),
            'Push your hips back with soft knees until you can grab the bar. Keep your back flat.'),
        (FigStep(Pz.dlBottom, Pz.dlStand, FigEquip.barbell),
            'Chest up, pull the slack out of the bar, then push the floor away.'),
        (FigStep(Pz.dlHinge, Pz.dlStand, FigEquip.barbell), 'Keep the bar close to your legs the whole way up.'),
        (FigStep(Pz.dlStand, null, FigEquip.barbell), 'Stand tall and squeeze your glutes. Do not lean back.'),
        (FigStep(Pz.dlStand, Pz.dlBottom, FigEquip.barbell),
            'Lower by pushing your hips back first, slowly and in control.'),
      ]
    );
  }
  return (
    camera: 'Film from the side or from the head end of the bench, at bench height.',
    demo: FigStep(Pz.benchUp, Pz.benchLow, FigEquip.barbell),
    focus: const [FigMuscle.chest, FigMuscle.triceps],
    steps: [
      (FigStep(Pz.benchUp, null, FigEquip.barbell),
          'Lie with your eyes under the bar, feet flat, shoulder blades pinched together, glutes on the bench.'),
      (FigStep(Pz.benchUp, null, FigEquip.barbell),
          'Grip slightly wider than your shoulders, with wrists straight over your forearms.'),
      (FigStep(Pz.benchUp, Pz.benchLow, FigEquip.barbell),
          'Lower the bar slowly to mid-chest. Elbows about 45-75 degrees from your body.'),
      (FigStep(Pz.benchLow, Pz.benchUp, FigEquip.barbell), 'Press up until your arms are locked out.'),
      (FigStep(Pz.benchUp, null, FigEquip.barbell), 'Use a spotter or safety rails for heavy sets.'),
    ]
  );
}

/// the "How to" button: camera setup, then the coach shows the movement step by step
void showExerciseGuide(BuildContext context, Exercise exercise) {
  final g = _guide(exercise);
  showDialog(
    context: context,
    builder: (c) => SpotDialog(
      title: 'How to: ${exercise.name}',
      content: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          const SpotChip('Camera setup', dot: Sp.mint),
          const SizedBox(height: 8),
          Text(g.camera),
          const SizedBox(height: 16),
          const SpotChip('Your coach', dot: Sp.mint),
          const SizedBox(height: 8),
          TrainerGuide(demo: g.demo, steps: g.steps, focus: g.focus),
        ]),
      ),
      actions: [SpotButton('Got it', onPressed: () => Navigator.pop(c))],
    ),
  );
}
