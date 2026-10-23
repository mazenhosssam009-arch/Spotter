/// the settings that are different between AiTrainer.py, SquatTrainer.py,
/// DeadliftTrainer.py and BenchPressTrainer.py
///
/// [limits] overrides any form threshold by key (all optional, defaults live
/// where each key is read). Keys: elbowDrift 25, swing 12, shrug 0.12, twist 0.2,
/// torsoLean 60, deepAngle 95, kneeCave 0.15, stanceMin 0.6, stanceMax 2.0,
/// kneeMin, kneeMax, spineDrift 25, flareMax 85, flareMin 25, forearmTilt 25,
/// wristMin 145, barTilt 0.25, asym 25, frontalRatio 0.5, maxSpeed, countFaulty 0,
/// squatRatio (deadlift, side view: knee bend / hip hinge above this = squat,
/// default 1.2, sumo 1.8, romanian 0.9), squatKnee (deadlift: knee angle below
/// this = squat, default 75, sumo 55, romanian 100), squatLegDrop
/// (deadlift facing the camera: hip-to-ankle height lost, default 0.38, sumo 0.50,
/// romanian 0.25), frontDead 10 and frontGain 1.5 (deadlift facing the camera),
/// swingReject 20 and elbowDriftReject 30 (curl: degrees PAST the warning limit
/// before a rep is rejected), lyingTilt 35 and lyingRatio 0.9 (bench: how
/// horizontal the torso must be).
/// armShorten 0.25 (curl facing the camera: how much the upper arm may look
/// shorter before "Elbow drifting forward"), smoothBase 1.5 and smoothSpan 2.0
/// (rep smoothness score calibration).
/// Sets: the set is ended by the user with the flag button, the rest time is set
/// with the timer button (no automatic set detection).
/// Squat depth: partialAngle 130 (knee angle that already counts as a PARTIAL rep),
/// deepAngle 110 (DEEP), extraDeepAngle 95 (EXTRA DEEP), countPartial 1 (0 = partial
/// reps are shown but not added to the total).
/// Deadlift facing the camera: frontReach 85 (percent of the bar that counts as the
/// bottom), handReach 0.40 and handDead 0.12 (how far the hands must travel down,
/// as a fraction of leg length), kneeCave 0.30.
/// Deadlift side view: sideReach 90 (percent of the bar that counts as the bottom).
/// Bench: descentMax 160 (deg/s, faster = "lower slowly"), hipLift 12 (degrees).
/// Defaults are commonly cited coaching/biomechanics ranges, not
/// clinical limits: tune them to your users. Pose estimation is 2D and
/// approximate; it can help you notice form problems but it cannot guarantee
/// injury prevention.
class Exercise {
  const Exercise({
    required this.name,
    required this.right,
    this.left,
    required this.downAngle,
    required this.upAngle,
    this.perFrameSmoothing = false,
    this.variant = '',
    this.limits = const {},
  });

  final String name;
  final List<int> right; // the 3 landmark ids of the right side
  final List<int>? left; // null = only the right side (AiTrainer.py)
  final double downAngle; // angle at 100%
  final double upAngle; // angle at 0%
  // true = exactly like the python file: "0.7*old + 0.3*new" every frame
  // (felt better for the squat on the phone than the timed version)
  final bool perFrameSmoothing;
  // deadlift variation: '' / 'conventional', 'sumo' or 'romanian'
  final String variant;
  // threshold overrides (see above)
  final Map<String, double> limits;

  /// AiTrainer.py is the first version: one arm
  bool get oneSide => left == null;
}
