import 'dart:math' as math;

/// Sets and fatigue of one workout. The USER ends a set with the flag button; a set
/// starts at its first counted rep.
class SetTracker {
  bool inSet = false; // lifting in the current set (starts at the first counted rep)
  int setNumber = 1; // the set you are doing now
  int setReps = 0, lastSetReps = 0;
  final setHistory = <int>[]; // reps of each finished set, shown under the camera
  double setStart = 0, lastRepEnd = -99, lastSetSecs = 0;
  final setDurs = <double>[]; // per rep of the current set
  final setRoms = <double>[];
  final setForms = <double>[];
  double? fatigue; // 0..100, null until 3 reps are done

  /// average form score of the set, null before the first rep
  double? get formAverage => setForms.isEmpty ? null : setForms.reduce((a, b) => a + b) / setForms.length;

  void _start(double at) {
    inSet = true;
    setStart = at;
    setReps = 0;
    setDurs.clear();
    setRoms.clear();
    setForms.clear();
    fatigue = null;
  }

  /// a counted rep that ended at [t] and took [dur] seconds belongs to the current set
  void addRep(double t, double dur, {required double rom, required double form}) {
    if (!inSet) _start(t - dur);
    setReps++;
    lastRepEnd = t;
    setDurs.add(dur);
    setRoms.add(rom);
    setForms.add(form);
    _updateFatigue();
  }

  /// +1 button: a rep the camera missed (no duration, range or form for it)
  void addManualRep(double t) {
    if (!inSet) _start(t);
    setReps++;
    lastRepEnd = t;
  }

  /// -1 button: a rep the camera added
  void removeRep() {
    if (setReps > 0) setReps--;
    if (setDurs.isNotEmpty) setDurs.removeLast();
    if (setRoms.isNotEmpty) setRoms.removeLast();
    if (setForms.isNotEmpty) setForms.removeLast();
    _updateFatigue();
    if (setReps == 0) inSet = false;
  }

  /// Finish set: the set ends and the rest screen opens
  void end() {
    inSet = false;
    lastSetReps = setReps;
    lastSetSecs = math.max(0.0, lastRepEnd - setStart); // first rep to last counted rep
  }

  /// Stop timer: back to the camera, still in the SAME set (the rest time is not counted in it)
  void resume(double restedSeconds) {
    if (setReps > 0) {
      setStart += restedSeconds;
      lastRepEnd += restedSeconds;
      inSet = true;
    }
  }

  /// the next set starts empty (from 0); the finished set's reps are kept in [setHistory]
  void next() {
    if (setReps > 0) {
      setHistory.add(setReps);
      setNumber++;
    }
    setReps = 0;
    inSet = false;
    setDurs.clear();
    setRoms.clear();
    setForms.clear();
    fatigue = null;
  }

  void reset() {
    inSet = false;
    setNumber = 1;
    setReps = 0;
    lastSetReps = 0;
    setHistory.clear();
    setStart = 0;
    lastRepEnd = -99;
    lastSetSecs = 0;
    setDurs.clear();
    setRoms.clear();
    setForms.clear();
    fatigue = null;
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
}
