import 'package:ai_trainer/features/voice_coach/domain/entities/coach_cue.dart';
import 'package:ai_trainer/features/voice_coach/domain/entities/voice_settings.dart';

/// Every spoken line of the coach, in English and Egyptian Arabic, in one place.
/// To add a language: add a column to the maps below and a value to CoachLanguage.
///
/// The Arabic is written the way people talk in an Egyptian gym (not formal Arabic).
/// With ArabicStyle.gymSlang the English gym words Egyptians use are written in Arabic
/// letters ("ريب", "سِت", "الفورم"), so the Arabic voice pronounces them correctly.
class PhraseBank {
  PhraseBank(this.s);
  final VoiceSettings s;

  bool get _ar => s.arabic;
  CoachPersonality get _p => s.personality;

  // ------------------------------------------------------------------ words

  String get _rep => s.arabicStyle == ArabicStyle.gymSlang ? 'ريب' : 'عدّة';
  String get _reps => s.arabicStyle == ArabicStyle.gymSlang ? 'ريبس' : 'عدّات';
  String get _set => s.arabicStyle == ArabicStyle.gymSlang ? 'سِت' : 'جولة';
  String get _form => s.arabicStyle == ArabicStyle.gymSlang ? 'الفورم' : 'الأداء';

  /// "3 reps" / "تلاتة ريبس"
  String repCount(int n) {
    if (!_ar) return n == 1 ? '1 rep' : '$n reps';
    if (n == 1) return '$_rep واحدة';
    if (n == 2) return s.arabicStyle == ArabicStyle.gymSlang ? 'اتنين $_reps' : 'عدّتين';
    return '${number(n)} $_reps';
  }

  // ------------------------------------------------------------------ numbers

  static const _arUnits = [
    'صفر', 'واحد', 'اتنين', 'تلاتة', 'أربعة', 'خمسة', 'ستة', 'سبعة', 'تمانية', 'تسعة', 'عشرة', //
    'حداشر', 'اتناشر', 'تلتاشر', 'أربعتاشر', 'خمستاشر', 'ستاشر', 'سبعتاشر', 'تمنتاشر', 'تسعتاشر',
  ];
  static const _arTens = ['', '', 'عشرين', 'تلاتين', 'أربعين', 'خمسين', 'ستين', 'سبعين', 'تمانين', 'تسعين'];

  /// a number the way it is said out loud (Egyptian words up to 99)
  String number(int n) {
    if (!_ar) return '$n';
    if (n < 0 || n > 99) return '$n';
    if (n < 20) return _arUnits[n];
    final t = n ~/ 10, u = n % 10;
    return u == 0 ? _arTens[t] : '${_arUnits[u]} و${_arTens[t]}';
  }

  // ------------------------------------------------------------------ cues

  static const _cues = <CoachCue, (String, String)>{
    CoachCue.spineNeutral: ('Keep your back straight', 'خلّي ضهرك مفرود'),
    CoachCue.kneesCaving: ('Push your knees out', 'زُقّ ركبك لبرّه'),
    CoachCue.chestUp: ('Chest up', 'ارفع صدرك'),
    CoachCue.lowerSlowly: ('Lower slowly, control the bar', 'نزّل البار براحة'),
    CoachCue.glutesOnBench: ('Keep your hips on the bench', 'خلّي وسطك لازق في البنش'),
    CoachCue.slowDown: ('Slow down, control it', 'براحة، سيطر على الحركة'),
    CoachCue.wristBent: ('Straighten your wrists', 'افرد رسغك'),
    CoachCue.stackWrist: ('Wrists over elbows', 'خلّي رسغك فوق كوعك'),
    CoachCue.elbowsFlared: ('Tuck your elbows in a bit', 'ضُمّ كوعك شوية لجوّه'),
    CoachCue.tooMuchKneeBend: ('Less knee bend, push your hips back', 'ماتثنيش ركبك أوي، رجّع وسطك لورا'),
    CoachCue.swinging: ('Stop swinging, stay still', 'ماتمرجحش جسمك، اثبت'),
    CoachCue.elbowDrift: ('Pin your elbows to your sides', 'ثبّت كوعك جنبك'),
    CoachCue.barUneven: ('The bar is uneven, push both sides equally', 'البار مايل، ادفع بإيديك الاتنين زي بعض'),
    CoachCue.unevenSides: ('Work both sides evenly', 'شغّل الناحيتين زي بعض'),
    CoachCue.barPath: ('Keep the bar in a straight line', 'خلّي البار ماشي في خط مستقيم'),
    CoachCue.torsoTwist: ("Don't twist, chest facing forward", 'ماتلفّش جسمك، صدرك لقدّام'),
    CoachCue.leaning: ("Don't lean, keep your body still", 'ماتميلش، خلّي جسمك ثابت'),
    CoachCue.shrugging: ('Relax your shoulders down', 'نزّل كتافك وريّحهم'),
    CoachCue.kneesTooStraight: ('Soften your knees a little', 'اثني ركبك سِنّة صغيرة'),
    CoachCue.elbowsTucked: ('Let your elbows open a little', 'افتح كوعك شوية'),
    CoachCue.stanceNarrow: ('Widen your stance', 'وسّع رجليك شوية'),
    CoachCue.stanceWide: ('Bring your feet in a bit', 'قرّب رجليك من بعض شوية'),
    CoachCue.showFullBody: ('Step back, I need to see you from head to feet', 'ارجع لورا شوية، عايز أشوفك من راسك لرجلك'),
    CoachCue.showArm: ('Keep your arm in view of the camera', 'خلّي دراعك باين في الكاميرا'),
    CoachCue.lieOnBench: ('Lie down on the bench to start', 'نام على البنش عشان نبدأ'),
    CoachCue.upperArmDown: ('Keep your upper arm down by your side', 'نزّل دراعك جنبك'),
    CoachCue.getInPosition: ('Get in position', 'خُد وضعك'),
    CoachCue.noPerson: ("I can't see you. Step in front of the camera", 'مش شايفك، تعالى قدّام الكاميرا'),
    CoachCue.checkLight: ("Still can't see you. Move into better light", 'لسه مش شايفك، اقف في مكان منوّر أكتر'),
    CoachCue.turnSideways: ('Turn sideways so I can check your back', 'لِفّ جنبك للكاميرا عشان أقدر أشوف ضهرك'),
    CoachCue.headBackHidden: ("I can't see your head and back", 'مش شايف راسك وضهرك'),
    CoachCue.flareView: ('Film from your head or feet to check your elbows', 'صوّر من ناحية راسك أو رجلك عشان أشوف كوعك'),
  };

  String cue(CoachCue c) {
    final p = _cues[c]!;
    return _ar ? p.$2 : p.$1;
  }

  String _lc(String t) => t.isEmpty ? t : t[0].toLowerCase() + t.substring(1);

  /// a form warning, worded by the coach personality. [repeat] = the user keeps doing it
  String warning(CoachCue c, {bool repeat = false}) {
    final t = cue(c);
    if (c.isSetup || _p == CoachPersonality.minimal) return t;
    if (_ar) {
      if (repeat) {
        return switch (_p) {
          CoachPersonality.calm => 'افتكر، $t',
          CoachPersonality.hype => 'يلا يا بطل، $t!',
          CoachPersonality.strict => 'قُلتلك $t!',
          CoachPersonality.minimal => t,
        };
      }
      return switch (_p) {
        CoachPersonality.calm => t,
        CoachPersonality.hype => '$t، يلا يا وحش!',
        CoachPersonality.strict => '$t، حالًا!',
        CoachPersonality.minimal => t,
      };
    }
    if (repeat) {
      return switch (_p) {
        CoachPersonality.calm => 'Remember, ${_lc(t)}.',
        CoachPersonality.hype => 'Come on, ${_lc(t)}!',
        CoachPersonality.strict => 'I said, ${_lc(t)}!',
        CoachPersonality.minimal => t,
      };
    }
    return switch (_p) {
      CoachPersonality.calm => '$t.',
      CoachPersonality.hype => '$t! Come on!',
      CoachPersonality.strict => '$t. Now!',
      CoachPersonality.minimal => t,
    };
  }

  // ------------------------------------------------------------------ rep results

  /// what is said after a rep. [fault] = the counter's first fault of that rep,
  /// [detail] = RepCounter.repDetail. Returns null when there is nothing worth saying
  /// (a plain good rep: praise is handled separately).
  String? repResult(RepResult r, {CoachCue? fault, String detail = ''}) {
    final f = fault == null ? null : cue(fault);
    switch (r) {
      case RepResult.good:
        return null;
      case RepResult.deep:
        return _ar ? 'عمق ممتاز' : 'Perfect depth';
      case RepResult.extraDeep:
        return _ar ? 'نزلة عميقة جدًا، جامد' : 'Extra deep, great';
      case RepResult.partial:
        return _ar ? 'نُص $_rep، انزل أكتر' : 'Half rep, go lower';
      case RepResult.partialNotCounted:
        return _ar ? 'دي ماتحسبتش، انزل أكتر' : "Too shallow, that one didn't count";
      case RepResult.incorrect:
      case RepResult.rejected:
        if (detail == 'Too shallow - not counted') {
          return _ar ? 'دي ماتحسبتش، انزل أكتر' : "Too shallow, that one didn't count";
        }
        if (f == null) return _ar ? 'دي ماتحسبتش' : "That one didn't count";
        return _ar ? 'دي ماتحسبتش. $f' : "That one didn't count. $f";
      case RepResult.countedCheckForm:
        if (f == null) return null;
        return _ar ? 'اتحسبت، بس $f' : 'Counted, but ${_lc(f)}';
      case RepResult.incomplete:
        return switch (detail) {
          'Curl through full range' =>
            _ar ? 'كمّل الحركة للآخر، طالع ونازل' : 'Full range, all the way up and all the way down',
          'Lower to chest, lock out' =>
            _ar ? 'نزّل البار لصدرك وبعدين افرد دراعك للآخر' : 'Bar to your chest, then lock out',
          'Hinge fully, then lock out' =>
            _ar ? 'انزل للآخر وبعدين اقف مفرود' : 'Hinge all the way, then stand tall',
          _ => _ar ? '$_rep مش كاملة' : 'Incomplete rep',
        };
      case RepResult.squatNotDeadlift:
        return _ar ? 'دي كانت سكوات مش ديدليفت، اتني من وسطك' : 'That was a squat. Hinge at your hips';
    }
  }

  // ------------------------------------------------------------------ praise / motivation

  static const _praise = <CoachPersonality, (List<String>, List<String>)>{
    CoachPersonality.calm: (
      ['Nice rep', 'Good, keep it smooth', 'Well done'],
      ['حلو', 'كده تمام، كمّل بهدوء', 'برافو عليك'],
    ),
    CoachPersonality.hype: (
      ['Yes! Beautiful rep!', "That's it, let's go!", 'Strong!'],
      ['أيوه كده! جامد!', 'يلا يا وحش!', 'قوي يا بطل!'],
    ),
    CoachPersonality.strict: (
      ['Good. Next.', 'Acceptable. Keep going.', 'Better.'],
      ['تمام، اللي بعدها', 'ماشي، كمّل', 'أحسن'],
    ),
    CoachPersonality.minimal: (['Good'], ['تمام']),
  };

  String praise(int i) {
    final p = _praise[_p]!;
    final l = _ar ? p.$2 : p.$1;
    return l[i % l.length];
  }

  /// bench press: a good rep that was lowered under control
  String get controlled => _ar ? 'حلو، نازل براحة' : 'Nice and controlled';

  String _byP(List<String> en, List<String> ar) {
    final l = _ar ? ar : en;
    return l[switch (_p) {
      CoachPersonality.calm || CoachPersonality.minimal => 0,
      CoachPersonality.hype => 1,
      CoachPersonality.strict => 2,
    }];
  }

  String get twoMore => _byP(
        ['Two more', 'Two more! Push!', 'Two more. No excuses.'],
        ['كمان اتنين', 'كمان اتنين! يلا!', 'كمان اتنين، مفيش أعذار'],
      );

  String get lastOne => _byP(
        ['Last one', 'Last one! Make it count!', 'Last one. Perfect form.'],
        ['آخر واحدة', 'آخر واحدة! خلّيها جامدة!', 'آخر واحدة، $_form يكون مظبوط'],
      );

  String get goalReached => _byP(
        ["That's your goal", 'Goal smashed!', 'Goal done.'],
        ['وصلت للهدف', 'كسّرت الهدف!', 'الهدف خلص'],
      );

  String get fatigue => _ar ? 'بدأت تتعب، ركّز على $_form' : "You're slowing down, keep your form tight";

  // ------------------------------------------------------------------ sets / rest

  String setSummary({required int reps, required int clean, int? form, CoachCue? topFault}) {
    final b = StringBuffer();
    if (_ar) {
      b.write(repCount(reps));
      if (clean < reps) b.write('، منهم ${number(clean)} نُضاف');
      b.write('.');
      if (form != null) b.write(' $_form ${number(form)}.');
      if (topFault != null) b.write(' الـ$_set الجاية خلّي بالك: ${cue(topFault)}.');
      if (_p == CoachPersonality.hype) b.write(' $_set جامد!');
      if (_p == CoachPersonality.strict) b.write(' ارتاح، واللي جاية أحسن.');
    } else {
      b.write(repCount(reps));
      if (clean < reps) b.write(', $clean clean');
      b.write('.');
      if (form != null) b.write(' Form $form.');
      if (topFault != null) b.write(' Next set, watch this: ${_lc(cue(topFault))}.');
      if (_p == CoachPersonality.hype) b.write(' Great set!');
      if (_p == CoachPersonality.strict) b.write(' Rest up. Next one better.');
    }
    return b.toString();
  }

  /// one tip during the rest, from the most common fault of the set
  String restTip(CoachCue c) => _ar ? 'نصيحة للـ$_set الجاية: ${cue(c)}' : 'Tip for the next set: ${_lc(cue(c))}';

  String restLeft(int seconds) {
    if (seconds <= 10) return _ar ? 'فاضل ${number(seconds)} ثواني، جهّز نفسك' : '$seconds seconds, get ready';
    return _ar ? 'فاضل ${number(seconds)} ثانية' : '$seconds seconds left';
  }

  String restOver(int nextSet, {required bool commands}) {
    if (_ar) {
      final t = 'الراحة خلصت. جاهز للـ$_set رقم ${number(nextSet)}؟';
      return commands ? '$t قول يلا، أو وقت زيادة' : t;
    }
    final t = 'Rest is over. Ready for set $nextSet?';
    return commands ? '$t Say next, or more time.' : t;
  }

  String setStarting(int n) => _ar ? 'الـ$_set رقم ${number(n)}' : 'Set $n';

  String get go => _byP(['Go', 'Go go go!', 'Go!'], ['يلا', 'يلا بينا!', 'ابدأ!']);

  // ------------------------------------------------------------------ celebrations

  String personalBestReps(int n) => _ar ? 'رقم قياسي جديد! ${repCount(n)}!' : 'New personal best, $n reps!';

  String personalBestForm(int f) =>
      _ar ? 'أحسن $_form ليك لحد دلوقتي، ${number(f)} في المية!' : 'Your best form yet, $f percent!';

  // ------------------------------------------------------------------ misc

  String formScore(int f) => _ar ? '$_form ${number(f)}' : 'Form $f';

  String countReport(int setReps) =>
      _ar ? '${repCount(setReps)} في الـ$_set ده' : '${repCount(setReps)} this set';

  String get muted => _ar ? 'الكوتش هيسكت' : 'Coach muted';
  String get unmuted => _ar ? 'الكوتش رجع' : 'Coach is back';
  String get listening => _ar ? 'سامعك' : 'Listening';

  static const _arNames = <String, (String, String)>{
    // (gym slang, plain)
    'Biceps Curl': ('بايسبس كيرل', 'تمرين الباي'),
    'Squat': ('سكوات', 'سكوات'),
    'Deadlift': ('ديدليفت', 'ديدليفت'),
    'Bench Press': ('بنش بريس', 'ضغط البنش'),
    'Sumo Deadlift': ('سومو ديدليفت', 'ديدليفت سومو'),
    'Romanian Deadlift': ('رومانيان ديدليفت', 'ديدليفت روماني'),
  };

  String exerciseName(String name) {
    if (!_ar) return name;
    final n = _arNames[name];
    if (n == null) return name;
    return s.arabicStyle == ArabicStyle.gymSlang ? n.$1 : n.$2;
  }

  String start(String exercise) {
    final e = exerciseName(exercise);
    if (_ar) {
      return switch (_p) {
        CoachPersonality.hype => '$e! يلا يا وحش، وريني!',
        CoachPersonality.strict => '$e. ركّز، ومن غير غلط.',
        _ => '$e، يلا نبدأ',
      };
    }
    return switch (_p) {
      CoachPersonality.hype => "$e! Let's go, show me what you've got!",
      CoachPersonality.strict => '$e. Focus. No sloppy reps.',
      _ => "$e. Let's start.",
    };
  }

  /// accessibility mode: where to put the phone (same advice as the How-to guide)
  String cameraSetup(String exercise) {
    if (exercise.contains('Curl')) {
      return _ar
          ? 'حُطّ الموبايل على مستوى وسطك، على بُعد مترين لتلاتة، وصوّر من الجنب عشان دراعك ووسطك يبانوا.'
          : 'Place the phone at hip height, two to three meters away, and film from the side.';
    }
    if (exercise.contains('Squat')) {
      return _ar
          ? 'حُطّ الموبايل على بُعد تلاتة متر على مستوى وسطك، لازم جسمك كله يبان لحد رجلك.'
          : 'Place the phone about three meters away at hip height, with your whole body in view.';
    }
    if (exercise.contains('Deadlift')) {
      return _ar
          ? 'صوّر من الجنب على مستوى وسطك، وابعد لحد ما راسك ورجلك يبانوا.'
          : 'Film from the side at hip height, far enough that your head and feet are in view.';
    }
    return _ar
        ? 'صوّر من الجنب أو من ناحية راس البنش، على مستوى البنش.'
        : 'Film from the side or from the head end of the bench, at bench height.';
  }

  /// the "Test voice" button in the settings
  String get sample {
    final w = warning(CoachCue.kneesCaving);
    return _ar ? '$w. ${number(5)}. عمق ممتاز. ${praise(0)}' : '$w 5. Perfect depth. ${praise(0)}';
  }
}
