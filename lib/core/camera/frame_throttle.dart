import 'package:ai_trainer/core/camera/camera_frame.dart';

/// While the detector is busy keep only the newest frame, and start it the moment
/// the detector is free instead of waiting for the camera's next frame.
/// One frame in flight: 2 was tested and gave the same fps (ML Kit works on one
/// frame at a time) but the skeleton lagged more.
class FrameThrottle {
  bool _busy = false;
  CameraFrame? _pending;

  Future<void> run(
    CameraFrame frame,
    Future<void> Function(CameraFrame frame) process, {
    required bool Function() isClosed,
  }) async {
    if (_busy) {
      _pending = frame;
      return;
    }
    _busy = true;
    try {
      CameraFrame? next = frame;
      while (next != null && !isClosed()) {
        await process(next);
        next = _pending;
        _pending = null;
      }
    } finally {
      _busy = false;
    }
  }
}
