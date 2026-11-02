import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_trainer/features/voice_coach/data/datasources/clip_text.dart';
import 'package:ai_trainer/features/voice_coach/domain/entities/egyptian_voice.dart';
import 'package:ai_trainer/features/voice_coach/domain/entities/voice_settings.dart';

/// The open-source online voice: VoiceTut-TTS (Apache-2.0, 19 Egyptian voices) running on the
/// user's own server (tool/voicetut, free on Google Colab). Every coach line is asked from the
/// server once and saved on the phone; from then on it plays like the recorded voices, offline.
/// A voice is only used when all its lines are saved (else the recorded voices play).
class VoiceTutPack {
  static const speakers = {
    VoiceGender.male: ['Ahmed', 'Ali', 'Hassan', 'Karim', 'Mahmoud', 'Mohammed', 'Mostafa', 'Ramy', 'Shaker',
        'Tareq', 'Yehia', 'Youssef'],
    VoiceGender.female: ['Hadeer', 'Hanan', 'Mariam', 'Rana', 'Sarah', 'Yasmin', 'Yara'],
  };

  static const _urlKey = 'voicetut_url';
  static const _doneFile = 'complete';

  /// clip folder id of a VoiceTut voice ('vt_yasmin')
  static String folderId(String speaker) => 'vt_${speaker.toLowerCase()}';
  static bool isPack(String? id) => id != null && id.startsWith('vt_');

  static String? speakerOf(String id) {
    for (final list in speakers.values) {
      for (final s in list) {
        if (folderId(s) == id) return s;
      }
    }
    return null;
  }

  static VoiceGender genderOf(String speaker) =>
      speakers[VoiceGender.female]!.contains(speaker) ? VoiceGender.female : VoiceGender.male;

  /// how the voice is listed in the settings
  static EgyptianVoice voice(String speaker) =>
      EgyptianVoice(folderId(speaker), 'VoiceTut $speaker (online model)', genderOf(speaker));

  static Future<Directory> _root() async =>
      Directory('${(await getApplicationDocumentsDirectory()).path}/voicetut');

  static Future<String> dir(String folder) async => '${(await _root()).path}/$folder';

  // ------------------------------------------------------------------ server link

  static Future<String> savedUrl() async => (await SharedPreferences.getInstance()).getString(_urlKey) ?? '';

  static Future<void> saveUrl(String url) async =>
      (await SharedPreferences.getInstance()).setString(_urlKey, url.trim());

  static Uri _uri(String base, String path) {
    var b = base.trim();
    if (!b.startsWith('http')) b = 'https://$b';
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    return Uri.parse('$b$path');
  }

  /// the server answers (the Colab notebook is running)
  static Future<bool> ping(String base) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final res = await (await client.getUrl(_uri(base, '/'))).close().timeout(const Duration(seconds: 10));
      final body = await utf8.decodeStream(res);
      return res.statusCode == 200 && body.contains('"ok"');
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  // ------------------------------------------------------------------ saved voices

  /// the complete VoiceTut voices on this phone: folder -> clip keys
  static Future<Map<String, Set<String>>> installed() async {
    final out = <String, Set<String>>{};
    if (kIsWeb) return out;
    try {
      final root = await _root();
      if (!root.existsSync()) return out;
      for (final d in root.listSync().whereType<Directory>()) {
        if (!File('${d.path}/$_doneFile').existsSync()) continue; // half downloaded: not used
        out[_name(d.path)] = {
          for (final f in d.listSync().whereType<File>())
            if (f.path.endsWith('.mp3')) _name(f.path).replaceAll('.mp3', ''),
        };
      }
    } catch (e) {
      debugPrint('voicetut packs: $e');
    }
    return out;
  }

  static String _name(String path) => path.split(RegExp(r'[\\/]')).last;

  static Future<void> delete(String speaker) async {
    final d = Directory(await dir(folderId(speaker)));
    if (d.existsSync()) await d.delete(recursive: true);
  }

  /// every line the app can say (the same list as the recorded voices): clip key -> text
  static Future<Map<String, String>> _pieces() async {
    final out = <String, String>{};
    for (final line in const LineSplitter().convert(await rootBundle.loadString('${ClipText.assetDir}/pieces.txt'))) {
      final tab = line.indexOf('\t');
      if (tab > 0 && line.substring(tab + 1).trim().isNotEmpty) out[line.substring(0, tab)] = line.substring(tab + 1);
    }
    return out;
  }

  /// asks the server for every line not saved yet; [onProgress] (done, total).
  /// Returns how many lines failed (0 = the voice is complete and ready).
  static Future<int> download(String base, String speaker,
      {required void Function(int done, int total) onProgress, bool Function()? cancelled}) async {
    final folder = Directory(await dir(folderId(speaker)));
    await folder.create(recursive: true);
    final done = File('${folder.path}/$_doneFile');
    if (done.existsSync()) await done.delete();
    final pieces = await _pieces();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    var failed = 0, n = 0;
    try {
      for (final e in pieces.entries) {
        if (cancelled?.call() ?? false) return pieces.length - n;
        final file = File('${folder.path}/${e.key}.mp3');
        if (!file.existsSync()) {
          try {
            final req = await client.postUrl(_uri(base, '/tts'));
            req.headers.contentType = ContentType.json;
            req.add(utf8.encode(jsonEncode({'text': e.value, 'speaker': speaker})));
            final res = await req.close().timeout(const Duration(seconds: 90));
            final bytes = await consolidateHttpClientResponseBytes(res);
            if (res.statusCode == 200 && bytes.length > 500) {
              await file.writeAsBytes(bytes);
            } else {
              failed++;
            }
          } catch (_) {
            failed++;
          }
        }
        onProgress(++n, pieces.length);
      }
    } finally {
      client.close(force: true);
    }
    if (failed == 0) await done.writeAsString('${pieces.length}');
    return failed;
  }
}
