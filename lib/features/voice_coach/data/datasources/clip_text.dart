/// Shared by the app and tool/make_egyptian_voice.dart (pure Dart, no Flutter), so
/// both cut the coach's sentences into the same pieces and give them the same file names.
///
/// The phrase bank marks where a sentence may be cut:
///   [piece]    between parts of one sentence ("تلاتة" | "ريبس")
///   [sentence] between two sentences
/// Each piece is one recorded clip. Numbers and fault names are separate pieces, so a
/// few hundred clips can build every sentence the coach says.
class ClipText {
  ClipText._();

  static const piece = '|';
  static const sentence = '\n';

  /// the pieces to play one after the other
  static List<String> pieces(String text) =>
      text.split(RegExp(r'[|\n]')).map(clean).where((s) => s.isNotEmpty).toList();

  /// the same text for the phone voice (no clip pack): separators become spaces / stops
  static String forTts(String text) => text
      .split(sentence)
      .map((s) => s.split(piece).map(clean).where((p) => p.isNotEmpty).join(' '))
      .where((s) => s.isNotEmpty)
      .join('. ');

  static String clean(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// file name of a piece: FNV-1a hash of its text, 8 hex digits (stable on every device)
  static String key(String pieceText) {
    var h = 0x811c9dc5;
    for (final c in clean(pieceText).codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  /// Azure neural voices for Egyptian Arabic
  static const maleVoice = 'ar-EG-ShakirNeural';
  static const femaleVoice = 'ar-EG-SalmaNeural';

  /// where the clips live inside the app
  static const assetDir = 'assets/voice/ar_eg';
  static const manifest = '$assetDir/manifest.json';
  static String assetPath(String folder, String pieceText) => '$assetDir/$folder/${key(pieceText)}.mp3';
}
