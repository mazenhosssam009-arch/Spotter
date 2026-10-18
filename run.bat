@echo off
rem Starts the emulator (if it is not running) and runs the app on it.
set ANDROID_HOME=C:\dev\android-sdk
set JAVA_HOME=C:\Program Files\Java\jdk-21
set PATH=C:\dev\flutter\bin;C:\dev\android-sdk\platform-tools;C:\dev\android-sdk\emulator;%PATH%
cd /d "%~dp0"

adb devices | findstr /R "emulator-[0-9]*.*device$" >nul
if errorlevel 1 (
    echo Starting emulator AI_Trainer_Phone...
    start "" emulator -avd AI_Trainer_Phone -no-snapshot-load
    adb wait-for-device
    :waitboot
    for /f %%i in ('adb shell getprop sys.boot_completed 2^>nul') do if "%%i"=="1" goto booted
    timeout /t 2 >nul
    goto waitboot
)
:booted
rem makes sure the camera / ML Kit plugins are registered in the build
call flutter pub get
rem release mode: about 2x the fps of the default debug mode (no hot reload)
flutter run --release
