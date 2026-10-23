class ExceptionHandler {
  static String poseExceptionHandler(String code) {
    return switch (code) {
      'unsupported-frame' =>
        "This camera's picture format isn't supported on this device.",
      'pose-detection-failed' =>
        "Couldn't read your pose from the camera. Please try again.",
      'face-detection-failed' =>
        "Couldn't detect faces from the camera. Please try again.",
      _ => 'Something went wrong with the camera tracking. Please try again.',
    };
  }
}
