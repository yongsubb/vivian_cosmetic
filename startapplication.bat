@echo off
title Vivian Cosmetic Shop - Flutter Application
echo ============================================
echo   Starting Vivian Cosmetic Shop Application
echo   Multi-Platform Support (No Web)
echo ============================================
echo.

cd /d "%~dp0"

REM Check if Flutter is available
where flutter >nul 2>nul
if %errorlevel% neq 0 (
    echo Error: Flutter is not installed or not in PATH!
    echo Please install Flutter and add it to your system PATH.
    pause
    exit /b 1
)

REM Get dependencies
echo Getting Flutter dependencies...
call flutter pub get

echo.
echo ============================================
echo   Choose a platform to run:
echo ============================================
echo   1. Windows (Desktop)
echo   2. Android (Phone/Tablet - Device/Emulator)
echo   3. iOS (iPhone/iPad - Requires Mac)
echo   4. macOS (Desktop - Requires Mac)
echo   5. Linux (Desktop - Requires Linux)
echo   6. List Available Devices
echo   7. Exit
echo ============================================
echo.

set /p choice="Enter your choice (1-7): "

if "%choice%"=="1" (
    echo.
    echo Starting Windows application...
    flutter run -d windows
) else if "%choice%"=="2" (
    echo.
    echo Starting Android application...
    echo Note: Make sure Android emulator is running or device is connected
    flutter run -d android
) else if "%choice%"=="3" (
    echo.
    echo Starting iOS application...
    echo Note: iOS development requires a Mac with Xcode
    flutter run -d ios
) else if "%choice%"=="4" (
    echo.
    echo Starting macOS application...
    echo Note: macOS development requires a Mac
    flutter run -d macos
) else if "%choice%"=="5" (
    echo.
    echo Starting Linux application...
    echo Note: Linux development requires Linux OS
    flutter run -d linux
) else if "%choice%"=="6" (
    echo.
    echo Available devices:
    echo ============================================
    flutter devices
    echo.
    echo Press any key to return to menu...
    pause >nul
    call "%~f0"
) else if "%choice%"=="7" (
    echo Exiting...
    exit /b 0
) else (
    echo Invalid choice!
    pause
    exit /b 1
)

pause
