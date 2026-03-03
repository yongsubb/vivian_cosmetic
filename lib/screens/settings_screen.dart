import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_strings.dart';
import '../core/constants/app_typography.dart';
import '../core/theme/theme_helper.dart';
import '../core/utils/ph_time.dart';
import '../services/api_service.dart';
import '../state/auth_provider.dart';
import '../state/cart_provider.dart';
import '../state/theme_provider.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  final String userName;
  final String userRole;

  const SettingsScreen({
    super.key,
    required this.userName,
    required this.userRole,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // Keep state when switching tabs

  final ApiService _apiService = ApiService();
  Map<String, dynamic> _settings = {};
  Map<String, dynamic>? _currentUser;
  bool _isLoading = true;
  bool _notificationsEnabled = true;
  bool _darkModeEnabled = false;
  bool _wasCurrentBefore = false;

  String get _displayName {
    final name = (_currentUser?['display_name'] ?? _currentUser?['nickname'])
        ?.toString();
    if (name != null && name.trim().isNotEmpty) return name.trim();
    return widget.userName;
  }

  String get _fullName {
    final name = _currentUser?['full_name']?.toString();
    if (name != null && name.trim().isNotEmpty) return name.trim();
    return widget.userName;
  }

  String get _nickname => (_currentUser?['nickname']?.toString() ?? '').trim();

  String get _email => (_currentUser?['email']?.toString() ?? '').trim();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadCurrentUser();
    // Initialize dark mode state from theme provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final themeProvider = context.read<ThemeProvider>();
        setState(() {
          _darkModeEnabled = themeProvider.isDarkMode;
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isCurrent = ModalRoute.of(context)?.isCurrent == true;

    // Reload data when page becomes visible (switches to this tab)
    if (isCurrent && !_wasCurrentBefore) {
      _loadSettings();
      _loadCurrentUser();
    }

    _wasCurrentBefore = isCurrent;
  }

  Future<void> _loadCurrentUser() async {
    final response = await _apiService.getCurrentUser();
    if (!mounted) return;
    if (response.success && response.data != null) {
      setState(() {
        _currentUser = response.data;
      });
    }
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final response = await _apiService.getSettings();
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (response.success && response.data != null) {
          _settings = response.data!;
        }
      });
    }
  }

  Future<void> _updateSettings(Map<String, dynamic> updates) async {
    final response = await _apiService.updateSettings(updates);
    if (mounted) {
      if (response.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Settings updated'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        _loadSettings();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message ?? 'Failed to update settings'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text(AppStrings.settings), centerTitle: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadSettings,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profile Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              color: AppColors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Center(
                              child: Text(
                                _displayName.isNotEmpty
                                    ? _displayName[0].toUpperCase()
                                    : 'U',
                                style: AppTypography.heading1.copyWith(
                                  color: AppColors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _displayName,
                                  style: AppTypography.heading4.copyWith(
                                    color: AppColors.white,
                                  ),
                                ),
                                if (_nickname.isNotEmpty &&
                                    _fullName.trim() != _displayName.trim())
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      _fullName,
                                      style: AppTypography.bodySmall.copyWith(
                                        color: AppColors.white.withValues(
                                          alpha: 0.9,
                                        ),
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.white.withValues(
                                      alpha: 0.2,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    widget.userRole == 'supervisor'
                                        ? 'Supervisor'
                                        : 'Cashier',
                                    style: AppTypography.labelSmall.copyWith(
                                      color: AppColors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => _showEditProfileDialog(context),
                            icon: const Icon(
                              Icons.edit_rounded,
                              color: AppColors.white,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Store Settings Section (Supervisor only)
                    if (widget.userRole == 'supervisor') ...[
                      Text('Store Settings', style: AppTypography.heading4),
                      const SizedBox(height: 12),
                      _SettingsGroup(
                        items: [
                          _SettingsItem(
                            icon: Icons.store_rounded,
                            title: 'Store Information',
                            subtitle:
                                _settings['store_name'] ?? 'Configure store',
                            onTap: () => _showStoreSettingsDialog(context),
                          ),
                          _SettingsItem(
                            icon: Icons.percent_rounded,
                            title: AppStrings.taxSettings,
                            subtitle:
                                'Current: ${_settings['tax_rate'] ?? 12}%',
                            onTap: () => _showTaxSettings(context),
                          ),
                          _SettingsItem(
                            icon: Icons.inventory_2_rounded,
                            title: 'Low Stock Alert',
                            subtitle:
                                'Threshold: ${_settings['low_stock_threshold'] ?? 10} items',
                            onTap: () => _showLowStockSettings(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Account Section
                    Text('Account', style: AppTypography.heading4),
                    const SizedBox(height: 12),
                    _SettingsGroup(
                      items: [
                        _SettingsItem(
                          icon: Icons.person_outline_rounded,
                          title: AppStrings.profile,
                          subtitle: 'View and edit your profile',
                          onTap: () => _showEditProfileDialog(context),
                        ),
                        _SettingsItem(
                          icon: Icons.lock_outline_rounded,
                          title: 'Change Password',
                          subtitle: 'Update your password',
                          onTap: () => _showChangePasswordDialog(context),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Admin Section (Only visible for supervisors)
                    if (widget.userRole == 'supervisor') ...[
                      Text('Administration', style: AppTypography.heading4),
                      const SizedBox(height: 12),
                      _SettingsGroup(
                        items: [
                          _SettingsItem(
                            icon: Icons.people_outline_rounded,
                            title: AppStrings.userManagement,
                            subtitle: 'Manage staff accounts',
                            onTap: () => _showUserManagement(context),
                          ),
                          _SettingsItem(
                            icon: Icons.history_rounded,
                            title: AppStrings.activityLog,
                            subtitle: 'View activity history',
                            onTap: () => _showActivityLog(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],

                    // App Settings Section
                    Text('App Settings', style: AppTypography.heading4),
                    const SizedBox(height: 12),
                    _SettingsGroup(
                      items: [
                        _SettingsItem(
                          icon: Icons.print_rounded,
                          title: AppStrings.printerSettings,
                          subtitle: 'Configure receipt printer',
                          onTap: () => _showPrinterSettings(context),
                        ),
                        _SettingsItem(
                          icon: Icons.notifications_outlined,
                          title: 'Notifications',
                          subtitle: 'Manage alert preferences',
                          hasSwitch: true,
                          switchValue: _notificationsEnabled,
                          onSwitchChanged: (value) {
                            setState(() => _notificationsEnabled = value);
                          },
                        ),
                        _SettingsItem(
                          icon: Icons.dark_mode_outlined,
                          title: 'Dark Mode',
                          subtitle: 'Enable dark theme',
                          hasSwitch: true,
                          switchValue: _darkModeEnabled,
                          onSwitchChanged: (value) async {
                            setState(() => _darkModeEnabled = value);
                            // Toggle theme using ThemeProvider
                            final themeProvider = context.read<ThemeProvider>();
                            await themeProvider.toggleTheme();
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Support Section
                    Text('Support', style: AppTypography.heading4),
                    const SizedBox(height: 12),
                    _SettingsGroup(
                      items: [
                        _SettingsItem(
                          icon: Icons.help_outline_rounded,
                          title: 'Help Center',
                          subtitle: 'Get help and support',
                          onTap: () {},
                        ),
                        _SettingsItem(
                          icon: Icons.info_outline_rounded,
                          title: 'About',
                          subtitle: 'Version 1.0.0',
                          onTap: () => _showAboutDialog(context),
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),

                    // Logout Button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: () => _showLogoutConfirmation(context),
                        icon: const Icon(
                          Icons.logout_rounded,
                          color: AppColors.error,
                        ),
                        label: Text(
                          AppStrings.logout,
                          style: AppTypography.buttonMedium.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.error),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }

  void _showStoreSettingsDialog(BuildContext context) {
    final storeNameController = TextEditingController(
      text: _settings['store_name'] ?? '',
    );
    final addressController = TextEditingController(
      text: _settings['address'] ?? '',
    );
    final phoneController = TextEditingController(
      text: _settings['phone'] ?? '',
    );
    final emailController = TextEditingController(
      text: _settings['email'] ?? '',
    );
    final receiptFooterController = TextEditingController(
      text: _settings['receipt_footer'] ?? '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Store Information', style: AppTypography.heading3),
              const SizedBox(height: 24),

              Text('Store Name', style: AppTypography.labelLarge),
              const SizedBox(height: 8),
              TextField(
                controller: storeNameController,
                decoration: InputDecoration(
                  hintText: 'Enter store name',
                  prefixIcon: Icon(
                    Icons.store_rounded,
                    color: context.textLightColor,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Text('Address', style: AppTypography.labelLarge),
              const SizedBox(height: 8),
              TextField(
                controller: addressController,
                decoration: InputDecoration(
                  hintText: 'Enter store address',
                  prefixIcon: Icon(
                    Icons.location_on_outlined,
                    color: context.textLightColor,
                  ),
                ),
                maxLines: 2,
              ),

              const SizedBox(height: 16),

              Text('Phone', style: AppTypography.labelLarge),
              const SizedBox(height: 8),
              TextField(
                controller: phoneController,
                decoration: InputDecoration(
                  hintText: 'Enter phone number',
                  prefixIcon: Icon(
                    Icons.phone_outlined,
                    color: context.textLightColor,
                  ),
                ),
                keyboardType: TextInputType.phone,
              ),

              const SizedBox(height: 16),

              Text('Email', style: AppTypography.labelLarge),
              const SizedBox(height: 8),
              TextField(
                controller: emailController,
                decoration: InputDecoration(
                  hintText: 'Enter email address',
                  prefixIcon: Icon(
                    Icons.email_outlined,
                    color: context.textLightColor,
                  ),
                ),
                keyboardType: TextInputType.emailAddress,
              ),

              const SizedBox(height: 16),

              Text('Receipt Footer', style: AppTypography.labelLarge),
              const SizedBox(height: 8),
              TextField(
                controller: receiptFooterController,
                decoration: InputDecoration(
                  hintText: 'Message shown at bottom of receipts',
                  prefixIcon: Icon(
                    Icons.receipt_long_rounded,
                    color: context.textLightColor,
                  ),
                ),
                maxLines: 2,
              ),

              const SizedBox(height: 32),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final messenger = ScaffoldMessenger.of(this.context);
                        final email = emailController.text.trim();

                        if (email.isNotEmpty && !_looksLikeEmail(email)) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Please enter a valid email address',
                              ),
                              backgroundColor: AppColors.error,
                            ),
                          );
                          return;
                        }

                        Navigator.pop(context);
                        _updateSettings({
                          'store_name': storeNameController.text,
                          'address': addressController.text,
                          'phone': phoneController.text,
                          'email': email,
                          'receipt_footer': receiptFooterController.text,
                        });
                      },
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showTaxSettings(BuildContext context) {
    int selectedTax = _settings['tax_rate'] ?? 12;
    final customController = TextEditingController();

    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Tax Settings', style: AppTypography.heading3),
              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.percent_rounded, color: AppColors.primary),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('VAT Rate', style: AppTypography.labelLarge),
                          Text(
                            'Applied to all transactions',
                            style: AppTypography.caption,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$selectedTax%',
                        style: AppTypography.heading4.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: _TaxOption(
                      label: '5%',
                      isSelected: selectedTax == 5,
                      onTap: () => setModalState(() => selectedTax = 5),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TaxOption(
                      label: '10%',
                      isSelected: selectedTax == 10,
                      onTap: () => setModalState(() => selectedTax = 10),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TaxOption(
                      label: '12%',
                      isSelected: selectedTax == 12,
                      onTap: () => setModalState(() => selectedTax = 12),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              Text('Custom Rate', style: AppTypography.labelLarge),
              const SizedBox(height: 8),
              TextField(
                controller: customController,
                decoration: const InputDecoration(
                  hintText: 'Enter custom tax rate',
                  suffixText: '%',
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  final rate = int.tryParse(value);
                  if (rate != null && rate >= 0 && rate <= 100) {
                    setModalState(() => selectedTax = rate);
                  }
                },
              ),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _updateSettings({'tax_rate': selectedTax});
                  },
                  child: const Text('Save Changes'),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showLowStockSettings(BuildContext context) {
    final thresholdController = TextEditingController(
      text: (_settings['low_stock_threshold'] ?? 10).toString(),
    );

    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Low Stock Alert', style: AppTypography.heading3),
            const SizedBox(height: 8),
            Text(
              'Get notified when product stock falls below this threshold',
              style: AppTypography.bodyMedium.copyWith(
                color: context.textSecondaryColor,
              ),
            ),
            const SizedBox(height: 24),

            Text('Stock Threshold', style: AppTypography.labelLarge),
            const SizedBox(height: 8),
            TextField(
              controller: thresholdController,
              decoration: InputDecoration(
                hintText: 'Enter minimum stock level',
                prefixIcon: Icon(
                  Icons.inventory_rounded,
                  color: context.textLightColor,
                ),
                suffixText: 'items',
              ),
              keyboardType: TextInputType.number,
            ),

            const SizedBox(height: 32),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      final threshold =
                          int.tryParse(thresholdController.text) ?? 10;
                      _updateSettings({'low_stock_threshold': threshold});
                    },
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showEditProfileDialog(BuildContext context) {
    final nicknameController = TextEditingController(text: _nickname);
    final fullNameController = TextEditingController(text: _fullName);
    final emailController = TextEditingController(text: _email);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Edit Profile', style: AppTypography.heading3),
              const SizedBox(height: 24),

              // Avatar
              Center(
                child: Stack(
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Center(
                        child: Text(
                          widget.userName.isNotEmpty
                              ? widget.userName[0].toUpperCase()
                              : 'U',
                          style: AppTypography.heading1.copyWith(
                            color: AppColors.white,
                            fontSize: 40,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          color: AppColors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Text('Nickname', style: AppTypography.labelLarge),
              const SizedBox(height: 8),
              TextField(
                decoration: InputDecoration(
                  hintText: 'Enter your nickname',
                  prefixIcon: Icon(
                    Icons.badge_outlined,
                    color: context.textLightColor,
                  ),
                ),
                controller: nicknameController,
              ),

              const SizedBox(height: 16),

              Text('Full Name', style: AppTypography.labelLarge),
              const SizedBox(height: 8),
              TextField(
                decoration: InputDecoration(
                  hintText: 'Enter your name',
                  prefixIcon: Icon(
                    Icons.person_outline,
                    color: context.textLightColor,
                  ),
                ),
                controller: fullNameController,
              ),

              const SizedBox(height: 16),

              Text('Email', style: AppTypography.labelLarge),
              const SizedBox(height: 8),
              TextField(
                decoration: InputDecoration(
                  hintText: 'Enter your email',
                  prefixIcon: Icon(
                    Icons.email_outlined,
                    color: context.textLightColor,
                  ),
                ),
                keyboardType: TextInputType.emailAddress,
                controller: emailController,
              ),

              const SizedBox(height: 32),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(this.context);
                        final email = emailController.text.trim();

                        if (email.isNotEmpty && !_looksLikeEmail(email)) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Please enter a valid email address',
                              ),
                              backgroundColor: AppColors.error,
                            ),
                          );
                          return;
                        }

                        final res = await _apiService.updateCurrentUser({
                          'nickname': nicknameController.text.trim(),
                          'full_name': fullNameController.text.trim(),
                          'email': email,
                        });

                        if (!context.mounted) return;
                        Navigator.pop(context);

                        if (res.success) {
                          await _loadCurrentUser();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Profile updated'),
                              backgroundColor: AppColors.success,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                res.message ?? 'Failed to update profile',
                              ),
                              backgroundColor: AppColors.error,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          );
                        }
                      },
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Change Password', style: AppTypography.heading3),
              const SizedBox(height: 24),

              Text('Current Password', style: AppTypography.labelLarge),
              const SizedBox(height: 8),
              TextField(
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'Enter current password',
                  prefixIcon: Icon(
                    Icons.lock_outline,
                    color: context.textLightColor,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Text('New Password', style: AppTypography.labelLarge),
              const SizedBox(height: 8),
              TextField(
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'Enter new password',
                  prefixIcon: Icon(
                    Icons.lock_outline,
                    color: context.textLightColor,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Text('Confirm Password', style: AppTypography.labelLarge),
              const SizedBox(height: 8),
              TextField(
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'Confirm new password',
                  prefixIcon: Icon(
                    Icons.lock_outline,
                    color: context.textLightColor,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Password updated'),
                            backgroundColor: AppColors.success,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                      },
                      child: const Text('Update'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showUserManagement(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _UserManagementSheet(apiService: _apiService),
    );
  }

  void _showActivityLog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ActivityLogSheet(
        apiService: _apiService,
        isSupervisor: widget.userRole == 'supervisor',
      ),
    );
  }

  void _showPrinterSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Printer Settings', style: AppTypography.heading3),
            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.print_rounded,
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('PDF Printing', style: AppTypography.labelLarge),
                        Text(
                          'System default printer',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.success,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Text(
              'Receipt printing uses the system print dialog. '
              'Ensure your printer is connected and set as default.',
              style: AppTypography.bodySmall.copyWith(
                color: context.textSecondaryColor,
              ),
            ),

            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.storefront_rounded,
                color: AppColors.white,
              ),
            ),
            const SizedBox(width: 12),
            Text('Vivian Cosmetics', style: AppTypography.heading4),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Point of Sale System', style: AppTypography.bodyMedium),
            const SizedBox(height: 8),
            Text(
              'Version 1.0.0',
              style: AppTypography.caption.copyWith(
                color: context.textSecondaryColor,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '© 2025 Vivian Cosmetics\nAll rights reserved.',
              style: AppTypography.bodySmall.copyWith(
                color: context.textSecondaryColor,
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Logout', style: AppTypography.heading4),
        content: Text(
          'Are you sure you want to logout?',
          style: AppTypography.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final auth = dialogContext.read<AuthProvider>();
              final cart = dialogContext.read<CartProvider>();
              Navigator.pop(dialogContext);
              await auth.logout();
              await cart.clear();
              if (!mounted) return;
              Navigator.pushAndRemoveUntil(
                this.context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// USER MANAGEMENT SHEET
// ============================================================

class _UserManagementSheet extends StatefulWidget {
  final ApiService apiService;

  const _UserManagementSheet({required this.apiService});

  @override
  State<_UserManagementSheet> createState() => _UserManagementSheetState();
}

class _UserManagementSheetState extends State<_UserManagementSheet> {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    final response = await widget.apiService.getUsers();
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (response.success && response.data != null) {
          _users = response.data!;
        }
      });
    }
  }

  void _showAddUserDialog() {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final fullNameController = TextEditingController();
    String selectedRole = 'cashier';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text('Add New User', style: AppTypography.heading4),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: fullNameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    prefixIcon: Icon(Icons.admin_panel_settings_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
                    DropdownMenuItem(
                      value: 'supervisor',
                      child: Text('Supervisor'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedRole = value);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(this.context);

                if (usernameController.text.isEmpty ||
                    passwordController.text.isEmpty ||
                    fullNameController.text.isEmpty) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('All fields are required')),
                  );
                  return;
                }

                final nameParts = fullNameController.text
                    .trim()
                    .split(RegExp(r'\s+'))
                    .where((p) => p.isNotEmpty)
                    .toList();
                if (nameParts.length < 2) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Please enter first and last name'),
                    ),
                  );
                  return;
                }

                final firstName = nameParts.first;
                final lastName = nameParts.sublist(1).join(' ');

                final response = await widget.apiService.createUser({
                  'username': usernameController.text,
                  'password': passwordController.text,
                  'first_name': firstName,
                  'last_name': lastName,
                  'role': selectedRole,
                });

                if (!mounted) return;
                navigator.pop();
                if (response.success) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: const Text('User created successfully'),
                      backgroundColor: AppColors.success,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                  _loadUsers();
                } else {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        response.message ?? 'Failed to create user',
                      ),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditUserDialog(Map<String, dynamic> user) async {
    final rootContext = context;
    final messenger = ScaffoldMessenger.of(rootContext);

    final firstNameController = TextEditingController(
      text: (user['first_name'] ?? '').toString(),
    );
    final lastNameController = TextEditingController(
      text: (user['last_name'] ?? '').toString(),
    );
    final nicknameController = TextEditingController(
      text: (user['nickname'] ?? '').toString(),
    );
    final emailController = TextEditingController(
      text: (user['email'] ?? '').toString(),
    );
    final phoneController = TextEditingController(
      text: (user['phone'] ?? '').toString(),
    );
    final passwordController = TextEditingController();
    final pinController = TextEditingController();

    String selectedRole = (user['role'] ?? 'cashier').toString();

    await showDialog<void>(
      context: rootContext,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final screenSize = MediaQuery.sizeOf(dialogContext);
          final dialogWidth = (screenSize.width * 0.92).clamp(360.0, 640.0);

          const minDialogHeight = 280.0;
          final maxHeightCap = screenSize.height - 120.0;
          final dialogMaxHeight = (screenSize.height * 0.80).clamp(
            minDialogHeight,
            maxHeightCap < minDialogHeight ? minDialogHeight : maxHeightCap,
          );

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            title: Text('Edit User', style: AppTypography.heading4),
            content: SizedBox(
              width: dialogWidth,
              height: dialogMaxHeight,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: firstNameController,
                      decoration: const InputDecoration(
                        labelText: 'First Name',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: lastNameController,
                      decoration: const InputDecoration(
                        labelText: 'Last Name',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nicknameController,
                      decoration: const InputDecoration(
                        labelText: 'Nickname (optional)',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email (optional)',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone (optional)',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      decoration: const InputDecoration(
                        labelText: 'Role',
                        prefixIcon: Icon(Icons.admin_panel_settings_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'cashier',
                          child: Text('Cashier'),
                        ),
                        DropdownMenuItem(
                          value: 'supervisor',
                          child: Text('Supervisor'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => selectedRole = value);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'New Password (optional)',
                        prefixIcon: Icon(Icons.lock_outline_rounded),
                        helperText: 'Leave blank to keep current password',
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final firstName = firstNameController.text.trim();
                  final lastName = lastNameController.text.trim();
                  final email = emailController.text.trim();
                  final phone = phoneController.text.trim();
                  final nickname = nicknameController.text.trim();
                  final password = passwordController.text;
                  final pin = pinController.text.trim();

                  if (firstName.isEmpty || lastName.isEmpty) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('First name and last name are required'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                    return;
                  }

                  if (email.isNotEmpty && !_looksLikeEmail(email)) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Please enter a valid email address'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                    return;
                  }

                  if (pin.isNotEmpty && pin.length != 4) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('PIN must be exactly 4 digits'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                    return;
                  }

                  final payload = <String, dynamic>{
                    'first_name': firstName,
                    'last_name': lastName,
                    'nickname': nickname,
                    'email': email,
                    'phone': phone,
                    'role': selectedRole,
                  };

                  if (password.trim().isNotEmpty) {
                    payload['password'] = password;
                  }
                  if (pin.isNotEmpty) {
                    payload['pin'] = pin;
                  }

                  final userId = (user['id'] as num?)?.toInt();
                  if (userId == null) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Invalid user id'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                    return;
                  }

                  final res = await widget.apiService.updateUser(
                    userId,
                    payload,
                  );
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext);

                  if (res.success) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: const Text('User updated'),
                        backgroundColor: AppColors.success,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    );
                    _loadUsers();
                  } else {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(res.message ?? 'Failed to update user'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleUsers = _users.where((u) {
      final isActive = u['is_active'] ?? true;
      return _showArchived ? !isActive : isActive;
    }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.dividerColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Text(AppStrings.userManagement, style: AppTypography.heading3),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _showAddUserDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add User'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Active'),
                  selected: !_showArchived,
                  onSelected: (_) => setState(() => _showArchived = false),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Archive'),
                  selected: _showArchived,
                  onSelected: (_) => setState(() => _showArchived = true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (visibleUsers.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.people_outline_rounded,
                      size: 64,
                      color: AppColors.textLight,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _showArchived
                          ? 'No archived users'
                          : 'No active users found',
                      style: AppTypography.bodyMedium.copyWith(
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: visibleUsers.length,
                itemBuilder: (context, index) {
                  final user = visibleUsers[index];
                  final isActive = user['is_active'] ?? true;
                  final role = user['role'] ?? 'cashier';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              (user['full_name'] ?? user['username'] ?? 'U')[0]
                                  .toUpperCase(),
                              style: AppTypography.heading4.copyWith(
                                color: AppColors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user['full_name'] ?? user['username'] ?? '',
                                style: AppTypography.labelLarge,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: role == 'supervisor'
                                          ? AppColors.accent.withValues(
                                              alpha: 0.2,
                                            )
                                          : AppColors.primaryLight,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      role == 'supervisor'
                                          ? 'Supervisor'
                                          : 'Cashier',
                                      style: AppTypography.labelSmall.copyWith(
                                        color: role == 'supervisor'
                                            ? AppColors.accent
                                            : AppColors.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isActive
                                          ? AppColors.successLight
                                          : AppColors.errorLight,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isActive ? 'Active' : 'Inactive',
                                      style: AppTypography.labelSmall.copyWith(
                                        color: isActive
                                            ? AppColors.success
                                            : AppColors.error,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(
                            Icons.more_vert,
                            color: AppColors.textLight,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit_rounded, size: 20),
                                  SizedBox(width: 12),
                                  Text('Edit'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'toggle',
                              child: Row(
                                children: [
                                  Icon(
                                    isActive
                                        ? Icons.block_rounded
                                        : Icons.check_circle_rounded,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(isActive ? 'Deactivate' : 'Activate'),
                                ],
                              ),
                            ),
                            if (isActive)
                              const PopupMenuItem(
                                value: 'archive',
                                child: Row(
                                  children: [
                                    Icon(Icons.archive_outlined, size: 20),
                                    SizedBox(width: 12),
                                    Text('Archive'),
                                  ],
                                ),
                              ),
                          ],
                          onSelected: (value) async {
                            final messenger = ScaffoldMessenger.of(
                              this.context,
                            );

                            if (value == 'edit') {
                              await _showEditUserDialog(user);
                              return;
                            }

                            if (value == 'toggle') {
                              final response = await widget.apiService
                                  .updateUser(user['id'], {
                                    'is_active': !isActive,
                                  });
                              if (response.success) {
                                _loadUsers();
                              } else if (mounted) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      response.message ??
                                          'Failed to update user',
                                    ),
                                    backgroundColor: AppColors.error,
                                  ),
                                );
                              }
                              return;
                            }

                            if (value == 'archive') {
                              if (!mounted) return;
                              final confirm = await showDialog<bool>(
                                context: this.context,
                                builder: (dialogContext) => AlertDialog(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  title: const Text('Archive User'),
                                  content: const Text(
                                    'This will move the account to Archive and prevent login. Continue?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext, false),
                                      child: const Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext, true),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                        foregroundColor: Theme.of(
                                          context,
                                        ).colorScheme.onError,
                                      ),
                                      child: const Text('Archive'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm != true) return;

                              final response = await widget.apiService
                                  .deleteUser(user['id']);
                              if (response.success) {
                                _loadUsers();
                              } else if (mounted) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      response.message ??
                                          'Failed to archive user',
                                    ),
                                    backgroundColor: AppColors.error,
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

bool _looksLikeEmail(String value) {
  final email = value.trim();
  if (email.isEmpty) return false;
  final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  return re.hasMatch(email);
}

// ============================================================
// HELPER WIDGETS
// ============================================================

class _SettingsGroup extends StatelessWidget {
  final List<_SettingsItem> items;

  const _SettingsGroup({required this.items});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          return Column(
            children: [
              item,
              if (index < items.length - 1)
                const Divider(height: 1, indent: 56),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool hasSwitch;
  final bool switchValue;
  final Function(bool)? onSwitchChanged;

  const _SettingsItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.hasSwitch = false,
    this.switchValue = false,
    this.onSwitchChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: hasSwitch ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.labelLarge),
                  Text(subtitle, style: AppTypography.caption),
                ],
              ),
            ),
            if (hasSwitch)
              Switch(
                value: switchValue,
                onChanged: onSwitchChanged,
                activeThumbColor: AppColors.primary,
              )
            else
              Icon(Icons.chevron_right_rounded, color: context.textLightColor),
          ],
        ),
      ),
    );
  }
}

class _TaxOption extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TaxOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.secondary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : context.dividerColor,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: AppTypography.labelMedium.copyWith(
              color: isSelected ? AppColors.white : context.textPrimaryColor,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityLogSheet extends StatefulWidget {
  final ApiService apiService;
  final bool isSupervisor;

  const _ActivityLogSheet({
    required this.apiService,
    required this.isSupervisor,
  });

  @override
  State<_ActivityLogSheet> createState() => _ActivityLogSheetState();
}

class _ActivityLogSheetState extends State<_ActivityLogSheet> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _logs = const [];
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await widget.apiService.getActivityLogs(
      limit: 100,
      archived: _showArchived,
    );
    if (!mounted) return;
    if (res.success && res.data != null) {
      setState(() {
        _logs = res.data!;
        _loading = false;
      });
      return;
    }
    setState(() {
      _error = res.message ?? 'Failed to load activity log.';
      _loading = false;
    });
  }

  String _formatTime(BuildContext context, String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = PhTime.parseToPhOrNow(iso);
      final tod = TimeOfDay.fromDateTime(dt);
      return MaterialLocalizations.of(context).formatTimeOfDay(tod);
    } catch (_) {
      return '';
    }
  }

  Future<void> _confirmAndArchive(int logId) async {
    final shouldArchive = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive activity?'),
        content: const Text('This will move this activity to the archive.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (shouldArchive != true) return;

    final res = await widget.apiService.deleteActivityLog(logId);
    if (!mounted) return;
    if (res.success) {
      setState(() {
        _logs = _logs.where((e) => (e['id'] as int?) != logId).toList();
      });
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(res.message ?? 'Archive failed.')));
  }

  Future<void> _confirmAndRestore(int logId) async {
    final shouldRestore = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore activity?'),
        content: const Text('This will move this activity back to Active.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (shouldRestore != true) return;

    final res = await widget.apiService.restoreActivityLog(logId);
    if (!mounted) return;
    if (res.success) {
      setState(() {
        _logs = _logs.where((e) => (e['id'] as int?) != logId).toList();
      });
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(res.message ?? 'Restore failed.')));
  }

  Future<void> _confirmAndDeleteForever(int logId) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: const Text(
          'This will permanently delete this activity log. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;

    final res = await widget.apiService.hardDeleteActivityLog(logId);
    if (!mounted) return;
    if (res.success) {
      setState(() {
        _logs = _logs.where((e) => (e['id'] as int?) != logId).toList();
      });
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(res.message ?? 'Delete failed.')));
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Text(AppStrings.activityLog, style: AppTypography.heading3),
                  const Spacer(),
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Active'),
                        selected: !_showArchived,
                        onSelected: (_) {
                          if (_showArchived) {
                            setState(() => _showArchived = false);
                            _load();
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Archive'),
                        selected: _showArchived,
                        onSelected: (_) {
                          if (!_showArchived) {
                            setState(() => _showArchived = true);
                            _load();
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: AppTypography.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: _load,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _logs.isEmpty
                  ? Center(
                      child: Text(
                        'No activity yet.',
                        style: AppTypography.bodySmall,
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        final id = (log['id'] as num?)?.toInt();
                        final user = (log['user_name'] ?? 'System').toString();
                        final action = (log['action'] ?? '').toString();
                        final time = _formatTime(
                          context,
                          log['created_at']?.toString(),
                        );

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.secondary.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.history_rounded,
                                  color: AppColors.primary,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(user, style: AppTypography.labelLarge),
                                    const SizedBox(height: 4),
                                    Text(
                                      action,
                                      style: AppTypography.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(time, style: AppTypography.caption),
                                  if (widget.isSupervisor && id != null)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: _showArchived
                                          ? [
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.restore_rounded,
                                                ),
                                                color: AppColors.primary,
                                                tooltip: 'Restore',
                                                onPressed: () =>
                                                    _confirmAndRestore(id),
                                              ),
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.delete_forever_outlined,
                                                ),
                                                color: AppColors.error,
                                                tooltip: 'Delete permanently',
                                                onPressed: () =>
                                                    _confirmAndDeleteForever(
                                                      id,
                                                    ),
                                              ),
                                            ]
                                          : [
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.archive_outlined,
                                                ),
                                                color: AppColors.error,
                                                tooltip: 'Archive',
                                                onPressed: () =>
                                                    _confirmAndArchive(id),
                                              ),
                                            ],
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
