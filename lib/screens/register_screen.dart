import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_typography.dart';
import '../core/theme/theme_helper.dart';
import '../services/api_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();

  static final RegExp _emailRegex = RegExp(
    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
    caseSensitive: false,
  );

  static final RegExp _phoneDigitsRegex = RegExp(r'^\d{11,12}$');
  static final RegExp _passwordUppercaseRegex = RegExp(r'[A-Z]');
  static final RegExp _passwordDigitRegex = RegExp(r'\d');
  static final RegExp _passwordSpecialRegex = RegExp(r'[^A-Za-z0-9]');
  static final RegExp _phoneAllowedCharsRegex = RegExp(r'^\d*$');

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();

    // Ensure cross-field validators (e.g. confirm password) update immediately
    // when related fields change.
    void revalidateForm() {
      if (!mounted) return;
      _formKey.currentState?.validate();
    }

    _passwordController.addListener(revalidateForm);
    _confirmPasswordController.addListener(revalidateForm);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() {
        _errorMessage = 'Passwords do not match';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final apiService = ApiService();
      final response = await apiService.post<Map<String, dynamic>>(
        '/auth/register',
        body: {
          'username': _usernameController.text.trim(),
          'password': _passwordController.text,
          'first_name': _firstNameController.text.trim(),
          'last_name': _lastNameController.text.trim(),
          'email': _emailController.text.trim(),
          'phone': _normalizePhone(_phoneController.text),
          'address': _addressController.text.trim(),
          'role': 'cashier', // Always register as cashier
        },
      );

      if (!mounted) return;

      if (response.success) {
        setState(() {
          _successMessage =
              'Account created successfully! Please wait for supervisor approval before you can login.';
          _isLoading = false;
        });
        // Clear the form
        _formKey.currentState?.reset();
        _usernameController.clear();
        _passwordController.clear();
        _confirmPasswordController.clear();
        _firstNameController.clear();
        _lastNameController.clear();
        _emailController.clear();
        _phoneController.clear();
        _addressController.clear();
      } else {
        setState(() {
          _errorMessage =
              response.message ?? 'Registration failed. Please try again.';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'An error occurred: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  bool _isValidEmail(String email) {
    if (email.length > 254) return false;
    return _emailRegex.hasMatch(email);
  }

  String _normalizePhone(String input) => input.trim();

  bool _isValidPhone(String normalizedPhone) {
    return _phoneDigitsRegex.hasMatch(normalizedPhone);
  }

  bool _hasOnlyAllowedPhoneChars(String rawPhone) {
    return _phoneAllowedCharsRegex.hasMatch(rawPhone.trim());
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Password is required';
    if (password.length < 8) return 'Password must be at least 8 characters';
    if (!_passwordUppercaseRegex.hasMatch(password)) {
      return 'Password must contain at least 1 uppercase letter';
    }
    if (!_passwordDigitRegex.hasMatch(password)) {
      return 'Password must contain at least 1 number';
    }
    if (!_passwordSpecialRegex.hasMatch(password)) {
      return 'Password must contain at least 1 special character';
    }
    return null;
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
            ? _buildDesktopLayout()
            : isTablet
            ? _buildTabletLayout()
            : _buildMobileLayout(),
      ),
    );
  }

  Widget _buildDesktopLayout() {
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
                          child: const Icon(
                            Icons.person_add_rounded,
                            size: 70,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 40),
                        const Text(
                          'Join Our Team',
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Create your cashier account',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                        const SizedBox(height: 48),
                        _buildInfoItem(
                          Icons.check_circle_outline,
                          'Quick registration process',
                        ),
                        const SizedBox(height: 16),
                        _buildInfoItem(
                          Icons.supervisor_account_outlined,
                          'Supervisor approval required',
                        ),
                        const SizedBox(height: 16),
                        _buildInfoItem(
                          Icons.security_outlined,
                          'Secure access to POS system',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Right side - Registration form
        Expanded(
          flex: 4,
          child: Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(48),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 450),
                  child: _buildRegistrationForm(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabletLayout() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            children: [
              _buildLogoSection(),
              const SizedBox(height: 32),
              _buildRegistrationForm(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 20),
          _buildLogoSection(),
          const SizedBox(height: 24),
          _buildRegistrationForm(),
        ],
      ),
    );
  }

  Widget _buildLogoSection() {
    return Column(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.person_add_rounded,
            size: 50,
            color: AppColors.white,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Create Account',
          style: AppTypography.heading2.copyWith(color: AppColors.primary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Register as a cashier',
          style: AppTypography.bodyMedium.copyWith(
            color: context.textSecondaryColor,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoItem(IconData icon, String text) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: Colors.white, size: 24),
        const SizedBox(width: 12),
        Text(text, style: const TextStyle(color: Colors.white, fontSize: 16)),
      ],
    );
  }

  Widget _buildRegistrationForm() {
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.always,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Create Your Account',
            style: AppTypography.heading3,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Fill in your details to register',
            style: AppTypography.bodyMedium.copyWith(
              color: context.textSecondaryColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Success Message
          if (_successMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: AppColors.success,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _successMessage!,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.success,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back to Login'),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Error Message
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3),
                  ),
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
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Name Row
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _firstNameController,
                    decoration: InputDecoration(
                      labelText: 'First Name',
                      hintText: 'Enter first name',
                      prefixIcon: Icon(
                        Icons.person_outline,
                        color: context.textLightColor,
                      ),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Required';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _lastNameController,
                    decoration: InputDecoration(
                      labelText: 'Last Name',
                      hintText: 'Enter last name',
                      prefixIcon: Icon(
                        Icons.person_outline,
                        color: context.textLightColor,
                      ),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Required';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Username
            TextFormField(
              controller: _usernameController,
              decoration: InputDecoration(
                labelText: 'Username',
                hintText: 'Choose a username',
                prefixIcon: Icon(
                  Icons.alternate_email,
                  color: context.textLightColor,
                ),
              ),
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Username is required';
                }
                if (value.length < 3) {
                  return 'Username must be at least 3 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Email
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email (Optional)',
                hintText: 'Enter your email',
                prefixIcon: Icon(
                  Icons.email_outlined,
                  color: context.textLightColor,
                ),
              ),
              textInputAction: TextInputAction.next,
              validator: (value) {
                final email = (value ?? '').trim();
                if (email.isEmpty) return null; // Optional field
                if (!_isValidEmail(email)) {
                  return 'Enter a valid email (e.g. name@example.com)';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Phone
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(12),
              ],
              decoration: InputDecoration(
                labelText: 'Phone (Optional)',
                hintText: 'Enter your phone number',
                prefixIcon: Icon(
                  Icons.phone_outlined,
                  color: context.textLightColor,
                ),
              ),
              textInputAction: TextInputAction.next,
              validator: (value) {
                final raw = (value ?? '').trim();
                if (raw.isEmpty) return null; // Optional field

                if (!_hasOnlyAllowedPhoneChars(raw)) {
                  return 'Phone can contain numbers only';
                }

                final normalized = _normalizePhone(raw);
                if (normalized.isEmpty) {
                  return 'Enter a valid phone number (11-12 digits)';
                }
                if (!_isValidPhone(normalized)) {
                  return 'Enter a valid phone number (11-12 digits)';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Home Address
            TextFormField(
              controller: _addressController,
              keyboardType: TextInputType.streetAddress,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Home Address',
                hintText: 'Enter your complete home address',
                prefixIcon: Icon(
                  Icons.home_outlined,
                  color: context.textLightColor,
                ),
                alignLabelWithHint: true,
              ),
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Home address is required for security purposes';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Password
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Password',
                hintText: 'Create a password',
                prefixIcon: Icon(
                  Icons.lock_outline,
                  color: context.textLightColor,
                ),
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
              textInputAction: TextInputAction.next,
              validator: _validatePassword,
            ),
            const SizedBox(height: 16),

            // Confirm Password
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirmPassword,
              decoration: InputDecoration(
                labelText: 'Confirm Password',
                hintText: 'Re-enter your password',
                prefixIcon: Icon(
                  Icons.lock_outline,
                  color: context.textLightColor,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: context.textLightColor,
                  ),
                  onPressed: () => setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword,
                  ),
                ),
              ),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _handleRegister(),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please confirm your password';
                }
                if (value != _passwordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            // Info note
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.info.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: AppColors.info,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your account will need supervisor approval before you can login.',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.info,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Register Button
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: _isLoading ? null : _handleRegister,
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: AppColors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text('Create Account', style: AppTypography.buttonLarge),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Back to login link
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Already have an account? ',
                style: AppTypography.bodyMedium.copyWith(
                  color: context.textSecondaryColor,
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Login',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
