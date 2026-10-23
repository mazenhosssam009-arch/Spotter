import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:ai_trainer/core/camera/camera_frame.dart';
import 'package:ai_trainer/core/camera/frame_throttle.dart';
import 'package:ai_trainer/core/utils/cv_math.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/pose_frame.dart';
import 'package:ai_trainer/features/pose_coaching/domain/usecases/detect_pose_usecase.dart';

part 'pose_event.dart';
part 'pose_state.dart';

// main() of PoseModule.py / Pose: skeleton + fps, no rep counting
class PoseBloc extends Bloc<PoseEvent, PoseState> {
  DetectPoseUseCase detectPose;

  final _throttle = FrameThrottle();
  double ptime = 0;
  int frameNumber = 0;

  PoseBloc({required this.detectPose}) : super(PoseIdle()) {
    on<PoseFrameReceived>((event, emit) async {
      await _throttle.run(event.frame, (frame) async {
        final res = await detectPose(DetectPoseParams(frame: frame));
        if (isClosed) return;
        res.fold((failure) => debugPrint('frame error: ${failure.message}'), (pose) {
          if (pose.hasPerson) {
            final l = pose.landmark(4);
            debugPrint('${[4, l.x.toInt(), l.y.toInt()]}');
          }
          final ctime = now();
          final fps = 1 / (ctime - ptime);
          ptime = ctime;
          emit(PoseActive(
            pose: pose,
            imageWidth: frame.uprightWidth,
            imageHeight: frame.uprightHeight,
            isMirrored: frame.isFrontCamera,
            fps: fps,
            frameNumber: ++frameNumber,
          ));
        });
      }, isClosed: () => isClosed);
    });
  }

  @override
  Future<void> close() async {
    await detectPose.dispose();
    return super.close();
  }
}
