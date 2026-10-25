// Makes the Egyptian Arabic voice clips of the voice coach, once, with Microsoft Azure
// (voices ar-EG-ShakirNeural = male, ar-EG-SalmaNeural = female).
//
// Run from the project folder (where pubspec.yaml is):
//   dart run tool/make_egyptian_voice.dart --key YOUR_AZURE_KEY --region YOUR_REGION
//
// It writes assets/voice/ar_eg/male/*.mp3, female/*.mp3 and manifest.json.
// Run it again after changing Arabic text in phrase_bank.dart: only new pieces are made,
// and clips nobody uses any more are deleted. Never commit your key.
//
// No Azure account? Only write the list of pieces, then record them with the free
// Edge voices (same Shakir / Salma) using tool/make_egyptian_voice_edge.py:
//   dart run tool/make_egyptian_voice.dart --list
//   python tool/make_egyptian_voice_edge.py

import 'dart:convert';
import 'dart:io';

import 'package:ai_trainer/features/voice_coach/data/datasources/clip_text.dart';
import 'package:ai_trainer/features/voice_coach/data/datasources/phrase_bank.dart';
import 'package:ai_trainer/features/voice_coach/domain/entities/coach_cue.dart';
import 'package:ai_trainer/features/voice_coach/domain/entities/voice_settings.dart';

/// every Arabic piece the coach can say (all personalities, both Arabic styles)
Set<String> allPieces() {
  final texts = <String>[];
  const exercises = ['Biceps Curl', 'Squat', 'Deadlift', 'Bench Press', 'Sumo Deadlift', 'Romanian Deadlift'];
  const details = [
    '',
    'Too shallow - not counted',
    'Curl through full range',
    'Lower to chest, lock out',
    'Hinge fully, then lock out',
    'Go deeper for full depth',
  ];
  for (final style in ArabicStyle.values) {
    for (final p in CoachPersonality.values) {
      final b = PhraseBank(VoiceSettings(
        language: CoachLanguage.arabicEgyptian,
        arabicStyle: style,
        personality: p,
      ));
      for (var n = 0; n <= 100; n++) {
        texts
          ..add(b.number(n))
          ..add(b.repCount(n))
          ..add(b.formScore(n))
          ..add(b.countReport(n))
          ..add(b.setStarting(n))
          ..add(b.personalBestReps(n))
          ..add(b.personalBestForm(n));
      }
      for (final c in CoachCue.values) {
        texts
          ..add(b.cue(c))
          ..add(b.warning(c))
          ..add(b.warning(c, repeat: true))
          ..add(b.restTip(c))
          ..add(b.setSummary(reps: 5, clean: 3, form: 80, topFault: c));
      }
      for (final r in RepResult.values) {
        for (final fault in <CoachCue?>[null, ...CoachCue.values]) {
          for (final d in details) {
            final t = b.repResult(r, fault: fault, detail: d);
            if (t != null) texts.add(t);
          }
        }
      }
      for (var i = 0; i < 3; i++) {
        texts.add(b.praise(i));
      }
      texts.addAll([
        b.controlled, b.twoMore, b.lastOne, b.goalReached, b.fatigue, b.go, //
        b.restStarted, b.muted, b.unmuted, b.listening, b.sample,
        b.restLeft(30), b.restLeft(10),
        b.restOver(2, commands: true), b.restOver(2, commands: false),
        b.setSummary(reps: 5, clean: 5),
      ]);
      for (final e in exercises) {
        texts
          ..add(b.start(e))
          ..add(b.cameraSetup(e));
      }
    }
  }
  return {for (final t in texts) ...ClipText.pieces(t)};
}

String _ssml(String voice, String text) {
  final safe = text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  return '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="ar-EG">'
      '<voice name="$voice">$safe</voice></speak>';
}

Future<List<int>?> _synth(HttpClient http, String region, String key, String voice, String text) async {
  final url = Uri.parse('https://$region.tts.speech.microsoft.com/cognitiveservices/v1');
  for (var attempt = 1; attempt <= 6; attempt++) {
    try {
      final req = await http.postUrl(url);
      req.headers
        ..set('Ocp-Apim-Subscription-Key', key)
        ..set('Content-Type', 'application/ssml+xml; charset=utf-8')
        ..set('X-Microsoft-OutputFormat', 'audio-24khz-48kbitrate-mono-mp3')
        ..set('User-Agent', 'spotter-voice-coach');
      req.add(utf8.encode(_ssml(voice, text)));
      final res = await req.close();
      final body = await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      if (res.statusCode == 200) return body;
      if (res.statusCode == 401 || res.statusCode == 403) {
        stderr.writeln('\nAzure says the key or region is wrong (${res.statusCode}). '
            'Copy KEY 1 and the Location/Region from your Speech resource again.');
        exit(1);
      }
      // 429 = too many requests (the free tier allows about 20 a minute): wait and retry
      final wait = int.tryParse(res.headers.value('retry-after') ?? '') ?? (res.statusCode == 429 ? 15 : 5);
      stdout.write(' [${res.statusCode}, waiting ${wait}s]');
      await Future<void>.delayed(Duration(seconds: wait));
    } on SocketException catch (e) {
      stdout.write(' [network: ${e.message}, retry]');
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }
  return null;
}

String? _arg(List<String> args, String name) {
  final i = args.indexOf('--$name');
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

void _writeListing(List<String> pieces) {
  final listing = StringBuffer();
  for (final p in pieces) {
    listing.writeln('${ClipText.key(p)}\t$p');
  }
  Directory(ClipText.assetDir).createSync(recursive: true);
  File('${ClipText.assetDir}/pieces.txt').writeAsStringSync(listing.toString());
}

/// a short set of real coach lines to judge the voice by ear (python ... --sample)
void _writeSample() {
  final b = PhraseBank(const VoiceSettings(language: CoachLanguage.arabicEgyptian));
  final lines = <String>[
    for (var n = 1; n <= 20; n++) b.number(n),
    for (final c in const [
      CoachCue.spineNeutral, CoachCue.kneesCaving, CoachCue.elbowDrift, CoachCue.swinging,
      CoachCue.stanceNarrow, CoachCue.lowerSlowly, CoachCue.getInPosition, CoachCue.noPerson,
    ])
      b.cue(c),
    b.praise(0), b.praise(1), b.twoMore, b.lastOne, b.restStarted,
    ...ClipText.pieces(b.restOver(2, commands: false)),
  ];
  File('tool/sample.txt').writeAsStringSync(lines.join('\n'));
}

Future<void> main(List<String> args) async {
  if (args.contains('--list')) {
    if (!File('pubspec.yaml').existsSync()) {
      stderr.writeln('Run this from your project folder (the one with pubspec.yaml).');
      exit(64);
    }
    final pieces = allPieces().toList()..sort();
    _writeListing(pieces);
    _writeSample();
    stdout.writeln('${pieces.length} Arabic pieces written to ${ClipText.assetDir}/pieces.txt');
    stdout.writeln('Now run: python tool/make_egyptian_voice_edge.py');
    return;
  }
  final key = _arg(args, 'key') ?? Platform.environment['AZURE_SPEECH_KEY'];
  final region = _arg(args, 'region') ?? Platform.environment['AZURE_SPEECH_REGION'];
  if (key == null || region == null) {
    stderr.writeln('Usage: dart run tool/make_egyptian_voice.dart --key YOUR_KEY --region YOUR_REGION');
    exit(64);
  }
  if (!File('pubspec.yaml').existsSync()) {
    stderr.writeln('Run this from your project folder (the one with pubspec.yaml).');
    exit(64);
  }

  final pieces = allPieces().toList()..sort();
  stdout.writeln('${pieces.length} Arabic pieces x 2 voices');

  final http = HttpClient();
  final manifest = <String, List<String>>{};
  for (final (folder, voice) in const [('male', ClipText.maleVoice), ('female', ClipText.femaleVoice)]) {
    final dir = Directory('${ClipText.assetDir}/$folder')..createSync(recursive: true);
    final done = <String>[];
    var made = 0, kept = 0, failed = 0;
    for (var i = 0; i < pieces.length; i++) {
      final p = pieces[i];
      final k = ClipText.key(p);
      final file = File('${dir.path}/$k.mp3');
      if (file.existsSync() && file.lengthSync() > 0) {
        kept++;
        done.add(k);
        continue;
      }
      stdout.write('\r$folder ${i + 1}/${pieces.length}  ');
      final audio = await _synth(http, region, key, voice, p);
      if (audio == null) {
        failed++;
        stdout.writeln('\nfailed: $p');
        continue;
      }
      file.writeAsBytesSync(audio);
      made++;
      done.add(k);
    }
    // clips of old text that is not used any more
    final wanted = done.toSet();
    for (final f in dir.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (name.endsWith('.mp3') && !wanted.contains(name.replaceAll('.mp3', ''))) f.deleteSync();
    }
    manifest[folder] = done..sort();
    stdout.writeln('\r$folder: $made new, $kept already there, $failed failed            ');
  }
  http.close();

  _writeListing(pieces);
  File(ClipText.manifest).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(manifest));
  stdout.writeln('Done. Clips are in ${ClipText.assetDir}/ (pieces.txt lists what each file says).');
}
