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
echo 🚀 STARTING PARALLEL DEPLOYMENT PIPELINE FOR %VERSION%
echo ========================================================

if exist web_done.tmp del web_done.tmp
if exist web_failed.tmp del web_failed.tmp

echo 🛠️ Launching Parallel Builds (Web and Android)...

:: --- WEB PROCESS (Background) ---
echo 🌐 [Web] Starting Web compilation and Vercel deployment...
start /b "" cmd /c "echo 🌐 [Web] Compiling... && flutter build web --release && echo ☁️ [Web] Deploying to Vercel... && cd build\web && vercel link --yes && vercel --prod --yes && cd ..\.. && echo ✅ [Web] Web Deployment Complete! && echo done > ..\..\web_done.tmp" || (echo done > web_failed.tmp && exit /b 1)

:: --- ANDROID PROCESS (Foreground) ---
echo 📱 [Android] Compiling Android APK...
call flutter build apk --release --no-pub
if %ERRORLEVEL% NEQ 0 (
  echo ❌ Android compilation failed. Exiting...
  del web_done.tmp
  pause
  exit /b %ERRORLEVEL%
)

set "ORIGINAL_APK=build\app\outputs\flutter-apk\app-release.apk"
set "RENAMED_APK=build\app\outputs\flutter-apk\gyanshala app %VERSION%.apk"
echo 🏷️ [Android] Renaming APK...
copy /y "%ORIGINAL_APK%" "%RENAMED_APK%" >nul
echo ✅ [Android] APK Ready!

:: --- WAIT FOR WEB TO FINISH ---
echo ⏳ Waiting for Web deployment pipeline to wrap up...
:loop
if exist web_failed.tmp (
  echo ❌ Background Web build or Vercel deployment failed! Check logs.
  del web_failed.tmp >nul
  pause
  exit /b 1
)
if not exist web_done.tmp (
  timeout /t 3 /nobreak >nul
  goto loop
)
del web_done.tmp >nul

:: ========================================================
:: 5. Create GitHub Release
:: ========================================================
echo 🛠️ Creating GitHub Release and uploading assets...
gh release create "%VERSION%" "%RENAMED_APK%" --title "Release %VERSION%" --notes "%NOTES%" --target main

if %ERRORLEVEL% NEQ 0 (
  echo ❌ GitHub Release failed. Check if version tag already exists.
  ) else (
  echo 🎉 PIPELINE SUCCESSFUL FOR %VERSION%!
)

pause
