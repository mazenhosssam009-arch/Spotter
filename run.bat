@echo off
rem Starts the emulator (if it is not running) and runs the app on it.
rem
rem   run.bat            -> debug build: hot reload, breakpoints, print() in the console
rem   run.bat --release  -> fast build (~2x fps) but NO hot reload and NO debug output
setlocal
set ANDROID_HOME=%LOCALAPPDATA%\Android\Sdk
if not defined JAVA_HOME set "JAVA_HOME=C:\Program Files\Android\Android Studio\jbr"
set PATH=C:\src\flutter\bin;%ANDROID_HOME%\platform-tools;%ANDROID_HOME%\emulator;%PATH%
set AVD_NAME=Pixel_9_Pro_API_36
cd /d "%~dp0"

adb devices | findstr /R "emulator-[0-9]*.*device$" >nul
if errorlevel 1 (
    echo Starting emulator %AVD_NAME%...
    start "" emulator -avd %AVD_NAME% -no-snapshot-load
    adb wait-for-device
    :waitboot
    for /f %%i in ('adb shell getprop sys.boot_completed 2^>nul') do if "%%i"=="1" goto booted
    timeout /t 2 >nul
    goto waitboot
)
:booted
rem makes sure the camera / ML Kit plugins are registered in the build
call flutter pub get
if /I "%~1"=="--release" (
    flutter run --release
) else (
    flutter run
)
