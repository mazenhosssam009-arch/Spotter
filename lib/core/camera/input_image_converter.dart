import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:ai_trainer/core/camera/camera_frame.dart';

class ConvertedImage {
  final InputImage inputImage;
  // the detector gets a smaller copy of the picture; multiply its results by this
  // to get pixels of the real picture
  final double scale;
  // the detector saw a mirrored picture (iOS front camera): x must be turned back with
  // [toX] and the left/right results swapped
  final bool mirrored;
  // width of the upright picture in real pixels (to mirror x back)
  final double uprightWidth;

  const ConvertedImage({
    required this.inputImage,
    required this.scale,
    this.mirrored = false,
    this.uprightWidth = 0,
  });

  /// a detector x (in the detector picture) -> x in pixels of the real, not mirrored picture
  double toX(double x) => mirrored ? uprightWidth - x * scale : x * scale;
}

// CameraFrame -> ML Kit InputImage ("imgRGB"), shared by pose and face detection
class InputImageConverter {
  ConvertedImage? convert(CameraFrame frame) {
    final rotation = InputImageRotationValue.fromRawValue(frame.rotationDegrees);
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(frame.format);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }

    var bytes = frame.bytes;
    var width = frame.width, height = frame.height, bytesPerRow = frame.bytesPerRow;
    // only when the buffer really is a full NV21 picture (Y rows + V/U rows) and big enough
    // to be worth shrinking
    if (Platform.isAndroid &&
        width > 800 &&
        bytes.length >= bytesPerRow * (height + height ~/ 2 - 1) + width) {
      (bytes, width, height) = _halfSize(bytes, width, height, bytesPerRow);
      bytesPerRow = width;
    }

    return ConvertedImage(
      inputImage: InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(width.toDouble(), height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: bytesPerRow,
        ),
      ),
      scale: frame.width / width,
      mirrored: frame.isMirroredStream,
      uprightWidth: frame.uprightWidth,
    );
  }

  /// NV21 picture at half the width and height (every 2nd pixel), so less data
  /// has to be copied to ML Kit and converted. Same shape, so same angles.
  /// Only used for big pictures (wider than 800 px); the 640x480 stream goes as it is.
  static (Uint8List, int, int) _halfSize(Uint8List src, int width, int height, int stride) {
    final w2 = (width ~/ 2) & ~1, h2 = (height ~/ 2) & ~1;
    final out = Uint8List(w2 * h2 * 3 ~/ 2);
    // Y plane
    var o = 0;
    for (var y = 0; y < h2; y++) {
      var s = 2 * y * stride;
      for (var x = 0; x < w2; x++, s += 2) {
        out[o++] = src[s];
      }
    }
    // interleaved V/U plane (one V,U pair for every 2x2 pixels)
    final vu = stride * height;
    for (var y = 0; y < h2 ~/ 2; y++) {
      var s = vu + 2 * y * stride;
      for (var x = 0; x < w2 ~/ 2; x++, s += 4) {
        out[o++] = src[s];
        out[o++] = src[s + 1];
      }
    }
    return (out, w2, h2);
  }
}
