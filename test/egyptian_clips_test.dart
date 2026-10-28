import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_trainer/features/voice_coach/data/datasources/clip_text.dart';

import '../tool/make_egyptian_voice.dart' show allPieces;

/// Clips are named by a hash of the exact Arabic text (tashkeel included). If the text in
/// phrase_bank.dart changes and the clips are not recorded again, nothing matches and the
/// app quietly falls back to the phone's standard-Arabic voice. Fix: run
///   dart run tool/make_egyptian_voice.dart --list
///   python tool/make_egyptian_voice_edge.py
void main() {
  final manifest = jsonDecode(File(ClipText.manifest).readAsStringSync()) as Map<String, dynamic>;
  final pieces = allPieces();

  // every voice in the manifest (only complete voices are added to it)
  for (final voice in manifest.keys) {
    test('every Arabic piece has a recorded $voice clip', () {
      final keys = (manifest[voice] as List).map((e) => '$e').toSet();
      final missing = [
        for (final p in pieces)
          if (!keys.contains(ClipText.key(p)) || !File(ClipText.assetPath(voice, p)).existsSync()) p,
      ];
      expect(missing, isEmpty, reason: 'no $voice clip for ${missing.length} pieces, e.g. ${missing.take(5)}');
    });
  }
}
