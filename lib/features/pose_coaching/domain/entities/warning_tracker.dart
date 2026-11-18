import 'package:ai_trainer/features/pose_coaching/domain/entities/form_evaluation.dart';

/// Turns the form checks of every frame into the warnings the user sees: a problem is
/// only shown after it lasted [delay] and is kept [hold] after it is gone, so nothing
/// flickers. Also remembers which warnings are clear faults (they reject the rep).
class WarningTracker {
  static const delay = 0.25; // a problem must last this long to be shown
  static const hold = 0.6; // and stays this long after it is gone

  final _first = <String, double>{};
  final _last = <String, double>{};
  final _severe = <String, double>{};

  /// warnings that passed the debounce, most important first
  final shown = <String>[];

  /// small grey hint of the last frame ("flare unchecked")
  String? note;

  /// true when warning [m] is a clear fault right now (it rejects the rep)
  bool isSevere(String m, double t) => t - (_severe[m] ?? -99) <= hold;

  void update(FormEvaluation ev, double t) {
    for (final m in ev.warns) {
      _first.putIfAbsent(m, () => t);
      _last[m] = t;
    }
    for (final m in ev.blocking) {
      _severe[m] = t;
    }
    final drop = <String>[];
    _last.forEach((m, last) {
      if (t - last > hold) drop.add(m);
    });
    for (final m in drop) {
      _last.remove(m);
      _first.remove(m);
    }
    shown.clear();
    for (final m in _last.keys) {
      if (_last[m]! - _first[m]! >= delay) shown.add(m);
    }
    note = ev.note;
  }

  void clear() {
    _first.clear();
    _last.clear();
    _severe.clear();
    shown.clear();
    note = null;
  }
}
