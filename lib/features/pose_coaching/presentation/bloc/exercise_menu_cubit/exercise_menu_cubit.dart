import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:ai_trainer/core/usecases/usecase.dart';
import 'package:ai_trainer/features/pose_coaching/domain/entities/exercise.dart';
import 'package:ai_trainer/features/pose_coaching/domain/usecases/get_exercises_usecase.dart';

part 'exercise_menu_state.dart';

// Main.py: choose your training
class ExerciseMenuCubit extends Cubit<ExerciseMenuState> {
  GetExercisesUseCase getExercises;

  ExerciseMenuCubit({required this.getExercises}) : super(ExerciseMenuLoading());

  Future<void> load() async {
    final res = await getExercises(NoParams());
    res.fold(
      (failure) => emit(ExerciseMenuError(message: failure.message)),
      (exercises) => emit(ExerciseMenuLoaded(exercises: exercises)),
    );
  }
}
