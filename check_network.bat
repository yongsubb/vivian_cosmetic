@echo off
title Network Access - IP Check
color 0A
echo.
echo ========================================
echo   VIVIAN COSMETIC SHOP
echo   Network Access Information
echo ========================================
echo.
echo Getting your computer's IP address...
echo.

for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /c:"IPv4 Address"') do (
    set IP=%%a
    set IP=!IP:~1!
    echo [FOUND] Your IP Address: !IP!
    echo.
)

echo ========================================
echo   Backend Configuration
echo ========================================
echo   Backend URL: http://192.168.1.4:5000
echo   XAMPP MySQL: Port 3306
echo   API Endpoints: /api/*
echo ========================================
echo.
echo ========================================
echo   How to Connect from Other Devices
echo ========================================
echo   1. Make sure device is on SAME WiFi
echo   2. Start backend: cd backend ^&^& python app.py
echo   3. Test in browser: http://192.168.1.4:5000
echo   4. Run Flutter app on device
echo ========================================
echo.
echo ========================================
echo   Current Device Configuration
echo ========================================
echo   - Windows: Uses localhost:5000
echo   - Android: Uses 192.168.1.4:5000
echo   - Android Emulator: Uses 10.0.2.2:5000
echo   - iOS: Uses localhost:5000
echo ========================================
echo.
echo Checking if backend is running...
echo.

curl -s http://localhost:5000 >nul 2>&1
if %errorlevel% == 0 (
    echo [OK] Backend is running!
    echo [OK] Accessible at: http://192.168.1.4:5000
) else (
    echo [WARNING] Backend is NOT running!
    echo [ACTION] Start it with: cd backend ^&^& python app.py
)

echo.
echo ========================================
echo   Firewall Check
echo ========================================
echo   Make sure Windows Firewall allows:
echo   - Python.exe (Port 5000)
echo   - Incoming connections from local network
echo.
echo   To add firewall rule, run as Administrator:
echo   netsh advfirewall firewall add rule name="Flask Backend" dir=in action=allow protocol=TCP localport=5000
echo ========================================
echo.
echo Press any key to test network connection...
pause >nul

echo.
echo Testing localhost connection...
curl -s -o nul -w "Status: %%{http_code}\n" http://localhost:5000
echo.

echo.
echo ========================================
echo   Next Steps
echo ========================================
echo   1. Start XAMPP MySQL
echo   2. Start backend: cd backend ^&^& python app.py
echo   3. Connect Android device via USB
echo   4. Run: flutter run -d android
echo   5. Or use: startapplication.bat
echo ========================================
echo.
pause
