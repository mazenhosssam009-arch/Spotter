import 'package:equatable/equatable.dart';

class BodyLandmark extends Equatable {
  final int id;
  final double x;
  final double y;
  final double z;
  final double likelihood;

  const BodyLandmark({
    required this.id,
    required this.x,
    required this.y,
    required this.z,
    required this.likelihood,
  });

  // same rule mediapipe uses when drawing: visibility > 0.5
  static const double minVisibleLikelihood = 0.5;

  bool get isVisible => likelihood >= minVisibleLikelihood;

  @override
  List<Object?> get props => [id, x, y, z, likelihood];
}
