import 'package:flutter/material.dart';

import 'package:ai_trainer/core/theme/spotter_theme.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/coaching_feedback.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/form_level.dart';

// Form colours (Spotter palette). They are also used to draw the depth bar on the
// camera picture, so they stay Flutter `Color`s.
const formGood = Sp.mint; // form correct
const formWarn = Sp.warn; // needs correction
const formBad = Sp.fault; // clear fault
const formNA = Color(0xFF8E9192); // cannot be assessed

Color formLevelColor(FormLevel level) => switch (level) {
  FormLevel.good => formGood,
  FormLevel.warn => formWarn,
  FormLevel.bad => formBad,
  FormLevel.notAssessable => formNA,
};

Color feedbackColor(FeedbackTone tone) => switch (tone) {
  FeedbackTone.good => formGood,
  FeedbackTone.warn => formWarn,
  FeedbackTone.bad => formBad,
  FeedbackTone.alert => Sp.faultSoft,
  FeedbackTone.muted => Sp.muted,
};

IconData feedbackIcon(FeedbackIcon icon) => switch (icon) {
  FeedbackIcon.warning => Icons.warning_amber_rounded,
  FeedbackIcon.check => Icons.check_circle_outline,
  FeedbackIcon.error => Icons.error_outline,
  FeedbackIcon.cancel => Icons.cancel_outlined,
  FeedbackIcon.info => Icons.info_outline,
  FeedbackIcon.person => Icons.accessibility_new,
};

String fatigueWord(double f) => f < 35 ? 'fresh' : (f < 65 ? 'tiring' : 'rest soon');
Color fatigueColor(double f) => f < 35 ? formGood : (f < 65 ? formWarn : formBad);

const armNames = ['Right arm', 'Left arm', 'Both arms', 'Alternate R>L', 'Alternate L>R'];
const armShort = ['Right arm', 'Left arm', 'Both arms', 'Alt R>L', 'Alt L>R'];
