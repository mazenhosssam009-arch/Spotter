import 'package:dartz/dartz.dart';
import 'package:ai_trainer/core/error/failure.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/exercise.dart';

abstract class IExerciseRepository {
  Future<Either<Failure, List<Exercise>>> getExercises();
}
