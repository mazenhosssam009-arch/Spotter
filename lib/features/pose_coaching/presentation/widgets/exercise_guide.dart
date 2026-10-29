import 'package:flutter/material.dart';

import 'package:ai_trainer/core/theme/spotter_theme.dart';
import 'package:ai_trainer/core/widgets/spot_widgets.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/exercise.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/widgets/exercise_figures.dart';

// ===================== beginner guide =====================

/// beginner guide: the coach shows the whole movement, then each step with its explanation under him,
/// then the don'ts (red pictures) that cause injuries
({String camera, FigStep demo, List<(FigStep, String)> steps, List<FigMuscle> focus}) _guide(Exercise e) {
  if (e.name.contains('Curl')) {
    const d = FigEquip.dumbbell;
    return (
      camera:
          'Place the phone at hip height, 2-3 m away, and film from the SIDE so your arm and hip are in view.',
      demo: FigStep(Pz.curlDown, Pz.curlUp, d),
      focus: const [FigMuscle.biceps],
      steps: [
        (FigStep(Pz.curlDown, null, d),
            'Stand tall, feet hip-width apart, knees soft, dumbbells in hand with palms facing forward, '
                'elbows slightly bent.'),
        (FigStep(Pz.curlPin, null, d), 'Pin your elbows to your sides. Only your forearms move.'),
        (FigStep(Pz.curlDown, Pz.curlUp, d),
            'Curl up slowly (about 2 seconds) until your forearm is just past level and the weight is in front of '
                'your shoulder. Your elbow stays at your side. Keep your wrists straight.'),
        (FigStep(Pz.curlUp, Pz.curlDown, d),
            'Lower slowly (about 3 seconds) until your arm is ALMOST straight, with a slight bend and the weight '
                'beside the front of your thigh. Do not lock the elbow.'),
        // don'ts
        (FigStep(Pz.curlDown, Pz.curlSwing, d, true),
            "Don't swing your body or lean back to lift the weight. It loads your lower back, not your biceps. Go lighter."),
        (FigStep(Pz.curlDown, Pz.curlElbowFwd, d, true),
            "Don't let your elbows drift forward or up. Your shoulders take over and the front of the shoulder gets strained."),
        (FigStep(Pz.curlUp, Pz.curlDown, d, true),
            "Don't drop the weight or snap your elbow straight at the bottom. That jolt is what hurts the elbow tendons."),
        (FigStep(Pz.curlPin, Pz.curlUp, d, true),
            "Don't bend your wrists back or curl them in, and don't shrug your shoulders up to your ears."),
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
        (FigStep(Pz.squatStand),
            'Feet shoulder-width apart, toes pointing slightly out, hands together in front of your chest.'),
        (FigStep(Pz.squatStand, Pz.squatQuarter),
            'Take a big breath, brace your stomach, chest up, look straight ahead.'),
        (FigStep(Pz.squatStand, Pz.squatDown), 'Push your hips back and down, like sitting on a chair.'),
        (FigStep(Pz.squatDown), 'Push your knees out so they stay in line with your toes.'),
        (FigStep(Pz.squatQuarter, Pz.squatDown),
            'Go down until your thighs are parallel to the floor (the white lines on the bar show partial and deep).'),
        (FigStep(Pz.squatDown, Pz.squatStand), 'Push through your whole foot and stand up fully.'),
        // don'ts
        (FigStep(Pz.squatStand, Pz.squatValgus, FigEquip.none, true),
            "Don't let your knees cave in towards each other. This is the most common cause of knee pain in squats."),
        (FigStep(Pz.squatStand, Pz.squatLean, FigEquip.none, true),
            "Don't fold forward or round your back. Keep your chest up and your back flat to protect your lower back."),
        (FigStep(Pz.squatStand, Pz.squatToes, FigEquip.none, true),
            "Don't shift onto your toes or let your heels lift. Keep your weight over the middle of your feet."),
        (FigStep(Pz.squatDown, Pz.squatStand, FigEquip.none, true),
            "Don't drop fast and bounce out of the bottom, and don't snap your knees locked at the top."),
        (FigStep(Pz.squatQuarter, Pz.squatDown, FigEquip.none, true),
            "Don't hold your breath for the whole set, and don't go deeper than you can keep your back flat."),
      ]
    );
  }
  if (e.name.contains('Deadlift')) {
    const b = FigEquip.barbell;
    return (
      camera:
          'Film from the SIDE at hip height, far enough away that your head and feet are both in view.',
      demo: FigStep(Pz.dlStand, Pz.dlBottom, b),
      focus: const [FigMuscle.hams, FigMuscle.glutes, FigMuscle.back],
      steps: [
        (FigStep(Pz.dlBottom, null, b), 'Feet hip-width apart, the bar over the middle of your feet.'),
        (FigStep(Pz.dlStand, Pz.dlHinge, b),
            'Push your hips back with soft knees until you can grab the bar just outside your legs. Keep your back flat.'),
        (FigStep(Pz.dlBottom, null, b),
            'Shins touch the bar, shoulders just over the bar, neck in line with your back.'),
        (FigStep(Pz.dlBottom, Pz.dlStand, b),
            'Brace your stomach, pull the slack out of the bar, then push the floor away.'),
        (FigStep(Pz.dlHinge, Pz.dlStand, b), 'Keep the bar close to your legs the whole way up.'),
        (FigStep(Pz.dlStand, null, b), 'Stand tall and squeeze your glutes at the top.'),
        (FigStep(Pz.dlStand, Pz.dlBottom, b),
            'Lower by pushing your hips back first, slowly and in control.'),
        // don'ts
        (FigStep(Pz.dlBottom, Pz.dlRound, b, true),
            "Don't round your back or drop your head. This is how most lower back injuries happen. Lower the weight."),
        (FigStep(Pz.dlBottom, Pz.dlBarAway, b, true),
            "Don't let the bar drift away from your legs. The further away it is, the more strain on your lower back."),
        (FigStep(Pz.dlStand, Pz.dlLeanBack, b, true),
            "Don't lean back or push your hips forward at the top. Just stand tall, your spine should stay neutral."),
        (FigStep(Pz.dlBottom, Pz.dlStiff, b, true),
            "Don't shoot your hips up first so your legs straighten before the bar moves. Hips and shoulders rise together."),
        (FigStep(Pz.dlBottom, Pz.dlStand, b, true),
            "Don't jerk the bar off the floor or bend your arms to pull it. Tighten up first, then push smoothly."),
      ]
    );
  }
  const b = FigEquip.barbell;
  return (
    camera: 'Film from the side or from the head end of the bench, at bench height.',
    demo: FigStep(Pz.benchUp, Pz.benchLow, b),
    focus: const [FigMuscle.chest, FigMuscle.triceps],
    steps: [
      (FigStep(Pz.benchUp, null, b),
          'Lie with your eyes under the bar, feet flat on the floor, shoulder blades pinched together, glutes on the bench.'),
      (FigStep(Pz.benchUp, null, b),
          'Grip slightly wider than your shoulders, with wrists straight over your forearms.'),
      (FigStep(Pz.benchUp, Pz.benchLow, b),
          'Lower the bar slowly to your lower chest. Elbows about 45 degrees from your body.'),
      (FigStep(Pz.benchLow, Pz.benchUp, b),
          'Press up and slightly back until the bar is over your shoulders and your arms are straight.'),
      (FigStep(Pz.benchUp, null, b), 'Use a spotter or safety rails for heavy sets.'),
      // don'ts
      (FigStep(Pz.benchUp, Pz.benchLowFlared, b, true),
          "Don't flare your elbows out to 90 degrees. It pinches the shoulder joint and is the main cause of shoulder pain."),
      (FigStep(Pz.benchUp, Pz.benchNeck, b, true),
          "Don't bring the bar down to your neck or upper chest. Touch your lower chest."),
      (FigStep(Pz.benchLow, Pz.benchHipsUp, b, true),
          "Don't lift your hips off the bench to push the weight up. It strains your lower back. Go lighter."),
      (FigStep(Pz.benchUp, Pz.benchLow, b, true),
          "Don't drop the bar and bounce it off your chest. Lower it with control and pause lightly."),
      (FigStep(Pz.benchLow, Pz.benchUp, b, true),
          "Don't bend your wrists back, use a thumbless grip, or lift heavy without a spotter or safety rails."),
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
