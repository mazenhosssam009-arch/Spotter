# Spotter – Flutter app

The Flutter app of Spotter. See the [main README](../README.md) for the full description.
The Chrome build supports the app interface; live camera detection requires Android or iOS.

```bash
flutter pub get
flutter run --release
```

Run the app interface in Chrome:

```bash
flutter run -d chrome
```

Build an APK for phones:

```bash
flutter build apk --release --split-per-abi
```

The phone file is `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`.
