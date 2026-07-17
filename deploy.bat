@echo off
setlocal enabledelayedexpansion

chcp 65001 >nul

echo ========================================================
echo 🔍 Reading configuration from pubspec.yaml...
echo ========================================================

for /f "tokens=2 delims=: " %%a in ('findstr /r "^version:" pubspec.yaml') do set RAW_VERSION=%%a
for /f "tokens=1 delims=+" %%a in ("%RAW_VERSION%") do set VERSION_NUM=%%a

set VERSION=v%VERSION_NUM%
echo Target Version found: %VERSION%
echo.

:: Check if user passed a clean argument (e.g. script.bat clean)
set "CLEAN_FIRST=false"
if /i "%~1"=="clean" set "CLEAN_FIRST=true"

if "%CLEAN_FIRST%"=="true" (
  echo 🧹 Hard cleanup requested...
  call flutter clean
)

set /p NOTES="Enter Release Notes (Optional, press Enter to skip): "

echo ========================================================
echo 🚀 STARTING DEPLOYMENT PIPELINE FOR %VERSION%
echo ========================================================

:: --- ANDROID PROCESS ---
echo 📱 [Android] Compiling Android APK...
call flutter build apk --release --no-pub --split-debug-info=build/app/outputs/symbols --no-shrink
if %ERRORLEVEL% NEQ 0 (
  echo ❌ Android compilation failed. Exiting...
  pause
  exit /b %ERRORLEVEL%
)

set "ORIGINAL_APK=build\app\outputs\flutter-apk\app-release.apk"
set "RENAMED_APK=build\app\outputs\flutter-apk\gyanshala app %VERSION%.apk"
echo 🏷️ [Android] Renaming APK...
copy /y "%ORIGINAL_APK%" "%RENAMED_APK%" >nul
echo ✅ [Android] APK Ready!

:: --- GIT & GITHUB RELEASE ---
echo 🛠️ Creating GitHub Release on Public Repository...
:: Pushes the release and APK directly to the public repository gyanshala-dev/gyanshala_app
gh release create "%VERSION%" "%RENAMED_APK%" --repo "gyanshala-dev/gyanshala_app" --title "Release %VERSION%" --notes "%NOTES%"

if %ERRORLEVEL% NEQ 0 (
  echo ❌ GitHub Release failed. Check if version tag already exists, or if 'gh' CLI is authenticated and has access to gyanshala-dev/gyanshala_app.
) else (
  echo.
  echo ========================================================
  echo 🎉 PIPELINE SUCCESSFUL FOR %VERSION%!
  echo 📦 APK successfully published to: https://github.com/gyanshala-dev/gyanshala_app
  echo ========================================================
)

pause