import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../theme/theme_helper.dart';
import '../services/permission_service.dart';
import '../../screens/dashboard_screen.dart';
import '../../screens/sales_screen.dart';
import '../../screens/products_screen.dart';
import '../../screens/loyalty_screen.dart';
import '../../screens/reports_screen.dart';
import '../../screens/settings_screen.dart';
import '../../screens/transactions_screen.dart';
import '../../screens/global_search_dialog.dart';

/// Enhanced responsive breakpoints
class ScreenBreakpoints {
  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1200;
  static const double wideDesktop = 1600;
}

/// Device type enumeration
enum DeviceType { mobile, tablet, desktop, wideDesktop }

/// Responsive helper extension
extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.of(this).size.width;
  double get screenHeight => MediaQuery.of(this).size.height;

  bool get isMobile => screenWidth < ScreenBreakpoints.mobile;
  bool get isTablet =>
      screenWidth >= ScreenBreakpoints.mobile &&
      screenWidth < ScreenBreakpoints.desktop;
  bool get isDesktop => screenWidth >= ScreenBreakpoints.desktop;
  bool get isWideDesktop => screenWidth >= ScreenBreakpoints.wideDesktop;

  DeviceType get deviceType {
    if (screenWidth >= ScreenBreakpoints.wideDesktop) {
      return DeviceType.wideDesktop;
    }
    if (screenWidth >= ScreenBreakpoints.desktop) return DeviceType.desktop;
    if (screenWidth >= ScreenBreakpoints.mobile) return DeviceType.tablet;
    return DeviceType.mobile;
  }

  /// Get responsive value based on device type
  T responsive<T>({required T mobile, T? tablet, T? desktop, T? wideDesktop}) {
    switch (deviceType) {
      case DeviceType.wideDesktop:
        return wideDesktop ?? desktop ?? tablet ?? mobile;
      case DeviceType.desktop:
        return desktop ?? tablet ?? mobile;
      case DeviceType.tablet:
        return tablet ?? mobile;
      case DeviceType.mobile:
        return mobile;
    }
  }
}

/// Navigation item data model
class NavigationItemData {
  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final Widget screen;
  final bool showInMobile;
  final bool showInDesktop;
  final List<NavigationItemData>? children;

  const NavigationItemData({
    required this.icon,
    this.selectedIcon,
    required this.label,
    required this.screen,
    this.showInMobile = true,
    this.showInDesktop = true,
    this.children,
  });
}

/// Responsive Navigation Shell - Adapts to all screen sizes
class ResponsiveNavigationShell extends StatefulWidget {
  final String userName;
  final String userRole;

  const ResponsiveNavigationShell({
    super.key,
    required this.userName,
    required this.userRole,
  });

  @override
  State<ResponsiveNavigationShell> createState() =>
      ResponsiveNavigationShellState();
}

class ResponsiveNavigationShellState extends State<ResponsiveNavigationShell> {
  int _currentIndex = 0;
  bool _isRailExpanded = true;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String get _normalizedRole =>
      widget.userRole.toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');

  bool get _canViewAnalytics {
    final role = _normalizedRole;
    return role == 'supervisor' || role == 'admin' || role == 'superadmin';
  }

  bool get _isCashierRole => _normalizedRole == 'cashier';

  List<int> get _mobileNavFullIndices {
    if (_isCashierRole) {
      return [0, 1, 2];
    }

    int idx(String label) =>
        _navigationItems.indexWhere((item) => item.label == label);

    final indices = <int>[
      idx('Dashboard'),
      idx('Point of Sales'),
      idx('Products'),
      idx('Loyalty'),
      if (_canViewAnalytics) idx('Analytics'),
      idx('Settings'),
    ].where((i) => i >= 0).toList();

    return indices;
  }

  late final List<NavigationItemData> _navigationItems;

  @override
  void initState() {
    super.initState();
    _navigationItems = _isCashierRole
        ? [
            NavigationItemData(
              icon: Icons.dashboard_outlined,
              selectedIcon: Icons.dashboard_rounded,
              label: 'Dashboard',
              screen: DashboardScreen(
                userName: widget.userName,
                userRole: widget.userRole,
              ),
            ),
            NavigationItemData(
              icon: Icons.point_of_sale_outlined,
              selectedIcon: Icons.point_of_sale_rounded,
              label: 'Point of Sales',
              screen: const SalesScreen(),
            ),
            NavigationItemData(
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings_rounded,
              label: 'Settings',
              screen: SettingsScreen(
                userName: widget.userName,
                userRole: widget.userRole,
              ),
            ),
          ]
        : [
            NavigationItemData(
              icon: Icons.dashboard_outlined,
              selectedIcon: Icons.dashboard_rounded,
              label: 'Dashboard',
              screen: DashboardScreen(
                userName: widget.userName,
                userRole: widget.userRole,
              ),
            ),
            NavigationItemData(
              icon: Icons.point_of_sale_outlined,
              selectedIcon: Icons.point_of_sale_rounded,
              label: 'Point of Sales',
              screen: const SalesScreen(),
            ),
            NavigationItemData(
              icon: Icons.inventory_2_outlined,
              selectedIcon: Icons.inventory_2_rounded,
              label: 'Products',
              screen: const ProductsScreen(),
            ),
            NavigationItemData(
              icon: Icons.receipt_long_outlined,
              selectedIcon: Icons.receipt_long_rounded,
              label: 'Transactions',
              screen: const TransactionsScreen(),
            ),
            NavigationItemData(
              icon: Icons.card_membership_outlined,
              selectedIcon: Icons.card_membership_rounded,
              label: 'Loyalty',
              screen: LoyaltyScreen(userRole: widget.userRole),
            ),
            NavigationItemData(
              icon: Icons.bar_chart_outlined,
              selectedIcon: Icons.analytics_rounded,
              label: 'Analytics',
              screen: const ReportsScreen(),
            ),
            NavigationItemData(
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings_rounded,
              label: 'Settings',
              screen: SettingsScreen(
                userName: widget.userName,
                userRole: widget.userRole,
              ),
            ),
          ];
  }

  void setCurrentIndex(int index) {
    final analyticsIndex = _navigationItems.indexWhere(
      (item) => item.label == 'Analytics',
    );
    if (!_canViewAnalytics && analyticsIndex >= 0 && index == analyticsIndex) {
      PermissionService.showUnauthorizedDialog(context);
      return;
    }
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    // Choose layout based on screen size
    if (context.isDesktop) {
      return _buildDesktopLayout();
    } else if (context.isTablet) {
      return _buildTabletLayout();
    } else {
      return _buildMobileLayout();
    }
  }

  /// Desktop Layout - Full sidebar navigation
  Widget _buildDesktopLayout() {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: context.isDarkMode
          ? colorScheme.surfaceContainerLowest
          : AppColors.background,
      body: Row(
        children: [
          // Sidebar Navigation
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _isRailExpanded ? 260 : 80,
            child: _DesktopSidebar(
              items: _navigationItems,
              currentIndex: _currentIndex,
              isExpanded: _isRailExpanded,
              onItemSelected: (index) => setCurrentIndex(index),
              onToggleExpanded: () =>
                  setState(() => _isRailExpanded = !_isRailExpanded),
              userName: widget.userName,
              userRole: widget.userRole,
            ),
          ),
          // Main Content
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: context.isDarkMode
                    ? colorScheme.surfaceContainerLow
                    : AppColors.background,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  bottomLeft: Radius.circular(24),
                ),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  bottomLeft: Radius.circular(24),
                ),
                child: _navigationItems[_currentIndex].screen,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tablet Layout - Collapsible rail navigation
  Widget _buildTabletLayout() {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: context.isDarkMode
          ? colorScheme.surfaceContainerLowest
          : AppColors.background,
      body: Row(
        children: [
          // Navigation Rail
          _TabletNavigationRail(
            items: _navigationItems,
            currentIndex: _currentIndex,
            onItemSelected: (index) => setCurrentIndex(index),
            userName: widget.userName,
            userRole: widget.userRole,
          ),
          // Main Content
          Expanded(child: _navigationItems[_currentIndex].screen),
        ],
      ),
    );
  }

  /// Mobile Layout - Bottom navigation bar
  Widget _buildMobileLayout() {
    // For mobile, show key tabs directly in the bottom nav.
    // (Include Analytics for supervisors.)
    final fullIndices = _mobileNavFullIndices;
    final mobileNavItems = fullIndices.map((i) => _navigationItems[i]).toList();

    return Scaffold(
      key: _scaffoldKey,
      body: IndexedStack(
        index: _getMobileIndex(),
        children: _navigationItems.map((item) => item.screen).toList(),
      ),
      bottomNavigationBar: _MobileBottomNav(
        items: mobileNavItems,
        currentIndex: _getMobileNavIndex(),
        onItemSelected: (index) {
          // Map mobile nav index to full nav index
          setCurrentIndex(fullIndices[index]);
        },
      ),
      drawer: _MobileDrawer(
        items: _navigationItems,
        currentIndex: _currentIndex,
        onItemSelected: (index) {
          Navigator.pop(context);
          setCurrentIndex(index);
        },
        userName: widget.userName,
        userRole: widget.userRole,
      ),
    );
  }

  int _getMobileIndex() => _currentIndex;

  int _getMobileNavIndex() {
    // Map full index to mobile nav index.
    final idx = _mobileNavFullIndices.indexOf(_currentIndex);
    return idx >= 0 ? idx : 0;
  }
}

String _normalizeRole(String role) {
  return role.toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');
}

bool _canViewAnalyticsForRole(String role) {
  final normalized = _normalizeRole(role);
  return normalized == 'supervisor' ||
      normalized == 'admin' ||
      normalized == 'superadmin';
}

String _roleLabel(String role) {
  final normalized = _normalizeRole(role);
  switch (normalized) {
    case 'superadmin':
      return 'Super Admin';
    case 'admin':
      return 'Admin';
    case 'supervisor':
      return 'Supervisor';
    default:
      return 'Cashier';
  }
}

/// Desktop Sidebar Navigation — Material 3
class _DesktopSidebar extends StatelessWidget {
  final List<NavigationItemData> items;
  final int currentIndex;
  final bool isExpanded;
  final ValueChanged<int> onItemSelected;
  final VoidCallback onToggleExpanded;
  final String userName;
  final String userRole;

  const _DesktopSidebar({
    required this.items,
    required this.currentIndex,
    required this.isExpanded,
    required this.onItemSelected,
    required this.onToggleExpanded,
    required this.userName,
    required this.userRole,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final colorScheme = Theme.of(context).colorScheme;

    final canViewAnalytics = _canViewAnalyticsForRole(userRole);
    final visibleIndices = <int>[];
    for (var i = 0; i < items.length; i++) {
      final isAnalyticsItem = items[i].label.toLowerCase() == 'analytics';
      if (!canViewAnalytics && isAnalyticsItem) continue;
      visibleIndices.add(i);
    }

    return Material(
      color: isDark ? colorScheme.surfaceContainer : colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: colorScheme.outlineVariant, width: 1),
          ),
        ),
        child: Column(
          children: [
            // Logo & Brand
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isExpanded ? 20 : 16,
                vertical: 24,
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  if (isExpanded) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vivian',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Colors.white
                                  : AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            'Cosmetic Shop',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white60
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Search Bar (when expanded)
            if (isExpanded)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => showGlobalSearchDialog(context),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search_rounded,
                            size: 18,
                            color: isDark ? Colors.white38 : Colors.grey,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Search',
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.white38 : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Navigation Items
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: visibleIndices.length,
                itemBuilder: (context, index) {
                  final fullIndex = visibleIndices[index];
                  final item = items[fullIndex];
                  final isSelected = fullIndex == currentIndex;

                  return _SidebarItem(
                    icon: isSelected
                        ? (item.selectedIcon ?? item.icon)
                        : item.icon,
                    label: item.label,
                    isSelected: isSelected,
                    isExpanded: isExpanded,
                    onTap: () => onItemSelected(fullIndex),
                  );
                },
              ),
            ),

            // Collapse Button
            Padding(
              padding: const EdgeInsets.all(16),
              child: InkWell(
                onTap: onToggleExpanded,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: isExpanded
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                    children: [
                      Icon(
                        isExpanded
                            ? Icons.chevron_left_rounded
                            : Icons.chevron_right_rounded,
                        color: isDark ? Colors.white60 : Colors.grey,
                      ),
                      if (isExpanded) ...[
                        const SizedBox(width: 10),
                        Text(
                          'Collapse',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white60 : Colors.grey,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // User Profile
            Container(
              margin: const EdgeInsets.all(16),
              padding: EdgeInsets.all(isExpanded ? 12 : 8),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: isExpanded ? 40 : 36,
                    height: isExpanded ? 40 : 36,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  if (isExpanded) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white
                                  : AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _roleLabel(userRole),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white60
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.more_vert_rounded,
                      color: isDark ? Colors.white38 : Colors.grey,
                      size: 20,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sidebar Item Widget — Material 3
class _SidebarItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isExpanded;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _isHovering = false;

  void _setHovering(bool value) {
    if (!mounted || _isHovering == value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isHovering == value) return;
      setState(() => _isHovering = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        onEnter: (_) => _setHovering(true),
        onExit: (_) => _setHovering(false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(28),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(
              horizontal: widget.isExpanded ? 16 : 12,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? (isDark
                        ? AppColors.primaryDark.withValues(alpha: 0.3)
                        : AppColors.primaryLight)
                  : _isHovering
                  ? colorScheme.surfaceContainerHigh
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(
              mainAxisAlignment: widget.isExpanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(
                  widget.icon,
                  size: 22,
                  color: widget.isSelected
                      ? AppColors.primary
                      : isDark
                      ? Colors.white60
                      : AppColors.textSecondary,
                ),
                if (widget.isExpanded) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: widget.isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: widget.isSelected
                            ? AppColors.primary
                            : isDark
                            ? Colors.white
                            : AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tablet Navigation Rail — Material 3
class _TabletNavigationRail extends StatelessWidget {
  final List<NavigationItemData> items;
  final int currentIndex;
  final ValueChanged<int> onItemSelected;
  final String userName;
  final String userRole;

  const _TabletNavigationRail({
    required this.items,
    required this.currentIndex,
    required this.onItemSelected,
    required this.userName,
    required this.userRole,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    final canViewAnalytics = _canViewAnalyticsForRole(userRole);
    final visibleIndices = <int>[];
    for (var i = 0; i < items.length; i++) {
      final isAnalyticsItem = items[i].label.toLowerCase() == 'analytics';
      if (!canViewAnalytics && isAnalyticsItem) continue;
      visibleIndices.add(i);
    }

    // Map currentIndex to visible selection
    final selectedVis = visibleIndices.indexOf(currentIndex);

    return NavigationRail(
      backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      selectedIndex: selectedVis >= 0 ? selectedVis : 0,
      onDestinationSelected: (index) => onItemSelected(visibleIndices[index]),
      labelType: NavigationRailLabelType.all,
      useIndicator: true,
      indicatorColor: isDark
          ? AppColors.primaryDark.withValues(alpha: 0.4)
          : AppColors.primaryLight,
      leading: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.storefront_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
      trailing: Expanded(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      destinations: visibleIndices.map((fullIndex) {
        final item = items[fullIndex];
        return NavigationRailDestination(
          icon: Icon(item.icon),
          selectedIcon: Icon(item.selectedIcon ?? item.icon),
          label: Text(item.label),
        );
      }).toList(),
    );
  }
}

/// Mobile Bottom Navigation — Material 3 NavigationBar
class _MobileBottomNav extends StatelessWidget {
  final List<NavigationItemData> items;
  final int currentIndex;
  final ValueChanged<int> onItemSelected;

  const _MobileBottomNav({
    required this.items,
    required this.currentIndex,
    required this.onItemSelected,
  });

  String _compactLabel(NavigationItemData item, int itemCount) {
    final label = item.label.trim();
    final lower = label.toLowerCase();
    if (itemCount <= 4) return label;
    if (lower == 'point of sales' || lower == 'point of sale') return 'POS';
    final firstWord = label.split(' ').first;
    return firstWord.isNotEmpty ? firstWord : label;
  }

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: onItemSelected,
      destinations: items.map((item) {
        return NavigationDestination(
          icon: Icon(item.icon),
          selectedIcon: Icon(item.selectedIcon ?? item.icon),
          label: _compactLabel(item, items.length),
        );
      }).toList(),
    );
  }
}

/// Mobile Drawer — Material 3 NavigationDrawer
class _MobileDrawer extends StatelessWidget {
  final List<NavigationItemData> items;
  final int currentIndex;
  final ValueChanged<int> onItemSelected;
  final String userName;
  final String userRole;

  const _MobileDrawer({
    required this.items,
    required this.currentIndex,
    required this.onItemSelected,
    required this.userName,
    required this.userRole,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final canViewAnalytics = _canViewAnalyticsForRole(userRole);

    final visibleIndices = <int>[];
    for (var i = 0; i < items.length; i++) {
      final isAnalyticsItem = items[i].label.toLowerCase() == 'analytics';
      if (!canViewAnalytics && isAnalyticsItem) continue;
      visibleIndices.add(i);
    }

    final selectedVis = visibleIndices.indexOf(currentIndex);

    return NavigationDrawer(
      selectedIndex: selectedVis >= 0 ? selectedVis : 0,
      onDestinationSelected: (index) => onItemSelected(visibleIndices[index]),
      backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      surfaceTintColor: Colors.transparent,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
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
                      userName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _roleLabel(userRole),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Divider(),
        ),
        const SizedBox(height: 4),
        // Navigation Destinations
        ...visibleIndices.map((fullIndex) {
          final item = items[fullIndex];
          return NavigationDrawerDestination(
            icon: Icon(item.icon),
            selectedIcon: Icon(item.selectedIcon ?? item.icon),
            label: Text(item.label),
          );
        }),
      ],
    );
  }
}
