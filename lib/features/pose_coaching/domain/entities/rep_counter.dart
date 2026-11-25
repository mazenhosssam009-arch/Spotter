import 'dart:math' as math;

import 'package:ai_trainer/core/utils/cv_math.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/coaching_feedback.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/exercise.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/form_checks/curl_form_check.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/form_checks/form_check.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/form_checks/form_evaluator.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/form_evaluation.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/form_level.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/form_score_tracker.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/joint_angle.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/pose_frame.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/pose_geometry.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/posture_baseline.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/set_tracker.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/warning_tracker.dart';

/// The trainer logic of AiTrainer.py, SquatTrainer.py, DeadliftTrainer.py and
/// BenchPressTrainer.py. Pure Dart (no Flutter, no ML Kit): it gets one [PoseFrame] per
/// camera frame through [update]. One instance = one workout; the TrainerBloc owns it and
/// the screens only read its fields.
///
/// This class is the rep state machine (top -> bottom -> top, holds, gates, rep results).
/// The rest of the work is done by the domain parts it owns:
/// - [PoseGeometry]: points, angles and the camera view of one frame
/// - [PostureBaseline]: the user's own start posture
/// - [FormEvaluator] + the FormCheck of each exercise: the form rules of one frame
/// - [WarningTracker]: which warnings are shown (debounced) and which are clear faults
/// - [FormScoreTracker]: the live form score and its colour
/// - [SetTracker]: sets, set history and fatigue
class RepCounter {
  RepCounter(this.exercise, {this.debug = false});

  final Exercise exercise;
  // true = fill [debugLines] every frame (debugHud); off it costs nothing
  final bool debug;

  final baseline = PostureBaseline(); // the user's own "start" posture
  final warnings = WarningTracker();
  final score = FormScoreTracker();
  final sets = SetTracker();

  double count = 0;
  int dir = 0;
  double? smoothAngle;
  double lastSmoothTime = 0;
  double lastRepTime = 0;

  // timing (seconds)
  static const holdSeconds =
      0.10; // must stay at 100% this long (1-frame spikes)
  // bench: touch-and-go reps only touch the bottom for a moment (the bottom is read from
  // the raw depth, so a quick pass through 90% is real, not a tracking spike)
  static const benchHoldSeconds = 0.05;
  static const minRepSeconds = 0.6; // a real rep is never faster than this
  static const maxRepSeconds = 20.0; // stale half-rep: forget it
  static const lostGrace = 0.4; // short landmark dropouts are ridden out
  static const maxJumpDeg =
      70.0; // angle jump per frame that is a tracking glitch
  static const attemptPer =
      30.0; // % reached before a return counts as "incomplete"
  static const warnDelay =
      WarningTracker.delay; // a problem must last this long to be shown
  static const warnHold =
      WarningTracker.hold; // and stays this long after it is gone
  static const formTau =
      FormScoreTracker.tau; // form score smoothing time constant
  // time to get into position before counting starts (FR-CV-10 asks for a pre-set countdown)
  static const setupSeconds = 5.0;
  double? setupUntil; // counting starts at this time (null = body not seen yet)

  // ---- deadlift (same as the python file: 10 frames at 15 fps) ----
  static const deadHoldSeconds =
      0.25; // python: 10 frames; a real lift rarely pauses 0.67 s
  static const deadLostGrace = 1.0; // python: hidden > 1 s cancels the rep
  bool squatLike = false; // knees bent to squat depth during this deadlift rep
  // deadlift only: faults (warning texts) that make the rep NOT count (see _finishRep).
  // Both are measured facing the camera only.
  static const deadFaultRejects = ['Knees caving in', 'Stance too narrow'];
  // deadlift facing the camera: smallest torso length (shoulder-to-hip / shoulder width) of
  // this rep as a fraction of the lifter's own standing value. A hinge foreshortens the torso
  // a lot toward the camera, a squat keeps it long. 99 = not measured.
  double minTorsoRatio = 99;
  double minKnee = 999; // smallest knee angle seen during the current rep
  bool deadFront =
      false; // deadlift filmed facing the camera (frozen during a rep)
  double dbgTilt = 0,
      dbgRatio = -1; // bench lying-gate numbers, shown when it blocks
  String dbgSrc = '-'; // bench: which landmarks the lying check used
  bool dbgAlong =
      false; // bench: upper arms hanging beside the ribs (a curl, not lying)
  double kneeFlexDbg = 0, hipFlexDbg = 0; // deadlift squat-check numbers

  // deadlift: this user's own standing / bottom angle (0% and 100% of the bar).
  // 0 = not learned yet, the fixed numbers of the exercise are used.
  double upEff = 0, downEff = 0;
  double? settledSince; // deadlift: standing still near the top after a rep
  double? deadBar; // deadlift: smoothed bar position (0..100), see _deadBarPer
  double deadBarTime = 0; // time of the last deadBar update (0 = none yet)
  bool frontSquatDbg =
      false; // facing the camera: squat-like hip drop seen (debug view only)
  double _up(Exercise e) => (isDead && upEff > 0) ? upEff : e.upAngle;
  double _down(Exercise e) => (isDead && downEff > 0) ? downEff : e.downAngle;

  // ---- bench: must really be lying down ----
  static const lyingSeconds = 0.3;
  static const armsDownSeconds = 0.25; // a curl: one jumpy frame must not count
  double? lyingSince; // null = gate closed
  // Running balance (seconds) of "clearly upright" evidence: grows while the check says
  // upright, drops fast while it says lying and slowly while it cannot tell. One noisy or
  // unknown frame can no longer reset it (or re-open the gate), so the verdict is steady.
  double uprightFor = 0;
  double?
  lastLyingT; // time of the last lying-check frame (for the balance above)
  double? armsDownSince; // upper arms hanging beside the ribs since
  String? gateMsg; // red hint when the exercise position is wrong
  bool lyingCheck =
      true; // false = never block the bench press (bed icon in the app bar)

  // ---- bench: elbows must not flare out to the sides ----
  // worst shoulder angle (torso to upper arm) of the current rep and of this frame,
  // in degrees. A rep past flareReject that stays there is rejected (see _finishRep),
  // so unlike the warning it cannot be "forgotten" during the push back up. A single
  // noisy frame is not enough: [flareOverSince] must stay over the limit briefly.
  double benchFlare = 0, benchFlareNow = 0;
  double? flareOverSince;
  bool benchFlared = false;

  // ---- bench: the forearms must point UP (wrist above the elbow, and above the shoulder at
  // lockout). Rotating the shoulder down so the forearm points forward is not a press. ----
  // seconds of this rep with the forearm out of the pressing position (see _checkPressPosition)
  double benchOffTime = 0;
  double pressLastT = 0;
  double pressTiltNow =
      0; // debug: worst forearm tilt from vertical this frame, degrees
  bool pressOffNow = false; // debug: forearm out of position this frame
  // the last frame in which the wrists could be judged: were they above the shoulders?
  // A rep that ends with the arms down (resting them on the floor) is not a press, see
  // _finishRep. Wrists that were not seen for a moment never reject (see pressUpFresh).
  static const pressUpFresh = 0.4; // seconds the last reading stays valid
  double pressUpLastT = -99;
  bool pressUpLast = true;
  // the flare is smoothed in TIME (not per frame): a phone at 8 fps and one at 25 fps must
  // reject the same reps. [flareSmooth] = smoothed worst-arm flare, null = no reading yet.
  static const flareTau = 0.2; // seconds
  static const flareRejectHold =
      0.5; // the smoothed flare must stay over the limit this long
  double? flareSmooth;
  FormEvaluation?
  lastEval; // the form checks of the last frame (debug view only)
  double flareSmoothTime = 0;
  // bench debug numbers: how end-on the view is, and the upper arm in the picture / learned
  double dbgSquash = double.nan, dbgArmPic = double.nan;

  bool get isDead => exercise.isDeadlift;
  bool get isBench => exercise.isBench;
  bool get isSquat => exercise.isSquat;
  bool get isCurl => exercise.isCurl;

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
  final repFaults = <String>{};
  double? lastRom;
  double? lastConsistency;
  final repDurations = <double>[];
  bool lastRepFast =
      false; // the last counted rep was rushed (the coach says "slow down")
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

  // ---- curl: swing faults are latched during a rep (see _stepRep) ----
  // a swing / elbow / shoulder fault that lasts this long rejects the rep (2+ frames, so a
  // one-frame tracking glitch does not)
  static const curlFaultSeconds = 0.08;
  final curlBlockSince = <String, double>{};

  // ---- per-rep smoothness ----
  double repSpeedPeak = 0, repSpeedVar = 0, lastRepSpeed = 0;
  bool repSpeedInit = false;
  double repFormSum = 0;
  int repFormN = 0;
  double? lastSmooth; // 0..100 of the last finished rep
  double dbgSmoothRatio = 0;

  // ---- read by the screens and the voice coach (owned by the parts above) ----
  List<String> get shown => warnings.shown; // warnings that passed the debounce
  String? get note => warnings.note;
  double get formScore => score.score;
  bool get formReady => score.ready; // false = "Form not assessable"
  int get formState => score.state; // 0 good, 1 warn, 2 bad (with hysteresis)
  bool get inSet => sets
      .inSet; // lifting in the current set (starts at the first counted rep)
  int get setNumber => sets.setNumber; // the set you are doing now
  int get setReps => sets.setReps;
  int get lastSetReps => sets.lastSetReps;
  List<int> get setHistory => sets.setHistory; // reps of each finished set
  double get setStart => sets.setStart;
  double get lastRepEnd => sets.lastRepEnd;
  double get lastSetSecs => sets.lastSetSecs;
  List<double> get setDurs => sets.setDurs;
  List<double> get setRoms => sets.setRoms;
  List<double> get setForms => sets.setForms;
  double? get fatigue => sets.fatigue; // 0..100, null until 3 reps are done

  /// average form score of the set, null before the first rep
  double? get setFormAverage => sets.formAverage;

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
    uprightFor = 0;
    lastLyingT = null;
    armsDownSince = null;
  }

  /// counting, sets and fatigue start again from the beginning
  void resetSession() {
    count = 0;
    repsR = 0;
    repsL = 0;
    lastRepTime = 0;
    needRest = false;
    sets.reset();
    lastSmooth = null;
    partialReps = 0;
    deepReps = 0;
    extraReps = 0;
  }

  // the python code ran at about 15 fps; "0.7*old + 0.3*new" every frame is made
  // to react the same in seconds at any fps (a 35 fps phone would otherwise react
  // more than twice as fast and let jumpy frames through)
  static const pythonFps = 15.0;

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
    sets.end();
    dir = 0;
    attempt = false;
    bottomSince = null;
  }

  /// Stop timer: back to the camera, still in the SAME set (the rest time is not counted in it)
  void resumeSet(double restedSeconds) {
    sets.resume(restedSeconds);
    resetTracking(); // fresh start posture, no half-finished rep
  }

  /// the next set starts empty (from 0); the finished set's reps are kept in [setHistory]
  void nextSet() => sets.next();

  /// +1 / -1 buttons: fix a rep the camera missed or added
  void adjustRep(int d, double t) {
    if (d > 0) {
      count += 1;
      sets.addManualRep(t);
      _trackArm();
    } else {
      if (count < 1) return;
      count -= 1;
      sets.removeRep();
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

  // ===================== exercise measurements that remember the user =====================

  /// "Ruler" for the deadlift: arm length (shoulder-elbow + elbow-wrist). The arms hang
  /// straight down the whole lift, so in the picture they only change with the distance to
  /// the camera (front and side view). Standing lengths are stored as multiples of it, not
  /// pixels, so stepping toward / away from the phone is not read as a hinge. Pose-based
  /// exercise systems normalise landmarks by a body length for the same reason
  /// (Ko, Nasridinov & Park (2024) IEEE Access 12). Used by the front-view squat check.
  /// Only STRAIGHT arms are a ruler: elbow >= 152 deg (180 - 2 x 14 deg elbow error, Francia
  /// et al. (2024) LNCS Extended Reality pp.40-49). Bent or folded arms (hands raised) look
  /// shorter, so then the last straight-arm length is kept. null = not seen yet (pixels).
  double? _armRuler(PoseGeometry g) {
    final arms = <double>[];
    for (final s in const [
      [12, 14, 16],
      [11, 13, 15],
    ]) {
      if (!g.visible(s)) continue;
      final a = g.point(s[0]), b = g.point(s[1]), c = g.point(s[2]);
      if (a == null || b == null || c == null) continue;
      if (PoseGeometry.angle(a, b, c) < 152)
        continue; // bent arm: not a reliable ruler
      arms.add((a - b).distance + (b - c).distance);
    }
    final r = arms.isEmpty ? 0.0 : arms.reduce((x, y) => x + y) / arms.length;
    if (r < 1) return baseline['armRuler'];
    if (baseline['armRuler'] == null) {
      // first time the arms are seen: lengths learned in pixels so far start again in arm lengths
      baseline.remove('legExt');
    }
    return baseline['armRuler'] = r;
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
  double? _deadBarPer(PoseGeometry g, double t) {
    final kn = g.mid(25, 26), an = g.mid(27, 28), wr = g.mid(15, 16);
    if (kn == null || an == null || wr == null || an.dy - kn.dy < 1)
      return null;
    final above =
        (kn.dy - wr.dy) /
        (an.dy - kn.dy); // wrists above the knee, in shin lengths
    final p = interp(above, 0, 0.81, 100, 0);
    // smoothing like the python files (0.7 old + 0.3 new), but per TIME like _smooth: per frame
    // it lagged far behind on slow phones (~7 fps measured), so a normal-speed rep never reached
    // the bottom before the user came back up
    final keep = deadBarTime == 0
        ? 0.0
        : math
              .pow(0.7, (t - deadBarTime).clamp(0.0, 1.0) * pythonFps)
              .toDouble();
    deadBarTime = t;
    deadBar = deadBar == null ? p : keep * deadBar! + (1 - keep) * p;
    return deadBar;
  }

  /// Curl facing the camera: the forearm moves toward the lens, so the 2D elbow angle drops
  /// far too early (a quarter curl already looked like a full one). Better: the height of the
  /// wrist above/below the elbow compared with the arm hanging. cos(flexion) = height / hanging
  /// height, so 0 deg flexion = hanging and about 150 = wrist up at the shoulder.
  /// Returned as an equivalent elbow angle (180 = straight).
  double? _curlFrontAngle(PoseGeometry g, List<int> arm, bool idle) {
    final el = g.point(arm[1]), wr = g.point(arm[2]);
    if (el == null || wr == null || !g.visible([arm[1], arm[2]])) return null;
    final drop = wr.dy - el.dy; // wrist below the elbow = positive
    // ruler: shoulder width (this only runs facing the camera, where both shoulders are seen).
    // The hanging height is stored in shoulder widths, not pixels, so stepping toward / away
    // from the phone does not change it (body-length normalisation, Ko et al. (2024) IEEE Access 12)
    final sa = g.point(11), sb = g.point(12);
    if (sa == null || sb == null || !g.visible([11, 12])) return null;
    final sw = (sa - sb).distance;
    if (sw < 1) return null;
    final full = baseline.standing('fa${arm[0]}', drop / sw, idle) * sw;
    if (full < 1) return null;
    final c = (drop / full).clamp(-1.0, 1.0).toDouble();
    return 180 - math.acos(c) * 180 / math.pi;
  }

  /// true = facing the camera, false = side on, null = unknown
  // TODO: Fix the front view
  bool? _frontal(PoseGeometry g, Exercise e) =>
      g.frontal(e.limit('frontalRatio', 0.5));

  /// bench: like [_frontal], but when the hips are hidden (very common lying down) a clearly
  /// end-on view is still recognised from the head, so the flare is not left unchecked.
  /// Only ever turns "unknown" into true; it never overrides a view that was measured.
  bool? _benchFront(PoseGeometry g, Exercise e) {
    final f = _frontal(g, e);
    if (f != null) return f;
    final sq = g.torsoSquash();
    return (sq != null && sq < PoseGeometry.endOnSquash) ? true : null;
  }

  /// bench: every visible upper arm hangs DOWN beside the ribs - never true on a bench
  /// press (the elbows are out at the bottom and the arms point up at lockout), always
  /// true for a curl. This is the second line of defence against a curl being counted as
  /// a bench press: the lying check cannot always tell (hips out of frame, or a
  /// foreshortened torso when filming across a desk), and it deliberately does not block
  /// when it is unsure. From the head/foot end the spread is read against the shoulder
  /// line; from the side the whole arm hanging straight down is used instead, because the
  /// flare itself is invisible there.
  bool _armsAlongTorso(PoseGeometry g, Exercise e) {
    var judged = 0;
    for (final arm in [e.right, if (e.left != null) e.left!]) {
      final sh = g.point(arm[0]), el = g.point(arm[1]);
      if (sh == null || el == null) continue;
      final other = arm[0] == 12 ? 11 : 12;
      final otherSh = g.point(other);
      final width = otherSh == null ? 0.0 : (otherSh - sh).distance;
      final upperArm = (el - sh).distance;
      final bool along;
      if (width > 0.6 * upperArm) {
        // head/foot end: the upper arm must hang down beside the ribs
        final hangs = g.upperArmHangs(arm[0], other, arm[1]);
        if (hangs == null) continue; // arm points at the lens: nothing to read
        along = hangs;
      } else {
        // side on: the whole arm hangs straight down (wrist well below the elbow)
        final wr = g.point(arm[2]);
        final forearm = wr == null ? 0.0 : (wr - el).distance;
        if (forearm < 1) continue;
        along = wr!.dy - el.dy > 0.4 * forearm;
      }
      judged++;
      if (!along) return false;
    }
    return judged > 0;
  }

  /// bench: is the user lying down? (keeps the numbers for the debug view)
  bool? _lying(PoseGeometry g, Exercise e) {
    final r = g.lying(
      tiltLimit: e.limit('lyingTilt', 45),
      ratioLimit: e.limit('lyingRatio', 1.0),
    );
    dbgSrc = r.source;
    if (r.tilt != null) dbgTilt = r.tilt!;
    if (r.ratio != null) dbgRatio = r.ratio!;
    return r.lying;
  }

  /// bench: remember the elbow flare of this rep. The form check already says
  /// "Elbows flared wide", but that warning fades [WarningTracker.hold] after the last
  /// frame it was seen in, so a slow push back up could still count the rep. Remembering
  /// it until the rep ends (and requiring it to last, see [flareOverSince]) makes the
  /// rejection deterministic without punishing one noisy frame.
  /// Flare (angle at the shoulder between the torso and the upper arm, see
  /// PoseGeometry.shoulderFlare) is only visible from the head/foot end: from the side
  /// the upper arm points at the lens. Like the form check it is measured in the bottom
  /// half only, where a flared elbow is clear; at lockout the arm is straight and the
  /// angle says nothing.
  void _checkFlare(
    PoseGeometry g,
    Exercise e,
    double t,
    double per,
    bool? front,
  ) {
    benchFlareNow = 0;
    if (!attempt || front != true || per < 50) {
      flareOverSince = null;
      flareSmooth = null;
      return;
    }
    double? raw;
    for (final arm in [e.right, if (e.left != null) e.left!]) {
      final f = g.shoulderFlare(
        arm[0] == 12 ? 24 : 23,
        arm[0],
        arm[1],
        armRef: baseline['upperArmSw'],
      );
      if (f != null && f.isFinite) raw = raw == null ? f : math.max(raw, f);
    }
    if (raw == null) return; // nothing readable this frame: keep what we had
    // smooth by time, so one noisy frame (or a slow phone's single frame) cannot reject a rep
    final dt = (t - flareSmoothTime).clamp(0.001, 0.5).toDouble();
    flareSmoothTime = t;
    final s = flareSmooth;
    flareSmooth = s == null
        ? raw
        : s + (1 - math.exp(-dt / flareTau)) * (raw - s);
    benchFlareNow = flareSmooth!;
    benchFlare = math.max(benchFlare, benchFlareNow);
    // only a flare that LASTS rejects
    if (benchFlareNow >= e.limit('flareReject', 100)) {
      flareOverSince ??= t;
      if (t - flareOverSince! >= flareRejectHold) benchFlared = true;
    } else {
      flareOverSince = null;
    }
  }

  /// bench: is the forearm in a pressing position? In a real press the forearm points UP
  /// the whole rep: the wrist is above the elbow and the forearm is near vertical, and at
  /// lockout the wrist is above the shoulder. Rotating the shoulder down (upper arm hanging,
  /// forearm swinging out in FRONT of the shoulder) moves the elbow angle through the same
  /// range, so the angle alone counted it as a rep. Frames where an arm is out of position
  /// add up in [benchOffTime]; _finishRep rejects the rep when it was out of position for too
  /// much of it. Measured only inside a rep, and only on arms that are really seen: when
  /// nothing can be judged the frame counts as fine, so a hidden wrist never rejects a rep.
  ///
  /// Also keeps [pressUpLast]: whether the wrists were above the shoulders in the last frame
  /// they could be judged. _finishRep uses it so a rep that ENDS with the arms down (arm
  /// dropped onto the floor after the set) is never counted, however short that drop was.
  void _checkPressPosition(PoseGeometry g, Exercise e, double t, double per) {
    final dt = (t - pressLastT).clamp(0.0, 0.5).toDouble();
    pressLastT = t;
    pressTiltNow = 0;
    pressOffNow = false;
    if (!attempt) return;
    var judged = 0, offArms = 0;
    var notUp = false; // a wrist is not above its shoulder this frame
    for (final arm in [e.right, if (e.left != null) e.left!]) {
      if (!g.visible(arm)) continue;
      final sh = g.point(arm[0]), el = g.point(arm[1]), wr = g.point(arm[2]);
      if (sh == null || el == null || wr == null) continue;
      final upper = (el - sh).distance;
      if (upper < 1 || (wr - el).distance < 1) continue;
      judged++;
      final tilt = PoseGeometry.fromVertical(el, wr); // forearm vs vertical
      pressTiltNow = math.max(pressTiltNow, tilt);
      // forearm must point up: wrist above the elbow and near vertical (image y grows down).
      // A real press leans the forearm 15-30 deg (the bar path curves; wider grips and
      // dumbbells lean more), a fake rep (shoulder rotated down) holds it near horizontal,
      // so 55 deg keeps the fakes out without rejecting real reps (40 rejected them)
      var armOff = wr.dy >= el.dy || tilt > e.limit('pressTilt', 55);
      // near lockout the wrist must be above the shoulder, not out in front of it
      if (per <= 30 && wr.dy > sh.dy - 0.25 * upper) armOff = true;
      if (armOff) offArms++;
      // same height test, in every frame: used by the end-of-rep check in _finishRep
      if (wr.dy > sh.dy - 0.25 * upper) notUp = true;
    }
    if (judged == 0) return;
    // out of position only when EVERY arm that can be judged is: from the side the far arm is
    // half hidden behind the body and its jitter alone used to reject good reps
    final off = offArms == judged;
    pressUpLast = !notUp;
    pressUpLastT = t;
    pressOffNow = off;
    if (off) benchOffTime += dt;
  }

  /// bench, camera at the head/foot end: learn the length of the upper arm in shoulder
  /// widths. PoseGeometry.shoulderFlare needs it to read the flare without the (noisy)
  /// depth. In the picture the upper arm can only look SHORTER than it is (when it points
  /// along the torso or at the lens), never longer, so the longest length seen is the best
  /// estimate: it goes up fast at any time, also mid-rep, and only drifts down slowly while
  /// idle. A value that is too short is the dangerous one (every flare then reads too
  /// high), so nothing is published until about a second of frames has been seen.
  void _learnUpperArm(PoseGeometry g, Exercise e, bool idle) {
    final sq = g.torsoSquash();
    dbgSquash = sq ?? double.nan;
    if (sq == null || sq >= PoseGeometry.endOnSquash) return;
    final a = g.point(11), b = g.point(12);
    if (a == null || b == null) return;
    final sw = (a - b).distance;
    if (sw < 1) return;
    final lens = <double>[];
    for (final arm in [e.right, if (e.left != null) e.left!]) {
      if (!g.visible([arm[0], arm[1]])) continue;
      final s = g.point(arm[0]), el = g.point(arm[1]);
      if (s == null || el == null) continue;
      lens.add((el - s).distance / sw);
    }
    if (lens.isEmpty) return;
    final v = lens.reduce(
      math.max,
    ); // the longer arm looks the least foreshortened
    dbgArmPic = v;
    if (v < 0.4 || v > 1.3)
      return; // not a believable upper arm: tracking glitch
    final cur = baseline['upperArmRaw'];
    final next = cur == null
        ? v
        : (v > cur
              ? cur + 0.3 * (v - cur)
              : (idle ? cur + 0.002 * (v - cur) : cur));
    baseline['upperArmRaw'] = next;
    final n = (baseline['upperArmN'] ?? 0) + 1;
    baseline['upperArmN'] = n;
    if (n >= 10) baseline['upperArmSw'] = next;
  }

  // ===================== warnings and rep result =====================

  /// true when warning [m] is a clear fault right now (it rejects the rep): the voice
  /// coach says these at once and may interrupt itself for them
  bool isSevere(String m, double t) => warnings.isSevere(m, t);

  /// colour of the depth bar, the rep progress and the form ring
  FormLevel formLevel(double t) => score.level(t, warnings);

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

  void _finishRep(Exercise e, double t) {
    final dur = t - repStartTime;
    if (dur < minRepSeconds || t - lastRepTime <= 1)
      return; // jitter (same 1 s rule as before)
    // deadlift only: knees bent to squat depth = it was a squat, do not count
    if (isDead && squatLike) {
      repLabel = 'Squat - not a deadlift';
      repLevel = FormLevel.bad;
      repDetail = 'Hinge at the hips';
      repLabelTime = t;
      return;
    }
    // deadlift only, facing the camera: the torso never foreshortened toward the lens, so the
    // lifter did not hinge = it was a squat (the wrists alone cannot tell the two apart:
    // they also pass between the knees and the ankles in a deadlift). frontHingeMax is the
    // highest torso ratio (fraction of the standing length) that still counts as a hinge.
    // Measured from the front: squat 0.46-0.49, real deadlift 0.05-0.07 -> limit 0.25.
    if (isDead &&
        deadFront &&
        minTorsoRatio < 90 &&
        minTorsoRatio > e.limit('frontHingeMax', 0.25)) {
      repLabel = 'Squat - not a deadlift';
      repLevel = FormLevel.bad;
      repDetail = 'Hinge at the hips';
      repLabelTime = t;
      return;
    }
    // deadlift only: faults that make the rep not count (knees caving in, stance too narrow).
    // Both are only measured facing the camera, so nothing is rejected from the side.
    if (isDead) {
      for (final f in deadFaultRejects) {
        if (repFaults.contains(f)) {
          repLabel = 'Rejected';
          repLevel = FormLevel.bad;
          repDetail = f;
          repLabelTime = t;
          return;
        }
      }
    }
    // bench only: elbows flared out to the sides = shoulder joint at risk, do not count.
    // This uses the worst angle of the whole rep (see _checkFlare), so the warning fading
    // on the way up cannot sneak a flared rep into the count; a flare that only showed up
    // in one noisy frame is ignored.
    if (isBench && benchFlared) {
      repLabel = 'Rejected';
      repLevel = FormLevel.bad;
      repDetail = 'Elbows flared wide';
      repLabelTime = t;
      return;
    }
    // bench only: the forearm was not pointing up for a good part of the rep (shoulder
    // rotated down, forearm out in front) = not a bench press, do not count.
    if (isBench && benchOffTime / dur >= e.limit('pressOffFrac', 0.2)) {
      repLabel = 'Rejected';
      repLevel = FormLevel.bad;
      repDetail = 'Keep forearms above shoulders';
      repLabelTime = t;
      return;
    }
    // bench only: a press ends with the wrists above the shoulders. If the last frame the
    // wrists could be seen shows them below the shoulders, the arm was dropped (e.g. onto
    // the floor after the set), not locked out: do not count. A reading older than
    // [pressUpFresh] (wrists hidden) is ignored, so a hidden wrist never rejects a rep.
    if (isBench && t - pressUpLastT <= pressUpFresh && !pressUpLast) {
      repLabel = 'Rejected';
      repLevel = FormLevel.bad;
      repDetail = 'Finish with arms up';
      repLabelTime = t;
      return;
    }
    lastRepTime = t;
    final squat = e.isSquat;
    final faults = repFaults.toList();
    final soft =
        isDead || isBench; // only the squat / lying checks decide these
    var counted = faults.isEmpty || e.limit('countFaulty', 0) > 0 || soft;
    // squat depth by the lowest knee angle: 0 partial, 1 deep, 2 extra deep
    var depth = 0;
    if (squat) {
      if (minAngle <= e.limit('extraDeepAngle', 95)) {
        depth = 2;
      } else if (minAngle <= e.limit('deepAngle', 110)) {
        depth = 1;
      }
      if (depth == 0 && e.limit('countPartial', 1) <= 0) counted = false;
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
      repLabel = faults.isEmpty
          ? 'Good rep'
          : (soft ? 'Counted - check form' : 'Rejected');
      repLevel = faults.isEmpty
          ? FormLevel.good
          : (soft ? FormLevel.warn : FormLevel.bad);
    }
    repDetail = faults.isNotEmpty
        ? faults.first
        : (repLabel == 'Partial' ? 'Go deeper for full depth' : '');
    repLabelTime = t;
    if (counted) count += 1;
    // down and up in under fastRepSeconds = rushed (momentum, no control)
    lastRepFast = counted && dur < e.limit('fastRepSeconds', 1.2);
    // range of motion of this rep (squat is scored against full depth, not the 120 counting line;
    // deadlift against the user's own standing / bottom angles)
    final up = _up(e);
    final target = squat ? e.limit('deepAngle', 110) : _down(e);
    lastRom = ((up - minAngle) / math.max(up - target, 1.0))
        .clamp(0.0, 1.0)
        .toDouble();
    // consistency: how close this rep's duration is to the recent ones
    repDurations.add(dur);
    if (repDurations.length > 6) repDurations.removeAt(0);
    if (repDurations.length >= 3) {
      final prev = repDurations.sublist(0, repDurations.length - 1);
      final mean = prev.reduce((a, b) => a + b) / prev.length;
      lastConsistency = (1 - ((dur - mean).abs() / mean - 0.35) / 0.65)
          .clamp(0.0, 1.0)
          .toDouble();
    }
    // smoothness of this rep: how much the speed jumped up and down. A clean rep is
    // one speed hill going down and one coming up (total change about 4 x peak speed).
    // Jerky reps change speed more often. smoothBase / smoothSpan calibrate the score.
    if (repSpeedPeak > 1) {
      final ratio = repSpeedVar / (4 * repSpeedPeak);
      dbgSmoothRatio = ratio;
      final sb = e.limit('smoothBase', 1.5), ss = e.limit('smoothSpan', 2.0);
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
      sets.addRep(
        t,
        dur,
        rom: lastRom ?? 1.0,
        form: repFormN > 0 ? repFormSum / repFormN : score.score,
      );
      if (altMode) _swapAlternateArm();
    }
  }

  void _incompleteRep(Exercise e, double t) {
    final squat = e.isSquat;
    repLabel = squat ? 'Incorrect' : 'Incomplete rep';
    repLevel = squat ? FormLevel.bad : FormLevel.warn;
    repDetail = squat
        ? 'Too shallow - not counted'
        : e.isCurl
        ? 'Curl through full range'
        : e.isBench
        ? 'Lower to chest, lock out'
        : e.isDeadlift
        ? 'Hinge fully, then lock out'
        : '';
    repLabelTime = t;
    final up = _up(e);
    lastRom = ((up - minAngle) / math.max(up - _down(e), 1.0))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  /// the person left or is hidden for a while: forget the half-finished rep
  /// (before, a rep started, the person walked out, came back and it was counted)
  void resetTracking({bool keepSetup = false}) {
    dir = 0;
    attempt = false;
    bottomSince = null;
    smoothAngle = null;
    prevRaw = null;
    prevSmooth = null;
    jumpRejects = 0;
    speed = 0;
    baseline.clear();
    repFaults.clear();
    warnings.clear();
    score.ready = false;
    lastRom = null;
    lastConsistency = null;
    repDurations.clear();
    squatLike = false;
    minTorsoRatio = 99;
    minKnee = 999;
    lyingSince = null;
    uprightFor = 0;
    lastLyingT = null;
    armsDownSince = null;
    gateMsg = null;
    benchFlare = 0;
    benchFlareNow = 0;
    flareOverSince = null;
    benchFlared = false;
    flareSmooth = null;
    benchOffTime = 0;
    pressTiltNow = 0;
    pressOffNow = false;
    pressUpLast = true;
    pressUpLastT = -99;
    upEff = 0;
    downEff = 0;
    settledSince = null;
    deadBar = null;
    deadBarTime = 0;
    frontSquatDbg = false;
    curlBlockSince.clear();
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

  // PoseModule.findAngle: whole pixels like lmList, 0-360 degrees (the line is drawn on the picture)
  double _findAngle(PoseGeometry g, List<int> joints) {
    final angle = g.findAngle(joints);
    jointAngles.add(JointAngle(joints: joints, angle: angle));
    return angle;
  }

  // ===================== one frame =====================

  /// one camera frame: count reps, check form, update the score. [t] = time.time()
  void update(PoseFrame lmList, double t) {
    final g = PoseGeometry(lmList);
    final e = active;
    jointAngles.clear();
    debugLines.clear();
    final dbg = debugLines;

    // deadlift: shoulder, hip, knee and ankle of at least ONE side must be clearly seen. Side on,
    // the far side is behind the body (ML Kit marks it unsure), so asking for both sides blocked
    // every side-view rep; facing the camera both sides are seen anyway.
    // Every exercise checks that its joints are really seen, and a short dropout
    // (lostGrace) is ridden out instead of resetting the rep.
    final fullBody =
        !isDead ||
        (g.hasPerson &&
            (g.visible([12, 24, 26, 28]) || g.visible([11, 23, 25, 27])));
    final rightOk = g.hasPerson && fullBody && g.visible(e.right);
    final leftOk =
        g.hasPerson && fullBody && e.left != null && g.visible(e.left!);
    gateMsg = null;
    tracking = rightOk || leftOk;
    if (rightOk || leftOk) {
      lastSeenTime = t;
    } else {
      bottomSince = null; // python: hold = 0 when joints are hidden
      curPer = 0;
      final lostFor = t - lastSeenTime;
      if (lostFor > ((isDead || isBench) ? deadLostGrace : lostGrace)) {
        // a short bench dropout must not bring back the 5 s countdown
        resetTracking(keepSetup: isBench && lostFor < 4.0);
      }
      // set after the reset, because resetTracking clears gateMsg
      if (isDead) gateMsg = 'Show your full body';
      if (isBench) gateMsg = 'Show shoulder, elbow, wrist';
      dbg.add(
        'joints not seen: R $rightOk L $leftOk lm ${lmList.landmarks.length}',
      );
      return;
    }

    // ---- the joint angle of this frame ----
    // curl: side on (or unknown) = false = everything works exactly as before
    if (isCurl && dir == 0 && !attempt) curlFront = _frontal(g, e) == true;
    var aR = rightOk ? PoseGeometry.fold(_findAngle(g, e.right)) : 0.0;
    var aL = leftOk ? PoseGeometry.fold(_findAngle(g, e.left!)) : 0.0;
    // curl facing the camera: the 2D angle drops too early (quarter reps counted), so a rep
    // needs the wrist-height angle to show the flexion too: the STRAIGHTER of the two is used
    if (isCurl && curlFront) {
      final idleNow = dir == 0 && !attempt;
      if (rightOk) {
        final f = _curlFrontAngle(g, e.right, idleNow);
        if (f != null && f.isFinite) {
          dbgCurlFront = f;
          aR = aR.isFinite ? math.max(aR, f) : f;
        }
      }
      if (leftOk) {
        final f = _curlFrontAngle(g, e.left!, idleNow);
        if (f != null && f.isFinite) {
          dbgCurlFront = f;
          aL = aL.isFinite ? math.max(aL, f) : f;
        }
      }
    }
    // bench from the side: the far arm is half hidden behind the body, and its jitter made the
    // "straighter arm" below read every bottom too shallow. When one arm is seen much less
    // surely than the other, the clearer arm alone is followed.
    if (isBench && rightOk && leftOk) {
      final cR = g.confidence(e.right), cL = g.confidence(e.left!);
      if (cR - cL > 0.2) aL = double.nan;
      if (cL - cR > 0.2) aR = double.nan;
    }
    // both sides must bend: use the straighter one, so moving one side can't count a rep
    // deadlift: decide side view / front view only while idle (never mid-rep)
    if (isDead && dir == 0 && !attempt) deadFront = _frontal(g, e) == true;
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
      final ref = baseline.standing('hipRef', angle, dir == 0 && !attempt);
      upA = math.min(e.upAngle, ref - 4).clamp(110.0, e.upAngle).toDouble();
      downA = math.min(
        e.downAngle,
        upA - math.min(45.0, e.upAngle - e.downAngle),
      );
      upEff = upA;
      downEff = downA;
    }

    final asym =
        (!(isDead && deadFront) &&
            rightOk &&
            leftOk &&
            aR.isFinite &&
            aL.isFinite)
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

    // ---- depth of the rep, 0..100 ----
    var per = interp(smoothed, downA, upA, 100, 0).clamp(0.0, 100.0).toDouble();
    // deadlift: the bar follows the wrists (the bar) between standing height and the knees
    if (isDead) {
      // wrists lost for a moment (hand over the bar): keep the last bar position
      final bp = _deadBarPer(g, t) ?? deadBar;
      if (bp != null) per = bp;
    }
    // curl: the elbow bend only counts while the upper arm hangs down beside the body
    // (see _armDown). Bending with the upper arm raised forward or to the side is not a
    // curl, so the bar cannot fill.
    final armDown = !isCurl || _armDown(g, e);
    if (!armDown) per = math.min(per, 90.0);
    // bench: the smoothing lags the bar, so in a normal touch-and-go set the smoothed
    // depth can stop short of both the chest and the lockout and reps are lost (one rep
    // never ends, or a rep never reaches the bottom). The bottom and the lockout of the
    // bench press are therefore read from the (jump-filtered) raw angle; the bottom hold
    // still stops a single bad frame from counting. Everything else (bar display, form
    // checks, ROM) keeps the smoothed depth. For every other exercise this is [per].
    final perRaw = isBench
        ? interp(angle, downA, upA, 100, 0).clamp(0.0, 100.0).toDouble()
        : per;
    curPer = per;

    // angular speed (smoothed): too fast = jerky / momentum
    final dtS = (t - lastSpeedTime).clamp(0.001, 1.0).toDouble();
    speed =
        0.8 * speed + 0.2 * ((smoothed - (prevSmooth ?? smoothed)).abs() / dtS);
    prevSmooth = smoothed;
    lastSpeedTime = t;

    // ---- gates: no rep can start or finish while one of these is closed ----
    final gateOk = _gates(g, e, t, armDown: armDown);

    // which way the body is filmed: true = shoulder line across the picture
    // (bench head/foot end), false = side on, null = unknown
    final front = isBench ? _benchFront(g, e) : _frontal(g, e);

    // ---- DEADLIFT: knees never bend to squat depth (python squat_like) ----
    if (isDead) _checkSquatLike(g, e, smoothed);

    // ---- BENCH: learn the arm length (end-on view), then remember the worst elbow flare ----
    if (isBench && front == true) _learnUpperArm(g, e, dir == 0 && !attempt);
    if (isBench) _checkFlare(g, e, t, per, front);
    if (isBench) _checkPressPosition(g, e, t, per);

    // ---- form checks for this frame ----
    final idle = dir == 0 && !attempt;
    final ev = FormEvaluator.evaluate(
      FormCheckInput(
        pose: g,
        exercise: e,
        per: per,
        idle: idle,
        front: front,
        baseline: baseline,
        curlFront: curlFront,
        deadFront: deadFront,
        lowering: dir == 0 && attempt,
        speed: speed,
        lyingSeen: lyingSince != null,
        flare: flareSmooth,
      ),
      asym: asym,
    );
    warnings.update(ev, t);
    lastEval = ev;

    // ---- rep state machine (the bloc stops sending frames while the rest timer runs) ----
    final reachPer = _stepRep(e, t, per, perRaw, smoothed, gateOk, armDown: armDown);
    score.update(
      ev,
      t,
      speed: speed,
      maxSpeed: e.maxSpeed,
      lastRom: lastRom,
      lastConsistency: lastConsistency,
    );

    if (debug)
      _debug(
        e,
        smoothed,
        sideRaw,
        per,
        downA,
        upA,
        gateOk,
        rightOk,
        leftOk,
        reachPer,
        front,
      );
  }

  /// bench lying check, curl upper-arm check and the 5 s setup countdown.
  /// Returns false while a rep may not start or finish (gateMsg says why).
  bool _gates(PoseGeometry g, Exercise e, double t, {required bool armDown}) {
    var gateOk = true;
    // ---- BENCH: only count while lying down (blocks shoulder press / curl) ----
    if (isBench && lyingCheck) {
      final ly = _lying(g, e);
      dbgAlong = _armsAlongTorso(g, e);
      // keep the balance of "upright" evidence (see [uprightFor])
      final dt = lastLyingT == null
          ? 0.0
          : (t - lastLyingT!).clamp(0.0, 0.5).toDouble();
      lastLyingT = t;
      if (ly == false) {
        uprightFor += dt;
      } else if (ly == true) {
        uprightFor = math.max(0.0, uprightFor - 3 * dt);
      } else {
        uprightFor = math.max(0.0, uprightFor - 0.5 * dt);
      }
      // one bad frame must not throw a real bench rep away: the arms have to hang there
      armsDownSince = dbgAlong ? (armsDownSince ?? t) : null;
      if (armsDownSince != null && t - armsDownSince! >= armsDownSeconds) {
        // arms hanging beside the torso = upright for sure (a bench press always has the
        // elbows away from the ribs): close the gate, so a curl is never counted as a
        // bench press
        lyingSince = null;
      } else if (uprightFor >= (attempt || dir != 0 ? 4.0 : 2.0)) {
        // clearly upright for 2 s (4 s mid-rep): close the gate and keep it closed until
        // the evidence has really gone (a few lying frames, or a longer stretch of unknown)
        lyingSince = null;
      } else if (lyingSince == null && uprightFor < 0.5) {
        // lying, or cannot tell: do not block
        lyingSince = t;
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
    // ---- CURL: upper arm raised (see armDown in update): no rep can start or reach the top ----
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
    return gateOk;
  }

  /// curl: the upper arm hangs down beside the body. At most 35 deg from the torso (Chen &
  /// Yang (2020) arXiv:2006.11718) + 10 deg pose-estimation error (Kim et al. (2023) Appl Sci
  /// 13(4):2700) = 45 deg from straight down (the torso is upright in a standing curl).
  bool _armDown(PoseGeometry g, Exercise e) {
    for (final arm in [e.right, if (e.left != null) e.left!]) {
      final s = g.point(arm[0]), el = g.point(arm[1]);
      if (s == null || el == null) continue;
      if (el.dy <= s.dy || PoseGeometry.fromVertical(s, el) > e.limit('armDownMax', 35)) {
        return false;
      }
    }
    return true;
  }

  /// deadlift: was this rep really a squat? Sets [squatLike] (and the debug numbers)
  void _checkSquatLike(PoseGeometry g, Exercise e, double smoothed) {
    final ks = <double>[];
    for (final s in const [
      [24, 26, 28],
      [23, 25, 27],
    ]) {
      final a = g.point(s[0]), b = g.point(s[1]), c = g.point(s[2]);
      if (a == null || b == null || c == null) continue;
      final v = PoseGeometry.angle(a, b, c);
      if (v.isFinite) ks.add(v);
    }
    final rdl = e.variant == 'romanian', sumo = e.variant == 'sumo';
    if (deadFront) {
      // facing the camera the torso is the hinge signal: in a deadlift it foreshortens a lot
      // (the chest goes toward the lens), in a squat it stays long. Torso length (shoulder
      // midpoint to hip midpoint) in shoulder widths, as a fraction of the lifter's own
      // standing value (learned while idle, frozen during a rep). The smallest value of the
      // rep is judged in _finishRep.
      final sa = g.point(11), sb = g.point(12), ha = g.point(23), hb = g.point(24);
      if (sa != null && sb != null && ha != null && hb != null) {
        final sw = (sa - sb).distance;
        if (sw > 1) {
          final torso = ((sa + sb) / 2 - (ha + hb) / 2).distance / sw;
          final stand = baseline.standing('frontTorso', torso, dir == 0 && !attempt);
          if (attempt && stand > 0) {
            minTorsoRatio = math.min(minTorsoRatio, torso / stand);
          }
        }
      }
      // facing the camera knee angles are useless (the knees bend toward the lens),
      // so a squat is detected by the hips dropping: hip-to-ankle height shrinks.
      // It keeps running, but only for the debug view: bent over facing the camera the hip
      // joints are hidden and ML Kit guesses them, so it rejected real deadlifts. The
      // research-based squat check runs from the side (knee angle, below).
      final an = g.mid(27, 28), hpm = g.mid(23, 24);
      if (an != null && hpm != null) {
        final ext = an.dy - hpm.dy;
        final ruler =
            _armRuler(g) ?? 1.0; // stored length in arm lengths (see _armRuler)
        if (ext > 1) {
          final stand =
              baseline.standing('legExt', ext / ruler, dir == 0 && !attempt) *
              ruler;
          final legDrop = e.limit(
            'squatLegDrop',
            rdl ? 0.25 : (sumo ? 0.50 : 0.38),
          );
          legDropDbg = 1 - ext / stand;
          if (attempt && legDropDbg > legDrop) frontSquatDbg = true;
        }
      }
    } else if (ks.isNotEmpty) {
      final knee = ks.reduce(math.max); // python: max of both knees
      // the lifter's own standing angles (follow while idle, frozen in a rep)
      final idleNow = dir == 0 && !attempt;
      final kneeStand = baseline.standing('kneeStand', knee, idleNow);
      final hipStand = baseline.standing('hipStand', smoothed, idleNow);
      if (attempt) {
        // checked during the WHOLE rep, not only after the bottom hold
        minKnee = math.min(minKnee, knee);
        final kneeFlex = kneeStand - minKnee; // how much the knees bent
        final hipFlex = math.max(
          hipStand - minAngle,
          1.0,
        ); // how much the hips hinged
        kneeFlexDbg = kneeFlex;
        hipFlexDbg = hipFlex;
        // a squat bends the knees past half-squat depth, a deadlift does not: half squat starts
        // at 110 deg (Schoenfeld (2010) J Strength Cond Res 24(12):3497-3506) - 10 deg pose
        // error (Kim et al. (2023) Appl Sci 13(4):2700) = 100; conventional deadlift knees are
        // ~120 deg at lift-off (Hanen et al. (2025) Front Bioeng Biotechnol 13:1597209).
        // (The old "knee bend > 1.2 x hip bend" rule had no source and compared a raw knee
        // angle with a lagging smoothed hip angle, so it randomly rejected real deadlifts.)
        final deepKnee = e.limit('squatKnee', sumo ? 55 : 100);
        if (minKnee < deepKnee) squatLike = true;
      }
    }
  }

  /// top -> bottom (held) -> top = one rep. Returns the depth that counts as the bottom.
  double _stepRep(
    Exercise e,
    double t,
    double per,
    double perRaw,
    double smoothed,
    bool gateOk, {
    bool armDown = true,
  }) {
    if (!attempt && perRaw > 15 && gateOk && !needRest) {
      attempt = true; // left the top
      repStartTime = t;
      peakPer = 0;
      minAngle = smoothed;
      repFaults.clear();
      curlBlockSince.clear();
      squatLike = false;
      minTorsoRatio = 99;
      frontSquatDbg = false;
      minKnee = 999;
      benchFlare = 0;
      benchFlareNow = 0;
      flareOverSince = null;
      benchFlared = false;
      flareSmooth = null;
      benchOffTime = 0;
      pressUpLast = true;
      pressUpLastT = -99;
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
      if (!isCurl) {
        for (final m in shown) {
          if (warnings.isSevere(m, t))
            repFaults.add(m); // only faults that lasted count
        }
      } else {
        // curl: swinging is quick (often shorter than warnDelay), so a swing / elbow / shoulder
        // fault, or the upper arm leaving the body, rejects the rep as soon as it lasts
        // curlFaultSeconds, without waiting for the warning to be shown. This latch is the only
        // rule for the curl: one reject-level frame (pose jitter at the top of the curl) after a
        // warning was already showing must not reject the rep.
        final now = <String>{
          ...?lastEval?.blocking,
          if (!armDown) 'Keep your upper arm down',
        };
        for (final m in now) {
          final since = curlBlockSince.putIfAbsent(m, () => t);
          // raised, tense shoulders are a held state, not a quick swing: the ear landmark is
          // noisier than the swing checks, so this one has to last longer before it rejects
          final need = m == CurlFormCheck.raisedMsg
              ? e.limit('shoulderRaiseSeconds', 0.4)
              : curlFaultSeconds;
          if (t - since >= need) repFaults.add(m);
        }
        curlBlockSince.removeWhere((m, _) => !now.contains(m));
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
        ? interp(
            e.limit('partialAngle', 130),
            e.downAngle,
            e.upAngle,
            100,
            0,
          ).clamp(35.0, 100.0).toDouble()
        : (isDead
              ? (deadFront
                    ? e.limit('frontReach', 85)
                    : e.limit('sideReach', 90))
              : (isBench
                    ? e.limit('benchReach', 90)
                    // curl: the smoothed 2D elbow angle rarely touches the exact 100% line
                    // (lag + pose noise, worse on faster reps), so the bottom counts a little
                    // earlier. Must stay above 90: the upper-arm-raised cap (per <= 90) must
                    // still block the bottom.
                    : (isCurl ? e.limit('curlReach', 92) : 100.0)));
    final holdNeed = isDead
        ? (deadFront ? holdSeconds : deadHoldSeconds)
        : (isBench ? benchHoldSeconds : holdSeconds);
    if (perRaw >= reachPer && gateOk) {
      bottomSince ??= t;
      if (dir == 0 && attempt && t - bottomSince! >= holdNeed) {
        dir = 1; // squatLike is NOT reset here: it must survive until the rep ends
      }
    } else {
      bottomSince = null;
    }
    // up: must come back to the top. Deadlift: a lockout is never perfectly 0%, so the rep also
    // ends when the bar is near the top (< 30%) and the lifter stands still for half a second.
    // Bench: the lockout is read from the raw depth too (see perRaw in update), otherwise a
    // continuous touch-and-go set never reaches the top in the smoothed signal.
    // curl: a relaxed arm hanging reads about 150-160 in 2D, so the top is a little before 0%
    // (still below the 15% that starts a rep, so the two do not flicker)
    final topPer = isDead
        ? 12.0
        : (isBench ? 10.0 : (isCurl ? e.limit('curlTop', 12) : 0.0));
    var atTop = perRaw <= topPer;
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
    return reachPer;
  }

  void _debug(
    Exercise e,
    double smoothed,
    double sideRaw,
    double per,
    double downA,
    double upA,
    bool gateOk,
    bool rightOk,
    bool leftOk,
    double reachPer,
    bool? front,
  ) {
    final dbg = debugLines;
    dbg.add(
      'angle ${smoothed.round()}  need ${downA.round()}..${upA.round()}  '
      'min ${minAngle == 999 ? '-' : minAngle.round()}',
    );
    dbg.add(
      'per ${per.round()}  dir $dir  attempt ${attempt ? 1 : 0}  hold ${bottomSince == null ? 0 : 1}',
    );
    if (isCurl) {
      dbg.add(
        'view ${curlFront ? 'FRONT' : 'side'}  smooth ratio ${dbgSmoothRatio.toStringAsFixed(2)}'
        '${curlFront ? '  wrist-angle ${dbgCurlFront.isFinite ? dbgCurlFront.round() : '-'}' : ''}'
        '${altMode ? '  next ${altRightNext ? 'R' : 'L'}' : ''}',
      );
    }
    final bad =
        lastEval?.named.entries.where((x) => x.value < 0.95).toList() ?? [];
    if (bad.isNotEmpty) {
      dbg.add(
        'score drags: ${bad.map((x) => '${x.key} ${(x.value * 100).round()}%').join(', ')}',
      );
    }
    if (isBench) {
      dbg.add(
        'lying ${gateOk ? 'YES' : 'no'}  src $dbgSrc  tilt ${dbgTilt.round()} '
        'need ${e.limit('lyingTilt', 30).round()}'
        '${dbgRatio >= 0 ? '  ratio ${dbgRatio.toStringAsFixed(1)}' : ''}',
      );
      dbg.add('R arm $rightOk  L arm $leftOk');
      dbg.add(
        'view ${front == true
            ? 'FRONT'
            : front == false
            ? 'side'
            : '?'}  '
        'flare ${benchFlareNow.round()} (worst ${benchFlare.round()}  '
        'reject ${e.limit('flareReject', 100).round()}  '
        'squash ${dbgSquash.isFinite ? dbgSquash.toStringAsFixed(2) : '-'}  '
        'armPic ${dbgArmPic.isFinite ? dbgArmPic.toStringAsFixed(2) : '-'}  '
        'armRef ${(baseline['upperArmSw'] ?? 0).toStringAsFixed(2)}'
        '${benchFlared ? '  REJECTED' : ''})  '
        'arms beside torso ${dbgAlong ? 'YES' : 'no'}',
      );
      dbg.add(
        'forearm tilt ${pressTiltNow.round()} (max ${e.limit('pressTilt', 45).round()})  '
        '${pressOffNow ? 'OFF' : 'ok'}  off ${benchOffTime.toStringAsFixed(2)}s  '
        'wrists up ${pressUpLast ? 'YES' : 'no'}',
      );
    }
    if (isDead) {
      String n(double? v) =>
          (v == null || !v.isFinite) ? '-' : v.round().toString();
      dbg.add(
        'hip angle ${n(sideRaw)}  bar (wrists above knee) ${n(deadBar)}%',
      );
      dbg.add(
        'knee flex ${kneeFlexDbg.round()}  hip flex ${hipFlexDbg.round()}  '
        'squat ${squatLike ? 'YES' : 'no'}  front squat (not shown) ${frontSquatDbg ? 'YES' : 'no'}',
      );
      dbg.add(
        'view ${deadFront ? 'FRONT' : 'side'}  '
        'bottom at per ${reachPer.round()}  leg drop ${legDropDbg.toStringAsFixed(2)}',
      );
      dbg.add(
        'front torso ratio ${minTorsoRatio < 90 ? minTorsoRatio.toStringAsFixed(2) : '-'}  '
        '(rejected as squat above ${e.limit('frontHingeMax', 0.25).toStringAsFixed(2)})',
      );
    }
  }

  /// knee angles (squat) where the white ticks on the depth bar go
  List<double> get depthTickAngles => [
    active.limit('partialAngle', 130),
    active.limit('deepAngle', 110),
  ];

  // ===================== what the panel under the camera shows =====================

  /// what the feedback card says right now (most important first)
  CoachingFeedback feedback(double t) {
    final g = gateMsg;
    if (g != null) {
      final sub = g == 'Show your full body'
          ? 'Step back until head to feet are in view'
          : (g == 'Show shoulder, elbow, wrist'
                ? 'Keep your arm in view of the camera'
                : null);
      return CoachingFeedback(FeedbackIcon.warning, FeedbackTone.alert, g, sub);
    }
    if (repLabel.isNotEmpty && t - repLabelTime < 4) {
      final ic = repLevel == FormLevel.good
          ? FeedbackIcon.check
          : (repLevel == FormLevel.warn
                ? FeedbackIcon.error
                : FeedbackIcon.cancel);
      final tone = switch (repLevel) {
        FormLevel.good => FeedbackTone.good,
        FormLevel.warn => FeedbackTone.warn,
        _ => FeedbackTone.bad,
      };
      return CoachingFeedback(
        ic,
        tone,
        repLabel,
        repDetail.isEmpty ? null : repDetail,
      );
    }
    if (shown.isNotEmpty) {
      final m = shown.first;
      return CoachingFeedback(
        FeedbackIcon.warning,
        warnings.isSevere(m, t) ? FeedbackTone.bad : FeedbackTone.warn,
        m,
        shown.length > 1 ? shown[1] : null,
      );
    }
    final n = note;
    if (formReady && n != null)
      return CoachingFeedback(FeedbackIcon.info, FeedbackTone.muted, n);
    if (formReady) {
      return formState == 0
          ? const CoachingFeedback(
              FeedbackIcon.check,
              FeedbackTone.good,
              'Form looks good',
              'Keep going',
            )
          : const CoachingFeedback(
              FeedbackIcon.error,
              FeedbackTone.warn,
              'Check your form',
            );
    }
    return CoachingFeedback(
      FeedbackIcon.person,
      FeedbackTone.muted,
      inSet ? 'Form not assessable' : 'Start lifting',
      inSet ? 'Show more of your body' : 'Reps are counted automatically',
    );
  }

  String get formWord => score.word(shown);
}