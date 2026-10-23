import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:ai_trainer/core/widgets/camera_view.dart';
import 'package:ai_trainer/core/widgets/overlay_canvas.dart';
import 'package:ai_trainer/features/face_detection/domain/entities/face_box.dart';
import 'package:ai_trainer/features/face_detection/presentation/bloc/face_detection_bloc.dart';
import 'package:ai_trainer/injection_container.dart';

/// main() of FaceDetectionModule
class FaceDetectionScreen extends StatelessWidget {
  const FaceDetectionScreen({super.key});

  // FaceDetector.fancyDraw: thin box with thick corners
  static void fancyDraw(OverlayFrame img, FaceBox b, {int l = 30, double t = 10, double rt = 1}) {
    final x = b.x, y = b.y, w = b.width, h = b.height;
    final x1 = x + w, y1 = y + h;
    img.rectangle(x, y, x1, y1, blue, rt);
    // Top left x,y
    img.line(x, y, x + l, y, blue, t);
    img.line(x, y, x, y + l, blue, t);
    // Top right x1,y
    img.line(x1, y, x1 - l, y, blue, t);
    img.line(x1, y, x1, y + l, blue, t);
    // Bottom left x,y1
    img.line(x, y1, x + l, y1, blue, t);
    img.line(x, y1, x, y1 - l, blue, t);
    // Bottom right x1,y1
    img.line(x1, y1, x1 - l, y1, blue, t);
    img.line(x1, y1, x1, y1 - l, blue, t);
  }

  OverlayFrame? _overlay(FaceDetectionState state) {
    if (state is! FaceDetectionActive) return null;
    final img = OverlayFrame(state.imageWidth, state.imageHeight, mirror: state.isMirrored);
    for (final face in state.faces) {
      fancyDraw(img, face);
    }
    img.hud.putText('${state.fps.toInt()}', 10, 70, 3, magenta, 3);
    return img;
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<FaceDetectionBloc>(),
      child: Builder(
        builder: (context) => CameraView(
          title: 'Face Detection',
          onFrame: (frame) =>
              context.read<FaceDetectionBloc>().add(FaceFrameReceived(frame: frame)),
          overlay: BlocBuilder<FaceDetectionBloc, FaceDetectionState>(
            builder: (context, state) => CustomPaint(painter: OverlayPainter(_overlay(state))),
          ),
        ),
      ),
    );
  }
}
