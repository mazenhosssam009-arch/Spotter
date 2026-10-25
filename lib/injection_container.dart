import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_trainer/core/camera/input_image_converter.dart';
import 'package:ai_trainer/features/face_detection/data/datasources/face_detector_data_source.dart';
import 'package:ai_trainer/features/face_detection/data/repositories/face_detector_impl.dart';
import 'package:ai_trainer/features/face_detection/domain/repositories/i_face_detector.dart';
import 'package:ai_trainer/features/face_detection/domain/usecases/detect_faces_usecase.dart';
import 'package:ai_trainer/features/face_detection/presentation/bloc/face_detection_bloc.dart';
import 'package:ai_trainer/features/pose_coaching/data/datasources/exercise_local_data_source.dart';
import 'package:ai_trainer/features/pose_coaching/data/datasources/landmark_smoother.dart';
import 'package:ai_trainer/features/pose_coaching/data/datasources/pose_detector_data_source.dart';
import 'package:ai_trainer/features/pose_coaching/data/repositories/exercise_repository_impl.dart';
import 'package:ai_trainer/features/pose_coaching/data/repositories/pose_estimator_impl.dart';
import 'package:ai_trainer/features/pose_coaching/domain/repositories/i_exercise_repository.dart';
import 'package:ai_trainer/features/pose_coaching/domain/repositories/i_pose_estimator.dart';
import 'package:ai_trainer/features/pose_coaching/domain/usecases/detect_pose_usecase.dart';
import 'package:ai_trainer/features/pose_coaching/domain/usecases/get_exercises_usecase.dart';
import 'package:ai_trainer/features/pose_coaching/domain/usecases/process_pose_frame_usecase.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/bloc/exercise_menu_cubit/exercise_menu_cubit.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/bloc/pose_bloc/pose_bloc.dart';
import 'package:ai_trainer/features/pose_coaching/presentation/bloc/trainer_bloc/trainer_bloc.dart';
import 'package:ai_trainer/features/voice_coach/data/datasources/tts_engine.dart';
import 'package:ai_trainer/features/voice_coach/data/datasources/voice_command_listener.dart';
import 'package:ai_trainer/features/voice_coach/data/datasources/voice_settings_store.dart';
import 'package:ai_trainer/features/voice_coach/presentation/cubit/voice_settings_cubit.dart';
import 'package:ai_trainer/features/voice_coach/presentation/voice_coach.dart';

final sl = GetIt.instance;

// one init(), Bloc = factory, stateless things = lazy singleton.
// The ML Kit detectors and the landmark smoother keep state (tracking between
// frames), so every screen gets its own: they are factories and the bloc closes them.
Future<void> init() async {
  initPoseCoaching();
  initFaceDetection();
  initCore();
  await initVoiceCoach();
}

void initPoseCoaching() {
  // Bloc
  sl.registerFactory(() => ExerciseMenuCubit(getExercises: sl()));
  sl.registerFactory(() => TrainerBloc(processPoseFrame: sl()));
  sl.registerFactory(() => PoseBloc(detectPose: sl()));

  // Use cases
  sl.registerLazySingleton(() => GetExercisesUseCase(exerciseRepository: sl()));
  sl.registerFactory(() => ProcessPoseFrameUseCase(poseEstimator: sl()));
  sl.registerFactory(() => DetectPoseUseCase(poseEstimator: sl()));

  // Repositories
  sl.registerLazySingleton<IExerciseRepository>(
    () => ExerciseRepositoryImpl(exerciseLocalDataSource: sl()),
  );
  sl.registerFactory<IPoseEstimator>(
    () => PoseEstimatorImpl(poseDetectorDataSource: sl(), landmarkSmoother: sl()),
  );

  // Data sources
  sl.registerLazySingleton<ExerciseLocalDataSource>(() => ExerciseLocalDataSourceImpl());
  sl.registerFactory<PoseDetectorDataSource>(
    () => PoseDetectorDataSourceImpl(inputImageConverter: sl()),
  );
  sl.registerFactory(() => LandmarkSmoother());
}

void initFaceDetection() {
  // Bloc
  sl.registerFactory(() => FaceDetectionBloc(detectFaces: sl()));

  // Use cases
  sl.registerFactory(() => DetectFacesUseCase(faceDetector: sl()));

  // Repositories
  sl.registerFactory<IFaceDetector>(() => FaceDetectorImpl(faceDetectorDataSource: sl()));

  // Data sources
  sl.registerFactory<FaceDetectorDataSource>(
    () => FaceDetectorDataSourceImpl(inputImageConverter: sl()),
  );
}

void initCore() {
  sl.registerLazySingleton(() => InputImageConverter());
}

// one voice and one microphone for the whole app; the settings cubit is app-wide so a
// change in the settings screen is heard at once. Every workout gets its own VoiceCoach.
Future<void> initVoiceCoach() async {
  final prefs = await SharedPreferences.getInstance();
  sl.registerLazySingleton(() => VoiceSettingsStore(prefs));
  sl.registerLazySingleton(() => TtsEngine());
  sl.registerLazySingleton(() => VoiceCommandListener());
  sl.registerLazySingleton(() => VoiceSettingsCubit(store: sl(), engine: sl()));
  sl.registerFactory(() => VoiceCoach(settings: sl(), engine: sl(), store: sl(), listener: sl()));
}
