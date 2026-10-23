import 'package:equatable/equatable.dart';

// PoseModule.findAngle result: the 3 joints and the raw 0-360 angle
class JointAngle extends Equatable {
  final List<int> joints;
  final double angle;

  const JointAngle({required this.joints, required this.angle});

  @override
  List<Object?> get props => [joints, angle];
}
