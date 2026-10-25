import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:ai_trainer/core/theme/spotter_theme.dart';
import 'package:ai_trainer/core/widgets/spot_widgets.dart';
import 'package:ai_trainer/features/voice_coach/data/datasources/phrase_bank.dart';
import 'package:ai_trainer/features/voice_coach/data/datasources/tts_engine.dart';
import 'package:ai_trainer/features/voice_coach/data/datasources/voice_command_listener.dart';
import 'package:ai_trainer/features/voice_coach/domain/entities/voice_settings.dart';
import 'package:ai_trainer/features/voice_coach/presentation/cubit/voice_settings_cubit.dart';
import 'package:ai_trainer/injection_container.dart';

/// everything about the voice coach: language, voice, personality, how much it talks,
/// speed, music, headphones, voice commands, accessibility, and a "Test voice" button
class VoiceSettingsScreen extends StatefulWidget {
  const VoiceSettingsScreen({super.key});

  @override
  State<VoiceSettingsScreen> createState() => _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends State<VoiceSettingsScreen> {
  final _engine = sl<TtsEngine>();
  VoiceSupport? _support;
  bool _pack = false; // the recorded Egyptian voice is inside the app
  final _drag = <String, double>{}; // slider values while dragging (saved on release)
  CoachLanguage? _supportFor;

  VoiceSettingsCubit get _cubit => context.read<VoiceSettingsCubit>();

  @override
  void initState() {
    super.initState();
    _engine.refreshVoices(); // the user may have installed a voice meanwhile
    _loadSupport(_cubit.state);
    _engine.hasEgyptianPack().then((v) {
      if (mounted) setState(() => _pack = v);
    });
  }

  Future<void> _loadSupport(VoiceSettings s) async {
    _supportFor = s.language;
    final sup = await _engine.support(s);
    if (mounted && _supportFor == s.language) setState(() => _support = sup);
  }

  void _set(VoiceSettings Function(VoiceSettings s) change) => _cubit.update(change);

  Future<void> _test(VoiceSettings s) => _engine.speak(PhraseBank(s).sample, interrupt: true, preview: true);

  Future<void> _toggleCommands(bool on) async {
    if (on && !await sl<VoiceCommandListener>().ensureReady()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Voice commands need the microphone and speech recognition permission.'),
      ));
      return;
    }
    _set((s) => s.copyWith(voiceCommands: on));
  }

  // ------------------------------------------------------------------ small widgets

  Widget _section(String title, List<Widget> children, {String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SpotCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title.toUpperCase(), style: Sp.labelMd.copyWith(color: Sp.mint)),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(hint, style: Sp.bodySm.copyWith(color: Sp.muted)),
            ],
            const SizedBox(height: 12),
            ...children,
          ]),
        ),
      );

  Widget _chips<T>(List<(T, String)> options, T selected, ValueChanged<T> onPick) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (v, label) in options)
            ChoiceChip(label: Text(label), selected: v == selected, onSelected: (_) => onPick(v)),
        ],
      );

  /// [testAfter] = say the sample when the slider is released (speed / pitch)
  Widget _slider(String label, double saved, double min, double max,
      {bool testAfter = false, String Function(double v)? text}) {
    final value = (_drag[label] ?? saved).clamp(min, max).toDouble();
    return Row(children: [
      SizedBox(width: 64, child: Text(label, style: Sp.bodyMd)),
      Expanded(
        child: Slider(
          value: value,
          min: min,
          max: max,
          divisions: ((max - min) * 20).round(),
          label: text?.call(value),
          onChanged: (v) => setState(() => _drag[label] = v),
          onChangeEnd: (v) async {
            await _cubit.update((s) => _withSlider(s, label, v));
            if (mounted) setState(() => _drag.remove(label));
            if (testAfter) await _test(_cubit.state);
          },
        ),
      ),
    ]);
  }

  VoiceSettings _withSlider(VoiceSettings s, String label, double v) => switch (label) {
        'Speed' => s.copyWith(rate: v),
        'Pitch' => s.copyWith(pitch: v),
        _ => s.copyWith(volume: v),
      };

  Widget _note(IconData icon, String text, {Color color = Sp.warn}) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: Sp.bodySm.copyWith(color: Sp.muted))),
        ]),
      );

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<VoiceSettingsCubit, VoiceSettings>(
      listenWhen: (a, b) => a.language != b.language || a.gender != b.gender,
      listener: (_, s) => _loadSupport(s),
      builder: (context, s) {
        final sup = _support;
        final voices = sup?.voices ?? const <VoiceInfo>[];
        final pickedExists = s.voiceName != null && voices.any((v) => v.name == s.voiceName);
        return Scaffold(
          backgroundColor: Sp.canvas,
          appBar: AppBar(title: const Text('Voice coach')),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SpotButton('Test voice', icon: Icons.play_arrow, onPressed: () => _test(s)),
            ),
          ),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            _section('Language', [
              SegmentedButton<CoachLanguage>(
                segments: const [
                  ButtonSegment(value: CoachLanguage.english, label: Text('English')),
                  ButtonSegment(value: CoachLanguage.arabicEgyptian, label: Text('العربية (مصري)')),
                ],
                selected: {s.language},
                onSelectionChanged: (v) => _cubit.chooseLanguage(v.first),
              ),
              if (s.arabic) ...[
                const SizedBox(height: 12),
                _chips<ArabicStyle>(
                  const [
                    (ArabicStyle.gymSlang, 'كلام جيم (ريب، سِت، فورم)'),
                    (ArabicStyle.plain, 'مصري عادي (تكرارة، مجموعة)'),
                  ],
                  s.arabicStyle,
                  (v) => _set((x) => x.copyWith(arabicStyle: v)),
                ),
              ],
            ]),
            _section('Voice', [
              if (s.arabic) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('صوت مصري حقيقي (Egyptian voice)'),
                  subtitle: Text(_pack
                      ? 'Recorded Egyptian voices: Shakir (male) / Salma (female). Works offline.'
                      : 'Not in this build yet: run tool/make_egyptian_voice.dart (see VOICE_COACH_SETUP.md).'),
                  value: _pack && s.egyptianClips,
                  onChanged: _pack ? (v) => _set((x) => x.copyWith(egyptianClips: v)) : null,
                ),
                const SizedBox(height: 8),
              ],
              SegmentedButton<VoiceGender>(
                segments: const [
                  ButtonSegment(value: VoiceGender.male, label: Text('Male'), icon: Icon(Icons.man)),
                  ButtonSegment(value: VoiceGender.female, label: Text('Female'), icon: Icon(Icons.woman)),
                ],
                selected: {s.gender},
                onSelectionChanged: (v) => _set((x) => x.copyWith(gender: v.first, clearVoiceName: true)),
              ),
              if (s.arabic && _pack && s.egyptianClips)
                _note(Icons.record_voice_over_outlined,
                    'Using the recorded Egyptian voice. The phone voice below is only used for '
                    'anything that has no recording.',
                    color: Sp.mint),
              if (voices.length > 1) ...[
                const SizedBox(height: 12),
                DropdownButton<String?>(
                  isExpanded: true,
                  value: pickedExists ? s.voiceName : null,
                  hint: const Text('Voice: automatic'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Automatic (best match)')),
                    for (final v in voices)
                      DropdownMenuItem<String?>(
                        value: v.name,
                        child: Text(v.label, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (name) => _set((x) =>
                      name == null ? x.copyWith(clearVoiceName: true) : x.copyWith(voiceName: name)),
                ),
              ],
              if (sup == null)
                const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator())
              else ...[
                if (!sup.available)
                  _note(
                    Icons.download_outlined,
                    s.arabic
                        ? 'No Arabic voice is installed. Android: Settings > Text-to-speech > Google > '
                            'Install voice data > Arabic. iPhone: Settings > Accessibility > Spoken Content > Voices > Arabic.'
                        : 'No English voice is installed. Install one in the phone\'s text-to-speech settings.',
                  ),
                if (sup.available && s.arabic && !sup.hasEgyptian)
                  _note(Icons.info_outline,
                      'Your phone has no Egyptian (ar-EG) voice, so a general Arabic voice reads the Egyptian text. '
                      'The words are Egyptian; the accent depends on the voice.',
                      color: Sp.outline),
                if (sup.available && !sup.genderMatched)
                  _note(Icons.info_outline,
                      'No ${s.gender.name} voice was found for this language, so the pitch is changed instead. '
                      'You can also pick a voice from the list above.',
                      color: Sp.outline),
              ],
            ]),
            _section('Coach personality', [
              _chips<CoachPersonality>(
                const [
                  (CoachPersonality.calm, 'Calm'),
                  (CoachPersonality.hype, 'Hype'),
                  (CoachPersonality.strict, 'Strict'),
                  (CoachPersonality.minimal, 'Minimal'),
                ],
                s.personality,
                (v) => _set((x) => x.copyWith(personality: v)),
              ),
              const SizedBox(height: 8),
              Text(
                switch (s.personality) {
                  CoachPersonality.calm => 'Gentle reminders and quiet praise.',
                  CoachPersonality.hype => 'Loud and motivating: "Two more! Push!"',
                  CoachPersonality.strict => 'Drill sergeant: "I said, chest up!"',
                  CoachPersonality.minimal => 'Short cues only, no extra words.',
                },
                style: Sp.bodySm.copyWith(color: Sp.muted),
              ),
            ]),
            _section('How much it talks', [
              _chips<CoachVerbosity>(
                const [
                  (CoachVerbosity.off, 'Silent'),
                  (CoachVerbosity.warnings, 'Warnings only'),
                  (CoachVerbosity.warningsReps, 'Warnings + reps'),
                  (CoachVerbosity.full, 'Full coach'),
                ],
                s.verbosity,
                (v) => _set((x) => x.copyWith(verbosity: v)),
              ),
              const SizedBox(height: 8),
              Text(
                switch (s.verbosity) {
                  CoachVerbosity.off => 'The coach does not speak.',
                  CoachVerbosity.warnings => 'Form warnings and camera setup help only.',
                  CoachVerbosity.warningsReps => 'Also counts reps, says rep results, the 3-2-1 and when the rest is over.',
                  CoachVerbosity.full =>
                    'Also praise, encouragement, rest countdown, set summary with a tip, and personal bests.',
                },
                style: Sp.bodySm.copyWith(color: Sp.muted),
              ),
            ]),
            _section('Rep counting', [
              _chips<CountStyle>(
                const [
                  (CountStyle.everyRep, 'Every rep'),
                  (CountStyle.milestones, 'Every 5th rep'),
                  (CountStyle.nearGoal, 'Last 3 before goal'),
                ],
                s.countStyle,
                (v) => _set((x) => x.copyWith(countStyle: v)),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: Text(s.repGoal == 0 ? 'Rep goal per set: off' : 'Rep goal per set: ${s.repGoal}',
                      style: Sp.bodyMd),
                ),
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: s.repGoal == 0 ? null : () => _set((x) => x.copyWith(repGoal: x.repGoal - 1)),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: s.repGoal >= 50 ? null : () => _set((x) => x.copyWith(repGoal: x.repGoal + 1)),
                ),
              ]),
              if (s.countStyle == CountStyle.nearGoal && s.repGoal == 0)
                _note(Icons.info_outline, 'Set a rep goal, otherwise every rep is counted.', color: Sp.outline),
            ], hint: 'With a goal the coach says "two more", "last one" and "goal reached".'),
            _section('Sound', [
              _slider('Speed', s.rate, 0.2, 0.9, testAfter: true, text: (v) => '${(v * 200).round()}%'),
              _slider('Pitch', s.pitch, 0.5, 2.0, testAfter: true, text: (v) => v.toStringAsFixed(2)),
              _slider('Volume', s.volume, 0.0, 1.0, text: (v) => '${(v * 100).round()}%'),
              const SizedBox(height: 8),
              Text('Your music while the coach talks', style: Sp.bodyMd),
              const SizedBox(height: 8),
              _chips<MusicMode>(
                const [
                  (MusicMode.duck, 'Lower it'),
                  (MusicMode.pause, 'Pause it'),
                  (MusicMode.mix, "Don't touch it"),
                ],
                s.musicMode,
                (v) => _set((x) => x.copyWith(musicMode: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Only with headphones'),
                subtitle: const Text('Stay quiet when no earbuds are connected (for a quiet gym)'),
                value: s.headphonesOnly,
                onChanged: (v) => _set((x) => x.copyWith(headphonesOnly: v)),
              ),
            ], hint: 'With earbuds connected the coach plays through them automatically.'),
            _section('Hands-free', [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Voice commands'),
                subtitle: const Text('Uses the microphone during the workout'),
                value: s.voiceCommands,
                onChanged: _toggleCommands,
              ),
              if (s.voiceCommands)
                Text(
                  s.arabic
                      ? 'قول: "خلصت" (خلّص السِت) · "يلا" (اللي بعده) · "تخطي" · "وقت زيادة" · "وقّف التايمر" · '
                          '"زوّد عدّة" · "شيل عدّة" · "عدّيت كام" · "اسكت" · "اتكلم"'
                      : 'Say: "finish" · "next" · "skip" · "more time" · "stop timer" · "plus one" · '
                          '"minus one" · "how many" · "mute" · "unmute"',
                  style: Sp.bodySm.copyWith(color: Sp.muted),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Describe everything'),
                subtitle: const Text('For low vision: camera setup, set number, form score and rest time out loud'),
                value: s.accessibility,
                onChanged: (v) => _set((x) => x.copyWith(accessibility: v)),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                'The coach uses the voices installed on your phone, so it works offline. '
                'Form feedback is an estimate from the camera and cannot guarantee injury prevention.',
                style: Sp.bodySm.copyWith(color: Sp.outline),
              ),
            ),
          ]),
        );
      },
    );
  }
}
