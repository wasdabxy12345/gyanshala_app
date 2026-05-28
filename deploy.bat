@echo off
SETLOCAL EnableDelayedExpansion

echo ========================================================
echo 🔍 Reading configuration from pubspec.yaml...
echo ========================================================

:: 1. Parse pubspec.yaml to find the version line
set PUBSPEC_VERSION=
for /f "tokens=1,2 delims=: " %%A in (pubspec.yaml) do (
  if "%%A"=="version" (
    set RAW_VERSION=%%B
  )
)

if "%RAW_VERSION%"=="" (
  echo ❌ Error: Could not find version in pubspec.yaml!
  pause
  exit /b 1
)

:: 2. Split the version at the '+' sign (extracting 0.0.2 from 0.0.2+2)
for /f "tokens=1 delims=+" %%A in ("%RAW_VERSION%") do (
  set CLEAN_VERSION=%%A
)

:: Format the final tag name (e.g., v0.0.2)
set VERSION=v%CLEAN_VERSION%

echo Target Version found: %VERSION% (Parsed from raw value: %RAW_VERSION%)
echo.

:: 3. Prompt for release notes only
set /p NOTES="Enter Release Notes (Optional, press Enter to skip): "
if "%NOTES%"=="" set NOTES="Automated release for version %VERSION%"

echo ========================================================
echo 🚀 STARTING FULL DEPLOYMENT PIPELINE FOR %VERSION%
echo ========================================================

:: 4. Clean and Fetch Dependencies
echo Clean project cache...
call flutter clean
echo Fetching dependencies...
call flutter pub get

:: 5. Build and Deploy Web App
echo 🌐 Compiling Flutter Web...
call flutter build web --release --no-service-worker
if %ERRORLEVEL% NEQ 0 (
  echo ❌ Web compilation failed! Exiting...
  pause
  exit /b %ERRORLEVEL%
)

echo ☁️ Deploying to Vercel...
call vercel --prod --yes
if %ERRORLEVEL% NEQ 0 (
  echo ❌ Vercel deployment failed! Exiting...
  pause
  exit /b %ERRORLEVEL%
)

:: 6. Build Mobile APK
echo 📱 Compiling Android APK...
call flutter build apk --release
if %ERRORLEVEL% NEQ 0 (
  echo ❌ APK compilation failed! Exiting...
  pause
  exit /b %ERRORLEVEL%
)

:: 7. Create GitHub Release and Upload APKs
echo 🛠️ Creating GitHub Release and uploading assets...
set APK_PATH=build\app\outputs\flutter-apk\app-release.apk

call gh release create %VERSION% "%APK_PATH%" --title "Release %VERSION%" --notes "%NOTES%"
if %ERRORLEVEL% NEQ 0 (
  echo ❌ GitHub Release failed! Check if version tag already exists.
  pause
  exit /b %ERRORLEVEL%
)

echo ========================================================
echo 🎉 SUCCESS! Web deployed, APK built, and GitHub Release %VERSION% Created!
echo ========================================================
pause
