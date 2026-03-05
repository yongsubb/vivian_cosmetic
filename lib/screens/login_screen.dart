import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_strings.dart';
import '../core/theme/theme_helper.dart';
import '../core/constants/app_typography.dart';
import '../core/widgets/responsive_navigation.dart';
import '../state/auth_provider.dart';
import '../services/api_service.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _showForgotPasswordDialog() async {
    final seedIdentifier = _usernameController.text.trim();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final identifierController = TextEditingController(
          text: seedIdentifier,
        );
        final otpController = TextEditingController();
        final newPasswordController = TextEditingController();
        final confirmPasswordController = TextEditingController();

        var step = 0; // 0=request, 1=confirm
        var isBusy = false;
        String? error;
        String? otpRef;
        String? destination;
        var obscureNewPassword = true;
        var obscureConfirmPassword = true;

        Future<void> sendOtp(StateSetter setState) async {
          final identifier = identifierController.text.trim();
          if (identifier.isEmpty) {
            setState(() => error = 'Please enter your username or email');
            return;
          }

          setState(() {
            isBusy = true;
            error = null;
          });

          final response = await ApiService().requestPasswordResetOtp(
            usernameOrEmail: identifier,
          );

          if (!dialogContext.mounted) return;

          if (response.success) {
            final ref = (response.data?['otp_ref'] ?? '').toString().trim();
            final dest = (response.data?['destination'] ?? '')
                .toString()
                .trim();

            if (ref.isEmpty) {
              setState(() {
                isBusy = false;
                error =
                    response.message ??
                    'If the account exists, a verification code has been sent.';
              });
              return;
            }

            setState(() {
              isBusy = false;
              step = 1;
              otpRef = ref;
              destination = dest.isNotEmpty ? dest : null;
            });
            return;
          }

          setState(() {
            isBusy = false;
            error = response.message ?? 'Failed to send verification code';
          });
        }

        Future<void> confirmReset(StateSetter setState) async {
          final ref = (otpRef ?? '').trim();
          final otp = otpController.text.trim();
          final newPwd = newPasswordController.text;
          final confirmPwd = confirmPasswordController.text;

          if (ref.isEmpty) {
            setState(
              () => error = 'Missing OTP reference. Please request again.',
            );
            return;
          }
          if (otp.isEmpty) {
            setState(() => error = 'Please enter the OTP code');
            return;
          }
          if (newPwd.trim().isEmpty) {
            setState(() => error = 'Please enter a new password');
            return;
          }
          if (newPwd.length < 6) {
            setState(() => error = 'Password must be at least 6 characters');
            return;
          }
          if (newPwd != confirmPwd) {
            setState(() => error = 'Passwords do not match');
            return;
          }

          setState(() {
            isBusy = true;
            error = null;
          });

          final response = await ApiService().confirmPasswordResetOtp(
            otpRef: ref,
            otpCode: otp,
            newPassword: newPwd,
          );

          if (!dialogContext.mounted) return;

          if (response.success) {
            Navigator.of(dialogContext).pop();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  response.message ?? 'Password reset successfully',
                ),
              ),
            );
            return;
          }

          setState(() {
            isBusy = false;
            error = response.message ?? 'Password reset failed';
          });
        }

        return StatefulBuilder(
          builder: (context, setState) {
            final title = step == 0 ? 'Forgot Password' : 'Reset Password';

            return AlertDialog(
              title: Text(title, style: AppTypography.heading4),
              content: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (step == 0) ...[
                        Text(
                          'Enter your username or email to receive a verification code.',
                          style: AppTypography.bodySmall.copyWith(
                            color: dialogContext.textSecondaryColor,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: identifierController,
                          decoration: InputDecoration(
                            hintText: 'Username or Email',
                            prefixIcon: Icon(
                              Icons.person_outline,
                              color: dialogContext.textLightColor,
                            ),
                          ),
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) {
                            if (!isBusy) {
                              sendOtp(setState);
                            }
                          },
                        ),
                      ] else ...[
                        if (destination != null) ...[
                          Text(
                            'We sent a code to $destination',
                            style: AppTypography.bodySmall.copyWith(
                              color: dialogContext.textSecondaryColor,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextField(
                          controller: otpController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            hintText: 'OTP Code',
                            prefixIcon: Icon(
                              Icons.lock_clock_outlined,
                              color: dialogContext.textLightColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: newPasswordController,
                          obscureText: obscureNewPassword,
                          decoration: InputDecoration(
                            hintText: 'New Password',
                            prefixIcon: Icon(
                              Icons.lock_outline,
                              color: dialogContext.textLightColor,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscureNewPassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: dialogContext.textLightColor,
                              ),
                              onPressed: () => setState(
                                () => obscureNewPassword = !obscureNewPassword,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: confirmPasswordController,
                          obscureText: obscureConfirmPassword,
                          decoration: InputDecoration(
                            hintText: 'Confirm New Password',
                            prefixIcon: Icon(
                              Icons.lock_outline,
                              color: dialogContext.textLightColor,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscureConfirmPassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: dialogContext.textLightColor,
                              ),
                              onPressed: () => setState(
                                () => obscureConfirmPassword =
                                    !obscureConfirmPassword,
                              ),
                            ),
                          ),
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) {
                            if (!isBusy) {
                              confirmReset(setState);
                            }
                          },
                        ),
                      ],

                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          error!,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                      ],

                      if (isBusy) ...[
                        const SizedBox(height: 16),
                        const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isBusy
                      ? null
                      : () {
                          if (step == 0) {
                            Navigator.of(dialogContext).pop();
                          } else {
                            setState(() {
                              step = 0;
                              error = null;
                              otpRef = null;
                              destination = null;
                              otpController.clear();
                              newPasswordController.clear();
                              confirmPasswordController.clear();
                            });
                          }
                        },
                  child: Text(step == 0 ? 'Cancel' : 'Back'),
                ),
                ElevatedButton(
                  onPressed: isBusy
                      ? null
                      : () {
                          if (step == 0) {
                            sendOtp(setState);
                          } else {
                            confirmReset(setState);
                          }
                        },
                  child: Text(step == 0 ? 'Send Code' : 'Reset Password'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    // Clear previous error
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    try {
      await _performApiLogin();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'An error occurred: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _performApiLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your username';
        _isLoading = false;
      });
      return;
    }

    if (password.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your password';
        _isLoading = false;
      });
      return;
    }

    // Login without specifying role - backend will determine role from username
    final response = await context.read<AuthProvider>().login(
      username: username,
      password: password,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (response.success && response.data != null) {
      final auth = context.read<AuthProvider>();
      // Navigate to responsive main screen - role comes from backend
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => ResponsiveNavigationShell(
            userRole: auth.role.isNotEmpty
                ? auth.role
                : (response.data!.user['role'] ?? 'cashier'),
            userName: auth.displayName,
          ),
        ),
      );
    } else {
      setState(() {
        _errorMessage = response.message ?? 'Login failed. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1200;
    final isTablet = screenWidth >= 600 && screenWidth < 1200;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: isDesktop
            ? _buildDesktopLoginLayout()
            : isTablet
            ? _buildTabletLoginLayout()
            : _buildMobileLoginLayout(),
      ),
    );
  }

  /// Desktop Login - Split screen with branding on left
  Widget _buildDesktopLoginLayout() {
    return Row(
      children: [
        // Left side - Branding
        Expanded(
          flex: 5,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.primaryDark],
              ),
            ),
            child: Stack(
              children: [
                // Decorative circles
                Positioned(
                  top: -100,
                  left: -100,
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -50,
                  right: -50,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                ),
                // Content
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(48),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 30,
                                offset: const Offset(0, 15),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/payment/icon-logo/vivian-cosmetic-shop-logo.png',
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                        const Text(
                          'Vivian Cosmetic Shop',
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'POS & Inventory Management System',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                        const SizedBox(height: 48),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _FeatureItem(
                              icon: Icons.inventory_2_rounded,
                              label: 'Inventory',
                            ),
                            const SizedBox(width: 32),
                            _FeatureItem(
                              icon: Icons.point_of_sale_rounded,
                              label: 'POS',
                            ),
                            const SizedBox(width: 32),
                            _FeatureItem(
                              icon: Icons.bar_chart_rounded,
                              label: 'Reports',
                            ),
                            const SizedBox(width: 32),
                            _FeatureItem(
                              icon: Icons.people_rounded,
                              label: 'Loyalty',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Right side - Login form
        Expanded(
          flex: 4,
          child: Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(48),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: _buildLoginForm(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Tablet Login - Centered with constrained width
  Widget _buildTabletLoginLayout() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildLogoSection(),
              const SizedBox(height: 48),
              _buildLoginForm(),
            ],
          ),
        ),
      ),
    );
  }

  /// Mobile Login - Original layout
  Widget _buildMobileLoginLayout() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            _buildLogoSection(),
            const SizedBox(height: 32),
            _buildLoginForm(),
          ],
        ),
      ),
    );
  }

  /// Logo and branding section
  Widget _buildLogoSection() {
    return Column(
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/payment/icon-logo/vivian-cosmetic-shop-logo.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          AppStrings.appName,
          style: AppTypography.heading2.copyWith(color: AppColors.primary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          AppStrings.appTagline,
          style: AppTypography.bodyMedium.copyWith(
            color: context.textSecondaryColor,
          ),
        ),
      ],
    );
  }

  /// Login form widgets
  Widget _buildLoginForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(AppStrings.welcomeBack, style: AppTypography.heading3),

        const SizedBox(height: 8),

        Text(
          AppStrings.loginSubtitle,
          style: AppTypography.bodyMedium.copyWith(
            color: context.textSecondaryColor,
          ),
        ),

        const SizedBox(height: 32),

        // Error Message
        if (_errorMessage != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppColors.error,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() => _errorMessage = null),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Username Field
        TextField(
          controller: _usernameController,
          decoration: InputDecoration(
            hintText: AppStrings.username,
            prefixIcon: Icon(
              Icons.person_outline,
              color: context.textLightColor,
            ),
          ),
          textInputAction: TextInputAction.next,
        ),

        const SizedBox(height: 16),

        // Password Field
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            hintText: AppStrings.password,
            prefixIcon: Icon(Icons.lock_outline, color: context.textLightColor),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: context.textLightColor,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _handleLogin(),
        ),

        const SizedBox(height: 12),

        // Forgot Password
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _showForgotPasswordDialog,
            child: Text(
              AppStrings.forgotPassword,
              style: AppTypography.bodySmall.copyWith(color: AppColors.primary),
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Login Button
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton(
            onPressed: _isLoading ? null : _handleLogin,
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: AppColors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(AppStrings.login, style: AppTypography.buttonLarge),
          ),
        ),

        const SizedBox(height: 24),

        // Create Account Link
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Don't have an account? ",
              style: AppTypography.bodyMedium.copyWith(
                color: context.textSecondaryColor,
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RegisterScreen(),
                  ),
                );
              },
              child: Text(
                'Create Account',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),
      ],
    );
  }
}

/// Feature item for desktop login branding section
class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
