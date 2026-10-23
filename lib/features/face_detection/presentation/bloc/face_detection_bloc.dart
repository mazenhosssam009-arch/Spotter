import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:ai_trainer/core/camera/camera_frame.dart';
import 'package:ai_trainer/core/camera/frame_throttle.dart';
import 'package:ai_trainer/core/utils/cv_math.dart';
import 'package:ai_trainer/features/face_detection/domain/entities/face_box.dart';
import 'package:ai_trainer/features/face_detection/domain/usecases/detect_faces_usecase.dart';

part 'face_detection_event.dart';
part 'face_detection_state.dart';

// main() of FaceDetectionModule: face boxes + fps
class FaceDetectionBloc extends Bloc<FaceDetectionEvent, FaceDetectionState> {
  DetectFacesUseCase detectFaces;

  final _throttle = FrameThrottle();
  double ptime = 0;
  int frameNumber = 0;

  FaceDetectionBloc({required this.detectFaces}) : super(FaceDetectionIdle()) {
    on<FaceFrameReceived>((event, emit) async {
      await _throttle.run(event.frame, (frame) async {
        final res = await detectFaces(DetectFacesParams(frame: frame));
        if (isClosed) return;
        res.fold((failure) => debugPrint('frame error: ${failure.message}'), (faces) {
          final ctime = now();
          final fps = 1 / (ctime - ptime);
          ptime = ctime;
          debugPrint('$faces');
          emit(FaceDetectionActive(
            faces: faces,
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
    await detectFaces.dispose();
    return super.close();
  }
}
