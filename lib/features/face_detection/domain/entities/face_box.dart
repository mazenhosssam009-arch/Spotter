import 'package:equatable/equatable.dart';

// FaceDetectionModule.findFaces: [id, (x, y, w, h)] in picture pixels.
// ML Kit does not give a detection score, so there is no "%".
class FaceBox extends Equatable {
  final int id;
  final int x;
  final int y;
  final int width;
  final int height;

  const FaceBox({
    required this.id,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  @override
  String toString() => '[$id, [$x, $y, $width, $height]]';

  @override
  List<Object?> get props => [id, x, y, width, height];
}
