import 'package:equatable/equatable.dart';

enum FeedbackIcon { warning, check, error, cancel, info, person }

/// colour of the feedback card: the form levels plus the soft red of a wrong
/// position and the grey of a hint
enum FeedbackTone { good, warn, bad, alert, muted }

/// what the feedback card under the camera says right now
class CoachingFeedback extends Equatable {
  const CoachingFeedback(this.icon, this.tone, this.title, [this.sub]);
  final FeedbackIcon icon;
  final FeedbackTone tone;
  final String title;
  final String? sub;

  @override
  List<Object?> get props => [icon, tone, title, sub];
}
