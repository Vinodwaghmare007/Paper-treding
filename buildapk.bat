@echo off
REM ============================================================================
REM  Crypto Paper Trader - APK build helper (Windows)
REM
REM  Run this from the project ROOT folder (same folder as pubspec.yaml).
REM  Requires: Flutter SDK on PATH, Android SDK/platform-tools installed
REM  (flutter doctor should show no blocking issues for Android).
REM
REM  This script only builds/installs the APK on YOUR machine - nothing
REM  here talks to any server on its own, other than whatever Firebase
REM  project you've wired up locally via android/app/google-services.json.
REM
REM  AI Forecast backend: that feature calls a separate Python service
REM  (backend/), which is NOT part of Firebase and must be deployed on its
REM  own (see backend/Dockerfile's deploy notes for Railway/Render). Once
REM  deployed, use option 6 below to save its URL to forecast_url.txt
REM  (gitignored, per-machine) - every build/run option then bakes it in
REM  automatically via --dart-define. Until you do that, AI Forecast will
REM  always show "timed out" since it has nowhere real to call.
REM
REM  AdMob: without admob_defines.txt every build shows Google's TEST ads.
REM  For real ads, create admob_defines.txt (gitignored) with ONE line:
REM    --dart-define=ADMOB_BANNER_ANDROID=ca-app-pub-XXXX/YYYY --dart-define=ADMOB_INTERSTITIAL_ANDROID=ca-app-pub-XXXX/ZZZZ
REM  and set ADMOB_APP_ID in android\gradle.properties.
REM ============================================================================

setlocal enabledelayedexpansion
cd /d "%~dp0"

set FORECAST_URL=
if exist "forecast_url.txt" (
    set /p FORECAST_URL=<forecast_url.txt
)
set FORECAST_DEFINE=
if not "%FORECAST_URL%"=="" set FORECAST_DEFINE=--dart-define=FORECAST_API_BASE_URL=%FORECAST_URL%

set ADMOB_DEFINE=
if exist "admob_defines.txt" (
    set /p ADMOB_DEFINE=<admob_defines.txt
)
set FORECAST_DEFINE=%FORECAST_DEFINE% %ADMOB_DEFINE%

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
if "%FORECAST_URL%"=="" (
    echo  AI Forecast backend URL: NOT SET - see option 6
) else (
    echo  AI Forecast backend URL: %FORECAST_URL%
)
echo ============================================
echo  1. Debug APK   (fast, unsigned, for testing on your own device)
echo  2. Release APK (optimized, needs android\key.properties - see docs\RELEASE.md)
echo  3. Debug APK + install on connected device/emulator (adb install)
echo  4. Just run "flutter doctor" (check your setup)
echo  5. Live debug session (flutter run) - hot reload, NO rebuild per change
echo  6. Set/update the deployed AI Forecast backend URL
echo  0. Exit
echo ============================================
set /p choice="Choose an option (0-6): "

if "%choice%"=="0" exit /b 0
if "%choice%"=="4" goto doctor
if "%choice%"=="1" goto debug
if "%choice%"=="2" goto release
if "%choice%"=="3" goto debug_install
if "%choice%"=="5" goto live_debug
if "%choice%"=="6" goto set_forecast_url

echo Invalid choice.
pause
exit /b 1

:set_forecast_url
echo.
echo Paste the deployed backend's public URL from Railway/Render's dashboard
echo ^(e.g. https://your-service.onrender.com - no trailing slash^).
echo Leave blank to clear it ^(reverts to the emulator-only default^).
set /p neturl="Forecast backend URL: "
if "%neturl%"=="" (
    if exist "forecast_url.txt" del "forecast_url.txt"
    echo.
    echo Cleared. Builds will use the emulator-only default again.
) else (
    >forecast_url.txt echo %neturl%
    echo.
    echo Saved to forecast_url.txt. This file is gitignored - it stays local to
    echo this machine and every build below will now use it automatically.
)
pause
exit /b 0

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
call flutter run %FORECAST_DEFINE%
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
call flutter build apk --debug %FORECAST_DEFINE%
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
call flutter install --debug %FORECAST_DEFINE%
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
call flutter build apk --release %FORECAST_DEFINE%
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
