import 'package:dartz/dartz.dart';
import 'package:ai_trainer/core/error/failure.dart';
import 'package:ai_trainer/core/usecases/usecase.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/exercise.dart';
import 'package:ai_trainer/features/pose_coaching/domain/repositories/i_exercise_repository.dart';

// Main.py: the exercises in the "choose your training" menu
class GetExercisesUseCase implements UseCase<List<Exercise>, NoParams> {
  IExerciseRepository exerciseRepository;
  GetExercisesUseCase({required this.exerciseRepository});

  @override
  Future<Either<Failure, List<Exercise>>> call(NoParams params) =>
      exerciseRepository.getExercises();
}
