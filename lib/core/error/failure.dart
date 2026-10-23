import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable {
  final String message;
  const Failure({this.message = 'Unexpected failure occurred'});

  @override
  List<Object?> get props => [message];
}

class PoseFailure extends Failure {
  const PoseFailure({super.message = 'Pose Failure'});
}

class CacheFailure extends Failure {
  const CacheFailure({super.message = 'Cache Failed'});
}
