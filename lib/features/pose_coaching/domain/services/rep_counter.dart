import 'dart:math' as math;

import 'package:ai_trainer/core/utils/cv_math.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/coaching_feedback.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/exercise.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/form_evaluation.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/form_level.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/joint_angle.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/pose_frame.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/vec2.dart';

/// The trainer logic of AiTrainer.py, SquatTrainer.py, DeadliftTrainer.py and
/// BenchPressTrainer.py: rep counting, form checks, form score, sets and fatigue.
/// Pure Dart (no Flutter, no ML Kit): it gets one [PoseFrame] per camera frame
/// through [update]. One instance = one workout; the TrainerBloc owns it and
/// the screens only read its fields.
class RepCounter {
  RepCounter(this.exercise, {this.debug = false});

  final Exercise exercise;
  // true = fill [debugLines] every frame (debugHud); off it costs nothing
  final bool debug;

  double count = 0;
  int dir = 0;
  double? smoothAngle;
  double lastSmoothTime = 0;
  double lastRepTime = 0;

  // timing (seconds)
  static const holdSeconds = 0.10; // must stay at 100% this long (1-frame spikes)
  static const minRepSeconds = 0.6; // a real rep is never faster than this
  static const maxRepSeconds = 20.0; // stale half-rep: forget it
  static const lostGrace = 0.4; // short landmark dropouts are ridden out
  static const maxJumpDeg = 70.0; // angle jump per frame that is a tracking glitch
  static const attemptPer = 30.0; // % reached before a return counts as "incomplete"
  static const warnDelay = 0.25; // a problem must last this long to be shown
  static const warnHold = 0.6; // and stays this long after it is gone
  static const formTau = 0.35; // form score smoothing time constant
  // time to get into position before counting starts (FR-CV-10 asks for a pre-set countdown)
  static const setupSeconds = 5.0;
  double? setupUntil; // counting starts at this time (null = body not seen yet)

  // ---- deadlift (same as the python file: 10 frames at 15 fps) ----
  static const deadHoldSeconds = 0.25; // python: 10 frames; a real lift rarely pauses 0.67 s
  static const deadLostGrace = 1.0; // python: hidden > 1 s cancels the rep
  bool squatLike = false; // knees bent to squat depth during this deadlift rep
  double minKnee = 999; // smallest knee angle seen during the current rep
  bool deadFront = false; // deadlift filmed facing the camera (frozen during a rep)
  double dbgTilt = 0, dbgRatio = -1; // bench lying-gate numbers, shown when it blocks
  String dbgSrc = '-'; // bench: which landmarks the lying check used
  double kneeFlexDbg = 0, hipFlexDbg = 0; // deadlift squat-check numbers

  // deadlift: this user's own standing / bottom angle (0% and 100% of the bar).
  // 0 = not learned yet, the fixed numbers of the exercise are used.
  double upEff = 0, downEff = 0;
  double? settledSince; // deadlift: standing still near the top after a rep
  double? deadBar; // deadlift: smoothed bar position (0..100), see _deadBarPer
  double deadBarTime = 0; // time of the last deadBar update (0 = none yet)
  bool frontSquatDbg = false; // facing the camera: squat-like hip drop seen (debug view only)
  double _up(Exercise e) => (isDead && upEff > 0) ? upEff : e.upAngle;
  double _down(Exercise e) => (isDead && downEff > 0) ? downEff : e.downAngle;

  // ---- bench: must really be lying down ----
  static const lyingSeconds = 0.3;
  double? lyingSince;
  double? notLyingSince;
  String? gateMsg; // red hint when the exercise position is wrong
  bool lyingCheck = true; // false = never block the bench press (bed icon in the app bar)

  bool get isDead => exercise.name.contains('Deadlift');
  bool get isBench => exercise.name.contains('Bench');
  bool get isSquat => exercise.name.contains('Squat');
  bool get isCurl => exercise.name.contains('Curl');

  // squat: reps counted per depth level
  int partialReps = 0, deepReps = 0, extraReps = 0;
  // deadlift facing the camera: the two hinge measures (debug) and the leg drop
  double dbgFrontTorso = double.nan, dbgFrontHands = double.nan, legDropDbg = 0;
  // curl facing the camera: angle estimated from the wrist height (debug)
  double dbgCurlFront = double.nan;

  double lastSeenTime = 0;
  double repStartTime = 0;
  bool attempt = false; // left the top, rep not finished yet
  double peakPer = 0;
  double minAngle = 999;
  double? bottomSince;
  double? prevRaw;
  int jumpRejects = 0;
  double? prevSmooth;
  double lastSpeedTime = 0;
  double speed = 0; // smoothed angular speed, deg/s
  final base = <String, double>{}; // the user's own "start" posture
  final repFaults = <String>{};
  final warnFirst = <String, double>{};
  final warnLast = <String, double>{};
  final warnSevere = <String, double>{};
  final shown = <String>[]; // warnings that passed the debounce
  String? note;
  double formScore = 0;
  bool formReady = false; // false = "Form not assessable"
  double lastFormTime = 0;
  double lastAssessable = -99;
  int formState = 0; // 0 good, 1 warn, 2 bad (with hysteresis)
  double? lastRom;
  double? lastConsistency;
  final repDurations = <double>[];
  String repLabel = '';
  String repDetail = '';
  FormLevel repLevel = FormLevel.good;
  double repLabelTime = -99;

  double curPer = 0; // depth of the current rep, 0..100

  // ---- what the last frame showed (drawn on the camera picture) ----
  bool tracking = false; // the exercise joints were seen in the last frame
  final jointAngles = <JointAngle>[]; // findAngle lines of the last frame
  final debugLines = <String>[]; // live numbers for the debug HUD

  // biceps curl only: 0 = right arm, 1 = left arm, 2 = both arms together,
  // 3 = alternate starting with the right arm, 4 = alternate starting with the left arm
  int armMode = 0;
  bool get altMode => isCurl && armMode >= 3;

  // ---- alternate mode: only the arm that is "next" can count a rep ----
  bool altRightNext = true;
  bool needRest = false; // after a swap the new arm must be at the bottom before a rep can start
  int repsR = 0, repsL = 0; // counted reps per arm (curl)

  // ---- curl: filmed facing the camera (frozen during a rep, like deadFront) ----
  bool curlFront = false;

  // ---- sets and fatigue (the USER ends a set with the flag button) ----
  bool inSet = false; // lifting in the current set (starts at the first counted rep)
  int setNumber = 1, setReps = 0, lastSetReps = 0; // setNumber = the set you are doing now
  double setStart = 0, lastRepEnd = -99, lastSetSecs = 0;
  final setDurs = <double>[]; // per rep of the current set
  final setRoms = <double>[];
  final setForms = <double>[];
  double? fatigue; // 0..100, null until 3 reps are done

  // ---- per-rep smoothness ----
  double repSpeedPeak = 0, repSpeedVar = 0, lastRepSpeed = 0;
  bool repSpeedInit = false;
  double repFormSum = 0;
  int repFormN = 0;
  double? lastSmooth; // 0..100 of the last finished rep
  double dbgSmoothRatio = 0;

  PoseFrame _pose = PoseFrame.empty(DateTime.fromMillisecondsSinceEpoch(0));
  bool _vis(List<int> ids) => _pose.isVisible(ids);

  /// the exercise with the arm(s) the user picked; everything else stays as configured
  Exercise get active {
    final e = exercise;
    if (!isCurl) return e;
    const rightArm = [12, 14, 16], leftArm = [11, 13, 15];
    // alternate: only the arm that is next is tracked (one-arm logic), then it swaps
    final useLeft = armMode >= 3 ? !altRightNext : armMode == 1;
    return Exercise(
      name: e.name,
      right: useLeft ? leftArm : rightArm,
      left: armMode == 2 ? leftArm : null,
      downAngle: e.downAngle,
      upAngle: e.upAngle,
      perFrameSmoothing: e.perFrameSmoothing,
      variant: e.variant,
      limits: e.limits,
    );
  }

  /// curl arm choice. Returns false when nothing changed.
  bool setArmMode(int m) {
    if (m == armMode) return false;
    armMode = m;
    altRightNext = m != 4; // 3 = right first, 4 = left first
    resetTracking(); // a half-finished rep of the other arm must not count
    resetSession(); // counting starts again from 0
    repLabel = '';
    return true;
  }

  /// bench: the bed button turns the lying check on / off
  void toggleLyingCheck() {
    lyingCheck = !lyingCheck;
    lyingSince = null;
    notLyingSince = null;
  }

  /// counting, sets and fatigue start again from the beginning
  void resetSession() {
    count = 0;
    repsR = 0;
    repsL = 0;
    lastRepTime = 0;
    needRest = false;
    inSet = false;
    setNumber = 1;
    setReps = 0;
    lastSetReps = 0;
    setStart = 0;
    lastRepEnd = -99;
    lastSetSecs = 0;
    setDurs.clear();
    setRoms.clear();
    setForms.clear();
    fatigue = null;
    lastSmooth = null;
    partialReps = 0;
    deepReps = 0;
    extraReps = 0;
  }

  // the python code ran at about 15 fps; "0.7*old + 0.3*new" every frame is made
  // to react the same in seconds at any fps (a 35 fps phone would otherwise react
  // more than twice as fast and let jumpy frames through)
  static const pythonFps = 15.0;

  // make the angle 0-180 no matter which way you face the camera
  double _fold(double angle) => angle > 180 ? 360 - angle : angle;

  double _smooth(double angle, double t) {
    final dt = (t - lastSmoothTime).clamp(0.0, 1.0);
    lastSmoothTime = t;
    if (smoothAngle == null) return smoothAngle = angle;
    final keep = math.pow(0.7, dt * pythonFps).toDouble();
    return smoothAngle = keep * smoothAngle! + (1 - keep) * angle;
  }

  // ===================== sets =====================

  /// Finish set: the set ends and the rest screen opens
  void endSet() {
    inSet = false;
    lastSetReps = setReps;
    lastSetSecs = math.max(0.0, lastRepEnd - setStart); // first rep to last counted rep
    dir = 0;
    attempt = false;
    bottomSince = null;
  }

  /// Stop timer: back to the camera, still in the SAME set (the rest time is not counted in it)
  void resumeSet(double restedSeconds) {
    if (setReps > 0) {
      setStart += restedSeconds;
      lastRepEnd += restedSeconds;
      inSet = true;
    }
    resetTracking(); // fresh start posture, no half-finished rep
  }

  /// the next set starts empty
  void nextSet() {
    if (setReps > 0) setNumber++;
    setReps = 0;
    inSet = false;
    setDurs.clear();
    setRoms.clear();
    setForms.clear();
    fatigue = null;
  }

  /// average form score of the set, null before the first rep
  double? get setFormAverage =>
      setForms.isEmpty ? null : setForms.reduce((a, b) => a + b) / setForms.length;

  /// +1 / -1 buttons: fix a rep the camera missed or added
  void adjustRep(int d, double t) {
    if (d > 0) {
      count += 1;
      if (!inSet) {
        inSet = true;
        setStart = t;
        setReps = 0;
        setDurs.clear();
        setRoms.clear();
        setForms.clear();
        fatigue = null;
      }
      setReps++;
      lastRepEnd = t;
      _trackArm();
    } else {
      if (count < 1) return;
      count -= 1;
      if (setReps > 0) setReps--;
      if (setDurs.isNotEmpty) setDurs.removeLast();
      if (setRoms.isNotEmpty) setRoms.removeLast();
      if (setForms.isNotEmpty) setForms.removeLast();
      _updateFatigue();
      if (setReps == 0) inSet = false;
      if (isCurl) {
        if (armMode == 0) repsR = math.max(0, repsR - 1);
        if (armMode == 1) repsL = math.max(0, repsL - 1);
        if (armMode == 2) {
          repsR = math.max(0, repsR - 1);
          repsL = math.max(0, repsL - 1);
        }
      }
    }
  }

  // ===================== helpers =====================

  double _lim(Exercise e, String key, double fallback) => e.limits[key] ?? fallback;

  double _maxSpeed(Exercise e) => _lim(e, 'maxSpeed', e.name.contains('Curl') ? 400 : 300);

  /// landmark [id] in whole pixels (like lmList = [id, cx, cy]), null when nobody is seen
  Vec2? _p(PoseFrame lm, int id) {
    if (!lm.hasPerson) return null;
    final q = lm.landmark(id);
    return Vec2(q.x.toInt().toDouble(), q.y.toInt().toDouble());
  }

  /// middle of two landmarks, using only the visible ones
  Vec2? _mid(PoseFrame lm, int a, int b) {
    final pts = <Vec2>[];
    for (final id in [a, b]) {
      final q = _p(lm, id);
      if (q != null && _vis([id])) pts.add(q);
    }
    if (pts.isEmpty) return null;
    return pts.length == 1 ? pts[0] : (pts[0] + pts[1]) / 2;
  }

  /// angle at [b] in degrees (0-180)
  double _ang(Vec2 a, Vec2 b, Vec2 c) {
    final v1 = a - b, v2 = c - b;
    final d = v1.distance * v2.distance;
    if (d < 1e-6) return double.nan;
    final c0 = ((v1.dx * v2.dx + v1.dy * v2.dy) / d).clamp(-1.0, 1.0).toDouble();
    return math.acos(c0) * 180 / math.pi;
  }

  /// how far the line from->to is tilted away from vertical (0 = straight up/down)
  double _fromVertical(Vec2 from, Vec2 to) =>
      math.atan2((to.dx - from.dx).abs(), (to.dy - from.dy).abs()) * 180 / math.pi;

  /// the user's own start posture (slowly follows while idle, frozen during a rep),
  /// so body type and camera angle don't need one fixed number
  double _base(String key, double v, bool idle) {
    final b = base[key];
    if (b == null) {
      base[key] = v;
      return v;
    }
    if (idle) return base[key] = 0.95 * b + 0.05 * v;
    return b;
  }

  /// true = facing the camera (shoulders wide), false = side on, null = unknown
  bool? _frontal(PoseFrame lm, Exercise e) {
    final a = _p(lm, 11), b = _p(lm, 12), c = _p(lm, 23), d = _p(lm, 24);
    if (a == null || b == null || c == null || d == null || !_vis([11, 12, 23, 24])) {
      return null;
    }
    final tl = ((a + b) / 2 - (c + d) / 2).distance;
    if (tl < 1) return null;
    return (a - b).distance / tl > _lim(e, 'frontalRatio', 0.5);
  }

  /// true = torso is horizontal (lying on a bench), false = clearly upright, null = unknown.
  /// "false" is only returned when the hips are really seen AND the torso is vertical AND
  /// not foreshortened. When the hips are hidden (very common lying down) the answer is
  /// "unknown" and the bench press is NOT blocked, because a vertical head-shoulder line
  /// also looks vertical from the head/foot end of the bench.
  bool? _lying(PoseFrame lm, Exercise e) {
    final tiltLim = _lim(e, 'lyingTilt', 35);
    final ratioLim = _lim(e, 'lyingRatio', 0.9);
    final sh = <Vec2>[], hp = <Vec2>[];
    for (final s in const [
      [11, 23],
      [12, 24]
    ]) {
      if (!_vis(s)) continue;
      final a = _p(lm, s[0]), b = _p(lm, s[1]);
      if (a != null && b != null) {
        sh.add(a);
        hp.add(b);
      }
    }
    if (sh.isNotEmpty) {
      final s = sh.length == 2 ? (sh[0] + sh[1]) / 2 : sh[0];
      final h = hp.length == 2 ? (hp[0] + hp[1]) / 2 : hp[0];
      final tl = (s - h).distance;
      if (tl >= 1) {
        dbgSrc = 'hips';
        dbgTilt = _fromVertical(h, s);
        dbgRatio = -1;
        if (dbgTilt >= tiltLim) return true; // side view: torso horizontal
        if (sh.length == 2) {
          // head/foot end: the torso is foreshortened compared with the shoulder width
          dbgRatio = tl / math.max((sh[0] - sh[1]).distance, 1.0);
          if (dbgRatio < ratioLim) return true;
        }
        return false; // hips seen, torso vertical and full length = really upright
      }
    }
    // hips hidden: the head line can PROVE lying (horizontal), but a vertical head line
    // proves nothing -> unknown, don't block
    for (final s in const [
      [7, 11],
      [8, 12],
      [0, 11],
      [0, 12]
    ]) {
      if (!_vis(s)) continue;
      final head = _p(lm, s[0]), shoulder = _p(lm, s[1]);
      if (head == null || shoulder == null || (head - shoulder).distance < 1) continue;
      dbgSrc = 'head';
      dbgRatio = -1;
      dbgTilt = _fromVertical(shoulder, head);
      return dbgTilt >= tiltLim ? true : null;
    }
    dbgSrc = 'none';
    return null;
  }

  /// like _base, but only follows while idle AND near the upright value, so a slow
  /// start of the lift cannot drag the "standing" reference down with it
  double _standBase(String key, double v, bool idle) {
    final b = base[key];
    if (b == null) {
      base[key] = v;
      return v;
    }
    if (!idle) return b;
    if (v > b) return base[key] = 0.8 * b + 0.2 * v;
    if (v > 0.9 * b) return base[key] = 0.95 * b + 0.05 * v;
    return base[key] = 0.9995 * b; // far below: slow drift, so one early spike can't stick
  }

  /// "Ruler" for the deadlift: arm length (shoulder-elbow + elbow-wrist). The arms hang
  /// straight down the whole lift, so in the picture they only change with the distance to
  /// the camera (front and side view). Standing lengths are stored as multiples of it, not
  /// pixels, so stepping toward / away from the phone is not read as a hinge. Pose-based
  /// exercise systems normalise landmarks by a body length for the same reason
  /// (Ko, Nasridinov & Park (2024) IEEE Access 12). Used by the front-view squat check.
  /// Only STRAIGHT arms are a ruler: elbow >= 152 deg (180 - 2 x 14 deg elbow error, Francia
  /// et al. (2024) LNCS Extended Reality pp.40-49). Bent or folded arms (hands raised) look
  /// shorter, so then the last straight-arm length is kept. null = not seen yet (pixels).
  double? _armRuler(PoseFrame lm) {
    final arms = <double>[];
    for (final s in const [
      [12, 14, 16],
      [11, 13, 15]
    ]) {
      if (!_vis(s)) continue;
      final a = _p(lm, s[0]), b = _p(lm, s[1]), c = _p(lm, s[2]);
      if (a == null || b == null || c == null) continue;
      if (_ang(a, b, c) < 152) continue; // bent arm: not a reliable ruler
      arms.add((a - b).distance + (b - c).distance);
    }
    final r = arms.isEmpty ? 0.0 : arms.reduce((x, y) => x + y) / arms.length;
    if (r < 1) return base['armRuler'];
    if (base['armRuler'] == null) {
      // first time the arms are seen: lengths learned in pixels so far start again in arm lengths
      base.remove('legExt');
    }
    return base['armRuler'] = r;
  }

  /// Deadlift bar (0..100) from the BAR POSITION: how high the wrists are above the user's own
  /// knee, in shin lengths (knee to ankle), in the SAME frame. Nothing is remembered, so it
  /// cannot get stuck, the distance to the phone does not matter, and it is the same facing the
  /// camera and from the side. The hip is not used: bent over facing the camera the hip joints
  /// are hidden behind the torso and ML Kit places them too high, which made the rep too hard.
  /// 0% = wrists at standing height: 0.81 shin lengths above the knee ((wrist 0.485 - knee
  /// 0.285) / shin 0.246 of body height - Winter (2009) Biomechanics and Motor Control of Human
  /// Movement, 4th ed., after Drillis & Contini). 100% = wrists at knee height: deadlift
  /// studies split the lift where the bar passes the knees (Escamilla et al. (2000) Med Sci
  /// Sports Exerc 32(7):1265-1275; Hanen et al. (2025) Front Bioeng Biotechnol 13:1597209).
  /// Raised or folded hands go UP, so they can never look like a rep. null = not seen.
  double? _deadBarPer(PoseFrame lm, double t) {
    final kn = _mid(lm, 25, 26), an = _mid(lm, 27, 28), wr = _mid(lm, 15, 16);
    if (kn == null || an == null || wr == null || an.dy - kn.dy < 1) return null;
    final above = (kn.dy - wr.dy) / (an.dy - kn.dy); // wrists above the knee, in shin lengths
    final p = interp(above, 0, 0.81, 100, 0);
    // smoothing like the python files (0.7 old + 0.3 new), but per TIME like _smooth: per frame
    // it lagged far behind on slow phones (~7 fps measured), so a normal-speed rep never reached
    // the bottom before the user came back up
    final keep = deadBarTime == 0 ? 0.0 : math.pow(0.7, (t - deadBarTime).clamp(0.0, 1.0) * pythonFps).toDouble();
    deadBarTime = t;
    deadBar = deadBar == null ? p : keep * deadBar! + (1 - keep) * p;
    return deadBar;
  }

  /// Curl facing the camera: the forearm moves toward the lens, so the 2D elbow angle drops
  /// far too early (a quarter curl already looked like a full one). Better: the height of the
  /// wrist above/below the elbow compared with the arm hanging. cos(flexion) = height / hanging
  /// height, so 0 deg flexion = hanging and about 150 = wrist up at the shoulder.
  /// Returned as an equivalent elbow angle (180 = straight).
  double? _curlFrontAngle(PoseFrame lm, List<int> arm, bool idle) {
    final el = _p(lm, arm[1]), wr = _p(lm, arm[2]);
    if (el == null || wr == null || !_vis([arm[1], arm[2]])) return null;
    final drop = wr.dy - el.dy; // wrist below the elbow = positive
    // ruler: shoulder width (this only runs facing the camera, where both shoulders are seen).
    // The hanging height is stored in shoulder widths, not pixels, so stepping toward / away
    // from the phone does not change it (body-length normalisation, Ko et al. (2024) IEEE Access 12)
    final sa = _p(lm, 11), sb = _p(lm, 12);
    if (sa == null || sb == null || !_vis([11, 12])) return null;
    final sw = (sa - sb).distance;
    if (sw < 1) return null;
    final full = _standBase('fa${arm[0]}', drop / sw, idle) * sw;
    if (full < 1) return null;
    final c = (drop / full).clamp(-1.0, 1.0).toDouble();
    return 180 - math.acos(c) * 180 / math.pi;
  }

  /// how far the worst knee is inside its toes (0 = over the toes), as a fraction
  /// of shin length. Uses the toe, so a deliberate toe-out stance is not punished.
  double? _kneeCave(PoseFrame lm) {
    final h1 = _p(lm, 23), h2 = _p(lm, 24);
    if (h1 == null || h2 == null) return null;
    final mx = (h1.dx + h2.dx) / 2;
    double? worst;
    for (final s in const [
      [25, 27, 31],
      [26, 28, 32]
    ]) {
      if (!_vis([s[0], s[1]])) continue;
      final kn = _p(lm, s[0]), an = _p(lm, s[1]), toe = _p(lm, s[2]);
      if (kn == null || an == null) continue;
      final Vec2 ft = (toe != null && _vis([s[2]])) ? toe : an;
      final shin = (kn - an).distance;
      if (shin < 1) continue;
      final inward = ((mx - ft.dx).abs() - (mx - kn.dx).abs()) / shin;
      worst = worst == null ? inward : math.max(worst, inward);
    }
    return worst;
  }

  /// stance width (ankles / shoulders) and knee cave: only meaningful facing the camera
  void _frontChecks(FormEvaluation ev, PoseFrame lm, Exercise e, double per, double sMin, double sMax,
      {double caveLim = 0.15, bool blockCave = true}) {
    final a1 = _p(lm, 27), a2 = _p(lm, 28), s1 = _p(lm, 11), s2 = _p(lm, 12);
    if (a1 != null && a2 != null && s1 != null && s2 != null && _vis([27, 28])) {
      final sw = (s1 - s2).distance;
      if (sw > 1) {
        final ratio = (a1 - a2).distance / sw;
        ev.limit(_lim(e, 'stanceMin', sMin) - ratio, 0.3, 'Stance too narrow');
        ev.limit(ratio - _lim(e, 'stanceMax', sMax), 0.5, 'Stance too wide');
      }
    }
    final cave = _kneeCave(lm);
    if (cave != null) {
      ev.limit(per >= 30 ? cave - _lim(e, 'kneeCave', caveLim) : -1, 0.2, 'Knees caving in',
          block: blockCave);
    }
  }

  // ===================== per-exercise form checks =====================

  FormEvaluation _curl(PoseFrame lm, Exercise e, double per, bool idle) {
    final ev = FormEvaluation();
    // one arm or both arms (see armMode): every active arm is checked
    for (final arm in [e.right, if (e.left != null) e.left!]) {
      final isRight = arm[0] == 12;
      final hipId = isRight ? 24 : 23, otherShId = isRight ? 11 : 12;
      final s = _p(lm, arm[0]), el = _p(lm, arm[1]), hip = _p(lm, hipId);
      if (s == null || el == null || hip == null || !_vis([arm[0], arm[1], hipId])) {
        continue; // hip hidden: swing cannot be judged for this arm
      }
      final torso = (s - hip).distance;
      if (torso < 1) continue;
      // 1) upper arm should stay near the torso; elbow swinging forward = shoulder is helping
      ev.limit(_ang(hip, s, el) - _lim(e, 'elbowDrift', 25), 30, 'Elbow drifting forward',
          block: true, blockAt: _lim(e, 'elbowDriftReject', 30));
      // 2) body swing: torso lean compared with the user's own start posture
      final lean = _fromVertical(hip, s);
      // side on, the far hip is partly hidden and wobbles, so this only REJECTS a rep
      // when the body really moves (swing + swingReject degrees from the start posture)
      ev.limit((lean - _base('lean$hipId', lean, idle)).abs() - _lim(e, 'swing', 12), 20,
          'Swinging - stay still',
          block: true, blockAt: _lim(e, 'swingReject', 20));
      // 3) shoulder shrug: torso length (hip to shoulder) changes
      ev.limit(((torso / _base('torso$hipId', torso, idle)) - 1).abs() - _lim(e, 'shrug', 0.12), 0.12,
          curlFront ? 'Leaning - keep still' : 'Shoulders shrugging');
      // 4) torso twist: shoulder width changes a lot
      final s2 = _p(lm, otherShId);
      if (s2 != null && _vis([otherShId])) {
        final sw = (s - s2).distance;
        ev.limit(((sw / _base('sw$hipId', sw, idle)) - 1).abs() - _lim(e, 'twist', 0.2), 0.2,
            'Torso twisting');
      }
      // 5) ONLY when facing the camera (curlFront): an elbow moving forward points at the
      // lens, so check 1 cannot see it. The upper arm then looks SHORTER than at the start.
      // Warn only (never rejects), and it does nothing at all when filmed from the side.
      if (curlFront) {
        final ua = (s - el).distance;
        final ba = _base('ua$hipId', ua, idle);
        if (ba > 1) {
          ev.limit(1 - ua / ba - _lim(e, 'armShorten', 0.25), 0.25, 'Elbow drifting forward');
        }
      }
      ev.assessable = true;
    }
    return ev;
  }

  FormEvaluation _squat(PoseFrame lm, Exercise e, double per, bool? front) {
    final ev = FormEvaluation();
    final sh = _mid(lm, 11, 12), hp = _mid(lm, 23, 24), kn = _mid(lm, 25, 26);
    if (sh != null && hp != null) {
      // trunk lean varies a lot with leg/torso proportions, so the limit adapts to the user:
      // long thighs (thigh / torso > 1) lean forward more, so they get a more generous limit.
      // The ratio is measured standing and frozen once the squat starts.
      var leanLim = _lim(e, 'torsoLean', 60);
      if (kn != null) {
        final torso = (sh - hp).distance, thigh = (hp - kn).distance;
        if (torso > 1 && thigh > 1) {
          final r = _base('legTorso', thigh / torso, per < 15);
          leanLim += ((r - 1.0) * 40).clamp(-10.0, 20.0).toDouble();
        }
      }
      ev.limit(_fromVertical(hp, sh) - leanLim, 20, 'Chest up - leaning far', block: true);
    }
    if (front == true) _frontChecks(ev, lm, e, per, 0.6, 2.0);
    ev.assessable = ev.scores.isNotEmpty;
    return ev;
  }

  FormEvaluation _deadlift(PoseFrame lm, Exercise e, double per, bool idle, bool? front) {
    final ev = FormEvaluation();
    final rdl = e.variant == 'romanian', sumo = e.variant == 'sumo';
    final low = per >= 60; // lower part of the lift
    // spine proxy: ear-shoulder-hip compared with the lifter's own upright posture.
    // It cannot see the lumbar spine, so it only warns and never rejects a rep.
    var spineSeen = deadFront; // facing the camera: spine angle cannot be seen
    for (final s in deadFront
        ? const <List<int>>[]
        : const [
            [8, 12, 24],
            [7, 11, 23]
          ]) {
      if (!_vis(s)) continue;
      final a = _p(lm, s[0]), b = _p(lm, s[1]), c = _p(lm, s[2]);
      if (a == null || b == null || c == null) continue;
      final ang = _ang(a, b, c);
      if (!ang.isFinite) continue;
      ev.limit((_base('neck', ang, idle) - ang) - _lim(e, 'spineDrift', 25), 15, 'Keep spine neutral');
      spineSeen = true;
      break;
    }
    if (deadFront) {
      ev.note = 'Facing camera: back not checked (film from the side)';
    } else if (!spineSeen) {
      ev.note = 'Head/back not visible';
    }
    // knee bend at the bottom depends on the variation
    final kLo = _lim(e, 'kneeMin', rdl ? 135 : (sumo ? 70 : 85));
    final kHi = _lim(e, 'kneeMax', rdl ? 178 : (sumo ? 140 : 150));
    final ks = <double>[];
    for (final s in const [
      [24, 26, 28],
      [23, 25, 27]
    ]) {
      if (!_vis(s)) continue;
      final a = _p(lm, s[0]), b = _p(lm, s[1]), c = _p(lm, s[2]);
      if (a == null || b == null || c == null) continue;
      final ang = _ang(a, b, c);
      if (ang.isFinite) ks.add(ang);
    }
    if (ks.isNotEmpty && !deadFront) {
      final knee = ks.reduce((a, b) => a + b) / ks.length;
      ev.limit(low ? kLo - knee : -1, 25, 'Too much knee bend');
      ev.limit(low ? knee - kHi : -1, 25, 'Knees too straight');
    }
    // conventional stance is about hip width (narrower than the shoulders), so 0.4 not 0.6.
    // Knee cave is a squat fault: here it only warns and with a looser limit (toe-out feet
    // made it fire on normal reps and paint the bar red).
    if (front == true) {
      _frontChecks(ev, lm, e, per, sumo ? 1.4 : 0.4, sumo ? 3.0 : 1.6, caveLim: 0.30, blockCave: false);
    }
    ev.assessable = ev.scores.isNotEmpty;
    return ev;
  }

  FormEvaluation _bench(PoseFrame lm, Exercise e, double per, bool idle, bool? front) {
    final ev = FormEvaluation();
    final flares = <double>[], tilts = <double>[], bends = <double>[];
    final wrists = <Vec2>[];
    var segs = 0.0;
    var sides = 0;
    for (final s in [e.right, if (e.left != null) e.left!]) {
      if (!_vis(s)) continue;
      final sh = _p(lm, s[0]), el = _p(lm, s[1]), wr = _p(lm, s[2]);
      if (sh == null || el == null || wr == null) continue;
      final isRight = s[0] == 12;
      final hipId = isRight ? 24 : 23, idxId = isRight ? 20 : 19;
      final hip = _vis([hipId]) ? _p(lm, hipId) : null;
      final idx = _vis([idxId]) ? _p(lm, idxId) : null;
      if (hip != null) flares.add(_ang(hip, sh, el)); // elbow-to-torso angle
      tilts.add(_fromVertical(el, wr)); // forearm vs vertical
      if (idx != null) bends.add(_ang(el, wr, idx)); // wrist straightness
      wrists.add(wr);
      segs += (sh - el).distance + (el - wr).distance;
      sides++;
    }
    if (sides == 0) return ev;
    final fl = flares.where((v) => v.isFinite).toList();
    final tl = tilts.where((v) => v.isFinite).toList();
    final bd = bends.where((v) => v.isFinite).toList();
    // elbow flare: a range, not one universal angle (bottom half only)
    // From the SIDE the elbow-to-torso angle is about 90 degrees on every normal rep,
    // so flare can only be judged from the head/foot end, and it only warns.
    if (front == true && fl.isNotEmpty) {
      ev.limit(per >= 50 ? fl.reduce(math.max) - _lim(e, 'flareMax', 75) : -1, 20, 'Elbows flared wide');
      ev.limit(per >= 50 ? _lim(e, 'flareMin', 30) - fl.reduce(math.min) : -1, 15, 'Elbows tucked in');
    } else if (front != true) {
      ev.note = 'Flare needs head/foot view';
    } else {
      ev.note = 'Hips hidden - flare unchecked';
    }
    // forearm should be close to vertical near the chest (wrist stacked over elbow)
    if (tl.isNotEmpty) {
      ev.limit(per >= 70 ? tl.reduce(math.max) - _lim(e, 'forearmTilt', 25) : -1, 20, 'Stack wrist over elbow');
    }
    // wrist alignment: elbow-wrist-knuckle should be near straight
    if (bd.isNotEmpty) {
      ev.limit(per >= 30 ? _lim(e, 'wristMin', 145) - bd.reduce(math.min) : -1, 25, 'Wrist bent back');
    }
    // bar path (the wrists stand in for the bar): sideways drift from the start line
    final x = wrists.map((p) => p.dx).reduce((a, b) => a + b) / wrists.length;
    final seg = segs / (2 * sides);
    if (seg > 1) {
      ev.limit((x - _base('barX', x, idle)).abs() / seg - 0.5, 0.4, 'Bar path drifting');
    }
    // controlled lowering: dropping the bar fast (bouncing it off the chest) is a classic
    // chest / shoulder injury. dir == 0 && attempt = on the way down, before the bottom.
    if (dir == 0 && attempt) {
      ev.limit(speed - _lim(e, 'descentMax', 160), 120, 'Lower slowly - control the bar');
    }
    // glutes must stay on the bench (side view): the shoulder-hip line keeps its start angle
    if (front != true && lyingSince != null) {
      for (final s in const [
        [11, 23],
        [12, 24]
      ]) {
        if (!_vis(s)) continue;
        final a = _p(lm, s[0]), b = _p(lm, s[1]);
        if (a == null || b == null || (a - b).distance < 1) continue;
        final tilt = _fromVertical(b, a);
        ev.limit((tilt - _base('benchTilt${s[0]}', tilt, idle)).abs() - _lim(e, 'hipLift', 12), 15,
            'Keep glutes on the bench');
        break;
      }
    }
    // uneven bar (facing the camera): one wrist higher than the other
    final s1 = _p(lm, 11), s2 = _p(lm, 12);
    if (front == true && wrists.length == 2 && s1 != null && s2 != null) {
      final sw = (s1 - s2).distance;
      if (sw > 1) {
        ev.limit((wrists[0].dy - wrists[1].dy).abs() / sw - _lim(e, 'barTilt', 0.25), 0.25, 'Bar uneven');
      }
    }
    ev.assessable = true;
    return ev;
  }

  FormEvaluation _evaluate(PoseFrame lm, Exercise e, double per, bool idle, bool? front, double? asym) {
    final n = e.name;
    final ev = n.contains('Curl')
        ? _curl(lm, e, per, idle)
        : n.contains('Squat')
            ? _squat(lm, e, per, front)
            : n.contains('Deadlift')
                ? _deadlift(lm, e, per, idle, front)
                : n.contains('Bench')
                    ? _bench(lm, e, per, idle, front)
                    : FormEvaluation();
    // one side doing more work than the other (needs both sides and a frontal view)
    if (ev.assessable && asym != null && front == true) {
      ev.limit(per >= 40 ? asym - _lim(e, 'asym', 25) : -1, 20, 'Uneven sides');
    }
    if (speed > 1.3 * _maxSpeed(e)) ev.warns.add('Slow down - control it');
    return ev;
  }

  // ===================== warnings, form score, rep result =====================

  bool _severeNow(String m, double t) => t - (warnSevere[m] ?? -99) <= warnHold;

  /// a problem is only shown after it lasted warnDelay and is kept warnHold: no flicker
  void _updateWarnings(FormEvaluation ev, double t) {
    for (final m in ev.warns) {
      warnFirst.putIfAbsent(m, () => t);
      warnLast[m] = t;
    }
    for (final m in ev.blocking) {
      warnSevere[m] = t;
    }
    final drop = <String>[];
    warnLast.forEach((m, last) {
      if (t - last > warnHold) drop.add(m);
    });
    for (final m in drop) {
      warnLast.remove(m);
      warnFirst.remove(m);
    }
    shown.clear();
    for (final m in warnLast.keys) {
      if (warnLast[m]! - warnFirst[m]! >= warnDelay) shown.add(m);
    }
    note = ev.note;
  }

  int _nextState(int s, double v) {
    const good = 80.0, bad = 55.0, hy = 5.0; // hysteresis: the colour doesn't flicker
    if (s == 0) return v < good - hy ? (v < bad ? 2 : 1) : 0;
    if (s == 1) return v >= good + hy ? 0 : (v < bad - hy ? 2 : 1);
    return v >= bad + hy ? (v >= good + hy ? 0 : 1) : 2;
  }

  /// form score = alignment (60%) + range of motion of the last rep (25%) +
  /// tempo/consistency (15%). Missing parts are left out, never faked.
  void _updateForm(Exercise e, FormEvaluation ev, double t) {
    if (!(ev.assessable && ev.scores.isNotEmpty)) {
      if (t - lastAssessable > 0.4) formReady = false;
      return;
    }
    lastAssessable = t;
    final mean = ev.scores.reduce((a, b) => a + b) / ev.scores.length;
    final align = 0.5 * mean + 0.5 * ev.scores.reduce(math.min); // worst check counts
    final ms = _maxSpeed(e);
    final tempoNow = speed <= ms ? 1.0 : (1 - (speed - ms) / ms).clamp(0.0, 1.0).toDouble();
    var acc = 0.0, wsum = 0.0;
    void part(double? v, double wt) {
      if (v != null) {
        acc += v * wt;
        wsum += wt;
      }
    }

    part(align, 0.6);
    part(lastRom, 0.25);
    final lc = lastConsistency;
    part(lc == null ? tempoNow : (tempoNow + lc) / 2, 0.15);
    final target = 100 * acc / wsum;
    final dt = (t - lastFormTime).clamp(0.0, 1.0).toDouble();
    lastFormTime = t;
    formScore = formReady ? formScore + (target - formScore) * (1 - math.exp(-dt / formTau)) : target;
    if (!formReady) formState = 0;
    formReady = true;
    formState = _nextState(formState, formScore);
  }

  /// colour of the depth bar, the rep progress and the form ring
  FormLevel formLevel(double t) {
    if (!formReady) return FormLevel.notAssessable;
    var st = formState;
    if (shown.isNotEmpty) st = math.max(st, 1); // never emerald while a warning is up
    if (shown.any((m) => _severeNow(m, t))) st = 2;
    return st == 0 ? FormLevel.good : (st == 1 ? FormLevel.warn : FormLevel.bad);
  }

  /// which arm did the counted rep (curl only)
  void _trackArm() {
    if (!isCurl) return;
    if (armMode == 0) {
      repsR++;
    } else if (armMode == 1) {
      repsL++;
    } else if (armMode == 2) {
      repsR++;
      repsL++;
    } else if (altRightNext) {
      repsR++;
    } else {
      repsL++;
    }
  }

  /// alternate mode: the other arm is next. Its angle history starts fresh and it
  /// must be at the bottom before a rep can begin (so a half-raised arm does not count).
  void _swapAlternateArm() {
    altRightNext = !altRightNext;
    smoothAngle = null;
    prevRaw = null;
    prevSmooth = null;
    jumpRejects = 0;
    speed = 0;
    needRest = true;
  }

  /// a counted rep belongs to the current set. The set is ended by the user (flag button).
  void _trackSet(double t, double dur) {
    if (!inSet) {
      inSet = true;
      setStart = t - dur;
      setReps = 0;
      setDurs.clear();
      setRoms.clear();
      setForms.clear();
      fatigue = null;
    }
    setReps++;
    lastRepEnd = t;
    setDurs.add(dur);
    setRoms.add(lastRom ?? 1.0);
    setForms.add(repFormN > 0 ? repFormSum / repFormN : formScore);
    _updateFatigue();
  }

  /// fatigue estimate (0-100) from the first 2 reps of the set against the latest ones:
  /// slower reps (50% slower = full), smaller range of motion (25% less = full) and a
  /// lower form score (30 points lower = full). Needs 3 reps. It is an estimate, not a measurement.
  void _updateFatigue() {
    final n = setDurs.length;
    if (n < 3) {
      fatigue = null;
      return;
    }
    double mean(Iterable<double> v) => v.reduce((a, b) => a + b) / v.length;
    final r = math.min(2, n - 2);
    final bd = mean(setDurs.take(2)), rd = mean(setDurs.skip(n - r));
    final br = mean(setRoms.take(2)), rr = mean(setRoms.skip(n - r));
    final bf = mean(setForms.take(2)), rf = mean(setForms.skip(n - r));
    final slow = bd > 0 ? ((rd / bd) - 1) / 0.5 : 0.0;
    final romDrop = (br - rr) / 0.25;
    final formDrop = (bf - rf) / 30;
    final p = [slow, romDrop, formDrop].map((v) => v.clamp(0.0, 1.0).toDouble()).toList();
    final mx = p.reduce(math.max);
    final avg = p.reduce((a, b) => a + b) / p.length;
    fatigue = 100 * (0.5 * mx + 0.5 * avg);
  }

  void _finishRep(Exercise e, double t) {
    final dur = t - repStartTime;
    if (dur < minRepSeconds || t - lastRepTime <= 1) return; // jitter (same 1 s rule as before)
    // deadlift only: knees bent to squat depth = it was a squat, do not count
    if (isDead && squatLike) {
      repLabel = 'Squat - not a deadlift';
      repLevel = FormLevel.bad;
      repDetail = 'Hinge at the hips';
      repLabelTime = t;
      return;
    }
    lastRepTime = t;
    final squat = e.name.contains('Squat');
    final faults = repFaults.toList();
    final soft = isDead || isBench; // only the squat / lying checks decide these
    var counted = faults.isEmpty || _lim(e, 'countFaulty', 0) > 0 || soft;
    // squat depth by the lowest knee angle: 0 partial, 1 deep, 2 extra deep
    var depth = 0;
    if (squat) {
      if (minAngle <= _lim(e, 'extraDeepAngle', 95)) {
        depth = 2;
      } else if (minAngle <= _lim(e, 'deepAngle', 110)) {
        depth = 1;
      }
      if (depth == 0 && _lim(e, 'countPartial', 1) <= 0) counted = false;
      if (faults.isNotEmpty) {
        repLabel = 'Incorrect';
        repLevel = FormLevel.bad;
      } else if (depth == 2) {
        repLabel = 'Extra deep';
        repLevel = FormLevel.good;
      } else if (depth == 1) {
        repLabel = 'Deep';
        repLevel = FormLevel.good;
      } else {
        repLabel = counted ? 'Partial' : 'Partial - not counted';
        repLevel = FormLevel.warn;
      }
    } else {
      repLabel = faults.isEmpty ? 'Good rep' : (soft ? 'Counted - check form' : 'Rejected');
      repLevel = faults.isEmpty ? FormLevel.good : (soft ? FormLevel.warn : FormLevel.bad);
    }
    repDetail = faults.isNotEmpty
        ? faults.first
        : (repLabel == 'Partial' ? 'Go deeper for full depth' : '');
    repLabelTime = t;
    if (counted) count += 1;
    // range of motion of this rep (squat is scored against full depth, not the 120 counting line;
    // deadlift against the user's own standing / bottom angles)
    final up = _up(e);
    final target = squat ? _lim(e, 'deepAngle', 110) : _down(e);
    lastRom = ((up - minAngle) / math.max(up - target, 1.0)).clamp(0.0, 1.0).toDouble();
    // consistency: how close this rep's duration is to the recent ones
    repDurations.add(dur);
    if (repDurations.length > 6) repDurations.removeAt(0);
    if (repDurations.length >= 3) {
      final prev = repDurations.sublist(0, repDurations.length - 1);
      final mean = prev.reduce((a, b) => a + b) / prev.length;
      lastConsistency = (1 - ((dur - mean).abs() / mean - 0.35) / 0.65).clamp(0.0, 1.0).toDouble();
    }
    // smoothness of this rep: how much the speed jumped up and down. A clean rep is
    // one speed hill going down and one coming up (total change about 4 x peak speed).
    // Jerky reps change speed more often. smoothBase / smoothSpan calibrate the score.
    if (repSpeedPeak > 1) {
      final ratio = repSpeedVar / (4 * repSpeedPeak);
      dbgSmoothRatio = ratio;
      final sb = _lim(e, 'smoothBase', 1.5), ss = _lim(e, 'smoothSpan', 2.0);
      lastSmooth = (100 * (1 - (ratio - sb) / ss)).clamp(0.0, 100.0).toDouble();
    }
    // arm counters, set, fatigue, alternate swap
    if (counted) {
      if (squat) {
        if (depth == 0) {
          partialReps++;
        } else if (depth == 1) {
          deepReps++;
        } else {
          extraReps++;
        }
      }
      _trackArm();
      _trackSet(t, dur);
      if (altMode) _swapAlternateArm();
    }
  }

  void _incompleteRep(Exercise e, double t) {
    final squat = e.name.contains('Squat');
    final n = e.name;
    repLabel = squat ? 'Incorrect' : 'Incomplete rep';
    repLevel = squat ? FormLevel.bad : FormLevel.warn;
    repDetail = squat
        ? 'Too shallow - not counted'
        : n.contains('Curl')
            ? 'Curl through full range'
            : n.contains('Bench')
                ? 'Lower to chest, lock out'
                : n.contains('Deadlift')
                    ? 'Hinge fully, then lock out'
                    : '';
    repLabelTime = t;
    final up = _up(e);
    lastRom = ((up - minAngle) / math.max(up - _down(e), 1.0)).clamp(0.0, 1.0).toDouble();
  }

  /// the person left or is hidden for a while: forget the half-finished rep
  /// (before, a rep started, the person walked out, came back and it was counted)
  void resetTracking() {
    dir = 0;
    attempt = false;
    bottomSince = null;
    smoothAngle = null;
    prevRaw = null;
    prevSmooth = null;
    jumpRejects = 0;
    speed = 0;
    base.clear();
    repFaults.clear();
    warnFirst.clear();
    warnLast.clear();
    warnSevere.clear();
    shown.clear();
    note = null;
    formReady = false;
    lastRom = null;
    lastConsistency = null;
    repDurations.clear();
    squatLike = false;
    minKnee = 999;
    lyingSince = null;
    notLyingSince = null;
    gateMsg = null;
    upEff = 0;
    downEff = 0;
    settledSince = null;
    deadBar = null;
    deadBarTime = 0;
    frontSquatDbg = false;
    setupUntil = null; // body lost: give the 5 s to get into position again
  }

  /// bad numbers (NaN) and one-frame tracking glitches must not move the angle
  double _cleanAngle(double a, Exercise e) {
    final pr = prevRaw;
    if (!a.isFinite) {
      a = pr ?? e.upAngle;
    } else if (pr != null && (a - pr).abs() > maxJumpDeg && jumpRejects < 2) {
      jumpRejects++;
      a = pr;
    } else {
      jumpRejects = 0;
    }
    prevRaw = a;
    return a;
  }

  // PoseModule.findAngle: whole pixels like lmList, 0-360 degrees
  double _findAngle(PoseFrame lm, List<int> joints) {
    final p1 = lm.landmark(joints[0]), p2 = lm.landmark(joints[1]), p3 = lm.landmark(joints[2]);
    final x1 = p1.x.toInt(), y1 = p1.y.toInt();
    final x2 = p2.x.toInt(), y2 = p2.y.toInt();
    final x3 = p3.x.toInt(), y3 = p3.y.toInt();
    var angle = (math.atan2(y3 - y2, x3 - x2) - math.atan2(y1 - y2, x1 - x2)) * 180 / math.pi;
    if (angle < 0) angle += 360;
    jointAngles.add(JointAngle(joints: joints, angle: angle));
    return angle;
  }

  /// one camera frame: count reps, check form, update the score. [t] = time.time()
  void update(PoseFrame lmList, double t) {
    _pose = lmList;
    final e = active;
    jointAngles.clear();
    debugLines.clear();
    final dbg = debugLines;

    // deadlift: shoulder, hip, knee and ankle of at least ONE side must be clearly seen. Side on,
    // the far side is behind the body (ML Kit marks it unsure), so asking for both sides blocked
    // every side-view rep; facing the camera both sides are seen anyway.
    // Every exercise checks that its joints are really seen, and a short dropout
    // (lostGrace) is ridden out instead of resetting the rep.
    final fullBody = !isDead ||
        (lmList.hasPerson && (_vis([12, 24, 26, 28]) || _vis([11, 23, 25, 27])));
    final rightOk = lmList.hasPerson && fullBody && _vis(e.right);
    final leftOk = lmList.hasPerson && fullBody && e.left != null && _vis(e.left!);
    gateMsg = null;
    tracking = rightOk || leftOk;
    if (rightOk || leftOk) {
      lastSeenTime = t;
    } else {
      bottomSince = null; // python: hold = 0 when joints are hidden
      curPer = 0;
      if (t - lastSeenTime > (isDead ? deadLostGrace : lostGrace)) resetTracking();
      // set after the reset, because resetTracking clears gateMsg
      if (isDead) gateMsg = 'Show your full body';
      if (isBench) gateMsg = 'Show shoulder, elbow, wrist';
      dbg.add('joints not seen: R $rightOk L $leftOk lm ${lmList.landmarks.length}');
      return;
    }

    // curl: side on (or unknown) = false = everything works exactly as before
    if (isCurl && dir == 0 && !attempt) curlFront = _frontal(lmList, e) == true;
    var aR = rightOk ? _fold(_findAngle(lmList, e.right)) : 0.0;
    var aL = leftOk ? _fold(_findAngle(lmList, e.left!)) : 0.0;
    // curl facing the camera: the 2D angle drops too early (quarter reps counted), so a rep
    // needs the wrist-height angle to show the flexion too: the STRAIGHTER of the two is used
    if (isCurl && curlFront) {
      final idleNow = dir == 0 && !attempt;
      if (rightOk) {
        final f = _curlFrontAngle(lmList, e.right, idleNow);
        if (f != null && f.isFinite) {
          dbgCurlFront = f;
          aR = aR.isFinite ? math.max(aR, f) : f;
        }
      }
      if (leftOk) {
        final f = _curlFrontAngle(lmList, e.left!, idleNow);
        if (f != null && f.isFinite) {
          dbgCurlFront = f;
          aL = aL.isFinite ? math.max(aL, f) : f;
        }
      }
    }
    // both sides must bend: use the straighter one, so moving one side can't count a rep
    // deadlift: decide side view / front view only while idle (never mid-rep)
    if (isDead && dir == 0 && !attempt) deadFront = _frontal(lmList, e) == true;
    final sideRaw = !aR.isFinite ? aL : (!aL.isFinite ? aR : math.max(aR, aL));
    // deadlift: this angle is the hip angle (used by the squat check and the speed); the bar
    // itself comes from the bar position (_deadBarPer below), not from this angle
    final raw = sideRaw;
    final angle = _cleanAngle(raw, e);

    // 0% / 100% of the bar. Deadlift: 0% = the user's OWN standing posture (learned while
    // idle, frozen during a rep) instead of a fixed 165, because a relaxed standing hip often
    // reads 140-155 in 2D. The bottom keeps at least 45 degrees of travel.
    var upA = e.upAngle, downA = e.downAngle;
    if (isDead) {
      final ref = _standBase('hipRef', angle, dir == 0 && !attempt);
      upA = math.min(e.upAngle, ref - 4).clamp(110.0, e.upAngle).toDouble();
      downA = math.min(e.downAngle, upA - math.min(45.0, e.upAngle - e.downAngle));
      upEff = upA;
      downEff = downA;
    }

    final asym = (!(isDead && deadFront) && rightOk && leftOk && aR.isFinite && aL.isFinite)
        ? (aR - aL).abs()
        : null;
    // smooth the angle so one jumpy frame can't change it much
    final double smoothed;
    if (e.perFrameSmoothing) {
      smoothAngle ??= angle;
      smoothed = smoothAngle = 0.7 * smoothAngle! + 0.3 * angle;
    } else {
      smoothed = _smooth(angle, t);
    }
    var per = interp(smoothed, downA, upA, 100, 0).clamp(0.0, 100.0).toDouble();
    // deadlift: the bar follows the wrists (the bar) between standing height and the knees
    if (isDead) {
      // wrists lost for a moment (hand over the bar): keep the last bar position
      final bp = _deadBarPer(lmList, t) ?? deadBar;
      if (bp != null) per = bp;
    }
    // curl: the elbow bend only counts while the upper arm hangs down beside the body:
    // at most 35 deg from the torso (Chen & Yang (2020) arXiv:2006.11718) + 10 deg
    // pose-estimation error (Kim et al. (2023) Appl Sci 13(4):2700) = 45 deg from straight
    // down (the torso is upright in a standing curl). Bending with the upper arm raised
    // forward or to the side is not a curl, so the bar cannot fill.
    var armDown = true;
    if (isCurl) {
      for (final arm in [e.right, if (e.left != null) e.left!]) {
        final s = _p(lmList, arm[0]), el = _p(lmList, arm[1]);
        if (s == null || el == null) continue;
        if (el.dy <= s.dy || _fromVertical(s, el) > 45) armDown = false;
      }
      if (!armDown) per = math.min(per, 90.0);
    }
    curPer = per;

    // angular speed (smoothed): too fast = jerky / momentum
    final dtS = (t - lastSpeedTime).clamp(0.001, 1.0).toDouble();
    speed = 0.8 * speed + 0.2 * ((smoothed - (prevSmooth ?? smoothed)).abs() / dtS);
    prevSmooth = smoothed;
    lastSpeedTime = t;

    // ---- BENCH: only count while lying down (blocks shoulder press / curl) ----
    var gateOk = true;
    if (isBench && lyingCheck) {
      final ly = _lying(lmList, e);
      if (ly == false) {
        // clearly upright: drop the lying state only after 2 s (4 s mid-rep)
        notLyingSince ??= t;
        if (t - notLyingSince! > (attempt || dir != 0 ? 4.0 : 2.0)) lyingSince = null;
      } else {
        // lying, or cannot tell (null): do not block
        lyingSince ??= t;
        notLyingSince = null;
      }
      gateOk = lyingSince != null && t - lyingSince! >= lyingSeconds;
      if (!gateOk) gateMsg = 'Lie on the bench';
      if (!gateOk && (attempt || dir != 0)) {
        // stood up / left the bench mid-rep: forget it
        attempt = false;
        dir = 0;
        bottomSince = null;
        repFaults.clear();
      }
    }
    // ---- CURL: upper arm raised (see armDown above): no rep can start or reach the top ----
    if (isCurl && !armDown) {
      gateOk = false;
      gateMsg = 'Keep your upper arm down';
    }
    // ---- all exercises: 5 s to get into position after the body is first seen ----
    setupUntil ??= t + setupSeconds;
    if (t < setupUntil!) {
      gateOk = false;
      gateMsg = 'Get in position: ${(setupUntil! - t).ceil()}';
    }

    // ---- DEADLIFT: knees never bend to squat depth (python squat_like) ----
    if (isDead) {
      final ks = <double>[];
      for (final s in const [
        [24, 26, 28],
        [23, 25, 27]
      ]) {
        final a = _p(lmList, s[0]), b = _p(lmList, s[1]), c = _p(lmList, s[2]);
        if (a == null || b == null || c == null) continue;
        final v = _ang(a, b, c);
        if (v.isFinite) ks.add(v);
      }
      final rdl = e.variant == 'romanian', sumo = e.variant == 'sumo';
      if (deadFront) {
        // facing the camera knee angles are useless (the knees bend toward the lens),
        // so a squat is detected by the hips dropping: hip-to-ankle height shrinks.
        // It keeps running, but only for the debug view: bent over facing the camera the hip
        // joints are hidden and ML Kit guesses them, so it rejected real deadlifts. The
        // research-based squat check runs from the side (knee angle, below).
        final an = _mid(lmList, 27, 28), hpm = _mid(lmList, 23, 24);
        if (an != null && hpm != null) {
          final ext = an.dy - hpm.dy;
          final ruler = _armRuler(lmList) ?? 1.0; // stored length in arm lengths (see _armRuler)
          if (ext > 1) {
            final stand = _standBase('legExt', ext / ruler, dir == 0 && !attempt) * ruler;
            final legDrop = _lim(e, 'squatLegDrop', rdl ? 0.25 : (sumo ? 0.50 : 0.38));
            legDropDbg = 1 - ext / stand;
            if (attempt && legDropDbg > legDrop) frontSquatDbg = true;
          }
        }
      } else if (ks.isNotEmpty) {
        final knee = ks.reduce(math.max); // python: max of both knees
        // the lifter's own standing angles (follow while idle, frozen in a rep)
        final idleNow = dir == 0 && !attempt;
        final kneeStand = _standBase('kneeStand', knee, idleNow);
        final hipStand = _standBase('hipStand', smoothed, idleNow);
        if (attempt) {
          // checked during the WHOLE rep, not only after the bottom hold
          minKnee = math.min(minKnee, knee);
          final kneeFlex = kneeStand - minKnee; // how much the knees bent
          final hipFlex = math.max(hipStand - minAngle, 1.0); // how much the hips hinged
          kneeFlexDbg = kneeFlex;
          hipFlexDbg = hipFlex;
          // a squat bends the knees past half-squat depth, a deadlift does not: half squat starts
          // at 110 deg (Schoenfeld (2010) J Strength Cond Res 24(12):3497-3506) - 10 deg pose
          // error (Kim et al. (2023) Appl Sci 13(4):2700) = 100; conventional deadlift knees are
          // ~120 deg at lift-off (Hanen et al. (2025) Front Bioeng Biotechnol 13:1597209).
          // (The old "knee bend > 1.2 x hip bend" rule had no source and compared a raw knee
          // angle with a lagging smoothed hip angle, so it randomly rejected real deadlifts.)
          final deepKnee = _lim(e, 'squatKnee', sumo ? 55 : 100);
          if (minKnee < deepKnee) squatLike = true;
        }
      }
    }

    // form checks for this frame
    final idle = dir == 0 && !attempt;
    final ev = _evaluate(lmList, e, per, idle, _frontal(lmList, e), asym);
    _updateWarnings(ev, t);

    // rep state machine (the bloc stops sending frames while the rest timer runs)
    if (!attempt && per > 15 && gateOk && !needRest) {
      attempt = true; // left the top
      repStartTime = t;
      peakPer = 0;
      minAngle = smoothed;
      repFaults.clear();
      squatLike = false;
      frontSquatDbg = false;
      minKnee = 999;
      settledSince = null;
      // smoothness / average form of this rep start from zero
      repSpeedPeak = 0;
      repSpeedVar = 0;
      repSpeedInit = false;
      repFormSum = 0;
      repFormN = 0;
    }
    if (attempt) {
      peakPer = math.max(peakPer, per);
      minAngle = math.min(minAngle, smoothed);
      for (final m in shown) {
        if (_severeNow(m, t)) repFaults.add(m); // only faults that lasted count
      }
      if (repSpeedInit) repSpeedVar += (speed - lastRepSpeed).abs();
      repSpeedInit = true;
      lastRepSpeed = speed;
      repSpeedPeak = math.max(repSpeedPeak, speed);
      if (formReady) {
        repFormSum += formScore;
        repFormN++;
      }
      if (t - repStartTime > maxRepSeconds) {
        attempt = false;
        dir = 0;
      }
    }
    // down: must reach the bottom and stay there (deadlift from the side: 10 frames like python).
    // Squat: a partial rep is already a rep, so the bottom is the partial depth (the bar still
    // fills to 100% at extra deep). Deadlift: nobody holds exactly 100% of a hinge, so its
    // bottom is a little earlier (side 90%, facing the camera 85%) with a short hold.
    final reachPer = isSquat
        ? interp(_lim(e, 'partialAngle', 130), e.downAngle, e.upAngle, 100, 0)
            .clamp(35.0, 100.0)
            .toDouble()
        : (isDead ? (deadFront ? _lim(e, 'frontReach', 85) : _lim(e, 'sideReach', 90)) : 100.0);
    final holdNeed = isDead ? (deadFront ? holdSeconds : deadHoldSeconds) : holdSeconds;
    if (per >= reachPer && gateOk) {
      bottomSince ??= t;
      if (dir == 0 && attempt && t - bottomSince! >= holdNeed) {
        dir = 1; // squatLike is NOT reset here: it must survive until the rep ends
      }
    } else {
      bottomSince = null;
    }
    // up: must come back to the top. Deadlift: a lockout is never perfectly 0%, so the rep also
    // ends when the bar is near the top (< 30%) and the lifter stands still for half a second.
    final topPer = isDead ? 12.0 : 0.0;
    var atTop = per <= topPer;
    if (isDead && dir == 1 && per < 30 && speed < 10) {
      settledSince ??= t;
      if (t - settledSince! >= 0.5) atTop = true;
    } else {
      settledSince = null;
    }
    if (atTop) {
      needRest = false; // (alternate mode: _finishRep below may set it again for the next arm)
      if (dir == 1) {
        _finishRep(e, t);
      } else if (attempt && peakPer >= attemptPer) {
        _incompleteRep(e, t); // went part way down and came back
      }
      dir = 0;
      attempt = false;
      bottomSince = null;
      settledSince = null;
    }
    _updateForm(e, ev, t);

    if (debug) {
      dbg.add('angle ${smoothed.round()}  need ${downA.round()}..${upA.round()}  '
          'min ${minAngle == 999 ? '-' : minAngle.round()}');
      dbg.add('per ${per.round()}  dir $dir  attempt ${attempt ? 1 : 0}  hold ${bottomSince == null ? 0 : 1}');
      if (isCurl) {
        dbg.add('view ${curlFront ? 'FRONT' : 'side'}  smooth ratio ${dbgSmoothRatio.toStringAsFixed(2)}'
            '${curlFront ? '  wrist-angle ${dbgCurlFront.isFinite ? dbgCurlFront.round() : '-'}' : ''}'
            '${altMode ? '  next ${altRightNext ? 'R' : 'L'}' : ''}');
      }
      if (isBench) {
        dbg.add('lying ${gateOk ? 'YES' : 'no'}  src $dbgSrc  tilt ${dbgTilt.round()} '
            'need ${_lim(e, 'lyingTilt', 35).round()}'
            '${dbgRatio >= 0 ? '  ratio ${dbgRatio.toStringAsFixed(1)}' : ''}');
        dbg.add('R arm $rightOk  L arm $leftOk');
      }
      if (isDead) {
        String n(double? v) => (v == null || !v.isFinite) ? '-' : v.round().toString();
        dbg.add('hip angle ${n(sideRaw)}  bar (wrists above knee) ${n(deadBar)}%');
        dbg.add('knee flex ${kneeFlexDbg.round()}  hip flex ${hipFlexDbg.round()}  '
            'squat ${squatLike ? 'YES' : 'no'}  front squat (not shown) ${frontSquatDbg ? 'YES' : 'no'}');
        dbg.add('view ${deadFront ? 'FRONT' : 'side'}  '
            'bottom at per ${reachPer.round()}  leg drop ${legDropDbg.toStringAsFixed(2)}');
      }
    }
  }

  /// knee angles (squat) where the white ticks on the depth bar go
  List<double> get depthTickAngles =>
      [_lim(active, 'partialAngle', 130), _lim(active, 'deepAngle', 110)];

  // ===================== what the panel under the camera shows =====================

  /// what the feedback card says right now (most important first)
  CoachingFeedback feedback(double t) {
    final g = gateMsg;
    if (g != null) {
      final sub = g == 'Show your full body'
          ? 'Step back until head to feet are in view'
          : (g == 'Show shoulder, elbow, wrist' ? 'Keep your arm in view of the camera' : null);
      return CoachingFeedback(FeedbackIcon.warning, FeedbackTone.alert, g, sub);
    }
    if (repLabel.isNotEmpty && t - repLabelTime < 4) {
      final ic = repLevel == FormLevel.good
          ? FeedbackIcon.check
          : (repLevel == FormLevel.warn ? FeedbackIcon.error : FeedbackIcon.cancel);
      final tone = switch (repLevel) {
        FormLevel.good => FeedbackTone.good,
        FormLevel.warn => FeedbackTone.warn,
        _ => FeedbackTone.bad,
      };
      return CoachingFeedback(ic, tone, repLabel, repDetail.isEmpty ? null : repDetail);
    }
    if (shown.isNotEmpty) {
      final m = shown.first;
      return CoachingFeedback(FeedbackIcon.warning, _severeNow(m, t) ? FeedbackTone.bad : FeedbackTone.warn,
          m, shown.length > 1 ? shown[1] : null);
    }
    final n = note;
    if (formReady && n != null) return CoachingFeedback(FeedbackIcon.info, FeedbackTone.muted, n);
    if (formReady) {
      return formState == 0
          ? const CoachingFeedback(FeedbackIcon.check, FeedbackTone.good, 'Form looks good', 'Keep going')
          : const CoachingFeedback(FeedbackIcon.error, FeedbackTone.warn, 'Check your form');
    }
    return CoachingFeedback(FeedbackIcon.person, FeedbackTone.muted,
        inSet ? 'Form not assessable' : 'Start lifting',
        inSet ? 'Show more of your body' : 'Reps are counted automatically');
  }

  String get formWord {
    if (!formReady) return 'NOT ASSESSABLE';
    if (formScore >= 90 && shown.isEmpty && formState == 0) return 'FLAWLESS';
    return const ['GOOD', 'ADJUST', 'FAULT'][formState.clamp(0, 2)];
  }
}
