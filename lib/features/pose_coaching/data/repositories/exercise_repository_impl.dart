import 'package:dartz/dartz.dart';
import 'package:ai_trainer/core/error/failure.dart';
import 'package:ai_trainer/features/pose_coaching/data/datasources/exercise_local_data_source.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/exercise.dart';
import 'package:ai_trainer/features/pose_coaching/domain/repositories/i_exercise_repository.dart';

class ExerciseRepositoryImpl implements IExerciseRepository {
  ExerciseLocalDataSource exerciseLocalDataSource;
  ExerciseRepositoryImpl({required this.exerciseLocalDataSource});

  @override
  Future<Either<Failure, List<Exercise>>> getExercises() async =>
      Right(exerciseLocalDataSource.getExercises());
}
