import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:ai_trainer/core/widgets/camera_view.dart';
import 'package:ai_trainer/core/widgets/overlay_canvas.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/bloc/pose_bloc/pose_bloc.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/widgets/skeleton_drawing.dart';
import 'package:ai_trainer/injection_container.dart';

/// main() of PoseModule.py / Pose
class PoseEstimationScreen extends StatelessWidget {
  const PoseEstimationScreen({super.key});

  OverlayFrame? _overlay(PoseState state) {
    if (state is! PoseActive) return null;
    final img = OverlayFrame(state.imageWidth, state.imageHeight, mirror: state.isMirrored);
    drawLandmarks(img, state.pose);
    drawPositions(img, state.pose);
    img.hud.putText('${state.fps.toInt()}', 10, 70, 3, magenta, 3);
    return img;
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<PoseBloc>(),
      child: Builder(
        builder: (context) => CameraView(
          title: 'Pose Estimation',
          onFrame: (frame) => context.read<PoseBloc>().add(PoseFrameReceived(frame: frame)),
          overlay: BlocBuilder<PoseBloc, PoseState>(
            builder: (context, state) => CustomPaint(painter: OverlayPainter(_overlay(state))),
          ),
        ),
      ),
    );
  }
}
