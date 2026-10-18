import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'camera_view.dart';
import 'cv.dart';
import 'exercise_figures.dart';
import 'pose_module.dart';
import 'spotter_theme.dart';

// Form colours (Spotter palette). They are also used to draw the depth bar on the
// camera picture, so they stay Flutter `Color`s.
const formGood = Sp.mint; // form correct
const formWarn = Sp.warn; // needs correction
const formBad = Sp.fault; // clear fault
const formNA = Color(0xFF8E9192); // cannot be assessed

/// shows live numbers (angle, %, gate state...) on the camera picture while testing.
/// Keep it false for normal use: drawing text on every frame costs FPS.
/// Set it to true for a minute when you want to tune the deadlift / other limits.
const debugHud = false;

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

/// result of the form checks for one frame
class _Eval {
  final scores = <double>[]; // one 0..1 score per alignment check
  final warns = <String>[]; // messages for checks that are out of tolerance
  final blocking = <String>[]; // clear faults: these reject the rep
  bool assessable = false; // false = not enough landmarks to judge form
  String? note; // small grey hint ("flare unchecked")

  /// [over] > 0 means outside tolerance; the score reaches 0 at [over] == [soft].
  /// A fault only blocks the rep when it is clearly outside tolerance (score < 0.5).
  void limit(double over, double soft, String msg, {bool block = false, double? blockAt}) {
    if (!over.isFinite) return;
    final s = over <= 0 ? 1.0 : (1 - over / soft).clamp(0.0, 1.0).toDouble();
    scores.add(s);
    if (over > 0) {
      warns.add(msg);
      // blockAt: reject the rep only when [over] reaches this (warn earlier, reject later)
      if (block && (blockAt != null ? over >= blockAt : s < 0.5)) blocking.add(msg);
    }
  }
}

/// what the feedback card under the camera says right now
class _Msg {
  const _Msg(this.icon, this.color, this.title, [this.sub]);
  final IconData icon;
  final Color color;
  final String title;
  final String? sub;
}

class TrainerPage extends StatefulWidget {
  const TrainerPage({super.key, required this.exercise});
  final Exercise exercise;

  @override
  State<TrainerPage> createState() => _TrainerPageState();
}

class _TrainerPageState extends State<TrainerPage> with WidgetsBindingObserver {
  final detector = PoseDetector();
  double ptime = 0;
  double ctime = 0;
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
  double _up(Exercise e) => (_isDead && upEff > 0) ? upEff : e.upAngle;
  double _down(Exercise e) => (_isDead && downEff > 0) ? downEff : e.downAngle;

  // ---- bench: must really be lying down ----
  static const lyingSeconds = 0.3;
  double? lyingSince;
  double? notLyingSince;
  String? gateMsg; // red hint when the exercise position is wrong
  bool lyingCheck = true; // false = never block the bench press (bed icon in the app bar)

  bool get _isDead => widget.exercise.name.contains('Deadlift');
  bool get _isBench => widget.exercise.name.contains('Bench');
  bool get _isSquat => widget.exercise.name.contains('Squat');

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
  Color repColor = formGood;
  double repLabelTime = -99;

  // ---- UI: the panel under the camera is redrawn from this (about 12 times a second) ----
  final ValueNotifier<int> _ui = ValueNotifier<int>(0);
  double _lastUi = 0;
  double curPer = 0; // depth of the current rep, 0..100
  bool _expanded = false; // false = slim panel (bigger camera), true = full panel

  // biceps curl only: 0 = right arm, 1 = left arm, 2 = both arms together,
  // 3 = alternate starting with the right arm, 4 = alternate starting with the left arm
  int armMode = 0;
  bool get _isCurl => widget.exercise.name.contains('Curl');
  bool get _altMode => _isCurl && armMode >= 3;
  static const _armNames = ['Right arm', 'Left arm', 'Both arms', 'Alternate R>L', 'Alternate L>R'];
  static const _armShort = ['Right arm', 'Left arm', 'Both arms', 'Alt R>L', 'Alt L>R'];

  // ---- alternate mode: only the arm that is "next" can count a rep ----
  bool altRightNext = true;
  bool needRest = false; // after a swap the new arm must be at the bottom before a rep can start
  int repsR = 0, repsL = 0; // counted reps per arm (curl)

  // ---- curl: filmed facing the camera (frozen during a rep, like deadFront) ----
  bool curlFront = false;

  // ---- sets, rest timer, fatigue (the USER ends a set with the flag button) ----
  bool inSet = false; // lifting in the current set (starts at the first counted rep)
  int setNumber = 1, setReps = 0, lastSetReps = 0; // setNumber = the set you are doing now
  double setStart = 0, lastRepEnd = -99, lastSetSecs = 0;
  double restSeconds = 90; // adjustable with the timer button
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

  /// the exercise with the arm(s) the user picked; everything else stays as configured
  Exercise get _active {
    final e = widget.exercise;
    if (!_isCurl) return e;
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

  void _setArmMode(int m) {
    if (m == armMode) return;
    setState(() {
      armMode = m;
      altRightNext = m != 4; // 3 = right first, 4 = left first
    });
    _resetTracking(); // a half-finished rep of the other arm must not count
    _resetSession(); // counting starts again from 0
    repLabel = '';
  }

  /// counting, sets and fatigue start again from the beginning
  void _resetSession() {
    count = 0;
    repsR = 0;
    repsL = 0;
    lastRepTime = 0;
    needRest = false;
    phase = 0;
    ringing = false;
    extraUsed = 0;
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

  double _smooth(double angle) {
    final t = now();
    final dt = (t - lastSmoothTime).clamp(0.0, 1.0);
    lastSmoothTime = t;
    if (smoothAngle == null) return smoothAngle = angle;
    final keep = math.pow(0.7, dt * pythonFps).toDouble();
    return smoothAngle = keep * smoothAngle! + (1 - keep) * angle;
  }

  // ===================== sets, rest screen, alerts =====================

  // 0 = camera works, 1 = resting (rest screen), 2 = "get ready" 3-2-1 before the next set
  int phase = 0;
  bool get resting => phase == 1;
  bool get getReady => phase == 2;
  bool get paused => phase != 0; // camera frames are ignored and an overlay covers the screen
  int restStartMs = 0, restEndMs = 0, restTotalMs = 1, readyEndMs = 0;
  int extraUsed = 0; // "more time" used in this rest
  static const maxExtensions = 2; // the rest can be extended only 2 times
  static const readySeconds = 3;
  bool ringing = false; // the "rest finished" dialog is open
  int _lastBeepSec = -1;
  Timer? _ticker;

  static const minRestSeconds = 5.0;
  static const maxRestSeconds = 600.0; // 10 minutes

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable(); // the screen stays on during the whole workout
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
  }

  /// timers use the wall clock, so after a phone call / background trip they are still right
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _tick();
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  void _armRest(int ms) {
    restEndMs = _nowMs() + ms;
    restTotalMs = math.max(ms, 1);
    _lastBeepSec = -1;
  }

  void _beep() {
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.selectionClick();
  }

  /// the rest is over: three long vibrations + system alert sound
  Future<void> _ringAlert() async {
    for (var i = 0; i < 3; i++) {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;
    }
  }

  void _tick() {
    if (!mounted || phase == 0) return;
    final n = _nowMs();
    if (phase == 1) {
      if (ringing) return;
      final left = restEndMs - n;
      if (left <= 0) {
        _restDone();
        return;
      }
      final sec = (left / 1000).ceil();
      if (sec <= 3 && sec != _lastBeepSec) {
        _lastBeepSec = sec; // short beep for the last 3 seconds
        _beep();
      }
      setState(() {});
    } else {
      final left = readyEndMs - n;
      if (left <= 0) {
        _endGetReady();
        return;
      }
      final sec = (left / 1000).ceil();
      if (sec != _lastBeepSec) {
        _lastBeepSec = sec;
        _beep();
      }
      setState(() {});
    }
  }

  /// starts the rest screen (call inside setState)
  void _startRestNow() {
    inSet = false;
    lastSetReps = setReps;
    lastSetSecs = math.max(0.0, lastRepEnd - setStart); // first rep to last counted rep
    dir = 0;
    attempt = false;
    bottomSince = null;
    extraUsed = 0;
    ringing = false;
    restStartMs = _nowMs();
    _armRest((restSeconds * 1000).round());
    phase = 1;
  }

  /// Finish button: ends the set and opens the rest screen
  void _finishSet() {
    if (setReps == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Do at least one counted rep first')));
      return;
    }
    setState(_startRestNow);
  }

  /// Stop timer: back to the camera, still in the SAME set (the rest time is not counted in it)
  void _stopRest() {
    final elapsed = (_nowMs() - restStartMs) / 1000.0;
    setState(() {
      phase = 0;
      ringing = false;
      if (setReps > 0) {
        setStart += elapsed;
        lastRepEnd += elapsed;
        inSet = true;
      }
      _resetTracking(); // fresh start posture, no half-finished rep
    });
  }

  /// the next set starts empty (call inside setState)
  void _nextSetState() {
    if (setReps > 0) setNumber++;
    setReps = 0;
    inSet = false;
    setDurs.clear();
    setRoms.clear();
    setForms.clear();
    fatigue = null;
  }

  /// Begin button / Next set: new set, then the 3-2-1 countdown
  void _startGetReady() {
    phase = 2;
    readyEndMs = _nowMs() + readySeconds * 1000;
    _lastBeepSec = -1;
  }

  void _endGetReady() {
    if (!mounted) return;
    setState(() {
      phase = 0;
      _resetTracking();
    });
  }

  /// the rest timer ran out: alert, then "Next set" or "More time" (max 2 times)
  Future<void> _restDone() async {
    if (!mounted || ringing || phase != 1) return;
    ringing = true;
    _ringAlert();
    final left = maxExtensions - extraUsed;
    final more = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => PopScope(
        canPop: false,
        child: SpotDialog(
          title: 'Rest finished',
          content: Text(left > 0
              ? 'Ready for set ${setNumber + 1}? You can add more time ($left left).'
              : 'Ready for set ${setNumber + 1}? No more extra time.'),
          actions: [
            SpotButton('Next set ${setNumber + 1}',
                icon: Icons.play_arrow, onPressed: () => Navigator.pop(c, false)),
            if (left > 0)
              SpotButton('More time +${_mmss(restSeconds)} · $left left',
                  icon: Icons.add, kind: SpotKind.secondary, onPressed: () => Navigator.pop(c, true)),
          ],
        ),
      ),
    );
    ringing = false;
    if (!mounted || phase != 1) return;
    setState(() {
      if (more == true) {
        extraUsed++;
        _armRest((restSeconds * 1000).round());
      } else {
        _nextSetState();
        _startGetReady();
      }
    });
  }

  /// Timer button (and "Edit time" on the rest screen): choose the rest time, 5 s to 10 min.
  /// While the rest is running, Save restarts the countdown with the new time at once.
  Future<void> _restSettings() async {
    var mins = restSeconds >= 60 && restSeconds % 60 == 0;
    final ctl = TextEditingController(
        text: (mins ? restSeconds / 60 : restSeconds).round().toString());
    String? err;
    final res = await showDialog<int>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) {
          // 1 = save, 2 = save and start the rest now
          void save(int result) {
            final v = double.tryParse(ctl.text.trim().replaceAll(',', '.'));
            if (v == null || v <= 0) {
              setD(() => err = 'Enter a number');
              return;
            }
            final secs = mins ? v * 60 : v;
            if (secs < minRestSeconds) {
              setD(() => err = 'Minimum is 5 seconds');
              return;
            }
            if (secs > maxRestSeconds) {
              setD(() => err = 'Maximum is 10 minutes');
              return;
            }
            restSeconds = secs;
            Navigator.pop(c, result);
          }

          return SpotDialog(
            title: resting ? 'Change rest time' : 'Rest timer',
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final q in const [30, 60, 90, 120, 180, 300])
                  ActionChip(
                    label: Text(q < 60 ? '${q}s' : '${q ~/ 60}:${(q % 60).toString().padLeft(2, '0')}'),
                    onPressed: () => setD(() {
                      mins = q >= 60 && q % 60 == 0;
                      ctl.text = (mins ? q / 60 : q).round().toString();
                      err = null;
                    }),
                  ),
              ]),
              const SizedBox(height: 16),
              TextField(
                controller: ctl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Rest time',
                  helperText: 'From 5 seconds to 10 minutes',
                  errorText: err,
                ),
                onChanged: (_) => setD(() => err = null),
              ),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Seconds')),
                  ButtonSegment(value: true, label: Text('Minutes')),
                ],
                selected: {mins},
                onSelectionChanged: (s) => setD(() {
                  mins = s.first;
                  err = null;
                }),
              ),
            ]),
            actions: [
              if (resting)
                SpotButton('Save & restart', onPressed: () => save(1))
              else ...[
                SpotButton('Start rest', icon: Icons.timer_outlined, onPressed: () => save(2)),
                SpotButton('Save', kind: SpotKind.secondary, onPressed: () => save(1)),
              ],
              SpotButton('Cancel', kind: SpotKind.link, onPressed: () => Navigator.pop(c, 0)),
            ],
          );
        },
      ),
    );
    // (the controller is not disposed on purpose: the dialog is still animating out)
    if (!mounted || res == null || res == 0) return;
    if (res == 2 && !paused) {
      if (setReps == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Do at least one counted rep first')));
        return;
      }
      setState(_startRestNow);
    } else if (res == 1 && resting) {
      setState(() => _armRest((restSeconds * 1000).round()));
    } else {
      setState(() {});
    }
  }

  /// +1 / -1 buttons: fix a rep the camera missed or added
  void _adjustRep(int d) {
    final t = now();
    setState(() {
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
        if (_isCurl) {
          if (armMode == 0) repsR = math.max(0, repsR - 1);
          if (armMode == 1) repsL = math.max(0, repsL - 1);
          if (armMode == 2) {
            repsR = math.max(0, repsR - 1);
            repsL = math.max(0, repsL - 1);
          }
        }
      }
    });
  }

  /// back button: ask first, so a workout is not lost by accident
  Future<void> _onBack() async {
    if (count == 0 && !paused) {
      Navigator.of(context).pop();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => SpotDialog(
        title: 'Leave the workout?',
        content: Text('Your ${count.toInt()} reps are not saved and will be lost.'),
        actions: [
          SpotButton('Stay', onPressed: () => Navigator.pop(c, false)),
          SpotButton('Leave', kind: SpotKind.destructive, onPressed: () => Navigator.pop(c, true)),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.of(context).pop();
  }

  // ===================== beginner guide =====================

  /// beginner guide: the coach shows the whole movement, then each step with its explanation under him
  ({String camera, FigStep demo, List<(FigStep, String)> steps, List<FigMuscle> focus}) _guide() {
    if (_isCurl) {
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
    if (_isSquat) {
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
    if (_isDead) {
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

  void _showGuide() {
    final g = _guide();
    showDialog(
      context: context,
      builder: (c) => SpotDialog(
        title: 'How to: ${widget.exercise.name}',
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

  // ===================== Spotter UI pieces =====================

  String _fatWord(double f) => f < 35 ? 'fresh' : (f < 65 ? 'tiring' : 'rest soon');
  Color _fatColor(double f) => f < 35 ? formGood : (f < 65 ? formWarn : formBad);

  /// top bar button: dark fill + mint border + mint icon/label, visible on any background
  Widget _pill(IconData icon, String label, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Material(
            color: Sp.card,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Sp.rChip), side: const BorderSide(color: Sp.mint)),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(Sp.rChip),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 18, color: Sp.mint),
                  if (label.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(label.toUpperCase(), style: Sp.labelMd.copyWith(color: Sp.mint)),
                  ],
                ]),
              ),
            ),
          ),
        ),
      );

  /// full-screen overlay: the rest screen, or the 3-2-1 "get ready" countdown
  Widget _pausedOverlay() {
    final endMs = getReady ? readyEndMs : restEndMs;
    final leftMs = math.max(0, endMs - _nowMs());
    final leftSec = (leftMs / 1000).ceil();
    Widget body;
    if (getReady) {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        SpotChip('Set $setNumber', dot: Sp.mint),
        const SizedBox(height: 24),
        Text('$leftSec', style: Sp.displayMetric.copyWith(fontSize: 160, height: 1, color: Sp.mint)),
        const SizedBox(height: 12),
        Text('GET IN POSITION', style: Sp.labelLg.copyWith(color: Sp.muted)),
        const SizedBox(height: 32),
        SpotButton('Skip', kind: SpotKind.link, onPressed: _endGetReady),
      ]);
    } else {
      final fat = fatigue, sm = lastSmooth;
      final avgForm = setForms.isEmpty ? null : setForms.reduce((a, b) => a + b) / setForms.length;
      body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: SpotChip('Rest · set $setNumber done', dot: Sp.mint)),
        const SizedBox(height: 24),
        Center(
          child: SizedBox(
            width: 220,
            height: 220,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: (leftMs / restTotalMs).clamp(0.0, 1.0).toDouble(),
                  strokeWidth: 8,
                  color: Sp.mint,
                  backgroundColor: Sp.line,
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_mmss(leftSec.toDouble()), style: Sp.displayMetric.copyWith(color: Sp.white)),
                Text('REMAINING', style: Sp.labelSm.copyWith(color: Sp.muted)),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: SpotMetric('Reps', '$lastSetReps')),
          const SizedBox(width: 12),
          Expanded(child: SpotMetric('Time', _mmss(lastSetSecs))),
          if (avgForm != null) ...[
            const SizedBox(width: 12),
            Expanded(
              child: SpotMetric('Form', '${avgForm.round()}%',
                  valueColor: avgForm >= 80 ? formGood : (avgForm >= 55 ? formWarn : formBad)),
            ),
          ],
        ]),
        if (sm != null || fat != null || extraUsed > 0) ...[
          const SizedBox(height: 12),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            if (sm != null) SpotChip('Smooth ${sm.round()}', dot: Sp.mint),
            if (fat != null) SpotChip('Fatigue ${fat.round()}% ${_fatWord(fat)}', dot: _fatColor(fat)),
            if (extraUsed > 0) SpotChip('Extra time $extraUsed/$maxExtensions', dot: formWarn),
          ]),
        ],
        const SizedBox(height: 24),
        SpotButton('Begin set ${setNumber + 1}',
            icon: Icons.play_arrow,
            onPressed: () => setState(() {
                  _nextSetState();
                  _startGetReady();
                })),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: SpotButton('Stop timer',
                  icon: Icons.stop, kind: SpotKind.secondary, height: 52, onPressed: _stopRest)),
          const SizedBox(width: 12),
          Expanded(
              child: SpotButton('Edit time',
                  icon: Icons.edit, kind: SpotKind.secondary, height: 52, onPressed: _restSettings)),
        ]),
      ]);
    }
    return Material(
      color: Sp.canvas,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: body),
          ),
        ),
      ),
    );
  }

  // ===================== helpers =====================

  double _lim(Exercise e, String key, double fallback) => e.limits[key] ?? fallback;

  double _maxSpeed(Exercise e) => _lim(e, 'maxSpeed', e.name.contains('Curl') ? 400 : 300);

  String _mmss(double s) {
    final v = s.isFinite ? s.round() : 0;
    return '${v ~/ 60}:${(v % 60).toString().padLeft(2, '0')}';
  }

  /// ASSUMPTION: each landmark in lmList looks like [id, x, y]. If your pose_module
  /// returns something else, this is the only place to change.
  /// A map is built once per frame, so every lookup is O(1) (it was a list scan
  /// called hundreds of times per frame).
  List? _lmSrc;
  final _lmMap = <int, Offset>{};
  Offset? _p(List lm, int id) {
    if (!identical(lm, _lmSrc)) {
      _lmSrc = lm;
      _lmMap.clear();
      for (final q in lm) {
        _lmMap[(q[0] as num).toInt()] = Offset((q[1] as num).toDouble(), (q[2] as num).toDouble());
      }
    }
    return _lmMap[id];
  }

  /// middle of two landmarks, using only the visible ones
  Offset? _mid(List lm, int a, int b) {
    final pts = <Offset>[];
    for (final id in [a, b]) {
      final q = _p(lm, id);
      if (q != null && detector.isVisible([id])) pts.add(q);
    }
    if (pts.isEmpty) return null;
    return pts.length == 1 ? pts[0] : (pts[0] + pts[1]) / 2;
  }

  /// angle at [b] in degrees (0-180)
  double _ang(Offset a, Offset b, Offset c) {
    final v1 = a - b, v2 = c - b;
    final d = v1.distance * v2.distance;
    if (d < 1e-6) return double.nan;
    final c0 = ((v1.dx * v2.dx + v1.dy * v2.dy) / d).clamp(-1.0, 1.0).toDouble();
    return math.acos(c0) * 180 / math.pi;
  }

  /// how far the line from->to is tilted away from vertical (0 = straight up/down)
  double _fromVertical(Offset from, Offset to) =>
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
  bool? _frontal(List lm, Exercise e) {
    final a = _p(lm, 11), b = _p(lm, 12), c = _p(lm, 23), d = _p(lm, 24);
    if (a == null || b == null || c == null || d == null || !detector.isVisible([11, 12, 23, 24])) {
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
  bool? _lying(List lm, Exercise e) {
    final tiltLim = _lim(e, 'lyingTilt', 35);
    final ratioLim = _lim(e, 'lyingRatio', 0.9);
    final sh = <Offset>[], hp = <Offset>[];
    for (final s in const [
      [11, 23],
      [12, 24]
    ]) {
      if (!detector.isVisible(s)) continue;
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
      if (!detector.isVisible(s)) continue;
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
  /// (Ko, Nasridinov & Park (2024) IEEE Access 12). Arms hidden for a moment = the last
  /// known arm length; null = arms not seen yet (then pixels are used, as before).
  double? _armRuler(List lm) {
    final arms = <double>[];
    for (final s in const [
      [12, 14, 16],
      [11, 13, 15]
    ]) {
      if (!detector.isVisible(s)) continue;
      final a = _p(lm, s[0]), b = _p(lm, s[1]), c = _p(lm, s[2]);
      if (a == null || b == null || c == null) continue;
      arms.add((a - b).distance + (b - c).distance);
    }
    final r = arms.isEmpty ? 0.0 : arms.reduce((x, y) => x + y) / arms.length;
    if (r < 1) return base['armRuler'];
    if (base['armRuler'] == null) {
      // first time the arms are seen: lengths learned in pixels so far start again in arm lengths
      base.remove('frontVert');
      base.remove('legExt');
    }
    return base['armRuler'] = r;
  }

  /// Deadlift facing the camera: the hip angle hardly changes in 2D, so use how much
  /// the torso got shorter vertically compared with standing: lean = acos(vert/standing).
  /// Returned as an equivalent hip angle (180 = upright) so the same up/down limits work.
  ///
  /// Two measures, the one showing MORE hinge wins:
  /// 1) torso: how much shorter shoulders-to-hips got. At a very deep hinge the shoulders
  ///    reach hip height or go below it, which counts as the deepest hinge.
  /// 2) hands: how far the wrists went down compared with standing, as a fraction of the leg
  ///    length. Facing the camera this is far more reliable than the torso length.
  double? _frontHinge(List lm, bool idle) {
    final e = widget.exercise;
    final sh = _mid(lm, 11, 12), hp = _mid(lm, 23, 24);
    if (sh == null || hp == null) return null;
    final ruler = _armRuler(lm) ?? 1.0; // arms not seen yet: pixels, as before
    final dead = _lim(e, 'frontDead', 10), gain = _lim(e, 'frontGain', 1.5);
    // dead zone (relaxed standing is never exactly upright) and gain (the camera
    // under-reads a forward lean): standing = 180, a real hinge reaches the limit
    double? torso;
    final vert = hp.dy - sh.dy; // shoulders are above the hips
    if (vert >= 1) {
      // standing torso length, stored in arm lengths (see _armRuler) and turned back into pixels
      final stand = _standBase('frontVert', vert / ruler, idle) * ruler;
      final lean = math.acos((vert / stand).clamp(0.0, 1.0).toDouble()) * 180 / math.pi;
      torso = 180 - math.max(0.0, lean - dead) * gain;
    } else if (base['frontVert'] != null) {
      // shoulders level with / below the hips: the torso points at the lens = deepest hinge
      torso = 180 - math.max(0.0, 90 - dead) * gain;
    }
    double? hands;
    final an = _mid(lm, 27, 28), wr = _mid(lm, 15, 16);
    if (an != null && wr != null) {
      final ext = an.dy - hp.dy;
      if (ext > 1) {
        // standing hip-to-ankle length, stored in arm lengths (see _armRuler)
        final leg = _standBase('legExt', ext / ruler, idle) * ruler;
        final drop = (wr.dy - hp.dy) / leg;
        // hands hanging, standing. While the torso is upright the reference also rises at a
        // moderate speed: if the first frames were taken with the hands up (holding the
        // phone, walking into view) the reference was stuck too low and showed a false hinge.
        final upright = torso == null || torso > 165;
        final h0 = _lowBase('handDrop0', drop, idle, rise: upright ? 0.05 : 0.005);
        final dz = _lim(e, 'handDead', 0.12), reach = _lim(e, 'handReach', 0.40);
        final p = ((drop - h0 - dz) / math.max(reach - dz, 0.05)).clamp(0.0, 1.0).toDouble();
        hands = 180 - 80 * p; // same scale as the hip angle: 100 = bottom
      }
    }
    dbgFrontTorso = torso ?? double.nan;
    dbgFrontHands = hands ?? double.nan;
    if (torso == null) return hands;
    if (hands == null) return torso;
    return math.min(torso, hands);
  }

  /// like _base, but follows quickly DOWNWARD and slowly upward while idle, for a value
  /// whose standing level is its minimum (hand height: lifting makes it bigger, so the
  /// start of a lift cannot drag the reference up with it)
  double _lowBase(String key, double v, bool idle, {double rise = 0.005}) {
    final b = base[key];
    if (b == null) {
      base[key] = v;
      return v;
    }
    if (!idle) return b;
    return base[key] = v < b ? 0.8 * b + 0.2 * v : (1 - rise) * b + rise * v;
  }

  /// Curl facing the camera: the forearm moves toward the lens, so the 2D elbow angle drops
  /// far too early (a quarter curl already looked like a full one). Better: the height of the
  /// wrist above/below the elbow compared with the arm hanging. cos(flexion) = height / hanging
  /// height, so 0 deg flexion = hanging and about 150 = wrist up at the shoulder.
  /// Returned as an equivalent elbow angle (180 = straight).
  double? _curlFrontAngle(List lm, List<int> arm, bool idle) {
    final el = _p(lm, arm[1]), wr = _p(lm, arm[2]);
    if (el == null || wr == null || !detector.isVisible([arm[1], arm[2]])) return null;
    final drop = wr.dy - el.dy; // wrist below the elbow = positive
    // ruler: shoulder width (this only runs facing the camera, where both shoulders are seen).
    // The hanging height is stored in shoulder widths, not pixels, so stepping toward / away
    // from the phone does not change it (body-length normalisation, Ko et al. (2024) IEEE Access 12)
    final sa = _p(lm, 11), sb = _p(lm, 12);
    if (sa == null || sb == null || !detector.isVisible([11, 12])) return null;
    final sw = (sa - sb).distance;
    if (sw < 1) return null;
    final full = _standBase('fa${arm[0]}', drop / sw, idle) * sw;
    if (full < 1) return null;
    final c = (drop / full).clamp(-1.0, 1.0).toDouble();
    return 180 - math.acos(c) * 180 / math.pi;
  }

  /// how far the worst knee is inside its toes (0 = over the toes), as a fraction
  /// of shin length. Uses the toe, so a deliberate toe-out stance is not punished.
  double? _kneeCave(List lm) {
    final h1 = _p(lm, 23), h2 = _p(lm, 24);
    if (h1 == null || h2 == null) return null;
    final mx = (h1.dx + h2.dx) / 2;
    double? worst;
    for (final s in const [
      [25, 27, 31],
      [26, 28, 32]
    ]) {
      if (!detector.isVisible([s[0], s[1]])) continue;
      final kn = _p(lm, s[0]), an = _p(lm, s[1]), toe = _p(lm, s[2]);
      if (kn == null || an == null) continue;
      final Offset ft = (toe != null && detector.isVisible([s[2]])) ? toe : an;
      final shin = (kn - an).distance;
      if (shin < 1) continue;
      final inward = ((mx - ft.dx).abs() - (mx - kn.dx).abs()) / shin;
      worst = worst == null ? inward : math.max(worst, inward);
    }
    return worst;
  }

  /// stance width (ankles / shoulders) and knee cave: only meaningful facing the camera
  void _frontChecks(_Eval ev, List lm, Exercise e, double per, double sMin, double sMax,
      {double caveLim = 0.15, bool blockCave = true}) {
    final a1 = _p(lm, 27), a2 = _p(lm, 28), s1 = _p(lm, 11), s2 = _p(lm, 12);
    if (a1 != null && a2 != null && s1 != null && s2 != null && detector.isVisible([27, 28])) {
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

  _Eval _curl(List lm, Exercise e, double per, bool idle) {
    final ev = _Eval();
    // one arm or both arms (see armMode): every active arm is checked
    for (final arm in [e.right, if (e.left != null) e.left!]) {
      final isRight = arm[0] == 12;
      final hipId = isRight ? 24 : 23, otherShId = isRight ? 11 : 12;
      final s = _p(lm, arm[0]), el = _p(lm, arm[1]), hip = _p(lm, hipId);
      if (s == null || el == null || hip == null || !detector.isVisible([arm[0], arm[1], hipId])) {
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
      if (s2 != null && detector.isVisible([otherShId])) {
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

  _Eval _squat(List lm, Exercise e, double per, bool? front) {
    final ev = _Eval();
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

  _Eval _deadlift(List lm, Exercise e, double per, bool idle, bool? front) {
    final ev = _Eval();
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
      if (!detector.isVisible(s)) continue;
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
      if (!detector.isVisible(s)) continue;
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

  _Eval _bench(List lm, Exercise e, double per, bool idle, bool? front) {
    final ev = _Eval();
    final flares = <double>[], tilts = <double>[], bends = <double>[];
    final wrists = <Offset>[];
    var segs = 0.0;
    var sides = 0;
    for (final s in [e.right, if (e.left != null) e.left!]) {
      if (!detector.isVisible(s)) continue;
      final sh = _p(lm, s[0]), el = _p(lm, s[1]), wr = _p(lm, s[2]);
      if (sh == null || el == null || wr == null) continue;
      final isRight = s[0] == 12;
      final hipId = isRight ? 24 : 23, idxId = isRight ? 20 : 19;
      final hip = detector.isVisible([hipId]) ? _p(lm, hipId) : null;
      final idx = detector.isVisible([idxId]) ? _p(lm, idxId) : null;
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
        if (!detector.isVisible(s)) continue;
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

  _Eval _evaluate(List lm, Exercise e, double per, bool idle, bool? front, double? asym) {
    final n = e.name;
    final ev = n.contains('Curl')
        ? _curl(lm, e, per, idle)
        : n.contains('Squat')
            ? _squat(lm, e, per, front)
            : n.contains('Deadlift')
                ? _deadlift(lm, e, per, idle, front)
                : n.contains('Bench')
                    ? _bench(lm, e, per, idle, front)
                    : _Eval();
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
  void _updateWarnings(_Eval ev, double t) {
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
  void _updateForm(Exercise e, _Eval ev, double t) {
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

  Color _formColor(double t) {
    if (!formReady) return formNA;
    var st = formState;
    if (shown.isNotEmpty) st = math.max(st, 1); // never emerald while a warning is up
    if (shown.any((m) => _severeNow(m, t))) st = 2;
    return st == 0 ? formGood : (st == 1 ? formWarn : formBad);
  }

  /// which arm did the counted rep (curl only)
  void _trackArm() {
    if (!_isCurl) return;
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
    if (_isDead && squatLike) {
      repLabel = 'Squat - not a deadlift';
      repColor = formBad;
      repDetail = 'Hinge at the hips';
      repLabelTime = t;
      return;
    }
    lastRepTime = t;
    final squat = e.name.contains('Squat');
    final faults = repFaults.toList();
    final soft = _isDead || _isBench; // only the squat / lying checks decide these
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
        repColor = formBad;
      } else if (depth == 2) {
        repLabel = 'Extra deep';
        repColor = formGood;
      } else if (depth == 1) {
        repLabel = 'Deep';
        repColor = formGood;
      } else {
        repLabel = counted ? 'Partial' : 'Partial - not counted';
        repColor = formWarn;
      }
    } else {
      repLabel = faults.isEmpty ? 'Good rep' : (soft ? 'Counted - check form' : 'Rejected');
      repColor = faults.isEmpty ? formGood : (soft ? formWarn : formBad);
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
      if (_altMode) _swapAlternateArm();
    }
  }

  void _incompleteRep(Exercise e, double t) {
    final squat = e.name.contains('Squat');
    final n = e.name;
    repLabel = squat ? 'Incorrect' : 'Incomplete rep';
    repColor = squat ? formBad : formWarn;
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
  void _resetTracking() {
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

  Future<void> onFrame(Frame img) async {
    if (paused) return; // rest screen / get-ready: nothing is counted, tracked or drawn
    final e = _active;
    final oneSide = widget.exercise.oneSide; // HUD layout does not change with the arm choice
    await detector.findPose(img);
    if (!mounted) return;
    final lmList = detector.findPosition(img, draw: false);
    final w = img.width, h = img.height;
    // python text sizes were made for a 640x480 (AiTrainer) or 1280x720 picture
    final k = math.min(w, h) / (oneSide ? 480 : 720);
    final hud = img.hud;
    final t = now();

    // debug text that always fits: shrinks, then cuts, instead of running into the bar
    void put(String s, double x, double y, double scale, Color color, double maxW,
        {bool right = false}) {
      const cw = 18.0; // about one letter at scale 1
      var sc = scale;
      var txt = s;
      if (txt.length * cw * sc > maxW) sc = math.max(maxW / (txt.length * cw), 0.45 * k);
      final fit = (maxW / (cw * sc)).floor();
      if (txt.length > fit && fit > 2) txt = '${txt.substring(0, fit - 2)}..';
      hud.putText(txt, right ? x - txt.length * cw * sc : x, y, sc, color, 2);
    }

    // deadlift (python): shoulders, hips, knees and ankles must ALL be visible.
    // Every exercise checks that its joints are really seen, and a short dropout
    // (lostGrace) is ridden out instead of resetting the rep.
    final fullBody =
        !_isDead || (lmList.isNotEmpty && detector.isVisible([11, 12, 23, 24, 25, 26, 27, 28]));
    final rightOk = lmList.isNotEmpty && fullBody && detector.isVisible(e.right);
    final leftOk = lmList.isNotEmpty && fullBody && e.left != null && detector.isVisible(e.left!);
    gateMsg = null;
    if (rightOk || leftOk) {
      lastSeenTime = t;
    } else {
      bottomSince = null; // python: hold = 0 when joints are hidden
      curPer = 0;
      if (t - lastSeenTime > (_isDead ? deadLostGrace : lostGrace)) _resetTracking();
      // set after the reset, because _resetTracking clears gateMsg
      if (_isDead) gateMsg = 'Show your full body';
      if (_isBench) gateMsg = 'Show shoulder, elbow, wrist';
    }

    final barX1 = w * 0.88; // (only used to keep the debug text away from the right edge)
    final dbg = <String>[];
    if (!(rightOk || leftOk)) {
      dbg.add('joints not seen: R $rightOk L $leftOk lm ${lmList.length}');
    }

    if (rightOk || leftOk) {
      // curl: side on (or unknown) = false = everything works exactly as before
      if (_isCurl && dir == 0 && !attempt) curlFront = _frontal(lmList, e) == true;
      // draw: debugHud -> the angle lines and numbers are only painted while testing (FPS)
      var aR = rightOk
          ? _fold(detector.findAngle(img, e.right[0], e.right[1], e.right[2], draw: debugHud))
          : 0.0;
      var aL = leftOk
          ? _fold(detector.findAngle(img, e.left![0], e.left![1], e.left![2], draw: debugHud))
          : 0.0;
      // curl facing the camera: the 2D angle drops too early (quarter reps counted), so a rep
      // needs the wrist-height angle to show the flexion too: the STRAIGHTER of the two is used
      if (_isCurl && curlFront) {
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
      if (_isDead && dir == 0 && !attempt) deadFront = _frontal(lmList, e) == true;
      final sideRaw = !aR.isFinite ? aL : (!aL.isFinite ? aR : math.max(aR, aL));
      // deadlift: take whichever measure shows MORE hinge. Side on, the hip angle shows it;
      // facing the camera, the torso getting shorter shows it. No view guessing needed.
      final frontRaw = _isDead ? _frontHinge(lmList, dir == 0 && !attempt) : null;
      final raw = (frontRaw != null && sideRaw.isFinite) ? math.min(sideRaw, frontRaw) : (frontRaw ?? sideRaw);
      final angle = _cleanAngle(raw, e);

      // 0% / 100% of the bar. Deadlift: 0% = the user's OWN standing posture (learned while
      // idle, frozen during a rep) instead of a fixed 165, because a relaxed standing hip often
      // reads 140-155 in 2D. The bottom keeps at least 45 degrees of travel.
      var upA = e.upAngle, downA = e.downAngle;
      if (_isDead) {
        final ref = _standBase('hipRef', angle, dir == 0 && !attempt);
        upA = math.min(e.upAngle, ref - 4).clamp(110.0, e.upAngle).toDouble();
        downA = math.min(e.downAngle, upA - math.min(45.0, e.upAngle - e.downAngle));
        upEff = upA;
        downEff = downA;
      }

      final asym = (!(_isDead && deadFront) && rightOk && leftOk && aR.isFinite && aL.isFinite)
          ? (aR - aL).abs()
          : null;
      // smooth the angle so one jumpy frame can't change it much
      final double smoothed;
      if (e.perFrameSmoothing) {
        smoothAngle ??= angle;
        smoothed = smoothAngle = 0.7 * smoothAngle! + 0.3 * angle;
      } else {
        smoothed = _smooth(angle);
      }
      final per = interp(smoothed, downA, upA, 100, 0).clamp(0.0, 100.0).toDouble();
      curPer = per;

      // angular speed (smoothed): too fast = jerky / momentum
      final dtS = (t - lastSpeedTime).clamp(0.001, 1.0).toDouble();
      speed = 0.8 * speed + 0.2 * ((smoothed - (prevSmooth ?? smoothed)).abs() / dtS);
      prevSmooth = smoothed;
      lastSpeedTime = t;

      // ---- BENCH: only count while lying down (blocks shoulder press / curl) ----
      var gateOk = true;
      if (_isBench && lyingCheck) {
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

      // ---- DEADLIFT: knees never bend to squat depth (python squat_like) ----
      if (_isDead) {
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
          // so a squat is detected by the hips dropping: hip-to-ankle height shrinks
          final an = _mid(lmList, 27, 28), hpm = _mid(lmList, 23, 24);
          if (an != null && hpm != null) {
            final ext = an.dy - hpm.dy;
            final ruler = _armRuler(lmList) ?? 1.0; // same units as in _frontHinge
            if (ext > 1) {
              final stand = _standBase('legExt', ext / ruler, dir == 0 && !attempt) * ruler;
              final legDrop = _lim(e, 'squatLegDrop', rdl ? 0.25 : (sumo ? 0.50 : 0.38));
              legDropDbg = 1 - ext / stand;
              if (attempt && legDropDbg > legDrop) squatLike = true;
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
            // a deadlift is mostly HIP hinge (knees bend little); a squat is mostly KNEE
            // bend. So compare them instead of using one fixed knee angle.
            final ratio = _lim(e, 'squatRatio', rdl ? 0.9 : (sumo ? 1.8 : 1.2));
            final deepKnee = _lim(e, 'squatKnee', rdl ? 100 : (sumo ? 55 : 75));
            if ((kneeFlex >= 45 && kneeFlex > ratio * hipFlex) || minKnee < deepKnee) squatLike = true;
          }
        }
      }

      // form checks for this frame
      final idle = dir == 0 && !attempt;
      final ev = _evaluate(lmList, e, per, idle, _frontal(lmList, e), asym);
      _updateWarnings(ev, t);

      // rep state machine (no new rep can start while the rest timer runs)
      if (!attempt && per > 15 && gateOk && !needRest && !resting) {
        attempt = true; // left the top
        repStartTime = t;
        peakPer = 0;
        minAngle = smoothed;
        repFaults.clear();
        squatLike = false;
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
      final reachPer = _isSquat
          ? interp(_lim(e, 'partialAngle', 130), e.downAngle, e.upAngle, 100, 0)
              .clamp(35.0, 100.0)
              .toDouble()
          : (_isDead ? (deadFront ? _lim(e, 'frontReach', 85) : _lim(e, 'sideReach', 90)) : 100.0);
      final holdNeed = _isDead ? (deadFront ? holdSeconds : deadHoldSeconds) : holdSeconds;
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
      final topPer = _isDead ? 12.0 : 0.0;
      var atTop = per <= topPer;
      if (_isDead && dir == 1 && per < 30 && speed < 10) {
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

      if (debugHud) {
        dbg.add('angle ${smoothed.round()}  need ${downA.round()}..${upA.round()}  '
            'min ${minAngle == 999 ? '-' : minAngle.round()}');
        dbg.add('per ${per.round()}  dir $dir  attempt ${attempt ? 1 : 0}  hold ${bottomSince == null ? 0 : 1}');
        if (_isCurl) {
          dbg.add('view ${curlFront ? 'FRONT' : 'side'}  smooth ratio ${dbgSmoothRatio.toStringAsFixed(2)}'
              '${curlFront ? '  wrist-angle ${dbgCurlFront.isFinite ? dbgCurlFront.round() : '-'}' : ''}'
              '${_altMode ? '  next ${altRightNext ? 'R' : 'L'}' : ''}');
        }
        if (_isBench) {
          dbg.add('lying ${gateOk ? 'YES' : 'no'}  src $dbgSrc  tilt ${dbgTilt.round()} '
              'need ${_lim(e, 'lyingTilt', 35).round()}'
              '${dbgRatio >= 0 ? '  ratio ${dbgRatio.toStringAsFixed(1)}' : ''}');
          dbg.add('R arm $rightOk  L arm $leftOk');
        }
        if (_isDead) {
          String n(double? v) => (v == null || !v.isFinite) ? '-' : v.round().toString();
          dbg.add('side ${n(sideRaw)}  front ${n(frontRaw)}  (lower one is used)');
          dbg.add('knee flex ${kneeFlexDbg.round()}  hip flex ${hipFlexDbg.round()}  '
              'squat ${squatLike ? 'YES' : 'no'}');
          dbg.add('view ${deadFront ? 'FRONT' : 'side'}  torso ${n(dbgFrontTorso)}  hands ${n(dbgFrontHands)}  '
              'bottom at per ${reachPer.round()}  leg drop ${legDropDbg.toStringAsFixed(2)}');
        }
      }
      // (the depth bar is a Flutter overlay now, see _depthBar)
    }

    if (debugHud) {
      final maxW = math.max(barX1 - 40 * k - 20, 120.0);
      var dy = h * 0.5;
      for (final s in dbg) {
        put(s, 10, dy, 0.6 * k, formNA, maxW);
        dy += 24 * k;
      }
      ctime = now();
      final dtFrame = ctime - ptime;
      final fps = dtFrame > 0 ? 1 / dtFrame : 0.0;
      ptime = ctime;
      hud.putText('${fps.toInt()}', 10, 70 * k, 2 * k, magenta, 3);
    }

    // redraw the panel under the camera (about 12 times a second is enough)
    if (mounted && t - _lastUi > 0.08) {
      _lastUi = t;
      _ui.value++;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    detector.close();
    _ui.dispose();
    super.dispose();
  }

  // ===================== the panel under the camera =====================

  /// what the feedback card says right now (most important first)
  _Msg _msg(double t) {
    final g = gateMsg;
    if (g != null) {
      final sub = g == 'Show your full body'
          ? 'Step back until head to feet are in view'
          : (g == 'Show shoulder, elbow, wrist' ? 'Keep your arm in view of the camera' : null);
      return _Msg(Icons.warning_amber_rounded, Sp.faultSoft, g, sub);
    }
    if (repLabel.isNotEmpty && t - repLabelTime < 4) {
      final ic = repColor == formGood
          ? Icons.check_circle_outline
          : (repColor == formWarn ? Icons.error_outline : Icons.cancel_outlined);
      return _Msg(ic, repColor, repLabel, repDetail.isEmpty ? null : repDetail);
    }
    if (shown.isNotEmpty) {
      final m = shown.first;
      return _Msg(Icons.warning_amber_rounded, _severeNow(m, t) ? formBad : formWarn, m,
          shown.length > 1 ? shown[1] : null);
    }
    final n = note;
    if (formReady && n != null) return _Msg(Icons.info_outline, Sp.muted, n);
    if (formReady) {
      return formState == 0
          ? const _Msg(Icons.check_circle_outline, formGood, 'Form looks good', 'Keep going')
          : const _Msg(Icons.error_outline, formWarn, 'Check your form');
    }
    return _Msg(Icons.accessibility_new, Sp.muted, inSet ? 'Form not assessable' : 'Start lifting',
        inSet ? 'Show more of your body' : 'Reps are counted automatically');
  }

  String _formWord() {
    if (!formReady) return 'NOT ASSESSABLE';
    if (formScore >= 90 && shown.isEmpty && formState == 0) return 'FLAWLESS';
    return const ['GOOD', 'ADJUST', 'FAULT'][formState.clamp(0, 2)];
  }

  Widget _squareBtn(IconData icon, String tip, VoidCallback onTap) => SizedBox(
        width: 56,
        height: 56,
        child: Tooltip(
          message: tip,
          child: OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(56, 56)),
            child: Icon(icon, size: 24),
          ),
        ),
      );

  /// the panel under the camera: slim by default (bigger camera), the arrow opens the full one
  Widget _bottomPanel() => Container(
        decoration: const BoxDecoration(
          color: Sp.canvas,
          border: Border(top: BorderSide(color: Sp.line)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: SizedBox(
                  height: 22,
                  width: double.infinity,
                  child: Icon(_expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                      color: Sp.muted),
                ),
              ),
              ValueListenableBuilder<int>(
                valueListenable: _ui,
                builder: (_, _, _) => _panelBody(),
              ),
            ]),
          ),
        ),
      );

  Widget _panelBody() => _expanded ? _fullPanel() : _compactPanel();

  /// slim panel: reps, form ring, feedback text, finish button (one row, 56 px)
  Widget _compactPanel() {
    final t = now();
    final msg = _msg(t);
    final fc = _formColor(t);
    return SizedBox(
      height: 56,
      child: Row(children: [
        Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('REPS', style: Sp.labelSm.copyWith(color: Sp.muted)),
          Text('${count.toInt()}', style: Sp.displayMetric.copyWith(fontSize: 30, height: 1, color: Sp.white)),
        ]),
        const SizedBox(width: 12),
        SizedBox(
          width: 44,
          height: 44,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: formReady ? (formScore / 100).clamp(0.0, 1.0).toDouble() : 0.0,
                strokeWidth: 4,
                color: fc,
                backgroundColor: Sp.line,
              ),
            ),
            Text(formReady ? '${formScore.round()}' : '--', style: Sp.labelMd.copyWith(color: Sp.white)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Row(children: [
            Icon(msg.icon, color: msg.color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(msg.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Sp.headlineSm.copyWith(fontSize: 14, color: Sp.white)),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'Finish set',
          child: SizedBox(
            width: 56,
            height: 56,
            child: FilledButton(
              onPressed: _finishSet,
              style: FilledButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(56, 56)),
              child: const Icon(Icons.flag_outlined),
            ),
          ),
        ),
      ]),
    );
  }

  /// full panel (arrow up): chips, feedback card, reps + form score, +/- and finish
  Widget _fullPanel() {
    final t = now();
    final msg = _msg(t);
    final fc = _formColor(t);
    final fat = fatigue, sm = lastSmooth;

    final chips = <Widget>[
      if (inSet)
        SpotChip('Set $setNumber · $setReps reps · ${_mmss(t - setStart)}', dot: Sp.mint)
      else
        SpotChip('Set $setNumber · start lifting', dot: formNA),
      if (_isCurl)
        SpotChip(
            _altMode ? 'Next ${altRightNext ? 'R' : 'L'} · R $repsR · L $repsL' : _armNames[armMode],
            dot: _altMode ? formWarn : Sp.mint),
      if (_isSquat) SpotChip('Partial $partialReps · Deep $deepReps · Extra $extraReps', dot: Sp.mint),
      if (sm != null) SpotChip('Smooth ${sm.round()}', dot: Sp.mint),
      if (inSet && fat != null) SpotChip('Fatigue ${fat.round()}% ${_fatWord(fat)}', dot: _fatColor(fat)),
    ];

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // status chips
      SizedBox(
        height: 32,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: chips.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) => Center(child: chips[i]),
        ),
      ),
      const SizedBox(height: 8),
      // feedback card
      SizedBox(
        height: 64,
        child: SpotCard(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(color: Sp.cardHigh, shape: BoxShape.circle),
              child: Icon(msg.icon, color: msg.color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(msg.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Sp.headlineSm.copyWith(fontSize: 16, color: Sp.white)),
                if (msg.sub != null)
                  Text(msg.sub!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Sp.bodySm.copyWith(color: Sp.muted)),
              ]),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      // reps + form score
      SizedBox(
        height: 100,
        child: Row(children: [
          Expanded(
            flex: 5,
            child: SpotCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('REPS DONE', style: Sp.labelSm.copyWith(color: Sp.muted)),
                Text('${count.toInt()}', style: Sp.displayMetric.copyWith(fontSize: 44, height: 1, color: Sp.white)),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: (curPer / 100).clamp(0.0, 1.0).toDouble(),
                    minHeight: 4,
                    color: fc,
                    backgroundColor: Sp.line,
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: SpotCard(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: formReady ? (formScore / 100).clamp(0.0, 1.0).toDouble() : 0.0,
                        strokeWidth: 5,
                        color: fc,
                        backgroundColor: Sp.line,
                      ),
                    ),
                    Text(formReady ? '${formScore.round()}' : '--',
                        style: Sp.headlineSm.copyWith(color: Sp.white)),
                  ]),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('FORM SCORE', maxLines: 1, style: Sp.labelSm.copyWith(color: Sp.muted, fontSize: 9)),
                    const SizedBox(height: 2),
                    Text(_formWord(), maxLines: 2, style: Sp.labelMd.copyWith(color: fc)),
                  ]),
                ),
              ]),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 8),
      // fix a rep + finish the set
      Row(children: [
        _squareBtn(Icons.remove, 'Remove a rep', () => _adjustRep(-1)),
        const SizedBox(width: 8),
        _squareBtn(Icons.add, 'Add a rep', () => _adjustRep(1)),
        const SizedBox(width: 8),
        Expanded(
          child: SpotButton(setReps > 0 ? 'Finish set · $setReps reps' : 'Finish set',
              icon: Icons.flag_outlined, onPressed: _finishSet),
        ),
      ]),
    ]);
  }

  /// the depth bar, drawn by Flutter on top of the camera (it used to be painted pixel by
  /// pixel on every camera frame). White ticks on a squat: lower = partial, upper = deep.
  Widget _depthBar(Exercise e) => Positioned.fill(
        child: IgnorePointer(
          child: LayoutBuilder(
            builder: (_, c) => ValueListenableBuilder<int>(
              valueListenable: _ui,
              builder: (_, _, _) {
                final top = c.maxHeight * 0.22, hh = c.maxHeight * 0.6;
                final col = _formColor(now());
                final fill = (curPer / 100).clamp(0.0, 1.0).toDouble();
                final ticks = <Widget>[];
                if (_isSquat) {
                  for (final a in [_lim(e, 'partialAngle', 130), _lim(e, 'deepAngle', 110)]) {
                    final pp = interp(a, e.downAngle, e.upAngle, 100, 0).clamp(0.0, 100.0).toDouble();
                    ticks.add(Positioned(
                        right: 12,
                        width: 24,
                        height: 2,
                        top: top + hh * (1 - pp / 100),
                        child: const ColoredBox(color: Colors.white)));
                  }
                }
                return Stack(children: [
                  Positioned(
                    right: 16,
                    width: 16,
                    top: top,
                    height: hh,
                    child: Container(
                      decoration: BoxDecoration(
                          border: Border.all(color: col, width: 2), borderRadius: BorderRadius.circular(4)),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                            heightFactor: fill, widthFactor: 1, child: ColoredBox(color: col)),
                      ),
                    ),
                  ),
                  ...ticks,
                ]);
              },
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final acts = <Widget>[
      _pill(Icons.timer_outlined, 'Timer', 'Rest timer', _restSettings),
      _pill(Icons.school_outlined, '', 'How to do this exercise', _showGuide),
      if (_isBench)
        IconButton(
          tooltip: lyingCheck ? 'Lying check ON (tap to turn off)' : 'Lying check OFF',
          icon: Icon(lyingCheck ? Icons.bed : Icons.bed_outlined),
          color: lyingCheck ? Sp.mint : Sp.outline,
          onPressed: () => setState(() {
            lyingCheck = !lyingCheck;
            lyingSince = null;
            notLyingSince = null;
          }),
        ),
      if (_isCurl)
        PopupMenuButton<int>(
          tooltip: 'Arms',
          initialValue: armMode,
          onSelected: _setArmMode,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 0, child: Text('Right arm')),
            PopupMenuItem(value: 1, child: Text('Left arm')),
            PopupMenuItem(value: 2, child: Text('Both arms')),
            PopupMenuItem(value: 3, child: Text('Alternate: right, left, right...')),
            PopupMenuItem(value: 4, child: Text('Alternate: left, right, left...')),
          ],
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            decoration: BoxDecoration(
              color: Sp.card,
              borderRadius: BorderRadius.circular(Sp.rChip),
              border: Border.all(color: Sp.line),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_armShort[armMode].toUpperCase(), style: Sp.labelMd.copyWith(color: Sp.white)),
              const Icon(Icons.arrow_drop_down, size: 20),
            ]),
          ),
        ),
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _onBack();
      },
      child: Material(
        color: Sp.canvas,
        child: Stack(children: [
          Positioned.fill(
            child: Column(children: [
              Expanded(
                child: Stack(fit: StackFit.expand, children: [
                  CameraView(
                    title: widget.exercise.name,
                    onFrame: onFrame,
                    actions: acts,
                  ),
                  _depthBar(_active),
                ]),
              ),
              _bottomPanel(),
            ]),
          ),
          if (paused) Positioned.fill(child: _pausedOverlay()),
        ]),
      ),
    );
  }
}