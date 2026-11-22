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
  Exercise(
    name: 'Biceps Curl',
    right: [12, 14, 16],
    downAngle: 64,
    upAngle: 160,
    limits: {
      'maxSpeed': 400,
      'shoulderMove': 0.15,
      'shoulderMoveReject': 0.15,
      'elbowMove': 0.30,
      'elbowMoveReject': 0.20,
      'elbowDrift': 20,
      'elbowDriftReject': 15,
      'swing': 10,
      'swingReject': 10,
      'shrug': 0.10,
      'shrugReject': 0.06,
      'armShorten': 0.12,
      'armShortenReject': 0.08,
      'armDownMax': 45,
      // raised, tense shoulders: warns when the ear-to-shoulder distance is 10% shorter than the
      // relaxed one, rejects the rep at 18% shorter if it lasts 0.4 s
      'shoulderRaise': 0.10,
      'shoulderRaiseReject': 0.1,
      'shoulderRaiseSeconds': 0.4,
      'frontStrict': 0.87, //front view strictness inverse
    },
  ),
  // Right Leg (hip=24, knee=26, ankle=28), Left Leg (hip=23, knee=25, ankle=27)
  // knee >=165 (standing) = 0% , <=95 (extra deep) = 100% on the bar.
  // A rep COUNTS from partialAngle: <=130 partial, <=110 deep, <=95 extra deep.
  Exercise(
    name: 'Squat',
    right: [24, 26, 28],
    left: [23, 25, 27],
    downAngle: 95,
    upAngle: 165,
    perFrameSmoothing: true,
    limits: {'partialAngle': 130, 'deepAngle': 110, 'extraDeepAngle': 95},
  ),
  // Right Hip (shoulder=12, hip=24, knee=26), Left Hip (shoulder=11, hip=23, knee=25)
  // hip >=165 (standing tall) = 0% , <=100 (full hinge) = 100%
  // (0% is replaced by the user's OWN standing angle, learned automatically)
  Exercise(
    name: 'Deadlift',
    right: [12, 24, 26],
    left: [11, 23, 25],
    downAngle: 100,
    upAngle: 165,
  ),
  // Right Arm (shoulder=12, elbow=14, wrist=16), Left Arm (shoulder=11, elbow=13, wrist=15)
  // arms extended 145 = 0% , bar near the chest 92 = 100%
  // Elbow flare (angle at the shoulder between the torso and the upper arm, measured
  // against the shoulder line): warns past 80, and the rep is NOT counted past 100 (the
  // elbows are then past straight out to the sides, a clear flare). A normal tucked press
  // is 45-70, so this leaves plenty of room for pose noise. Only visible with the camera
  // at the head or foot end of the bench (along the torso).
  //   flareMax     = warn above this ("Elbows flared wide")
  //   flareReject  = the rep does not count above this
  //   flareMin     = warn below this ("Elbows tucked in")
  Exercise(
    name: 'Bench Press',
    right: [12, 14, 16],
    left: [11, 13, 15],
    downAngle: 92,
    upAngle: 145,
    limits: {
      // elbow flare = torso-to-upper-arm angle at the shoulder (shoulder abduction)
      // ~45 deg at a 1.5x biacromial grip, >75 at 2x (Green & Comfort 2007, Strength Cond J 29(5):10-14)
      // near 90 = suspected subacromial impingement zone; these are clinical expert opinion,
      // not measured injury thresholds (Noteboom et al. 2024, Front Physiol 15:1393235)
      'flareMax': 75, // warn above this (wide-grip figure)
      'flareReject': 80,
      'flareMin': 0, // 0 = the "Elbows tucked in" warning never fires (no research basis for a lower bound)
    },
  ),
];

// Deadlift variations (not in the menu list; add them to `exercises` if wanted).
// Starting values: sumo has a more upright torso, the Romanian deadlift needs a
// deeper hinge with nearly straight knees.
const deadliftSumo = Exercise(
  name: 'Sumo Deadlift',
  variant: 'sumo',
  right: [12, 24, 26],
  left: [11, 23, 25],
  downAngle: 145,
  upAngle: 158,
);
const deadliftRomanian = Exercise(
  name: 'Romanian Deadlift',
  variant: 'romanian',
  right: [12, 24, 26],
  left: [11, 23, 25],
  downAngle: 130,
  upAngle: 158,
);
