import 'package:flutter/material.dart';

import 'package:ai_trainer/core/theme/spotter_theme.dart';
import 'package:ai_trainer/core/widgets/spot_widgets.dart';
import 'package:ai_trainer/features/voice_coach/data/datasources/voicetut_pack.dart';
import 'package:ai_trainer/features/voice_coach/domain/entities/voice_settings.dart';

/// Voice settings: the open-source online voice (VoiceTut). The user runs the server
/// (tool/voicetut/VoiceTut_server.ipynb on Colab), pastes its link, picks a voice and downloads
/// it once; [onReady] then selects it (folder id `vt_<speaker>`).
class VoiceTutSection extends StatefulWidget {
  const VoiceTutSection({super.key, required this.gender, required this.onReady});

  final VoiceGender gender;
  final void Function(String folderId) onReady;

  @override
  State<VoiceTutSection> createState() => _VoiceTutSectionState();
}

class _VoiceTutSectionState extends State<VoiceTutSection> {
  final _url = TextEditingController();
  String? _speaker;
  int _done = 0, _total = 0;
  bool _busy = false, _stop = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    VoiceTutPack.savedUrl().then((u) {
      if (mounted) setState(() => _url.text = u);
    });
  }

  @override
  void dispose() {
    _stop = true; // leaving the screen ends the download (what is saved stays)
    _url.dispose();
    super.dispose();
  }

  List<String> get _names => VoiceTutPack.speakers[widget.gender]!;

  Future<void> _download() async {
    final speaker = _speaker ?? _names.first;
    final url = _url.text.trim();
    if (url.isEmpty) {
      setState(() => _message = 'Paste the link from the Colab notebook first.');
      return;
    }
    await VoiceTutPack.saveUrl(url);
    setState(() {
      _busy = true;
      _stop = false;
      _done = 0;
      _message = 'Connecting to the server...';
    });
    if (!await VoiceTutPack.ping(url)) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = 'The server does not answer. Is the Colab notebook still running? '
              'A new run gives a new link.';
        });
      }
      return;
    }
    final failed = await VoiceTutPack.download(url, speaker,
        cancelled: () => _stop,
        onProgress: (d, t) {
          if (!mounted) return;
          setState(() {
            _done = d;
            _total = t;
            _message = null;
          });
        });
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = failed == 0
          ? 'VoiceTut $speaker is ready and saved on the phone (works offline now).'
          : '$failed lines did not download. Tap Download again: it continues where it stopped.';
    });
    if (failed == 0) widget.onReady(VoiceTutPack.folderId(speaker));
  }

  @override
  Widget build(BuildContext context) {
    final speaker = _names.contains(_speaker) ? _speaker! : _names.first;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Online voice: VoiceTut (open source)', style: Sp.labelMd.copyWith(color: Sp.white)),
      const SizedBox(height: 4),
      Text(
        'An open-source Egyptian voice model on your own server. Run tool/voicetut/VoiceTut_server.ipynb '
        'on Google Colab (free GPU), paste its link, pick a voice and download it once. '
        'The recorded voices stay as they are and are used when this one is not downloaded.',
        style: Sp.bodySm.copyWith(color: Sp.muted),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _url,
        enabled: !_busy,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: const InputDecoration(labelText: 'Server link', hintText: 'https://....trycloudflare.com'),
      ),
      const SizedBox(height: 8),
      DropdownButton<String>(
        isExpanded: true,
        value: speaker,
        items: [for (final n in _names) DropdownMenuItem(value: n, child: Text('VoiceTut voice: $n'))],
        onChanged: _busy ? null : (n) => setState(() => _speaker = n),
      ),
      const SizedBox(height: 8),
      if (_busy && _total > 0) ...[
        LinearProgressIndicator(value: _done / _total),
        const SizedBox(height: 4),
        Text('$_done / $_total lines', style: Sp.bodySm.copyWith(color: Sp.muted)),
        const SizedBox(height: 8),
      ],
      Row(children: [
        Expanded(
          child: SpotButton(_busy ? 'Stop' : 'Download voice',
              icon: _busy ? Icons.stop : Icons.download,
              kind: _busy ? SpotKind.secondary : SpotKind.primary,
              onPressed: _busy ? () => setState(() => _stop = true) : _download),
        ),
      ]),
      if (_message != null) ...[
        const SizedBox(height: 6),
        Text(_message!, style: Sp.bodySm.copyWith(color: Sp.muted)),
      ],
    ]);
  }
}
