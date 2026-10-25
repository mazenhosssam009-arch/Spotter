import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:ai_trainer/core/utils/cv_math.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/exercise.dart';
import 'package:ai_trainer/features/pose_coaching/domain/services/rep_counter.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/bloc/trainer_bloc/trainer_bloc.dart';
import 'package:ai_trainer/features/voice_coach/data/datasources/phrase_bank.dart';
import 'package:ai_trainer/features/voice_coach/data/datasources/tts_engine.dart';
import 'package:ai_trainer/features/voice_coach/data/datasources/voice_command_listener.dart';
import 'package:ai_trainer/features/voice_coach/data/datasources/voice_settings_store.dart';
import 'package:ai_trainer/features/voice_coach/domain/entities/coach_cue.dart';
import 'package:ai_trainer/features/voice_coach/domain/entities/voice_settings.dart';
import 'package:ai_trainer/features/voice_coach/presentation/cubit/voice_settings_cubit.dart';

/// one thing to say
class _Utterance {
  _Utterance(this.text, this.priority, {required this.maxAge, this.key, this.force = false});
  final String text;
  final bool force; // said even when muted (the user asked a question)
  final int priority;
  final double maxAge; // seconds; older = no longer relevant, dropped
  final String? key; // same key replaces the queued one
  final double created = now();
}

/// The voice coach of one workout. It watches the TrainerBloc and decides what to say:
/// - form warnings by severity: a clear fault (one that rejects the rep) is said at once
///   and may interrupt; a smaller one only when it lasts 1 s or keeps coming back
/// - a cooldown per warning (7 s) and a short gap between warnings, so it never spams;
///   when the user keeps doing it the wording changes ("Remember, ...")
/// - only the most important problem is said when there are several (safety first)
/// - rep counts, rep results (deep / partial / not counted), rep-goal motivation
/// - setup guidance, rest countdown, set summary with a tip, personal bests
/// - voice commands (handled by the trainer screen through [commands])
class VoiceCoach {
  VoiceCoach({
    required this.settings,
    required this.engine,
    required this.store,
    required this.listener,
  });

  final VoiceSettingsCubit settings;
  final TtsEngine engine;
  final VoiceSettingsStore store;
  final VoiceCommandListener listener;

  // priorities (higher is said first)
  static const _pSafety = 100, _pCountdown = 90, _pWarn = 70, _pRep = 60, _pSetup = 50, _pInfo = 40, _pPraise = 20;

  final _queue = <_Utterance>[];
  bool _busy = false;
  int _currentPriority = 0;

  final _commandsOut = StreamController<VoiceCommand>.broadcast();
  StreamSubscription<TrainerState>? _stateSub;
  StreamSubscription<VoiceSettings>? _settingsSub;
  StreamSubscription<VoiceCommand>? _cmdSub;
  TrainerBloc? _bloc;
  late Exercise _exercise;

  /// muted for this workout only (the speaker button / "mute" command)
  final muted = ValueNotifier<bool>(false);

  /// commands the trainer screen carries out (finish set, next, more time...)
  Stream<VoiceCommand> get commands => _commandsOut.stream;

  VoiceSettings get _s => settings.state;
  PhraseBank get _say => PhraseBank(_s);
  bool get _on => _s.enabled && !muted.value;
  bool _atLeast(CoachVerbosity v) => _on && _s.verbosity.index >= v.index;

  /// the coach says the 3-2-1 itself, so the screen can skip its click sound
  bool get speaksCountdown => _atLeast(CoachVerbosity.warningsReps);

  // ------------------------------------------------------------------ tracking state

  WorkoutPhase _phase = WorkoutPhase.active;
  bool _restFinished = false;
  double _lastCount = 0;
  double _lastRepLabelTime = -99;
  int _lastReadySec = -1;
  final _restSaid = <int>{};

  // warnings
  final _shownSince = <String, double>{};
  final _lastSpoken = <CoachCue, double>{};
  final _spokenTimes = <CoachCue, List<double>>{};
  final _appearances = <CoachCue, List<double>>{};
  double _lastWarningAt = -99;

  // setup
  CoachCue? _lastGate;
  double _gateSpokenAt = -99;
  final _notesSaid = <CoachCue>{};
  double? _noPersonSince;
  bool _saidNoPerson = false, _saidLight = false;

  // this set
  final _setFaults = <CoachCue, int>{};
  int _setClean = 0, _setLabeled = 0, _goodStreak = 0, _praiseIdx = 0;
  bool _fatigueSaid = false;

  // ------------------------------------------------------------------ lifecycle

  void attach(TrainerBloc bloc, Exercise exercise) {
    _bloc = bloc;
    _exercise = exercise;
    _stateSub = bloc.stream.listen(_onState, onError: (Object e) => debugPrint('voice coach: $e'));
    _settingsSub = settings.stream.listen(_onSettings);
    _cmdSub = listener.commands.listen(_onCommand);
    engine.speaking.addListener(_onSpeaking);
    engine.apply(_s);
    if (_s.voiceCommands) {
      listener.start(_s.language);
      _listenLang = _s.language;
    }

    if (_atLeast(CoachVerbosity.full) || (_on && _s.accessibility)) {
      _enqueue(_say.start(exercise.name), _pInfo, maxAge: 10);
    }
    if (_on && _s.accessibility) _enqueue(_say.cameraSetup(exercise.name), _pInfo, maxAge: 20);
  }

  Future<void> dispose() async {
    engine.speaking.removeListener(_onSpeaking);
    await _stateSub?.cancel();
    await _settingsSub?.cancel();
    await _cmdSub?.cancel();
    _queue.clear();
    await listener.stop();
    await engine.stop();
    await _commandsOut.close();
    muted.dispose();
  }

  CoachLanguage? _listenLang;

  void _onSettings(VoiceSettings s) {
    if (s.voiceCommands && listener.active && _listenLang != s.language) {
      // new language: listen for the commands of that language
      listener.stop().then((_) => listener.start(s.language));
      _listenLang = s.language;
    }
    if (s.voiceCommands && !listener.active) {
      listener.start(s.language);
      _listenLang = s.language;
    }
    if (!s.voiceCommands && listener.active) listener.stop();
    if (!s.enabled) _silence();
  }

  void _onSpeaking() {
    if (!listener.active) return;
    engine.speaking.value ? listener.pause() : listener.resume();
  }

  void toggleMute() {
    if (muted.value) {
      muted.value = false;
      _enqueue(_say.unmuted, _pCountdown, maxAge: 3);
    } else {
      _silence();
      muted.value = true;
      if (_s.enabled) _enqueue(_say.muted, _pCountdown, maxAge: 3, force: true);
    }
  }

  void _silence() {
    _queue.clear();
    engine.stop();
  }

  // ------------------------------------------------------------------ commands

  void _onCommand(VoiceCommand c) {
    switch (c) {
      case VoiceCommand.mute:
        if (!muted.value) toggleMute();
      case VoiceCommand.unmute:
        if (muted.value) toggleMute();
      case VoiceCommand.howMany:
        final reps = _bloc?.state.counter?.setReps ?? 0;
        // the user asked: answer even when muted
        if (_s.enabled) _enqueue(_say.countReport(reps), _pCountdown, maxAge: 4, force: true);
      default:
        if (!_commandsOut.isClosed) _commandsOut.add(c);
    }
  }

  // ------------------------------------------------------------------ speaking queue

  void _enqueue(String text, int priority,
      {double maxAge = 3, String? key, bool interrupt = false, bool force = false}) {
    if (text.trim().isEmpty || !(_on || force)) return;
    if (key != null) _queue.removeWhere((u) => u.key == key);
    _queue.add(_Utterance(text, priority, maxAge: maxAge, key: key, force: force));
    // a clear fault cuts off less important talk (a rep count, praise, a summary)
    if (interrupt && _busy && priority > _currentPriority) {
      engine.stop();
    }
    _pump();
  }

  Future<void> _pump() async {
    if (_busy) return;
    _busy = true;
    try {
      while (_queue.isNotEmpty) {
        _queue.sort((a, b) => b.priority - a.priority);
        final u = _queue.removeAt(0);
        if (now() - u.created > u.maxAge || !(_on || u.force)) continue;
        _currentPriority = u.priority;
        await engine.speak(u.text);
      }
    } finally {
      _busy = false;
      _currentPriority = 0;
    }
  }

  // ------------------------------------------------------------------ the workout

  void _onState(TrainerState st) {
    final c = st.counter;
    if (c == null) return;
    final t = now();

    if (st.phase != _phase) _onPhaseChange(_phase, st, c);
    _phase = st.phase;

    if (st.resting) {
      _onRest(st, c);
    } else if (st.getReady) {
      _onGetReady(st);
    } else {
      _onActive(st, c, t);
    }
    _restFinished = st.restFinished;
  }

  void _onPhaseChange(WorkoutPhase from, TrainerState st, RepCounter c) {
    if (st.phase == WorkoutPhase.resting && from == WorkoutPhase.active) {
      _queue.removeWhere((u) => u.priority <= _pWarn); // old warnings are over
      _restSaid.clear();
      _onSetEnd(st, c);
    } else if (st.phase == WorkoutPhase.getReady) {
      _lastReadySec = -1;
      _resetSet();
      if (_on && _s.accessibility) _enqueue(_say.setStarting(c.setNumber), _pCountdown, maxAge: 3);
    } else if (st.phase == WorkoutPhase.active && from == WorkoutPhase.getReady) {
      if (_atLeast(CoachVerbosity.warningsReps)) _enqueue(_say.go, _pCountdown, maxAge: 2);
      _lastCount = c.count;
      _lastRepLabelTime = c.repLabelTime;
    }
  }

  void _resetSet() {
    _setFaults.clear();
    _setClean = 0;
    _setLabeled = 0;
    _goodStreak = 0;
    _fatigueSaid = false;
    _shownSince.clear();
  }

  // ---------------------------------------------------------- end of a set

  void _onSetEnd(TrainerState st, RepCounter c) {
    final reps = c.lastSetReps;
    if (reps <= 0) return;
    final name = _exercise.name;
    final form = c.setForms.length >= 3 ? c.setFormAverage?.round() : null;

    // personal bests are always saved, and celebrated in the full mode
    final bestReps = store.bestReps(name);
    final newRepsPb = reps > bestReps;
    if (newRepsPb) store.setBestReps(name, reps);
    final bestForm = store.bestForm(name);
    final newFormPb = form != null && form > bestForm;
    if (form != null && newFormPb) store.setBestForm(name, form);

    if (!_atLeast(CoachVerbosity.warningsReps)) return;
    if (!_atLeast(CoachVerbosity.full)) {
      _enqueue(_say.repCount(reps), _pInfo, maxAge: 8);
      return;
    }

    // the most common fault of the set (ties: the more dangerous one)
    CoachCue? top;
    var topN = 0;
    for (final e in _setFaults.entries) {
      final cur = top;
      if (e.value > topN || (e.value == topN && cur != null && e.key.priority > cur.priority)) {
        top = e.key;
        topN = e.value;
      }
    }
    if (topN < 2) top = null; // one slip is not a pattern
    final clean = _setLabeled == 0 ? reps : _setClean.clamp(0, reps);
    _enqueue(_say.setSummary(reps: reps, clean: clean, form: form, topFault: top), _pInfo, maxAge: 10);

    if (newRepsPb && bestReps > 0) {
      _enqueue(_say.personalBestReps(reps), _pInfo, maxAge: 15);
    } else if (form != null && newFormPb && bestForm > 0) {
      _enqueue(_say.personalBestForm(form), _pInfo, maxAge: 15);
    }
    if (top != null) _enqueue(_say.restTip(top), _pPraise, maxAge: 30);
    if (_s.accessibility) _enqueue(_say.restLeft(st.restSeconds.round()), _pPraise, maxAge: 30);
  }

  // ---------------------------------------------------------- rest / 3-2-1

  void _onRest(TrainerState st, RepCounter c) {
    if (st.restFinished && !_restFinished) {
      if (_atLeast(CoachVerbosity.warningsReps)) {
        _enqueue(_say.restOver(c.setNumber + 1, commands: _s.voiceCommands), _pCountdown,
            maxAge: 6, key: 'rest');
      }
      return;
    }
    if (st.restFinished || !_atLeast(CoachVerbosity.full)) return;
    final left = ((st.restEndMs - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
    final total = st.restTotalMs / 1000;
    for (final mark in const [30, 10]) {
      if (left == mark && total > mark + 8 && _restSaid.add(mark)) {
        _enqueue(_say.restLeft(mark), _pCountdown, maxAge: 2, key: 'rest');
      }
    }
  }

  void _onGetReady(TrainerState st) {
    if (!_atLeast(CoachVerbosity.warningsReps)) return;
    final left = ((st.readyEndMs - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
    if (left <= 0 || left == _lastReadySec) return;
    _lastReadySec = left;
    _enqueue(_say.number(left), _pCountdown, maxAge: 0.9, key: 'ready', interrupt: true);
  }

  // ---------------------------------------------------------- lifting

  void _onActive(TrainerState st, RepCounter c, double t) {
    _onRep(c, t);
    _onSetup(st, c, t);
    _onWarnings(c, t);
    final f = c.fatigue;
    if (!_fatigueSaid && f != null && f >= 60 && c.setReps >= 4) {
      _fatigueSaid = true;
      if (_atLeast(CoachVerbosity.full)) _enqueue(_say.fatigue, _pInfo, maxAge: 4);
    }
  }

  bool _countThis(int n) {
    final goal = _s.repGoal;
    return switch (_s.countStyle) {
      CountStyle.everyRep => true,
      CountStyle.milestones => n % 5 == 0,
      CountStyle.nearGoal => goal <= 0 || n >= goal - 2,
    };
  }

  void _onRep(RepCounter c, double t) {
    final counted = c.count > _lastCount;
    _lastCount = c.count;
    final labelNew = c.repLabelTime != _lastRepLabelTime && c.repLabel.isNotEmpty;
    _lastRepLabelTime = c.repLabelTime;
    if (!counted && !labelNew) return;

    final parts = <String>[];
    var priority = _pRep;
    final n = c.setReps;

    if (counted && _atLeast(CoachVerbosity.warningsReps) && _countThis(n)) parts.add(_say.number(n));

    if (labelNew) {
      final r = RepResult.fromLabel(c.repLabel);
      final fault = CoachCue.fromWarning(c.repDetail);
      if (r != null) {
        _setLabeled++;
        if (r.clean) {
          _setClean++;
          _goodStreak++;
        } else {
          _goodStreak = 0;
        }
        if (fault != null) {
          _setFaults[fault] = (_setFaults[fault] ?? 0) + 1;
          _lastSpoken[fault] = t; // said with the rep: no separate warning right after
        }
        final text = _say.repResult(r, fault: fault, detail: c.repDetail);
        if (text != null) {
          if (!r.clean && _atLeast(CoachVerbosity.warnings)) {
            parts.add(text);
            priority = _pWarn;
          } else if (r.clean && _atLeast(CoachVerbosity.warningsReps)) {
            parts.add(text);
          }
        } else if (r.clean && _atLeast(CoachVerbosity.full) && _goodStreak % 3 == 0) {
          // praise now and then, not on every rep
          parts.add(c.isBench && _praiseIdx.isOdd ? _say.controlled : _say.praise(_praiseIdx));
          _praiseIdx++;
        }
      }
    }

    final goal = _s.repGoal;
    if (counted && goal > 0 && _atLeast(CoachVerbosity.warningsReps)) {
      if (n == goal - 2) parts.add(_say.twoMore);
      if (n == goal - 1) parts.add(_say.lastOne);
      if (n == goal) parts.add(_say.goalReached);
    }
    if (counted && _on && _s.accessibility && n > 0 && n % 5 == 0 && c.formReady) {
      parts.add(_say.formScore(c.formScore.round()));
    }

    if (parts.isNotEmpty) _enqueue(parts.join('. '), priority, maxAge: 1.8, key: 'rep');
  }

  void _onSetup(TrainerState st, RepCounter c, double t) {
    if (!_atLeast(CoachVerbosity.warnings)) return;

    // nobody in the picture (st.pose == null: the camera has not started yet)
    final pose = st.pose;
    if (pose != null && !pose.hasPerson) {
      _noPersonSince ??= t;
      final away = t - _noPersonSince!;
      if (away >= 4 && !_saidNoPerson) {
        _saidNoPerson = true;
        _enqueue(_say.cue(CoachCue.noPerson), _pSetup, maxAge: 3, key: 'setup');
      } else if (away >= 12 && !_saidLight) {
        _saidLight = true;
        _enqueue(_say.cue(CoachCue.checkLight), _pSetup, maxAge: 3, key: 'setup');
      }
      return;
    }
    if (pose != null) {
      _noPersonSince = null;
      _saidNoPerson = false;
      _saidLight = false;
    }

    // wrong position: step back, lie on the bench, arm down, 5 s to get in position
    final gate = c.gateMsg;
    final cue = gate == null ? null : CoachCue.fromGate(gate);
    if (cue != _lastGate) {
      if (cue != null && (cue != CoachCue.getInPosition || _lastGate == null)) {
        _enqueue(_say.cue(cue), _pSetup, maxAge: 3, key: 'setup');
        _gateSpokenAt = t;
      }
      // the 5 s setup is over: start
      if (_lastGate == CoachCue.getInPosition && cue == null && _atLeast(CoachVerbosity.warningsReps)) {
        _enqueue(_say.go, _pCountdown, maxAge: 2, key: 'setup');
      }
      _lastGate = cue;
    } else if (cue != null && cue != CoachCue.getInPosition && t - _gateSpokenAt > 12) {
      // still in the wrong position: remind every 12 s
      _enqueue(_say.cue(cue), _pSetup, maxAge: 3, key: 'setup');
      _gateSpokenAt = t;
    }

    // grey hints about the camera angle: once per workout
    final note = c.note;
    final nc = note == null ? null : CoachCue.fromNote(note);
    if (nc != null && !_notesSaid.contains(nc)) {
      final worth = nc == CoachCue.flareView
          ? (_atLeast(CoachVerbosity.full) || _s.accessibility)
          : _atLeast(CoachVerbosity.warningsReps);
      if (worth && c.formReady) {
        _notesSaid.add(nc);
        _enqueue(_say.cue(nc), _pSetup, maxAge: 4);
      }
    }
  }

  void _onWarnings(RepCounter c, double t) {
    // forget warnings that are gone
    _shownSince.removeWhere((m, _) => !c.shown.contains(m));
    if (c.gateMsg != null) return; // a position problem is said instead

    CoachCue? best;
    var bestSevere = false;
    for (final m in c.shown) {
      final cue = CoachCue.fromWarning(m);
      if (cue == null) continue;
      if (!_shownSince.containsKey(m)) {
        _shownSince[m] = t;
        _appearances.putIfAbsent(cue, () => <double>[]).add(t);
        if (c.inSet) _setFaults[cue] = (_setFaults[cue] ?? 0) + 1;
      }
      final severe = c.isSevere(m, t);
      final lasting = t - _shownSince[m]! >= 1.0;
      final apps = _appearances.putIfAbsent(cue, () => <double>[])..removeWhere((x) => t - x > 20);
      final recurring = apps.length >= 2;
      if (!(severe || lasting || recurring)) continue;
      if (t - (_lastSpoken[cue] ?? -99) < 7) continue; // cooldown per warning
      final better = best == null ||
          (severe && !bestSevere) ||
          (severe == bestSevere && cue.priority > best.priority);
      if (better) {
        best = cue;
        bestSevere = severe;
      }
    }
    if (best == null || !_atLeast(CoachVerbosity.warnings)) return;
    if (t - _lastWarningAt < 2.5) return; // a short gap between two warnings

    final times = _spokenTimes.putIfAbsent(best, () => <double>[])..removeWhere((x) => t - x > 45);
    final repeat = times.isNotEmpty;
    times.add(t);
    _lastSpoken[best] = t;
    _lastWarningAt = t;
    _enqueue(
      _say.warning(best, repeat: repeat),
      bestSevere ? _pSafety : _pWarn,
      maxAge: 1.5,
      key: 'warn',
      interrupt: bestSevere,
    );
  }
}
