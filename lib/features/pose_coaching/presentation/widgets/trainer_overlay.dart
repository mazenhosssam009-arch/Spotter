import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ai_trainer/core/constants.dart';
import 'package:ai_trainer/core/widgets/overlay_canvas.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/bloc/trainer_bloc/trainer_bloc.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/widgets/form_colors.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/widgets/skeleton_drawing.dart';

/// what is drawn on the camera picture: the skeleton and (debugHud) the findAngle lines,
/// the live numbers and fps. The depth bar is a Flutter widget on top (see DepthBar) and
/// all the other text lives in the panel.
OverlayFrame? trainerOverlay(TrainerState state) {
  final counter = state.counter, pose = state.pose;
  if (counter == null || pose == null || state.paused) return null;
  final img = OverlayFrame(state.imageWidth, state.imageHeight, mirror: state.isMirrored);
  drawLandmarks(img, pose);
  // the angle lines and numbers are only painted while testing (FPS)
  if (debugHud) {
    for (final a in counter.jointAngles) {
      drawAngle(img, pose, a);
    }
  }

  final w = img.width, h = img.height;
  // python text sizes were made for a 640x480 (AiTrainer) or 1280x720 picture
  final k = math.min(w, h) / (counter.exercise.oneSide ? 480 : 720);
  final hud = img.hud;

  // debug text that always fits: shrinks, then cuts, instead of running into the bar
  void put(String s, double x, double y, double scale, Color color, double maxW) {
    const cw = 18.0; // about one letter at scale 1
    var sc = scale;
    var txt = s;
    if (txt.length * cw * sc > maxW) sc = math.max(maxW / (txt.length * cw), 0.45 * k);
    final fit = (maxW / (cw * sc)).floor();
    if (txt.length > fit && fit > 2) txt = '${txt.substring(0, fit - 2)}..';
    hud.putText(txt, x, y, sc, color, 2);
  }

  final barX1 = w * 0.88; // (only used to keep the debug text away from the right edge)

  if (debugHud) {
    final maxW = math.max(barX1 - 40 * k - 20, 120.0);
    var dy = h * 0.5;
    for (final s in counter.debugLines) {
      put(s, 10, dy, 0.6 * k, formNA, maxW);
      dy += 24 * k;
    }
    hud.putText('${state.fps.toInt()}', 10, 70 * k, 2 * k, magenta, 3);
  }
  return img;
}
