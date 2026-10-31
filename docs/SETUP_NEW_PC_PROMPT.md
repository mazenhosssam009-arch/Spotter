Set up this brand-new Windows PC so I can build and run the Spotter Flutter app, the same way it works on my other PC. The project is already cloned from GitHub (the Flutter project is the `Spotter` folder, where `pubspec.yaml` is). Nothing is installed yet: no Flutter, no Dart, no Java, no Android tools. The PC has plenty of disk space, so install the full Android Studio app (with its SDK Manager and Device Manager), not just the command-line SDK and emulator.

Match these exact versions (they are what the project builds with on my other PC):
- Flutter 3.47.7, stable channel (comes with Dart 3.13.5; pubspec needs Dart ^3.13.5)
- JDK 21 (the project compiles for Java 17; Gradle 9.3.1 and Android Gradle Plugin 9.1.0 run on JDK 21)
- Android SDK: platforms android-34, android-35 and android-36; build-tools 36.0.0; NDK 28.2.13676358; CMake 3.22.1; platform-tools; emulator; command-line tools (latest)
- Emulator: an AVD named `AI_Trainer_Phone` (run.bat starts it by this name) on the latest stable Android version and the newest Pixel phone that Android Studio's Device Manager offers. Use the x86_64 "Google Play" system image (Google APIs if no Play image exists for that version), a hardware profile no older than Pixel 9, front camera = webcam0, back camera = emulated (the app uses the camera for pose detection). Give it at least 4 GB RAM and 8 GB storage. If the latest Android version is newer than API 36, also install that SDK platform. Tell me which Android version and device you picked.

Use these install locations so the project's `run.bat` works without edits:
- Flutter in `C:\dev\flutter` (add `C:\dev\flutter\bin` to my user PATH)
- Android SDK in `C:\dev\android-sdk` (choose this folder in Android Studio's setup wizard; set ANDROID_HOME to it; add its `platform-tools` and `emulator` folders to PATH)
- JDK 21 in `C:\Program Files\Java\jdk-21` (or point `flutter config --jdk-dir` at whichever JDK 21 you install, and tell me if run.bat needs a different JAVA_HOME)

Steps:
1. Install Git if missing, JDK 21, and Android Studio (winget is fine: e.g. `Microsoft.OpenJDK.21` or Oracle JDK 21, and `Google.AndroidStudio`). Get Flutter by cloning the stable channel into `C:\dev\flutter` and checking out tag 3.47.7.
2. In Android Studio's SDK Manager (or with sdkmanager), install every SDK component listed above, then create the `AI_Trainer_Phone` emulator in Device Manager. Accept all Android licenses (`flutter doctor --android-licenses`).
3. Run `flutter doctor -v` and fix everything it reports for Android and Windows. Ignore Visual Studio / Chrome / iOS warnings unless they block the Android build.
4. In the `Spotter` folder: `flutter pub get`, then `flutter test` (all 8 tests should pass), then `flutter build apk --release --split-per-abi`. The phone APK is `build\app\outputs\flutter-apk\app-arm64-v8a-release.apk`.
5. Start the emulator and run the app on it with `run.bat` (it starts the emulator, then runs `flutter run --release`). Confirm the app opens and the camera preview works. If the app fails only on the newest Android version, tell me instead of changing the code.
6. Optional, only if I ask for it later: the voice recording tools in `tool/` need Python 3.12 and `pip install lameenc truststore` (`faster-whisper` only for checking clips). The Gemini key is only ever set in the terminal (`$env:GEMINI_API_KEY = "..."`); never write it into a file or commit it.

Known issues from the other PC:
- If Gradle cannot find a package that `flutter pub get` downloaded (for example audio_session), the pub cache landed somewhere Gradle cannot read. Set the environment variable PUB_CACHE to a folder outside AppData, such as `C:\Users\<me>\flutter_pub_cache`, then run `flutter pub get` again.
- My phone is an Infinix X6873 (Android 16). To install on it, I turn on USB debugging and plug it in; `adb devices` must list it, then `adb install -r` the arm64 APK.

Rules:
- Do not change project files to make the setup work without asking me first. The project already builds on my other PC, so a build error here means something is missing or misconfigured on this PC.
- Never create a git branch. I commit to `main` myself.
- When everything works, give me a short summary: what you installed, where, the versions, and anything I still need to do by hand.
