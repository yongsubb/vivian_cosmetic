import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:math' as math;
import '../core/constants/app_colors.dart';
import '../core/constants/app_typography.dart';
import '../core/theme/theme_helper.dart';
import '../services/api_service.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // Keep state when switching tabs

  late TabController _tabController;
  final ApiService _apiService = ApiService();
  int _selectedReportType = 0; // 0: Daily, 1: Weekly, 2: Monthly

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Child tabs handle their own loading, no need to reload here
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(
        backgroundColor: context.cardColor,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Reports & Analytics',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: context.textPrimaryColor,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFE91E63),
          labelColor: const Color(0xFFE91E63),
          unselectedLabelColor: context.textSecondaryColor,
          tabs: const [
            Tab(icon: Icon(Icons.show_chart), text: 'Sales Report'),
            Tab(icon: Icon(Icons.star), text: 'Top Products'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Report Type Selector
          Card(
            margin: const EdgeInsets.all(16),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  _buildReportTypeButton('Daily', 0, Icons.today_rounded),
                  _buildReportTypeButton('Weekly', 1, Icons.date_range_rounded),
                  _buildReportTypeButton(
                    'Monthly',
                    2,
                    Icons.calendar_month_rounded,
                  ),
                  _buildReportTypeButton(
                    'Yearly',
                    3,
                    Icons.calendar_today_rounded,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _SalesReportView(
                  apiService: _apiService,
                  reportType: _selectedReportType,
                ),
                _TopProductsView(
                  apiService: _apiService,
                  reportType: _selectedReportType,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportTypeButton(String label, int index, IconData icon) {
    final isSelected = _selectedReportType == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedReportType = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : context.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primary : context.dividerColor,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : context.textSecondaryColor,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : context.textSecondaryColor,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// SALES REPORT VIEW
// ============================================================

class _SalesReportView extends StatefulWidget {
  final ApiService apiService;
  final int reportType;

  const _SalesReportView({required this.apiService, required this.reportType});

  @override
  State<_SalesReportView> createState() => _SalesReportViewState();
}

class _SalesReportViewState extends State<_SalesReportView> {
  DateTime _selectedDate = DateTime.now();
  Map<String, dynamic>? _reportData;
  bool _isLoading = false;
  String? _error;
  int _touchedIndex = -1;

  String get _refundSubtitle {
    switch (widget.reportType) {
      case 0:
        return 'Approved today';
      case 1:
        return 'Approved this week';
      case 2:
        return 'Approved this month';
      case 3:
        return 'Approved this year';
      default:
        return 'Approved refunds';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload when dependencies change (e.g., when parent screen becomes visible)
    _loadReport();
  }

  @override
  void didUpdateWidget(covariant _SalesReportView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reportType != widget.reportType) {
      _loadReport();
    }
  }

  Future<void> _loadReport() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      late final ApiResponse<Map<String, dynamic>> response;

      switch (widget.reportType) {
        case 0: // Daily
          response = await widget.apiService.getDailyReport(dateStr);
          break;
        case 1: // Weekly
          response = await widget.apiService.getWeeklyReport(dateStr);
          break;
        case 2: // Monthly
          response = await widget.apiService.getMonthlyReport(
            year: _selectedDate.year,
            month: _selectedDate.month,
          );
          break;
        case 3: // Yearly
          response = await widget.apiService.getYearlyReport(
            year: _selectedDate.year,
          );
          break;
        default:
          throw Exception('Invalid report type');
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          if (response.success && response.data != null) {
            _reportData = response.data;
          } else {
            _error = response.message ?? 'Failed to load report';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Error loading report: $e';
        });
      }
    }
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFE91E63),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );
    if (date != null) {
      setState(() => _selectedDate = date);
      _loadReport();
    }
  }

  Future<void> _exportToPDF() async {
    if (_reportData == null) return;

    final totalSalesRaw = _reportData!['total_sales'] ?? 0;
    final totalSales = totalSalesRaw is num
        ? totalSalesRaw.toDouble()
        : double.tryParse(totalSalesRaw.toString()) ?? 0.0;
    final averageSaleRaw = _reportData!['average_sale'] ?? 0;
    final averageSale = averageSaleRaw is num
        ? averageSaleRaw.toDouble()
        : double.tryParse(averageSaleRaw.toString()) ?? 0.0;

    final pdf = pw.Document();
    final dateFormat = DateFormat('MMM dd, yyyy');
    final reportTypeNames = ['Daily', 'Weekly', 'Monthly', 'Yearly'];

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Header
            pw.Container(
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                color: PdfColors.pink100,
                borderRadius: pw.BorderRadius.circular(12),
              ),
              child: pw.Row(
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Vivian Cosmetics',
                        style: pw.TextStyle(
                          fontSize: 24,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.pink800,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        '${reportTypeNames[widget.reportType]} Sales Report',
                        style: const pw.TextStyle(fontSize: 14),
                      ),
                      pw.Text(
                        'Date: ${dateFormat.format(_selectedDate)}',
                        style: const pw.TextStyle(
                          fontSize: 12,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 30),

            // Summary Section
            pw.Text(
              'Sales Summary',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 15),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(10),
                      child: pw.Text(
                        'Metric',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(10),
                      child: pw.Text(
                        'Value',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                _buildPdfTableRow(
                  'Total Sales',
                  '₱${totalSales.toStringAsFixed(2)}',
                ),
                _buildPdfTableRow(
                  'Transactions',
                  '${_reportData!['total_transactions'] ?? 0}',
                ),
                _buildPdfTableRow(
                  'Items Sold',
                  '${_reportData!['total_items_sold'] ?? 0}',
                ),
                _buildPdfTableRow(
                  'Average Sale',
                  '₱${averageSale.toStringAsFixed(2)}',
                ),
                _buildPdfTableRow(
                  'Refunded Products',
                  '${_reportData!['refunded_products'] ?? _reportData!['refunded_items'] ?? 0}',
                ),
              ],
            ),
            pw.SizedBox(height: 30),

            // Footer
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Text(
              'Generated on ${DateFormat('MMM dd, yyyy HH:mm').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
            ),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  pw.TableRow _buildPdfTableRow(String label, String value) {
    return pw.TableRow(
      children: [
        pw.Padding(padding: const pw.EdgeInsets.all(10), child: pw.Text(label)),
        pw.Padding(
          padding: const pw.EdgeInsets.all(10),
          child: pw.Text(
            value,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFFE91E63)),
            SizedBox(height: 16),
            Text('Loading report...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.red.shade400,
              ),
            ),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadReport,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadReport,
      color: const Color(0xFFE91E63),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date Selector Card
            _buildDateSelectorCard(),
            const SizedBox(height: 16),

            // Stats Grid
            _buildStatsGrid(),
            const SizedBox(height: 20),

            // Sales Chart
            _buildSalesChart(),
            const SizedBox(height: 20),

            // Payment Methods Breakdown
            if (_reportData?['payment_methods'] != null) ...[
              _buildPaymentMethodsChart(),
              const SizedBox(height: 20),
            ],

            // Export Buttons
            _buildExportButtons(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelectorCard() {
    final reportTypeLabels = [
      'Daily Report',
      'Weekly Report',
      'Monthly Report',
      'Yearly Report',
    ];
    final dateFormats = [
      DateFormat('EEEE, MMMM d, yyyy'),
      DateFormat("'Week of' MMM d, yyyy"),
      DateFormat('MMMM yyyy'),
      DateFormat('yyyy'),
    ];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE91E63),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.calendar_today_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reportTypeLabels[widget.reportType],
                    style: const TextStyle(
                      color: Color(0xFFE91E63),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dateFormats[widget.reportType].format(_selectedDate),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            Material(
              color: const Color(0xFFE91E63),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: _selectDate,
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.edit_calendar, color: Colors.white, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Change',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    final totalSales = (_reportData?['total_sales'] ?? 0).toDouble();
    final totalTransactions = _reportData?['total_transactions'] ?? 0;
    final itemsSold = _reportData?['total_items_sold'] ?? 0;
    final avgSale = (_reportData?['average_sale'] ?? 0).toDouble();
    final refundedRaw =
        _reportData?['refunded_products'] ??
        _reportData?['refunded_items'] ??
        0;
    final refundedProducts = refundedRaw is num
        ? refundedRaw.toInt()
        : int.tryParse(refundedRaw.toString()) ?? 0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.payments_rounded,
                iconColor: const Color(0xFFE91E63),
                title: 'Total Sales',
                value: '₱${NumberFormat('#,##0.00').format(totalSales)}',
                subtitle: 'Revenue generated',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.receipt_long_rounded,
                iconColor: Colors.orange,
                title: 'Transactions',
                value: '$totalTransactions',
                subtitle: 'Completed sales',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.inventory_2_rounded,
                iconColor: Colors.blue,
                title: 'Items Sold',
                value: '$itemsSold',
                subtitle: 'Products moved',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.trending_up_rounded,
                iconColor: Colors.purple,
                title: 'Avg Sale',
                value: '₱${NumberFormat('#,##0.00').format(avgSale)}',
                subtitle: 'Per transaction',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.assignment_return_rounded,
                iconColor: AppColors.error,
                title: 'Refunded Products',
                value: '$refundedProducts',
                subtitle: _refundSubtitle,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSalesChart() {
    // Parse real sales data from API
    final List<double> salesData = [];
    final List<String> labels = [];

    // Check report type by data structure
    final hourlyBreakdown =
        _reportData?['hourly_breakdown'] as Map<String, dynamic>?;
    final dailyBreakdown =
        _reportData?['daily_breakdown'] as Map<String, dynamic>?;
    final monthlyBreakdown =
        _reportData?['monthly_breakdown'] as Map<String, dynamic>?;

    if (hourlyBreakdown != null && hourlyBreakdown.isNotEmpty) {
      // Daily report: show hourly data
      final hoursToShow = [0, 3, 6, 9, 12, 15, 18, 21]; // Every 3 hours

      for (var hour in hoursToShow) {
        final hourData =
            hourlyBreakdown[hour.toString()] as Map<String, dynamic>?;
        final sales = (hourData?['sales'] ?? 0).toDouble();
        salesData.add(sales);

        // Format hour labels (12AM, 3AM, 6AM, 9AM, 12PM, 3PM, 6PM, 9PM)
        if (hour == 0) {
          labels.add('12AM');
        } else if (hour < 12) {
          labels.add('${hour}AM');
        } else if (hour == 12) {
          labels.add('12PM');
        } else {
          labels.add('${hour - 12}PM');
        }
      }
    } else if (monthlyBreakdown != null && monthlyBreakdown.isNotEmpty) {
      // Yearly report: show monthly data
      final sortedMonths = monthlyBreakdown.keys.toList()..sort();
      const monthNames = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];

      for (var monthKey in sortedMonths) {
        final monthData = monthlyBreakdown[monthKey] as Map<String, dynamic>?;
        final sales = (monthData?['sales'] ?? 0).toDouble();
        salesData.add(sales);

        // Extract month number from key (YYYY-MM format)
        final monthNum = int.parse(monthKey.split('-')[1]);
        labels.add(monthNames[monthNum - 1]);
      }
    } else if (dailyBreakdown != null && dailyBreakdown.isNotEmpty) {
      // Weekly or Monthly report: show daily or weekly data
      final sortedDates = dailyBreakdown.keys.toList()..sort();

      if (sortedDates.length <= 7) {
        // Weekly view: show all 7 days
        for (var date in sortedDates) {
          final dayData = dailyBreakdown[date] as Map<String, dynamic>?;
          final sales = (dayData?['sales'] ?? 0).toDouble();
          salesData.add(sales);

          final dateObj = DateTime.parse(date);
          const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
          labels.add(dayNames[(dateObj.weekday - 1) % 7]);
        }
      } else {
        // Monthly view: group into 4 weeks
        final daysPerWeek = (sortedDates.length / 4).ceil();

        for (int week = 0; week < 4; week++) {
          double weekSales = 0;
          final startIdx = week * daysPerWeek;
          final endIdx = (startIdx + daysPerWeek).clamp(0, sortedDates.length);

          for (int i = startIdx; i < endIdx; i++) {
            final dayData =
                dailyBreakdown[sortedDates[i]] as Map<String, dynamic>?;
            weekSales += (dayData?['sales'] ?? 0).toDouble();
          }

          salesData.add(weekSales);
          labels.add('W${week + 1}');
        }
      }
    }

    // Fallback: if no data, show zero line
    if (salesData.isEmpty) {
      salesData.addAll([0, 0, 0, 0, 0, 0, 0, 0]);
      labels.addAll(['12AM', '3AM', '6AM', '9AM', '12PM', '3PM', '6PM', '9PM']);
    }

    // Get trend percentage from API
    final trendPercentage = (_reportData?['trend_percentage'] ?? 0).toDouble();
    final isPositive = trendPercentage >= 0;
    final trendColor = isPositive ? Colors.green : Colors.red;
    final trendIcon = isPositive ? Icons.trending_up : Icons.trending_down;
    final trendSign = isPositive ? '+' : '';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE91E63).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.show_chart_rounded,
                        color: Color(0xFFE91E63),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Sales Trend',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: trendColor.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(trendIcon, size: 16, color: trendColor.shade700),
                      const SizedBox(width: 4),
                      Text(
                        '$trendSign${trendPercentage.abs().toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: trendColor.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 1,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: const Color.fromARGB(
                          255,
                          235,
                          227,
                          227,
                        ).withValues(alpha: 0.1),
                        strokeWidth: 1,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index >= 0 && index < labels.length) {
                            return Text(
                              labels[index],
                              style: AppTypography.caption.copyWith(
                                color: context.textSecondaryColor,
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: salesData
                          .asMap()
                          .entries
                          .map((e) => FlSpot(e.key.toDouble(), e.value))
                          .toList(),
                      isCurved: true,
                      curveSmoothness: 0,
                      gradient: AppColors.primaryGradient,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 4,
                            color: Colors.white,
                            strokeWidth: 2,
                            strokeColor: AppColors.primary,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.1),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          return LineTooltipItem(
                            '₱${NumberFormat('#,##0').format(spot.y)}',
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        }).toList();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethodsChart() {
    final paymentMethods =
        _reportData?['payment_methods'] as Map<String, dynamic>? ?? {};
    if (paymentMethods.isEmpty) return const SizedBox();

    final colors = [
      const Color(0xFFE91E63),
      const Color(0xFF2196F3),
      const Color(0xFF4CAF50),
      const Color(0xFFFF9800),
      const Color(0xFF9C27B0),
    ];

    final entries = paymentMethods.entries.toList();
    final total = entries.fold<double>(
      0,
      (sum, e) => sum + (e.value ?? 0).toDouble(),
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.pie_chart_rounded,
                  color: AppColors.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text('Payment Methods', style: AppTypography.heading4),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              // Pie Chart
              SizedBox(
                height: 160,
                width: 160,
                child: PieChart(
                  PieChartData(
                    pieTouchData: PieTouchData(
                      touchCallback: (FlTouchEvent event, pieTouchResponse) {
                        setState(() {
                          if (!event.isInterestedForInteractions ||
                              pieTouchResponse == null ||
                              pieTouchResponse.touchedSection == null) {
                            _touchedIndex = -1;
                            return;
                          }
                          _touchedIndex = pieTouchResponse
                              .touchedSection!
                              .touchedSectionIndex;
                        });
                      },
                    ),
                    sectionsSpace: 3,
                    centerSpaceRadius: 40,
                    sections: entries.asMap().entries.map((entry) {
                      final index = entry.key;
                      final data = entry.value;
                      final value = (data.value ?? 0).toDouble();
                      final percentage = total > 0 ? (value / total * 100) : 0;
                      final isTouched = index == _touchedIndex;
                      final radius = isTouched ? 45.0 : 35.0;

                      return PieChartSectionData(
                        color: colors[index % colors.length],
                        value: value,
                        title: isTouched
                            ? '${percentage.toStringAsFixed(1)}%'
                            : '',
                        radius: radius,
                        titleStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              // Legend
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: entries.asMap().entries.map((entry) {
                    final index = entry.key;
                    final data = entry.value;
                    final value = (data.value ?? 0).toDouble();
                    final percentage = total > 0 ? (value / total * 100) : 0;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: colors[index % colors.length],
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              data.key,
                              style: AppTypography.bodySmall,
                            ),
                          ),
                          Text(
                            '${percentage.toStringAsFixed(0)}%',
                            style: AppTypography.labelSmall.copyWith(
                              color: context.textSecondaryColor,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExportButtons() {
    return Row(
      children: [
        Expanded(
          child: _ExportButton(
            icon: Icons.picture_as_pdf_rounded,
            label: 'Export PDF',
            color: const Color(0xFFE53935),
            onTap: _exportToPDF,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ExportButton(
            icon: Icons.table_chart_rounded,
            label: 'Export Excel',
            color: const Color(0xFF43A047),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Excel export coming soon!'),
                  backgroundColor: AppColors.info,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ============================================================
// TOP PRODUCTS VIEW
// ============================================================

class _TopProductsView extends StatefulWidget {
  final ApiService apiService;
  final int reportType;

  const _TopProductsView({required this.apiService, required this.reportType});

  @override
  State<_TopProductsView> createState() => _TopProductsViewState();
}

class _TopProductsViewState extends State<_TopProductsView> {
  List<Map<String, dynamic>> _products = [];
  bool _isLoading = false;
  String? _error;
  int _limit = 10;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload when dependencies change (e.g., when parent screen becomes visible)
    _loadProducts();
  }

  @override
  void didUpdateWidget(covariant _TopProductsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reportType != widget.reportType) {
      _loadProducts();
    }
  }

  String _timeframeForReportType(int reportType) {
    switch (reportType) {
      case 0:
        return 'day';
      case 1:
        return 'week';
      case 3:
        return 'year';
      case 2:
      default:
        return 'month';
    }
  }

  Future<void> _loadProducts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final response = await widget.apiService.getTopProducts(
      limit: _limit,
      timeframe: _timeframeForReportType(widget.reportType),
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (response.success && response.data != null) {
          _products = response.data!;
        } else {
          _error = response.message ?? 'Failed to load products';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text(_error!, style: AppTypography.bodyMedium),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadProducts,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadProducts,
      color: AppColors.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Filter Buttons
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: context.cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                children: [5, 10, 20].map((limit) {
                  final isSelected = _limit == limit;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _limit = limit);
                        _loadProducts();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          gradient: isSelected
                              ? AppColors.primaryGradient
                              : null,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            'Top $limit',
                            style: AppTypography.labelMedium.copyWith(
                              color: isSelected
                                  ? Colors.white
                                  : context.textSecondaryColor,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),

            if (_products.isEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: context.cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.dividerColor),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      color: context.textSecondaryColor,
                      size: 40,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No product sales found for this period.',
                      style: AppTypography.bodyMedium.copyWith(
                        color: context.textSecondaryColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Products Chart
            if (_products.isNotEmpty) ...[
              _buildProductsBarChart(),
              const SizedBox(height: 20),
            ],

            // Products List
            ...List.generate(_products.length, (index) {
              final product = _products[index];
              final rank = index + 1;
              final quantitySold =
                  product['quantity_sold'] ?? product['total_quantity'] ?? 0;
              final revenue =
                  (product['total_revenue'] ?? product['total_sales'] ?? 0)
                      .toDouble();

              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Rank Badge
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: rank == 1
                              ? AppColors.goldGradient
                              : rank == 2
                              ? LinearGradient(
                                  colors: [AppColors.infoLight, AppColors.info],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : rank == 3
                              ? LinearGradient(
                                  colors: [
                                    AppColors.primaryLight,
                                    AppColors.primary,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          color: rank > 3 ? AppColors.secondary : null,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            '#$rank',
                            style: AppTypography.labelMedium.copyWith(
                              color: rank <= 3
                                  ? Colors.white
                                  : context.textSecondaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Product Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product['product_name'] ??
                                  product['name'] ??
                                  'Unknown',
                              style: AppTypography.labelLarge.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                                    color: AppColors.primary.withValues(
                                      alpha: isDark ? 0.18 : 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '$quantitySold sold',
                                    style: AppTypography.labelSmall.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Revenue
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '₱${NumberFormat('#,##0').format(revenue)}',
                            style: AppTypography.labelLarge.copyWith(
                              color: AppColors.success,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text('revenue', style: AppTypography.caption),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildProductsBarChart() {
    final topProducts = _products.take(5).toList();
    if (topProducts.isEmpty) return const SizedBox();

    final maxRevenue = topProducts.fold<double>(
      0,
      (max, p) => math.max(
        max,
        (p['total_revenue'] ?? p['total_sales'] ?? 0).toDouble(),
      ),
    );

    final safeMaxY = maxRevenue <= 0 ? 1.0 : maxRevenue * 1.2;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.bar_chart_rounded,
                    color: AppColors.accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text('Revenue Distribution', style: AppTypography.heading4),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: safeMaxY,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final product = topProducts[group.x.toInt()];
                        return BarTooltipItem(
                          '${product['product_name'] ?? product['name']}\n₱${NumberFormat('#,##0').format(rod.toY)}',
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
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= topProducts.length) {
                            return const Text('');
                          }
                          return Text(
                            '#${value.toInt() + 1}',
                            style: AppTypography.caption,
                          );
                        },
                        reservedSize: 30,
                      ),
                    ),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barGroups: topProducts.asMap().entries.map((entry) {
                    final index = entry.key;
                    final product = entry.value;
                    final revenue =
                        (product['total_revenue'] ??
                                product['total_sales'] ??
                                0)
                            .toDouble();
                    final colors = <Color>[
                      AppColors.primary,
                      AppColors.primaryDark,
                      AppColors.accent,
                      AppColors.info,
                      AppColors.warning,
                    ];
                    final baseColor = colors[index % colors.length];

                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: revenue,
                          gradient: LinearGradient(
                            colors: [
                              baseColor,
                              baseColor.withValues(alpha: 0.7),
                            ],
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                          ),
                          width: 28,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(8),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// HELPER WIDGETS
// ============================================================

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;
  final String subtitle;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ExportButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              Text(
                label,
                style: AppTypography.labelMedium.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
