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
      // Flare is read from the head/foot end at bench height (the only view that shows it). In
      // a 3D-projected test of that view one reading is ~5-8 deg LOW (true 20/45/75/95 ->
      // 13/37/69/90) and the average over the bottom of the rep (what rejects a rep) ~9 low
      // (true 30/75/90 -> 22/65/81), so the limits are the true angles minus those offsets.
      // Studied abduction range 45-90 deg (Noteboom et al. 2024); <1.5x shoulder-width grips stay
      // below 45, 2x grips go past 75 (Fees 1998, cited there).
      'flareMax': 70, // warn: wider than a wide grip (true ~75)
      // reject (bottom average) from the 90 deg "high abduction" variant on: 80 = true ~89, a
      // little below 90 so a 90 deg flare is never left on the knife edge (85 still counts)
      'flareReject': 80,
      // Very tucked: below the studied 45-90 range, elbows pinned to the ribs. A coaching
      // limit, not an injury threshold (close-grip pressing near 45 deg is normal).
      'flareMin': 32, // warn (true ~40)
      'tuckReject': 22, // reject (bottom average, true 30)
      // the bar must come down to <= 65% of the lockout height above the shoulders: a full rep
      // reaches 33-38% in the 3D test (55% with the upper arm only level with the torso), a
      // half rep stops at ~80%. Partial reps are defined by the
      // bar distance from the chest / lockout (Massey et al. 2004, J Strength Cond Res 18(3))
      'barReach': 0.65,
      // wrists more than 0.4 torso lengths past the shoulders toward the head = overhead press
      // (bench pushes across the body axis, the overhead press along it; measured bench <= 0.09,
      // overhead press >= 0.51)
      'overheadMax': 0.4,
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
