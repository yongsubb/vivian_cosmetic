import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_typography.dart';
import '../core/theme/theme_helper.dart';
import '../state/auth_provider.dart';

/// PIN lock screen that appears when app resumes after timeout
class PinLockScreen extends StatefulWidget {
  const PinLockScreen({super.key});

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  final _pinController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePin = true;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final pin = _pinController.text.trim();
    if (pin.isEmpty) {
      setState(() => _errorMessage = 'Please enter your PIN');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final auth = context.read<AuthProvider>();
    final username = auth.user?['username']?.toString() ?? '';
    final role = auth.user?['role']?.toString();

    if (username.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Session expired. Please login again.';
      });
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        await auth.logout();
      }
      return;
    }

    final response = await auth.login(username: username, pin: pin, role: role);

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (response.success) {
      // Pop the PIN lock screen
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _errorMessage = response.message ?? 'Invalid PIN';
        _pinController.clear();
      });
    }
  }

  void _logout() async {
    final auth = context.read<AuthProvider>();
    await auth.logout();
    if (mounted) {
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final displayName = auth.displayName;

    return PopScope(
      canPop: false, // Prevent back button
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Lock icon
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_outline,
                      size: 64,
                      color: AppColors.primary,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Title
                  Text(
                    'App Locked',
                    style: AppTypography.heading2.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Welcome back, $displayName',
                    style: AppTypography.bodyLarge.copyWith(
                      color: context.textSecondaryColor,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Enter your PIN to continue',
                    style: AppTypography.bodySmall.copyWith(
                      color: context.textSecondaryColor,
                    ),
                  ),

                  const SizedBox(height: 48),

                  // PIN input
                  Container(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: TextField(
                      controller: _pinController,
                      obscureText: _obscurePin,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: AppTypography.heading3,
                      decoration: InputDecoration(
                        hintText: '••••••',
                        hintStyle: AppTypography.heading3.copyWith(
                          color: context.textSecondaryColor.withValues(
                            alpha: 0.3,
                          ),
                        ),
                        filled: true,
                        fillColor: context.cardColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePin
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: context.textSecondaryColor,
                          ),
                          onPressed: () {
                            setState(() => _obscurePin = !_obscurePin);
                          },
                        ),
                        counterText: '',
                        errorText: _errorMessage,
                      ),
                      onSubmitted: (_) => _unlock(),
                      enabled: !_isLoading,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Unlock button
                  Container(
                    constraints: const BoxConstraints(maxWidth: 400),
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _unlock,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              'Unlock',
                              style: AppTypography.labelLarge.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Logout button
                  TextButton(
                    onPressed: _isLoading ? null : _logout,
                    child: Text(
                      'Logout',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
