import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'core/services/app_lifecycle_service.dart';
import 'core/services/error_handler.dart';
import 'core/services/inactivity_service.dart';
import 'core/services/in_app_notification_service.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/responsive_navigation.dart';
import 'screens/login_screen.dart';
import 'screens/pin_lock_screen.dart';
import 'services/api_service.dart';
import 'offline/offline_store.dart';
import 'state/auth_provider.dart';
import 'state/cart_provider.dart';
import 'state/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize window manager for desktop platforms (Windows, macOS, Linux)
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux)) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      size: Size(1280, 800),
      minimumSize: Size(800, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: 'Vivian Cosmetic Shop',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setFullScreen(true);
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // Initialize global error handler
  ErrorHandler.initialize();

  // Initialize local offline store (Hive)
  await OfflineStore.init();

  // Initialize API service to load saved tokens
  await ApiService().init();

  // Initialize theme provider
  final themeProvider = ThemeProvider();
  await themeProvider.initialize();

  // Allow all orientations for tablets and desktops
  // Portrait lock can be enforced per-screen if needed
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(
    ChangeNotifierProvider.value(
      value: themeProvider,
      child: const VivianCosmeticShopApp(),
    ),
  );
}

class VivianCosmeticShopApp extends StatelessWidget {
  const VivianCosmeticShopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          // Update system UI based on theme
          SystemChrome.setSystemUIOverlayStyle(
            SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: themeProvider.isDarkMode
                  ? Brightness.light
                  : Brightness.dark,
              systemNavigationBarColor: themeProvider.isDarkMode
                  ? const Color(0xFF1E1E1E)
                  : Colors.white,
              systemNavigationBarIconBrightness: themeProvider.isDarkMode
                  ? Brightness.light
                  : Brightness.dark,
            ),
          );

          return MaterialApp(
            title: 'Vivian Cosmetic Shop',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            scaffoldMessengerKey: InAppNotificationService.messengerKey,
            // Disable theme animation to avoid TextStyle lerp errors
            themeAnimationDuration: Duration.zero,
            home: const AuthGate(),
          );
        },
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    if (_started) return;
    _started = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();

      // Initialize inactivity timer with auto-logout
      InactivityService().init(
        onTimeout: () {
          if (auth.isLoggedIn) {
            auth.logout();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Logged out due to inactivity'),
                  duration: Duration(seconds: 3),
                ),
              );
            }
          }
        },
        timeoutMinutes: 15, // 15 minutes of inactivity
        enabled: true,
      );

      // Initialize app lifecycle service for PIN lock on resume
      AppLifecycleService().init(
        onResumeLocked: () async {
          if (!mounted || !auth.isLoggedIn) return false;

          final result = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (context) => const PinLockScreen(),
              fullscreenDialog: true,
            ),
          );

          // If result is false or null, user logged out or dismissed
          if (result != true && mounted) {
            // Ensure logout is called
            await auth.logout();
          }

          return result ?? false;
        },
        lockThreshold: const Duration(
          minutes: 5,
        ), // Lock after 5 mins in background
      );

      auth.initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.initializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Wrap the app with InactivityDetector to track user interactions
    // Use ResponsiveNavigationShell for multi-platform adaptive layout
    final child = auth.isLoggedIn
        ? ResponsiveNavigationShell(
            userRole: auth.role,
            userName: auth.displayName,
          )
        : const LoginScreen();

    return InactivityDetector(child: child);
  }
}
