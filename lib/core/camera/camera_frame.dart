import 'dart:typed_data';

import 'package:equatable/equatable.dart';

// one picture from the camera stream ("cap.read()")
class CameraFrame extends Equatable {
  final Uint8List bytes;
  final int width;
  final int height;
  final int bytesPerRow;
  final int rotationDegrees;
  final int format; // raw camera image format
  final bool isFrontCamera;
  // iOS: the camera plugin already turns the stream upright and mirrors the front camera
  // (camera_avfoundation: videoOrientation + isVideoMirrored), and ML Kit on iOS reads the
  // picture as it is (it ignores the rotation). Android sends the raw sensor picture.
  final bool isUprightStream;
  final DateTime capturedAt;

  const CameraFrame({
    required this.bytes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.rotationDegrees,
    required this.format,
    required this.isFrontCamera,
    this.isUprightStream = false,
    required this.capturedAt,
  });

  bool get isSideways => !isUprightStream && (rotationDegrees == 90 || rotationDegrees == 270);

  /// the picture the detector gets is already mirrored (iOS front camera): its results must be
  /// mirrored back, so every platform gives the same, not mirrored, coordinates and left/right
  bool get isMirroredStream => isUprightStream && isFrontCamera;

  // size of the picture after turning it upright (what the user sees)
  double get uprightWidth => (isSideways ? height : width).toDouble();
  double get uprightHeight => (isSideways ? width : height).toDouble();

  @override
  List<Object?> get props => [
    width,
    height,
    rotationDegrees,
    isFrontCamera,
    isUprightStream,
    capturedAt,
  ];
}
