@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Vivian Cosmetic Shop - Backend Server
echo ============================================
echo   Starting Vivian Cosmetic Shop Backend
echo ============================================
echo.

cd /d "%~dp0"

REM ------------------------------------------------------------
REM Ensure .env exists (copy from .env.example on first run)
REM ------------------------------------------------------------
if not exist ".env" (
    if exist ".env.example" (
        echo Creating .env from .env.example...
        copy ".env.example" ".env" >NUL
        echo.
        echo NOTE: Update backend\.env with your SMTP settings to enable Email OTP.
        echo       Required: SMTP_HOST, SMTP_USERNAME, SMTP_PASSWORD
        echo.
    ) else (
        echo WARNING: .env not found and .env.example is missing.
    )
)

REM ------------------------------------------------------------
REM Start ngrok tunnel (needed for PayMongo webhooks/redirects)
REM ------------------------------------------------------------
REM Skip if ngrok is already running.
tasklist /FI "IMAGENAME eq ngrok.exe" 2>NUL | find /I "ngrok.exe" >NUL
if not errorlevel 1 (
    echo ngrok is already running. Skipping tunnel start.
) else (
    set "NGROK_EXE=%LOCALAPPDATA%\Microsoft\WinGet\Links\ngrok.exe"
    if exist "!NGROK_EXE!" (
        echo Starting ngrok tunnel: http 5000
        echo Using: !NGROK_EXE!
        REM Start in a separate window so you can see errors and keep it running.
        start "ngrok" "!NGROK_EXE!" http 5000 --log stdout --log-format logfmt
    ) else (
        REM Fallback: try to resolve ngrok from PATH
        for %%I in (ngrok.exe) do set "NGROK_EXE=%%~$PATH:I"
        if not "!NGROK_EXE!"=="" (
            echo Starting ngrok tunnel: http 5000
            echo Using: !NGROK_EXE!
            start "ngrok" "!NGROK_EXE!" http 5000 --log stdout --log-format logfmt
        ) else (
            echo ERROR: ngrok not found. Install it or ensure it is on PATH.
            echo Expected: %LOCALAPPDATA%\Microsoft\WinGet\Links\ngrok.exe
        )
    )
)

REM Activate virtual environment
if exist "venv\Scripts\activate.bat" (
    echo Activating virtual environment...
    call venv\Scripts\activate.bat
) else (
    echo Warning: Virtual environment not found!
    echo Creating virtual environment...
    python -m venv venv
    call venv\Scripts\activate.bat
    echo Installing dependencies...
    pip install -r requirements.txt
)

echo.
echo Starting Flask server on http://localhost:5000
echo.
REM Apply safe one-off schema patches (adds missing columns if needed)
set RUN_SCHEMA_PATCH_ON_STARTUP=true
python app.py

pause
