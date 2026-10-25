/// Everything the coach can say about form or setup. Each cue has one spoken line per
/// language (see phrase_bank.dart). [priority]: higher = more important. When two
/// problems show at once only the higher one is spoken (safety first).
enum CoachCue {
  // ---------- form warnings (from RepCounter.shown) ----------
  spineNeutral(100),
  kneesCaving(95),
  chestUp(90),
  lowerSlowly(88),
  glutesOnBench(85),
  slowDown(80),
  wristBent(70),
  stackWrist(65),
  elbowsFlared(62),
  tooMuchKneeBend(60),
  swinging(58),
  elbowDrift(55),
  barUneven(52),
  unevenSides(50),
  barPath(48),
  torsoTwist(45),
  leaning(42),
  shrugging(40),
  kneesTooStraight(38),
  elbowsTucked(35),
  stanceNarrow(30),
  stanceWide(30),

  // ---------- setup guidance (RepCounter.gateMsg / note / no person) ----------
  showFullBody(20),
  showArm(20),
  lieOnBench(20),
  upperArmDown(20),
  getInPosition(10),
  noPerson(15),
  checkLight(12),
  turnSideways(8),
  headBackHidden(8),
  flareView(5);

  const CoachCue(this.priority);
  final int priority;

  bool get isSetup => index >= CoachCue.showFullBody.index;

  /// RepCounter warning text -> cue (the counter's English strings stay the source)
  static CoachCue? fromWarning(String m) => _warnings[m];

  /// RepCounter.gateMsg -> cue ("Get in position: 4" has a number in it)
  static CoachCue? fromGate(String g) {
    if (g.startsWith('Get in position')) return CoachCue.getInPosition;
    return _gates[g];
  }

  /// RepCounter.note -> cue (grey hints, only spoken once per workout)
  static CoachCue? fromNote(String n) => _notes[n];

  static const _warnings = <String, CoachCue>{
    'Stance too narrow': CoachCue.stanceNarrow,
    'Stance too wide': CoachCue.stanceWide,
    'Knees caving in': CoachCue.kneesCaving,
    'Elbow drifting forward': CoachCue.elbowDrift,
    'Swinging - stay still': CoachCue.swinging,
    'Leaning - keep still': CoachCue.leaning,
    'Shoulders shrugging': CoachCue.shrugging,
    'Torso twisting': CoachCue.torsoTwist,
    'Chest up - leaning far': CoachCue.chestUp,
    'Keep spine neutral': CoachCue.spineNeutral,
    'Too much knee bend': CoachCue.tooMuchKneeBend,
    'Knees too straight': CoachCue.kneesTooStraight,
    'Elbows flared wide': CoachCue.elbowsFlared,
    'Elbows tucked in': CoachCue.elbowsTucked,
    'Stack wrist over elbow': CoachCue.stackWrist,
    'Wrist bent back': CoachCue.wristBent,
    'Bar path drifting': CoachCue.barPath,
    'Lower slowly - control the bar': CoachCue.lowerSlowly,
    'Keep glutes on the bench': CoachCue.glutesOnBench,
    'Bar uneven': CoachCue.barUneven,
    'Uneven sides': CoachCue.unevenSides,
    'Slow down - control it': CoachCue.slowDown,
  };

  static const _gates = <String, CoachCue>{
    'Show your full body': CoachCue.showFullBody,
    'Show shoulder, elbow, wrist': CoachCue.showArm,
    'Lie on the bench': CoachCue.lieOnBench,
    'Keep your upper arm down': CoachCue.upperArmDown,
  };

  static const _notes = <String, CoachCue>{
    'Facing camera: back not checked (film from the side)': CoachCue.turnSideways,
    'Head/back not visible': CoachCue.headBackHidden,
    'Flare needs head/foot view': CoachCue.flareView,
  };
}

/// result of a finished rep (RepCounter.repLabel)
enum RepResult {
  good,
  deep,
  extraDeep,
  partial,
  partialNotCounted,
  incorrect,
  rejected,
  countedCheckForm,
  incomplete,
  squatNotDeadlift;

  bool get clean => this == good || this == deep || this == extraDeep;

  static RepResult? fromLabel(String label) => switch (label) {
        'Good rep' => RepResult.good,
        'Deep' => RepResult.deep,
        'Extra deep' => RepResult.extraDeep,
        'Partial' => RepResult.partial,
        'Partial - not counted' => RepResult.partialNotCounted,
        'Incorrect' => RepResult.incorrect,
        'Rejected' => RepResult.rejected,
        'Counted - check form' => RepResult.countedCheckForm,
        'Incomplete rep' => RepResult.incomplete,
        'Squat - not a deadlift' => RepResult.squatNotDeadlift,
        _ => null,
      };
}
