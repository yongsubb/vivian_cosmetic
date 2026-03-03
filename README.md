# Vivian Cosmetic Shop Application

A multi-platform Flutter application for managing a cosmetic shop with inventory, sales, customers, and reporting features.

## 🎯 Supported Platforms

This application runs on **ALL native platforms** (NO WEB):
- ✅ **Windows** (Desktop)
- ✅ **Android** (Phones & Tablets)
- ✅ **iOS** (iPhones & iPads - requires Mac)
- ✅ **macOS** (Desktop - requires Mac)
- ✅ **Linux** (Desktop)

## 📋 Prerequisites

### Required for All Platforms:
1. **Flutter SDK** (version 3.9.2 or higher)
   - Download: https://flutter.dev/docs/get-started/install
   - Add Flutter to your system PATH
2. **XAMPP** (for MySQL database)
3. **Python 3.9+** (for backend)

### Platform-Specific Requirements:

#### Windows Development:
- Visual Studio 2022 or Visual Studio Build Tools
- Windows 10 or higher

#### Android Development:
- Android Studio
- Android SDK
- Android Emulator or physical device with USB debugging enabled

#### iOS Development (Mac only):
- Xcode (latest version)
- CocoaPods
- iOS Simulator or physical device

#### macOS Development (Mac only):
- Xcode (latest version)

#### Linux Development (Linux only):
- Required Linux libraries (install via `flutter doctor`)

## 🚀 Quick Start Guide

### Step 1: Setup the Backend

1. **Start XAMPP MySQL:**
   ```bash
   # Open XAMPP Control Panel and start MySQL
   ```

2. **Configure Database:**
   - Open phpMyAdmin: http://localhost/phpmyadmin
   - Import the database schema from `backend/database/schema.sql`

3. **Setup Backend Environment:**
   ```bash
   cd backend
   pip install -r requirements.txt
   # Copy .env.example to .env and configure if needed
   ```

4. **Run Backend:**
   ```bash
   cd backend
   python app.py
   ```
   Or use: `backend\startbackend.bat`

### Step 2: Run the Flutter Application

#### Easy Method - Use the Launcher:
```bash
cd c:\xampp\htdocs\vivian_cosmetic_shop_application
startapplication.bat
```

Then select your platform:
1. Windows (Desktop)
2. Android (Phone/Tablet)
3. iOS (iPhone/iPad)
4. macOS (Desktop)
5. Linux (Desktop)
6. List Available Devices
7. Exit

#### Manual Method:
```bash
cd c:\xampp\htdocs\vivian_cosmetic_shop_application

# Get dependencies first
flutter pub get

# Then run on your platform:
flutter run -d windows      # For Windows
flutter run -d android      # For Android
flutter run -d ios          # For iOS (Mac only)
flutter run -d macos        # For macOS (Mac only)
flutter run -d linux        # For Linux
```

## 📱 Platform-Specific Notes

### Windows:
- The app runs as a native Windows desktop application
- Recommended resolution: 1280x720 or higher

### Android:
- **Emulator**: Start Android emulator before running the app
- **Physical Device**: 
  1. Enable USB debugging in Developer Options
  2. Connect via USB
  3. Accept debugging permission on device

### iOS (Requires Mac):
- First time setup: `cd ios && pod install`
- Sign your app in Xcode with your Apple ID
- For physical device: Trust the developer certificate on device

### macOS (Requires Mac):
- Runs as native macOS application
- May require entitlements for network access

### Linux:
- Install required dependencies: `sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev`

## 🔧 Troubleshooting

### Check Available Devices:
```bash
flutter devices
```

### Check Flutter Installation:
```bash
flutter doctor
```

### Common Issues:

**"No devices found"**
- Windows: Enable Windows desktop support: `flutter config --enable-windows-desktop`
- Android: Start emulator or connect device with USB debugging
- Check with: `flutter devices`

**Build Errors:**
- Run: `flutter clean && flutter pub get`
- Update Flutter: `flutter upgrade`

**Backend Connection Issues:**
- Ensure backend is running on http://localhost:5000
- Check MySQL is running in XAMPP
- Verify `.env` file in backend directory

## 🎨 Features

- Point of Sale (POS) system
- Inventory management
- Customer loyalty program
- Sales reporting and analytics
- Offline mode support
- Barcode scanning
- Receipt printing/PDF export
- Multi-user support with roles
- Dark mode support
- Responsive design for all screen sizes

## 📖 Additional Documentation

- [Phase 17: Error Handling](PHASE_17_ERROR_HANDLING_SUMMARY.md)
- [Phase 18: Implementation Report](PHASE_18_IMPLEMENTATION_REPORT.md)
- [Phase 19-20: Implementation Guide](PHASE_19_20_IMPLEMENTATION_GUIDE.md)

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
