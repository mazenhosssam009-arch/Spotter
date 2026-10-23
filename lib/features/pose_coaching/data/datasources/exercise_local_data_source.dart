import 'package:ai_trainer/features/pose_coaching/domain/entities/exercise.dart';

// the exercise catalogue on the device (Main.py menu)
abstract class ExerciseLocalDataSource {
  List<Exercise> getExercises();
}

class ExerciseLocalDataSourceImpl implements ExerciseLocalDataSource {
  @override
  List<Exercise> getExercises() => exercises;
}

const exercises = [
  // Right Arm (shoulder=12, elbow=14, wrist=16)
  // elbow >=160 (extended) -> <=64 (flexed)
  // full curl = 130 deg elbow flexion = 50 deg here (Pinto et al. (2012) J Strength Cond Res
  // 26(8):2140-2145) + 14 deg pose-estimation elbow error (Francia et al. (2024) LNCS
  // Extended Reality pp.40-49) = 64. 45 needed 135 deg of flexion, more than a full curl.
  Exercise(name: 'Biceps Curl', right: [12, 14, 16], downAngle: 64, upAngle: 160,
      limits: {'maxSpeed': 400}),
  // Right Leg (hip=24, knee=26, ankle=28), Left Leg (hip=23, knee=25, ankle=27)
  // knee >=165 (standing) = 0% , <=95 (extra deep) = 100% on the bar.
  // A rep COUNTS from partialAngle: <=130 partial, <=110 deep, <=95 extra deep.
  Exercise(name: 'Squat', right: [24, 26, 28], left: [23, 25, 27], downAngle: 95, upAngle: 165,
      perFrameSmoothing: true,
      limits: {'partialAngle': 130, 'deepAngle': 110, 'extraDeepAngle': 95}),
  // Right Hip (shoulder=12, hip=24, knee=26), Left Hip (shoulder=11, hip=23, knee=25)
  // hip >=165 (standing tall) = 0% , <=100 (full hinge) = 100%
  // (0% is replaced by the user's OWN standing angle, learned automatically)
  Exercise(name: 'Deadlift', right: [12, 24, 26], left: [11, 23, 25], downAngle: 100, upAngle: 165),
  // Right Arm (shoulder=12, elbow=14, wrist=16), Left Arm (shoulder=11, elbow=13, wrist=15)
  // arms extended 145 = 0% , bar near the chest 92 = 100%
  Exercise(name: 'Bench Press', right: [12, 14, 16], left: [11, 13, 15], downAngle: 92, upAngle: 145),
];

// Deadlift variations (not in the menu list; add them to `exercises` if wanted).
// Starting values: sumo has a more upright torso, the Romanian deadlift needs a
// deeper hinge with nearly straight knees.
const deadliftSumo = Exercise(
    name: 'Sumo Deadlift', variant: 'sumo', right: [12, 24, 26], left: [11, 23, 25],
    downAngle: 145, upAngle: 158);
const deadliftRomanian = Exercise(
    name: 'Romanian Deadlift', variant: 'romanian', right: [12, 24, 26], left: [11, 23, 25],
    downAngle: 130, upAngle: 158);
