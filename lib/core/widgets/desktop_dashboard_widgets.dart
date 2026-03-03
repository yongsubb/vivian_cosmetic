import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:fl_chart/fl_chart.dart';
import '../constants/app_colors.dart';
import '../theme/theme_helper.dart';

/// Desktop Dashboard Widgets for larger screens
/// These provide chart visualizations and enhanced layouts

enum DashboardTimeframe { day, week, month, year }

/// Sales Statistics Card with gradient background
class SalesStatCard extends StatefulWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final String? trend;
  final bool isPositive;
  final VoidCallback? onTap;
  final Widget? trailing;

  const SalesStatCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    required this.color,
    this.trend,
    this.isPositive = true,
    this.onTap,
    this.trailing,
  });

  @override
  State<SalesStatCard> createState() => _SalesStatCardState();
}

class _SalesStatCardState extends State<SalesStatCard> {
  bool _isHovered = false;

  void _setHovered(bool value) {
    if (!mounted || _isHovered == value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isHovered == value) return;
      setState(() => _isHovered = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final colorScheme = Theme.of(context).colorScheme;
    final isClickable = widget.onTap != null;

    return MouseRegion(
      cursor: isClickable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: isClickable ? (_) => _setHovered(true) : null,
      onExit: isClickable ? (_) => _setHovered(false) : null,
      child: Semantics(
        button: isClickable,
        child: Card(
          elevation: _isHovered ? 2 : 0,
          color: isDark
              ? colorScheme.surfaceContainerHigh
              : colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: isClickable && _isHovered
                ? BorderSide(color: AppColors.primary.withValues(alpha: 0.25))
                : BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: widget.color.withValues(
                            alpha: isDark ? 0.15 : 0.1,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(widget.icon, color: widget.color, size: 24),
                      ),
                      const Spacer(),
                      if (widget.trailing != null) ...[
                        widget.trailing!,
                        if (widget.trend != null) const SizedBox(width: 8),
                      ],
                      if (widget.trend != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: widget.isPositive
                                ? Colors.green.withValues(alpha: 0.1)
                                : Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                widget.isPositive
                                    ? Icons.trending_up
                                    : Icons.trending_down,
                                size: 14,
                                color: widget.isPositive
                                    ? Colors.green
                                    : Colors.red,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                widget.trend!,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: widget.isPositive
                                      ? Colors.green
                                      : Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.title,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isDark ? Colors.white60 : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.value,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: isDark ? Colors.white38 : AppColors.textLight,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sales Bar Chart Widget
class SalesBarChart extends StatelessWidget {
  final List<double> data;
  final List<String> labels;
  final String title;

  const SalesBarChart({
    super.key,
    required this.data,
    required this.labels,
    this.title = 'Gross Sales',
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final isMousePlatform =
        kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;

    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: isDark ? colorScheme.surfaceContainerHigh : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                // Ensure we have valid constraints before rendering chart
                if (constraints.maxWidth == 0 ||
                    constraints.maxWidth == double.infinity) {
                  return const SizedBox(height: 200);
                }

                final maxValue = data.isEmpty
                    ? 0.0
                    : data.reduce((a, b) => a > b ? a : b);

                // Prevent fl_chart assertions when the dataset is all zeros.
                final safeMaxY = maxValue > 0 ? maxValue * 1.2 : 100.0;
                final safeGridInterval = maxValue > 0
                    ? (maxValue / 5).clamp(0.01, double.infinity)
                    : 20.0;

                return SizedBox(
                  height: 200,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: safeMaxY,
                      barTouchData: BarTouchData(
                        // fl_chart can throw RangeError on hover (mouse)
                        // when the pointer is near/outside the last bar.
                        // Disable built-in touch/hover on mouse platforms.
                        enabled: !isMousePlatform,
                        touchTooltipData: BarTouchTooltipData(
                          tooltipRoundedRadius: 8,
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            return BarTooltipItem(
                              '₱${rod.toY.toStringAsFixed(0)}',
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          },
                        ),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              if (value.toInt() >= labels.length) {
                                return const SizedBox();
                              }

                              // Avoid cramped X-axis labels for large datasets.
                              if (labels.length > 20 &&
                                  value.toInt() % 3 != 0) {
                                return const SizedBox();
                              }
                              if (labels.length > 12 &&
                                  labels.length <= 20 &&
                                  value.toInt() % 2 != 0) {
                                return const SizedBox();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  labels[value.toInt()],
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? Colors.white60
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 50,
                            getTitlesWidget: (value, meta) {
                              return Text(
                                _formatNumber(value),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white60
                                      : AppColors.textSecondary,
                                ),
                              );
                            },
                          ),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: safeGridInterval,
                        getDrawingHorizontalLine: (value) {
                          return FlLine(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : Colors.grey.shade200,
                            strokeWidth: 1,
                          );
                        },
                      ),
                      barGroups: List.generate(data.length, (index) {
                        return BarChartGroupData(
                          x: index,
                          barRods: [
                            BarChartRodData(
                              toY: data[index],
                              color: const Color(0xFF4FC3F7),
                              width: 24,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(6),
                                topRight: Radius.circular(6),
                              ),
                              backDrawRodData: BackgroundBarChartRodData(
                                show: true,
                                toY: safeMaxY,
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.grey.shade100,
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatNumber(double value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(0)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(0)}k';
    return value.toStringAsFixed(0);
  }
}

/// Sales Line Chart Widget
class SalesLineChart extends StatelessWidget {
  final List<double> currentData;
  final List<double>? previousData;
  final List<String> labels;
  final String title;
  final String currentLabel;
  final String previousLabel;

  const SalesLineChart({
    super.key,
    required this.currentData,
    this.previousData,
    required this.labels,
    this.title = 'Sales Trends',
    this.currentLabel = 'This Month',
    this.previousLabel = 'Last Month',
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final isMousePlatform =
        kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;

    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: isDark ? colorScheme.surfaceContainerHigh : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                Row(
                  children: [
                    _LegendItem(color: AppColors.primary, label: currentLabel),
                    const SizedBox(width: 16),
                    _LegendItem(color: Colors.orange, label: previousLabel),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth == 0 ||
                    constraints.maxWidth == double.infinity) {
                  return const SizedBox(height: 200);
                }
                return SizedBox(
                  height: 200,
                  child: LineChart(
                    LineChartData(
                      lineTouchData: LineTouchData(enabled: !isMousePlatform),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 20,
                        getDrawingHorizontalLine: (value) {
                          return FlLine(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : Colors.grey.shade200,
                            strokeWidth: 1,
                          );
                        },
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              if (value.toInt() >= labels.length ||
                                  value.toInt() % 2 != 0) {
                                return const SizedBox();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  labels[value.toInt()],
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? Colors.white60
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            getTitlesWidget: (value, meta) {
                              return Text(
                                '${value.toInt()}k',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white60
                                      : AppColors.textSecondary,
                                ),
                              );
                            },
                          ),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        // Current month line
                        LineChartBarData(
                          spots: List.generate(
                            currentData.length,
                            (index) =>
                                FlSpot(index.toDouble(), currentData[index]),
                          ),
                          isCurved: true,
                          color: AppColors.primary,
                          curveSmoothness: 0.5,
                          barWidth: 3,
                          isStrokeCapRound: true,
                          preventCurveOverShooting: true,
                          preventCurveOvershootingThreshold: 0,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: AppColors.primary.withValues(alpha: 0.1),
                          ),
                        ),
                        // Previous month line
                        if (previousData != null)
                          LineChartBarData(
                            spots: List.generate(
                              previousData!.length,
                              (index) => FlSpot(
                                index.toDouble(),
                                previousData![index],
                              ),
                            ),
                            isCurved: true,
                            color: Colors.orange,
                            curveSmoothness: 0.5,
                            barWidth: 3,
                            isStrokeCapRound: true,
                            preventCurveOverShooting: true,
                            preventCurveOvershootingThreshold: 0,
                            dotData: const FlDotData(show: false),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white60 : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Pie Chart for Payment Methods or Categories
class SalesPieChart extends StatelessWidget {
  final Map<String, double> data;
  final String title;

  const SalesPieChart({
    super.key,
    required this.data,
    this.title = 'Sales by Category',
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final isMousePlatform =
        kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;
    final total = data.values.fold<double>(0.0, (sum, v) => sum + v);
    final colors = [
      AppColors.primary,
      Colors.blue,
      Colors.orange,
      Colors.green,
      Colors.purple,
      Colors.teal,
    ];

    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: isDark ? colorScheme.surfaceContainerHigh : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth == 0 ||
                    constraints.maxWidth == double.infinity) {
                  return const SizedBox(height: 180);
                }
                return SizedBox(
                  height: 180,
                  child: Row(
                    children: [
                      Expanded(
                        child: PieChart(
                          PieChartData(
                            pieTouchData: PieTouchData(
                              enabled: !isMousePlatform,
                            ),
                            sectionsSpace: 2,
                            centerSpaceRadius: 40,
                            sections: data.entries.toList().asMap().entries.map(
                              (entry) {
                                final index = entry.key;
                                final item = entry.value;
                                final pct = total > 0
                                    ? (item.value / total) * 100
                                    : 0.0;
                                return PieChartSectionData(
                                  value: item.value,
                                  title: '${pct.toStringAsFixed(0)}%',
                                  color: colors[index % colors.length],
                                  radius: 50,
                                  titleStyle: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                );
                              },
                            ).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: data.entries.toList().asMap().entries.map((
                          entry,
                        ) {
                          final index = entry.key;
                          final item = entry.value;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: colors[index % colors.length],
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  item.key,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white70
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Quick Stats Row for Desktop
class QuickStatsRow extends StatelessWidget {
  final double todaySales;
  final int transactions;
  final int itemsSold;
  final double growthPercentage;
  final String salesSubtitle;
  final String totalSalesTimeframeLabel;
  final VoidCallback? onTotalSalesTap;
  final VoidCallback? onTransactionsTap;
  final VoidCallback? onItemsSoldTap;
  final VoidCallback? onAvgOrderTap;

  const QuickStatsRow({
    super.key,
    required this.todaySales,
    required this.transactions,
    required this.itemsSold,
    required this.growthPercentage,
    this.salesSubtitle = 'Today',
    this.totalSalesTimeframeLabel = 'Day',
    this.onTotalSalesTap,
    this.onTransactionsTap,
    this.onItemsSoldTap,
    this.onAvgOrderTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SalesStatCard(
            title: 'Total Sales',
            value: '₱${_formatCurrency(todaySales)}',
            subtitle: salesSubtitle,
            icon: Icons.monetization_on_rounded,
            color: AppColors.primary,
            trend:
                '${growthPercentage >= 0 ? '+' : ''}${growthPercentage.toStringAsFixed(1)}%',
            isPositive: growthPercentage >= 0,
            onTap: onTotalSalesTap,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.calendar_month_rounded,
                    size: 14,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    totalSalesTimeframeLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: SalesStatCard(
            title: 'Transactions',
            value: transactions.toString(),
            subtitle: 'Completed',
            icon: Icons.receipt_long_rounded,
            color: Colors.blue,
            onTap: onTransactionsTap,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: SalesStatCard(
            title: 'Items Sold',
            value: itemsSold.toString(),
            subtitle: 'Products',
            icon: Icons.shopping_bag_rounded,
            color: Colors.green,
            onTap: onItemsSoldTap,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: SalesStatCard(
            title: 'Avg. Order',
            value:
                '₱${transactions > 0 ? (todaySales / transactions).toStringAsFixed(2) : '0.00'}',
            subtitle: 'Per transaction',
            icon: Icons.analytics_rounded,
            color: Colors.orange,
            onTap: onAvgOrderTap,
          ),
        ),
      ],
    );
  }

  String _formatCurrency(double amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(2)}M';
    } else if (amount >= 1000) {
      return amount
          .toStringAsFixed(2)
          .replaceAllMapped(
            RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
            (Match m) => '${m[1]},',
          );
    }
    return amount.toStringAsFixed(2);
  }
}

/// Recent Activity Card for Desktop
class RecentActivityCard extends StatelessWidget {
  final List<ActivityItem> activities;
  final VoidCallback? onViewAll;

  const RecentActivityCard({
    super.key,
    required this.activities,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: isDark ? colorScheme.surfaceContainerHigh : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Activity',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (onViewAll != null)
                  TextButton(
                    onPressed: onViewAll,
                    child: Text(
                      'View All',
                      style: TextStyle(fontSize: 14, color: AppColors.primary),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            ...activities
                .take(5)
                .map((activity) => _ActivityListItem(activity: activity)),
          ],
        ),
      ),
    );
  }
}

class ActivityItem {
  final String title;
  final String subtitle;
  final String time;
  final IconData icon;
  final Color color;

  const ActivityItem({
    required this.title,
    required this.subtitle,
    required this.time,
    required this.icon,
    required this.color,
  });
}

class _ActivityListItem extends StatelessWidget {
  final ActivityItem activity;

  const _ActivityListItem({required this.activity});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: activity.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(activity.icon, color: activity.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                Text(
                  activity.subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            activity.time,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white38 : AppColors.textLight,
            ),
          ),
        ],
      ),
    );
  }
}
