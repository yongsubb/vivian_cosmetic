import 'package:flutter/material.dart';

/// Responsive layout utilities for different screen sizes
class ResponsiveLayout {
  // Breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 900;
  static const double desktopBreakpoint = 1200;

  /// Check if device is mobile
  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < mobileBreakpoint;
  }

  /// Check if device is tablet
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= mobileBreakpoint && width < desktopBreakpoint;
  }

  /// Check if device is desktop
  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= desktopBreakpoint;
  }

  /// Get number of grid columns based on screen width
  static int getGridCrossAxisCount(
    BuildContext context, {
    int mobile = 2,
    int tablet = 3,
    int desktop = 4,
  }) {
    if (isDesktop(context)) return desktop;
    if (isTablet(context)) return tablet;
    return mobile;
  }

  /// Get responsive padding
  static EdgeInsets getResponsivePadding(
    BuildContext context, {
    double mobile = 16,
    double tablet = 24,
    double desktop = 32,
  }) {
    if (isDesktop(context)) {
      return EdgeInsets.all(desktop);
    }
    if (isTablet(context)) {
      return EdgeInsets.all(tablet);
    }
    return EdgeInsets.all(mobile);
  }

  /// Get responsive value based on screen size
  static T getResponsiveValue<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    if (isDesktop(context) && desktop != null) return desktop;
    if (isTablet(context) && tablet != null) return tablet;
    return mobile;
  }

  /// Get screen type
  static ScreenType getScreenType(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= desktopBreakpoint) return ScreenType.desktop;
    if (width >= mobileBreakpoint) return ScreenType.tablet;
    return ScreenType.mobile;
  }

  /// Get max content width for large screens
  static double getMaxContentWidth(BuildContext context) {
    return getResponsiveValue(
      context,
      mobile: double.infinity,
      tablet: 800,
      desktop: 1200,
    );
  }
}

enum ScreenType { mobile, tablet, desktop }

/// Responsive widget builder
class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, ScreenType screenType) builder;

  const ResponsiveBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return builder(context, ResponsiveLayout.getScreenType(context));
  }
}

/// Responsive grid with adaptive column count
class ResponsiveGrid extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final double childAspectRatio;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final int mobileColumns;
  final int tabletColumns;
  final int desktopColumns;

  const ResponsiveGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.childAspectRatio = 1.0,
    this.mainAxisSpacing = 12,
    this.crossAxisSpacing = 12,
    this.mobileColumns = 2,
    this.tabletColumns = 3,
    this.desktopColumns = 4,
  });

  @override
  Widget build(BuildContext context) {
    final crossAxisCount = ResponsiveLayout.getGridCrossAxisCount(
      context,
      mobile: mobileColumns,
      tablet: tabletColumns,
      desktop: desktopColumns,
    );

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: childAspectRatio,
        mainAxisSpacing: mainAxisSpacing,
        crossAxisSpacing: crossAxisSpacing,
      ),
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }
}

/// Two-pane layout for tablets (master-detail)
class MasterDetailLayout extends StatelessWidget {
  final Widget master;
  final Widget detail;
  final double masterWidth;

  const MasterDetailLayout({
    super.key,
    required this.master,
    required this.detail,
    this.masterWidth = 300,
  });

  @override
  Widget build(BuildContext context) {
    if (ResponsiveLayout.isMobile(context)) {
      // On mobile, show only master or detail (handled by navigation)
      return master;
    }

    // On tablet/desktop, show both side by side
    return Row(
      children: [
        SizedBox(width: masterWidth, child: master),
        Expanded(child: detail),
      ],
    );
  }
}

/// Adaptive scaffold with responsive navigation
class AdaptiveScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? drawer;
  final Widget? floatingActionButton;
  final List<BottomNavigationBarItem>? bottomNavigationBarItems;
  final int? currentIndex;
  final ValueChanged<int>? onNavigationIndexChanged;

  const AdaptiveScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.drawer,
    this.floatingActionButton,
    this.bottomNavigationBarItems,
    this.currentIndex,
    this.onNavigationIndexChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isLargeScreen =
        ResponsiveLayout.isTablet(context) ||
        ResponsiveLayout.isDesktop(context);

    if (isLargeScreen && drawer != null) {
      // On large screens, show persistent navigation rail or drawer
      return Scaffold(
        appBar: appBar,
        body: Row(
          children: [
            if (drawer != null) drawer!,
            Expanded(child: body),
          ],
        ),
        floatingActionButton: floatingActionButton,
      );
    }

    // On mobile, use standard scaffold with bottom navigation
    return Scaffold(
      appBar: appBar,
      body: body,
      drawer: drawer,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBarItems != null
          ? BottomNavigationBar(
              items: bottomNavigationBarItems!,
              currentIndex: currentIndex ?? 0,
              onTap: onNavigationIndexChanged,
            )
          : null,
    );
  }
}
