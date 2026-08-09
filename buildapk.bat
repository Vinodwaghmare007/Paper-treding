@echo off
REM ============================================================================
REM  Crypto Paper Trader - APK build helper (Windows)
REM
REM  Run this from the project ROOT folder (same folder as pubspec.yaml).
REM  Requires: Flutter SDK on PATH, Android SDK/platform-tools installed
REM  (flutter doctor should show no blocking issues for Android).
REM
REM  This script only builds/installs the APK on YOUR machine - nothing
REM  here talks to any server. There is currently no live backend hosted
REM  anywhere for this app (see the chat reply for details), so debug
REM  builds will use whatever Firebase project you've wired up locally
REM  via android/app/google-services.json.
REM ============================================================================

setlocal enabledelayedexpansion
cd /d "%~dp0"

where flutter >nul 2>nul
if errorlevel 1 (
    echo [ERROR] "flutter" command not found on PATH.
    echo Install Flutter SDK and add it to PATH, then run this script again.
    pause
    exit /b 1
)

echo.
echo ============================================
echo  Crypto Paper Trader - APK Build
echo ============================================
echo  1. Debug APK   (fast, unsigned, for testing on your own device)
echo  2. Release APK (optimized, needs android\key.properties - see docs\RELEASE.md)
echo  3. Debug APK + install on connected device/emulator (adb install)
echo  4. Just run "flutter doctor" (check your setup)
echo  5. Live debug session (flutter run) - hot reload, NO rebuild per change
echo  0. Exit
echo ============================================
set /p choice="Choose an option (0-5): "

if "%choice%"=="0" exit /b 0
if "%choice%"=="4" goto doctor
if "%choice%"=="1" goto debug
if "%choice%"=="2" goto release
if "%choice%"=="3" goto debug_install
if "%choice%"=="5" goto live_debug

echo Invalid choice.
pause
exit /b 1

:doctor
call flutter doctor -v
pause
exit /b 0

:live_debug
call :prepare
echo.
echo [2/2] Starting live debug session on a connected device/emulator...
echo   - Press "r" to hot reload after saving a code change (usually under 1s)
echo   - Press "R" for a hot restart (resets app state, still no full rebuild)
echo   - Press "q" to quit
echo   This needs a device connected over USB with USB debugging on
echo   (or an emulator already running) - check "adb devices" if it hangs.
echo.
call flutter run
pause
exit /b 0

:prepare
echo.
echo [1/2] Getting Flutter/Dart packages...
call flutter pub get
if errorlevel 1 (
    echo [ERROR] "flutter pub get" failed - fix the error above and re-run.
    pause
    exit /b 1
)
exit /b 0

:debug
call :prepare
echo.
echo [2/2] Building DEBUG APK...
call flutter build apk --debug
if errorlevel 1 (
    echo [ERROR] Build failed - see the error above.
    pause
    exit /b 1
)
echo.
echo Done. Debug APK is at:
echo   build\app\outputs\flutter-apk\app-debug.apk
pause
exit /b 0

:debug_install
call :prepare
echo.
echo [2/2] Building and installing DEBUG APK on a connected device/emulator...
call flutter install --debug
if errorlevel 1 (
    echo [ERROR] Build/install failed - is a device connected? Check "adb devices".
    pause
    exit /b 1
)
echo.
echo Installed. You can also view live logs with:
echo   flutter logs
pause
exit /b 0

:release
call :prepare
if not exist "android\key.properties" (
    echo.
    echo [WARNING] android\key.properties not found.
    echo A release build will fall back to DEBUG signing ^(see docs\RELEASE.md,
    echo section 1^) - fine for local testing, but NOT for a real Play Store
    echo upload. Generate a real keystore first if this is for Play Store.
    echo.
)
echo.
echo [2/2] Building RELEASE APK...
call flutter build apk --release
if errorlevel 1 (
    echo [ERROR] Build failed - see the error above.
    pause
    exit /b 1
)
echo.
echo Done. Release APK is at:
echo   build\app\outputs\flutter-apk\app-release.apk
echo.
echo Reminder: docs\RELEASE.md step 4 says to actually INSTALL and test this
echo release build before trusting it - R8/ProGuard can break things that
echo work fine in debug.
pause
exit /b 0
