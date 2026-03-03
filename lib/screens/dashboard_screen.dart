import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_colors.dart';
import '../core/theme/theme_helper.dart';
import '../core/constants/app_strings.dart';
import '../core/constants/app_typography.dart';
import '../core/utils/ph_time.dart';
import '../core/widgets/responsive_navigation.dart';
import '../core/widgets/desktop_dashboard_widgets.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import 'transactions_screen.dart';
import 'main_navigation_screen.dart';
import 'receipt_screen.dart';
import 'sales_screen.dart';
import 'products_screen.dart';
import 'reports_screen.dart';
import 'loyalty_screen.dart';
import 'global_search_dialog.dart';

enum DashboardTimeframe { day, week, month, year }

enum DashboardNotificationType { success, warning, error, info }

enum _NotificationStatus { unread, read, archived }

enum _NotificationsFilter { all, unread, archived }

class _DashboardNotificationItem {
  final String id;
  final String sourceKey;
  final DateTime createdAt;
  final DashboardNotificationType type;
  final String title;
  final String message;
  final _NotificationStatus status;
  final VoidCallback? onTap;

  const _DashboardNotificationItem({
    required this.id,
    required this.sourceKey,
    required this.createdAt,
    required this.type,
    required this.title,
    required this.message,
    required this.status,
    this.onTap,
  });

  _DashboardNotificationItem copyWith({_NotificationStatus? status}) {
    return _DashboardNotificationItem(
      id: id,
      sourceKey: sourceKey,
      createdAt: createdAt,
      type: type,
      title: title,
      message: message,
      status: status ?? this.status,
      onTap: onTap,
    );
  }
}

String _ymd(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

class DashboardScreen extends StatefulWidget {
  final String userName;
  final String userRole;

  const DashboardScreen({
    super.key,
    required this.userName,
    required this.userRole,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // Keep state when switching tabs

  final ApiService _apiService = ApiService();

  SharedPreferences? _prefs;
  bool _notificationStorageReady = false;

  // Loading states
  bool _isLoadingSales = true;
  bool _isLoadingLowStock = true;
  bool _isLoadingTransactions = true;
  bool _isRefreshing = false;
  bool _wasCurrentBefore = false;

  // Data
  Map<String, dynamic>? _dailyReport;
  List<Product> _lowStockProducts = [];
  List<_TransactionData> _recentTransactions = [];

  double _totalSalesGrowthPercent = 0.0;

  DashboardTimeframe _timeframe = DashboardTimeframe.day;
  List<double> _grossSalesChartData = List<double>.filled(12, 0.0);
  List<String> _grossSalesChartLabels = const [
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

  // Error messages
  String? _salesError;
  String? _lowStockError;
  String? _transactionsError;

  // Notifications (in-app inbox)
  final List<_DashboardNotificationItem> _notifications = [];
  final Set<String> _suppressedSourceKeys = <String>{};

  final Set<String> _activeLowStockProductIds = <String>{};
  final Set<String> _activePendingAccountIds = <String>{};
  final Set<String> _activePendingRefundRequestIds = <String>{};
  final Set<String> _seenRefundDecisionRequestIds = <String>{};
  String? _activeSalesError;
  String? _activeLowStockError;
  String? _activeTransactionsError;

  String get _notificationStorageKey {
    final role = widget.userRole.toLowerCase();
    final name = widget.userName.toLowerCase().trim();
    return 'dashboard_notifications_v1:$role:$name';
  }

  String get _notificationMetaStorageKey {
    final role = widget.userRole.toLowerCase();
    final name = widget.userName.toLowerCase().trim();
    return 'dashboard_notification_meta_v1:$role:$name';
  }

  final List<String> _monthLabels = const [
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

  String _extractTransactionCode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final match = RegExp(r'(TXN-[A-Za-z0-9]+)').firstMatch(trimmed);
    if (match != null) return match.group(1) ?? trimmed;
    return trimmed;
  }

  Future<void> _showReceiptLookupDialog() async {
    final controller = TextEditingController();
    final memberCardController = TextEditingController();
    bool isScanning = false;
    bool hasDetected = false;

    bool isSubmitting = false;
    String? submitError;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> submitRefund() async {
                if (isSubmitting) return;

                final code = _extractTransactionCode(controller.text);
                if (code.isEmpty) return;

                setDialogState(() {
                  isSubmitting = true;
                  submitError = null;
                });

                try {
                  var txnRes = await _apiService.getTransactionByCode(code);

                  // Back-compat: allow numeric transaction id input.
                  if (!txnRes.success) {
                    final idMatch = RegExp(r'^\d+$').firstMatch(code);
                    if (idMatch != null) {
                      txnRes = await _apiService.getTransaction(
                        int.parse(code),
                      );
                    }
                  }

                  if (!mounted) return;

                  if (!txnRes.success || txnRes.data == null) {
                    setDialogState(() {
                      submitError =
                          txnRes.message ?? 'Transaction not found for "$code"';
                      isSubmitting = false;
                    });
                    return;
                  }

                  final idRaw = txnRes.data!['id'];
                  final txnId = (idRaw is int) ? idRaw : int.tryParse('$idRaw');
                  if (txnId == null) {
                    setDialogState(() {
                      submitError = 'Invalid transaction ID for "$code"';
                      isSubmitting = false;
                    });
                    return;
                  }

                  final refundRes = await _apiService.requestRefund(
                    txnId,
                    memberCard: memberCardController.text,
                  );
                  if (!mounted) return;

                  if (refundRes.success) {
                    if (!dialogContext.mounted) return;
                    Navigator.of(dialogContext).pop();
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(
                        content: Text(
                          refundRes.message ??
                              (_canManageApprovals
                                  ? 'Transaction refunded successfully'
                                  : 'Refund request submitted for approval'),
                        ),
                        backgroundColor: AppColors.success,
                      ),
                    );
                    unawaited(_onRefresh());
                    return;
                  }

                  setDialogState(() {
                    submitError = refundRes.message ?? 'Refund failed';
                    isSubmitting = false;
                  });
                } catch (e) {
                  if (!mounted) return;
                  setDialogState(() {
                    submitError = 'Refund failed. $e';
                    isSubmitting = false;
                  });
                }
              }

              return Dialog(
                insetPadding: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SizedBox(
                  width: 520,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('Quick Refund', style: AppTypography.heading4),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Close',
                              onPressed: isSubmitting
                                  ? null
                                  : () => Navigator.of(dialogContext).pop(),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _canManageApprovals
                              ? 'Scan/enter the receipt code then press Refund.'
                              : 'Scan/enter the receipt code then press Request Refund.',
                          style: AppTypography.bodySmall.copyWith(
                            color: context.textSecondaryColor,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: controller,
                                decoration: InputDecoration(
                                  hintText:
                                      'Scan or enter Transaction ID (TXN-...)',
                                  prefixIcon: const Icon(
                                    Icons.receipt_long_rounded,
                                  ),
                                  isDense: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onSubmitted: (_) => submitRefund(),
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              onPressed: isSubmitting
                                  ? null
                                  : () {
                                      setDialogState(() {
                                        hasDetected = false;
                                        isScanning = !isScanning;
                                        submitError = null;
                                      });
                                    },
                              icon: const Icon(Icons.qr_code_scanner_rounded),
                              label: Text(isScanning ? 'Stop' : 'Scan'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: memberCardController,
                          decoration: InputDecoration(
                            hintText:
                                'Member card (optional, for redeemed rewards)',
                            prefixIcon: const Icon(
                              Icons.card_membership_rounded,
                            ),
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        if (isScanning) ...[
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              height: 260,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  MobileScanner(
                                    onDetect: (capture) {
                                      if (hasDetected) return;
                                      final barcodes = capture.barcodes;
                                      if (barcodes.isEmpty) return;
                                      final raw = barcodes.first.rawValue;
                                      if (raw == null || raw.trim().isEmpty) {
                                        return;
                                      }
                                      final code = _extractTransactionCode(raw);
                                      if (code.isEmpty) return;
                                      setDialogState(() {
                                        hasDetected = true;
                                        controller.text = code;
                                        isScanning = false;
                                        submitError = null;
                                      });
                                    },
                                  ),
                                  Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Container(
                                      margin: const EdgeInsets.all(10),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.6,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Text(
                                        'Point the camera at the QR/barcode',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        if (submitError != null) ...[
                          Text(
                            submitError!,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            TextButton(
                              onPressed: isSubmitting
                                  ? null
                                  : () => Navigator.of(dialogContext).pop(),
                              child: const Text('Cancel'),
                            ),
                            const Spacer(),
                            ElevatedButton.icon(
                              onPressed:
                                  (controller.text.trim().isEmpty ||
                                      isSubmitting)
                                  ? null
                                  : submitRefund,
                              icon: isSubmitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.undo_rounded),
                              label: Text(
                                _canManageApprovals
                                    ? 'Refund'
                                    : 'Request Refund',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      controller.dispose();
      memberCardController.dispose();
    }
  }

  final List<double> _grossSalesByMonth = List<double>.filled(12, 0.0);
  List<double> _trendCurrentYear = List<double>.filled(12, 0.0);
  List<double> _trendPreviousYear = List<double>.filled(12, 0.0);
  List<String> _trendLabels = const [
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
  Map<String, double> _salesByCategory = const {};

  DateTime _startOfWeek(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    // DateTime.weekday: Mon=1..Sun=7
    return d.subtract(Duration(days: d.weekday - 1));
  }

  String get _timeframeSubtitle {
    switch (_timeframe) {
      case DashboardTimeframe.day:
        return 'Today';
      case DashboardTimeframe.week:
        return 'This Week';
      case DashboardTimeframe.month:
        return 'This Month';
      case DashboardTimeframe.year:
        return 'This Year';
    }
  }

  String get _timeframePickerLabel {
    switch (_timeframe) {
      case DashboardTimeframe.day:
        return 'Day';
      case DashboardTimeframe.week:
        return 'Week';
      case DashboardTimeframe.month:
        return 'Month';
      case DashboardTimeframe.year:
        return 'Year';
    }
  }

  Future<void> _onTimeframeChanged(DashboardTimeframe value) async {
    if (value == _timeframe) return;

    setState(() {
      _timeframe = value;
    });

    // Reload dashboard data for the selected timeframe.
    await Future.wait([
      _loadDailyReport(),
      _loadRecentTransactions(),
      _loadAnalyticsData(),
    ]);
  }

  Future<void> _showTotalSalesTimeframePopup() async {
    final selected = await showDialog<DashboardTimeframe>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        final isDark = context.isDarkMode;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_month_rounded,
                        color: isDark
                            ? Colors.white70
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Select timeframe',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Colors.white
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(
                          Icons.close,
                          color: isDark
                              ? Colors.white70
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose what period you want to view in the dashboard.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _TimeframePickTile(
                    label: 'Day',
                    subtitle: 'Today',
                    value: DashboardTimeframe.day,
                    groupValue: _timeframe,
                    onSelected: (v) => Navigator.of(context).pop(v),
                  ),
                  _TimeframePickTile(
                    label: 'Week',
                    subtitle: 'This week',
                    value: DashboardTimeframe.week,
                    groupValue: _timeframe,
                    onSelected: (v) => Navigator.of(context).pop(v),
                  ),
                  _TimeframePickTile(
                    label: 'Month',
                    subtitle: 'This month',
                    value: DashboardTimeframe.month,
                    groupValue: _timeframe,
                    onSelected: (v) => Navigator.of(context).pop(v),
                  ),
                  _TimeframePickTile(
                    label: 'Year',
                    subtitle: 'This year',
                    value: DashboardTimeframe.year,
                    groupValue: _timeframe,
                    onSelected: (v) => Navigator.of(context).pop(v),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (selected != null) {
      await _onTimeframeChanged(selected);
    }
  }

  String get _trendCurrentLabel {
    switch (_timeframe) {
      case DashboardTimeframe.day:
        return 'Today';
      case DashboardTimeframe.week:
        return 'This Week';
      case DashboardTimeframe.month:
        return 'This Month';
      case DashboardTimeframe.year:
        return 'This Year';
    }
  }

  String get _trendPreviousLabel {
    switch (_timeframe) {
      case DashboardTimeframe.day:
        return 'Yesterday';
      case DashboardTimeframe.week:
        return 'Last Week';
      case DashboardTimeframe.month:
        return 'Last Month';
      case DashboardTimeframe.year:
        return 'Last Year';
    }
  }

  void _syncGrossSalesChartFromReport(Map<String, dynamic> report) {
    // Supports report payloads from /daily, /monthly, /yearly.
    switch (_timeframe) {
      case DashboardTimeframe.day:
        final raw = report['hourly_breakdown'];
        if (raw is Map) {
          final map = Map<String, dynamic>.from(raw);
          final data = List<double>.filled(24, 0.0);
          final labels = List<String>.generate(24, (i) => i.toString());

          for (var h = 0; h < 24; h++) {
            final v = map['$h'];
            if (v is Map) {
              final sales = (v['sales'] ?? 0);
              data[h] = (sales is num)
                  ? sales.toDouble()
                  : double.tryParse('$sales') ?? 0.0;
            }
          }

          _grossSalesChartData = data;
          _grossSalesChartLabels = labels;
        }
        break;
      case DashboardTimeframe.week:
        final raw = report['daily_breakdown'];
        if (raw is Map) {
          final map = Map<String, dynamic>.from(raw);
          final keys = map.keys.toList()..sort();
          final data = <double>[];
          final labels = <String>[];
          for (final k in keys) {
            final v = map[k];
            if (v is Map) {
              final sales = (v['sales'] ?? 0);
              data.add(
                (sales is num)
                    ? sales.toDouble()
                    : double.tryParse('$sales') ?? 0.0,
              );

              final parsed = DateTime.tryParse(k.toString());
              labels.add(
                parsed == null
                    ? k.toString()
                    : DateFormat('EEE').format(parsed),
              );
            }
          }

          if (data.isNotEmpty && labels.length == data.length) {
            _grossSalesChartData = data;
            _grossSalesChartLabels = labels;
          }
        }
        break;
      case DashboardTimeframe.month:
        final raw = report['daily_breakdown'];
        if (raw is Map) {
          final map = Map<String, dynamic>.from(raw);
          final keys = map.keys.toList()..sort();
          final data = <double>[];
          final labels = <String>[];
          for (final k in keys) {
            final v = map[k];
            if (v is Map) {
              final sales = (v['sales'] ?? 0);
              data.add(
                (sales is num)
                    ? sales.toDouble()
                    : double.tryParse('$sales') ?? 0.0,
              );
              final day = DateTime.tryParse(k)?.day;
              labels.add(day?.toString() ?? k);
            }
          }
          if (data.isNotEmpty && labels.length == data.length) {
            _grossSalesChartData = data;
            _grossSalesChartLabels = labels;
          }
        }
        break;
      case DashboardTimeframe.year:
        final raw = report['monthly_breakdown'];
        if (raw is Map) {
          final map = Map<String, dynamic>.from(raw);
          final data = List<double>.filled(12, 0.0);
          for (var i = 1; i <= 12; i++) {
            final key =
                '${DateTime.now().year}-${i.toString().padLeft(2, '0')}';
            final v = map[key];
            if (v is Map) {
              final sales = (v['sales'] ?? 0);
              data[i - 1] = (sales is num)
                  ? sales.toDouble()
                  : double.tryParse('$sales') ?? 0.0;
            }
          }
          _grossSalesChartData = data;
          _grossSalesChartLabels = _monthLabels;
        } else {
          // Fallback to the already-loaded yearly arrays.
          _grossSalesChartData = _grossSalesByMonth;
          _grossSalesChartLabels = _monthLabels;
        }
        break;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeDashboard();
    });
  }

  String get _normalizedRole {
    // Normalize roles like "super_admin", "Super Admin", "super-admin" => "superadmin"
    return widget.userRole.toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');
  }

  Future<void> _initializeDashboard() async {
    await _initNotificationStorage();
    if (!mounted) return;
    await _loadDashboardData();
  }

  Future<void> _initNotificationStorage() async {
    if (_notificationStorageReady) return;

    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;

    // Restore inbox
    final raw = prefs.getString(_notificationStorageKey);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _notifications
            ..clear()
            ..addAll(
              decoded
                  .whereType<Map>()
                  .map((m) => Map<String, dynamic>.from(m))
                  .map(_notificationFromJson)
                  .toList(),
            );
        }
      } catch (_) {
        // If storage is corrupted, ignore and start fresh.
      }
    }

    // Restore meta (active state/suppressions)
    final metaRaw = prefs.getString(_notificationMetaStorageKey);
    if (metaRaw != null && metaRaw.trim().isNotEmpty) {
      try {
        final meta = jsonDecode(metaRaw);
        if (meta is Map) {
          final map = Map<String, dynamic>.from(meta);

          final suppressed = map['suppressed'];
          if (suppressed is List) {
            _suppressedSourceKeys
              ..clear()
              ..addAll(suppressed.map((e) => e.toString()));
          }

          final activeLowStock = map['active_low_stock_ids'];
          if (activeLowStock is List) {
            _activeLowStockProductIds
              ..clear()
              ..addAll(activeLowStock.map((e) => e.toString()));
          }

          final activePending = map['active_pending_account_ids'];
          if (activePending is List) {
            _activePendingAccountIds
              ..clear()
              ..addAll(activePending.map((e) => e.toString()));
          }

          final activeRefunds = map['active_pending_refund_ids'];
          if (activeRefunds is List) {
            _activePendingRefundRequestIds
              ..clear()
              ..addAll(activeRefunds.map((e) => e.toString()));
          }

          final seenRefundDecisions = map['seen_refund_decision_ids'];
          if (seenRefundDecisions is List) {
            _seenRefundDecisionRequestIds
              ..clear()
              ..addAll(seenRefundDecisions.map((e) => e.toString()));
          }

          _activeSalesError = map['active_sales_error']?.toString();
          _activeLowStockError = map['active_low_stock_error']?.toString();
          _activeTransactionsError = map['active_transactions_error']
              ?.toString();
        }
      } catch (_) {
        // Ignore corrupted meta.
      }
    }

    if (!mounted) return;
    setState(() {
      _notificationStorageReady = true;
    });
  }

  Map<String, dynamic> _notificationToJson(_DashboardNotificationItem n) {
    return {
      'id': n.id,
      'sourceKey': n.sourceKey,
      'createdAt': n.createdAt.toIso8601String(),
      'type': n.type.name,
      'title': n.title,
      'message': n.message,
      'status': n.status.name,
    };
  }

  _DashboardNotificationItem _notificationFromJson(Map<String, dynamic> m) {
    DashboardNotificationType parseType(String raw) {
      return DashboardNotificationType.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => DashboardNotificationType.info,
      );
    }

    _NotificationStatus parseStatus(String raw) {
      return _NotificationStatus.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => _NotificationStatus.read,
      );
    }

    final sourceKey = (m['sourceKey'] ?? '').toString();
    return _DashboardNotificationItem(
      id: (m['id'] ?? DateTime.now().microsecondsSinceEpoch.toString())
          .toString(),
      sourceKey: sourceKey,
      createdAt:
          DateTime.tryParse((m['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      type: parseType((m['type'] ?? 'info').toString()),
      title: (m['title'] ?? '').toString(),
      message: (m['message'] ?? '').toString(),
      status: parseStatus((m['status'] ?? 'read').toString()),
      onTap: _onTapForSourceKey(sourceKey),
    );
  }

  VoidCallback? _onTapForSourceKey(String sourceKey) {
    if (sourceKey.startsWith('low_stock:')) {
      return () => _navigateToProducts(context);
    }
    if (sourceKey == 'sales_error' || sourceKey.startsWith('sales_error:')) {
      return _loadDailyReport;
    }
    if (sourceKey == 'low_stock_error' ||
        sourceKey.startsWith('low_stock_error:')) {
      return _loadLowStockProducts;
    }
    if (sourceKey == 'transactions_error' ||
        sourceKey.startsWith('transactions_error:')) {
      return _loadRecentTransactions;
    }
    if (sourceKey.startsWith('pending_account:') ||
        sourceKey == 'pending_accounts_error') {
      return () => _navigateToSettings(context);
    }
    if (sourceKey.startsWith('pending_refund:') ||
        sourceKey == 'pending_refunds_error') {
      return _showPendingRefundsDialog;
    }
    return null;
  }

  Future<void> _persistNotificationStorage() async {
    final prefs = _prefs;
    if (prefs == null) return;

    final inboxJson = jsonEncode(
      _notifications.map(_notificationToJson).toList(),
    );
    final metaJson = jsonEncode({
      'suppressed': _suppressedSourceKeys.toList(),
      'active_low_stock_ids': _activeLowStockProductIds.toList(),
      'active_pending_account_ids': _activePendingAccountIds.toList(),
      'active_pending_refund_ids': _activePendingRefundRequestIds.toList(),
      'seen_refund_decision_ids': _seenRefundDecisionRequestIds.toList(),
      'active_sales_error': _activeSalesError,
      'active_low_stock_error': _activeLowStockError,
      'active_transactions_error': _activeTransactionsError,
    });

    // Fire-and-forget; storage isn't critical-path.
    unawaited(prefs.setString(_notificationStorageKey, inboxJson));
    unawaited(prefs.setString(_notificationMetaStorageKey, metaJson));
  }

  bool get _isSupervisor => _normalizedRole == 'supervisor';

  bool get _canManageApprovals {
    final role = _normalizedRole;
    return role == 'supervisor' || role == 'superadmin' || role == 'admin';
  }

  bool get _canViewAnalytics {
    final role = _normalizedRole;
    return role == 'supervisor' || role == 'superadmin' || role == 'admin';
  }

  bool get _isCashier => !_canViewAnalytics;

  String get _refundSubtitle {
    switch (_timeframe) {
      case DashboardTimeframe.day:
        return 'Approved today';
      case DashboardTimeframe.week:
        return 'Approved this week';
      case DashboardTimeframe.month:
        return 'Approved this month';
      case DashboardTimeframe.year:
        return 'Approved this year';
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isCurrent = ModalRoute.of(context)?.isCurrent == true;

    // Reload data when page becomes visible (switches to this tab)
    if (isCurrent && !_wasCurrentBefore) {
      if (_notificationStorageReady) {
        _loadDashboardData();
      } else {
        _initializeDashboard();
      }
    }

    _wasCurrentBefore = isCurrent;
  }

  Future<void> _loadDashboardData() async {
    if (_canViewAnalytics) {
      await Future.wait([
        _loadDailyReport(),
        _loadLowStockProducts(),
        _loadRecentTransactions(),
      ]);

      await _loadAnalyticsData();

      if (_canManageApprovals) {
        await _loadPendingApprovalsForNotifications();
        await _loadPendingRefundsForNotifications();
      }
    } else {
      await _loadRecentTransactions();
      await _loadRefundDecisionsForNotifications();
    }
  }

  List<double> _hourlySalesFromDailyReport(Map<String, dynamic> report) {
    final raw = report['hourly_breakdown'];
    final data = List<double>.filled(24, 0.0);
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      for (var h = 0; h < 24; h++) {
        final v = map['$h'];
        if (v is Map) {
          final sales = (v['sales'] ?? 0);
          data[h] = (sales is num)
              ? sales.toDouble()
              : double.tryParse('$sales') ?? 0.0;
        }
      }
    }
    return data;
  }

  List<double> _dailySalesFromMonthlyReport(
    Map<String, dynamic> report, {
    required int year,
    required int month,
    required int targetDays,
  }) {
    final raw = report['daily_breakdown'];
    final data = List<double>.filled(targetDays, 0.0);
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      for (final entry in map.entries) {
        final k = entry.key;
        final v = entry.value;
        if (v is! Map) continue;
        final parsed = DateTime.tryParse(k.toString());
        if (parsed == null) continue;
        if (parsed.year != year || parsed.month != month) continue;
        final dayIndex = parsed.day - 1;
        if (dayIndex < 0 || dayIndex >= targetDays) continue;
        final sales = (v['sales'] ?? 0);
        data[dayIndex] = (sales is num)
            ? sales.toDouble()
            : double.tryParse('$sales') ?? 0.0;
      }
    }
    return data;
  }

  List<double> _dailySalesFromWeeklyReport(
    Map<String, dynamic> report, {
    required DateTime weekStart,
  }) {
    final raw = report['daily_breakdown'];
    final data = List<double>.filled(7, 0.0);
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);

      for (var i = 0; i < 7; i++) {
        final d = weekStart.add(Duration(days: i));
        final key = _ymd(d);
        dynamic v = map[key];
        if (v == null) {
          // Fallback: try parse keys if server used a different shape.
          for (final entry in map.entries) {
            final parsed = DateTime.tryParse(entry.key.toString());
            if (parsed == null) continue;
            if (parsed.year == d.year &&
                parsed.month == d.month &&
                parsed.day == d.day) {
              v = entry.value;
              break;
            }
          }
        }
        if (v is Map) {
          final sales = (v['sales'] ?? 0);
          data[i] = (sales is num)
              ? sales.toDouble()
              : double.tryParse('$sales') ?? 0.0;
        }
      }
    }
    return data;
  }

  List<double> _monthlySalesFromYearlyReport(
    Map<String, dynamic> report, {
    required int year,
  }) {
    final breakdown =
        (report['monthly_breakdown'] ?? const {}) as Map<String, dynamic>;
    final monthly = List<double>.filled(12, 0.0);
    for (var m = 1; m <= 12; m++) {
      final key = '${year.toString()}-${m.toString().padLeft(2, '0')}';
      final cur = breakdown[key];
      if (cur is Map) {
        final sales = (cur['sales'] ?? 0);
        monthly[m - 1] = (sales is num)
            ? sales.toDouble()
            : double.tryParse('$sales') ?? 0.0;
      }
    }
    return monthly;
  }

  Future<void> _loadPendingApprovalsForNotifications() async {
    try {
      final res = await _apiService.get<List<dynamic>>(
        '/auth/pending-accounts',
        fromJsonT: (data) => data as List<dynamic>,
      );
      if (!mounted) return;

      if (!res.success) {
        final err = res.message ?? 'Failed to load pending approvals';
        final sourceKey = 'pending_accounts_error';
        if (!_suppressedSourceKeys.contains(sourceKey)) {
          _enqueueNotification(
            _DashboardNotificationItem(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              sourceKey: sourceKey,
              createdAt: DateTime.now(),
              type: DashboardNotificationType.error,
              title: 'Approvals check failed',
              message: err,
              status: _NotificationStatus.unread,
              onTap: () => _navigateToSettings(context),
            ),
          );
          _persistNotificationStorage();
        }
        return;
      }

      final list = res.data ?? const [];
      final currentIds = <String>{};
      for (final item in list) {
        if (item is Map) {
          final id = (item['id'] ?? item['user_id'] ?? item['userId']);
          if (id != null) currentIds.add(id.toString());
        }
      }

      final previousIds = Set<String>.from(_activePendingAccountIds);

      // New pending accounts => new notifications
      for (final id in currentIds) {
        if (previousIds.contains(id)) continue;
        final sourceKey = 'pending_account:$id';
        if (_suppressedSourceKeys.contains(sourceKey)) continue;

        _enqueueNotification(
          _DashboardNotificationItem(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            sourceKey: sourceKey,
            createdAt: DateTime.now(),
            type: DashboardNotificationType.info,
            title: 'Account needs approval',
            message: 'A cashier account is waiting for approval.',
            status: _NotificationStatus.unread,
            onTap: () => _navigateToSettings(context),
          ),
        );
      }

      // If an account is no longer pending, allow future re-notification.
      for (final oldId in previousIds) {
        if (!currentIds.contains(oldId)) {
          _suppressedSourceKeys.remove('pending_account:$oldId');
        }
      }

      _activePendingAccountIds
        ..clear()
        ..addAll(currentIds);

      _persistNotificationStorage();
    } catch (_) {
      // Best-effort.
      return;
    }
  }

  Future<void> _loadPendingRefundsForNotifications() async {
    try {
      final res = await _apiService.getPendingRefundRequests();
      if (!mounted) return;

      if (!res.success) {
        final err = res.message ?? 'Failed to load pending refunds';
        final sourceKey = 'pending_refunds_error';
        if (!_suppressedSourceKeys.contains(sourceKey)) {
          _enqueueNotification(
            _DashboardNotificationItem(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              sourceKey: sourceKey,
              createdAt: DateTime.now(),
              type: DashboardNotificationType.error,
              title: 'Refund approvals check failed',
              message: err,
              status: _NotificationStatus.unread,
              onTap: _showPendingRefundsDialog,
            ),
          );
          _persistNotificationStorage();
        }
        return;
      }

      final list = res.data ?? const [];
      final currentIds = <String>{};
      for (final item in list) {
        final id = item['id'];
        if (id != null) currentIds.add(id.toString());
      }

      final previousIds = Set<String>.from(_activePendingRefundRequestIds);

      for (final id in currentIds) {
        if (previousIds.contains(id)) continue;
        final sourceKey = 'pending_refund:$id';
        if (_suppressedSourceKeys.contains(sourceKey)) continue;

        _enqueueNotification(
          _DashboardNotificationItem(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            sourceKey: sourceKey,
            createdAt: DateTime.now(),
            type: DashboardNotificationType.info,
            title: 'Refund needs approval',
            message: 'A refund request is waiting for approval.',
            status: _NotificationStatus.unread,
            onTap: _showPendingRefundsDialog,
          ),
        );
      }

      for (final oldId in previousIds) {
        if (!currentIds.contains(oldId)) {
          _suppressedSourceKeys.remove('pending_refund:$oldId');
        }
      }

      _activePendingRefundRequestIds
        ..clear()
        ..addAll(currentIds);

      _persistNotificationStorage();
    } catch (_) {
      return;
    }
  }

  Future<void> _loadRefundDecisionsForNotifications() async {
    try {
      final res = await _apiService.getMyRefundRequests(
        limit: 50,
        status: 'approved,rejected',
      );
      if (!mounted) return;
      if (!res.success) return;

      final list = res.data ?? const [];
      var changed = false;

      for (final rr in list) {
        final id = rr['id'];
        if (id == null) continue;
        final idStr = id.toString();
        if (_seenRefundDecisionRequestIds.contains(idStr)) continue;

        final status = (rr['status'] ?? '').toString().toLowerCase();
        final txn = rr['transaction'];
        String txnCode = '';
        if (txn is Map) {
          txnCode = (txn['transaction_id'] ?? txn['id'] ?? '').toString();
        }
        if (txnCode.isEmpty) {
          txnCode = (rr['transaction_id'] ?? '').toString();
        }

        final isApproved = status == 'approved';
        _enqueueNotification(
          _DashboardNotificationItem(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            sourceKey: 'refund_decision:$idStr',
            createdAt: DateTime.now(),
            type: isApproved
                ? DashboardNotificationType.success
                : DashboardNotificationType.warning,
            title: isApproved ? 'Refund approved' : 'Refund rejected',
            message: txnCode.isNotEmpty
                ? 'Request for $txnCode was ${isApproved ? 'approved' : 'rejected'}.'
                : 'Your refund request was ${isApproved ? 'approved' : 'rejected'}.',
            status: _NotificationStatus.unread,
          ),
        );

        _seenRefundDecisionRequestIds.add(idStr);
        changed = true;
      }

      if (changed) {
        _persistNotificationStorage();
      }
    } catch (_) {
      return;
    }
  }

  Future<void> _showPendingRefundsDialog() async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return _PendingRefundsDialog(apiService: _apiService);
      },
    );

    if (_canManageApprovals) {
      await _loadPendingRefundsForNotifications();
    }
  }

  String? _pendingAccountIdFromSourceKey(String sourceKey) {
    if (!sourceKey.startsWith('pending_account:')) return null;
    final id = sourceKey.substring('pending_account:'.length).trim();
    return id.isEmpty ? null : id;
  }

  Future<bool> _approvePendingAccountFromNotification({
    required String accountId,
  }) async {
    final userId = int.tryParse(accountId);
    if (userId == null) {
      _showDashboardNotification(
        'Invalid account id',
        type: DashboardNotificationType.error,
      );
      return false;
    }

    try {
      final res = await _apiService.post<Map<String, dynamic>>(
        '/auth/approve-account/$userId',
      );

      if (!mounted) return false;

      if (res.success) {
        _showDashboardNotification(
          'Account approved',
          type: DashboardNotificationType.success,
        );
        // Refresh pending list so we don't re-notify.
        await _loadPendingApprovalsForNotifications();
        return true;
      }

      _showDashboardNotification(
        res.message ?? 'Failed to approve account',
        type: DashboardNotificationType.error,
      );
      return false;
    } catch (e) {
      if (!mounted) return false;
      _showDashboardNotification(
        'Error approving account: $e',
        type: DashboardNotificationType.error,
      );
      return false;
    }
  }

  Future<void> _loadAnalyticsData() async {
    if (!_canViewAnalytics) return;

    try {
      final now = DateTime.now();

      List<double> currentTrend = _trendCurrentYear;
      List<double> previousTrend = _trendPreviousYear;
      List<String> trendLabels = _trendLabels;
      Map<String, double> categoryMap = {};

      if (_timeframe == DashboardTimeframe.day) {
        final today = DateTime(now.year, now.month, now.day);
        final yesterday = today.subtract(const Duration(days: 1));

        final results = await Future.wait<ApiResponse<Map<String, dynamic>>>([
          _apiService.getDailyReport(_ymd(today)),
          _apiService.getDailyReport(_ymd(yesterday)),
          _apiService.getCategoryBreakdown(timeframe: 'day', date: _ymd(today)),
        ]);

        final todayRes = results[0];
        final yesterdayRes = results[1];
        final categoryRes = results[2];

        if (!mounted) return;

        if (todayRes.success && todayRes.data != null) {
          currentTrend = _hourlySalesFromDailyReport(todayRes.data!);
        } else {
          currentTrend = List<double>.filled(24, 0.0);
        }
        if (yesterdayRes.success && yesterdayRes.data != null) {
          previousTrend = _hourlySalesFromDailyReport(yesterdayRes.data!);
        } else {
          previousTrend = List<double>.filled(24, 0.0);
        }

        trendLabels = List<String>.generate(
          24,
          (i) => i.toString().padLeft(2, '0'),
        );

        if (categoryRes.success && categoryRes.data != null) {
          final cats = categoryRes.data!['categories'];
          if (cats is List) {
            for (final item in cats) {
              if (item is Map) {
                final name = (item['category'] ?? 'Other').toString();
                final val = (item['total_sales'] ?? 0);
                categoryMap[name] = (val is num)
                    ? val.toDouble()
                    : double.tryParse('$val') ?? 0.0;
              }
            }
          }
        }
      } else if (_timeframe == DashboardTimeframe.week) {
        final today = DateTime(now.year, now.month, now.day);
        final lastWeekDay = today.subtract(const Duration(days: 7));
        final weekStart = _startOfWeek(today);

        final results = await Future.wait<ApiResponse<Map<String, dynamic>>>([
          _apiService.getWeeklyReport(_ymd(today)),
          _apiService.getWeeklyReport(_ymd(lastWeekDay)),
          _apiService.getCategoryBreakdown(
            timeframe: 'week',
            date: _ymd(today),
          ),
        ]);

        final currentRes = results[0];
        final previousRes = results[1];
        final categoryRes = results[2];

        if (!mounted) return;

        if (currentRes.success && currentRes.data != null) {
          currentTrend = _dailySalesFromWeeklyReport(
            currentRes.data!,
            weekStart: weekStart,
          );
        } else {
          currentTrend = List<double>.filled(7, 0.0);
        }

        if (previousRes.success && previousRes.data != null) {
          previousTrend = _dailySalesFromWeeklyReport(
            previousRes.data!,
            weekStart: weekStart.subtract(const Duration(days: 7)),
          );
        } else {
          previousTrend = List<double>.filled(7, 0.0);
        }

        trendLabels = List<String>.generate(
          7,
          (i) => DateFormat('EEE').format(weekStart.add(Duration(days: i))),
        );

        if (categoryRes.success && categoryRes.data != null) {
          final cats = categoryRes.data!['categories'];
          if (cats is List) {
            for (final item in cats) {
              if (item is Map) {
                final name = (item['category'] ?? 'Other').toString();
                final val = (item['total_sales'] ?? 0);
                categoryMap[name] = (val is num)
                    ? val.toDouble()
                    : double.tryParse('$val') ?? 0.0;
              }
            }
          }
        }
      } else if (_timeframe == DashboardTimeframe.month) {
        final year = now.year;
        final month = now.month;
        final firstOfNextMonth = DateTime(year, month + 1, 1);
        final daysInMonth = firstOfNextMonth
            .subtract(const Duration(days: 1))
            .day;

        final prevMonthDate = DateTime(year, month - 1, 1);
        final prevYear = prevMonthDate.year;
        final prevMonth = prevMonthDate.month;

        final results = await Future.wait<ApiResponse<Map<String, dynamic>>>([
          _apiService.getMonthlyReport(year: year, month: month),
          _apiService.getMonthlyReport(year: prevYear, month: prevMonth),
          _apiService.getCategoryBreakdown(
            timeframe: 'month',
            year: year,
            month: month,
          ),
        ]);

        final currentRes = results[0];
        final previousRes = results[1];
        final categoryRes = results[2];

        if (!mounted) return;

        if (currentRes.success && currentRes.data != null) {
          currentTrend = _dailySalesFromMonthlyReport(
            currentRes.data!,
            year: year,
            month: month,
            targetDays: daysInMonth,
          );
        } else {
          currentTrend = List<double>.filled(daysInMonth, 0.0);
        }

        if (previousRes.success && previousRes.data != null) {
          previousTrend = _dailySalesFromMonthlyReport(
            previousRes.data!,
            year: prevYear,
            month: prevMonth,
            targetDays: daysInMonth,
          );
        } else {
          previousTrend = List<double>.filled(daysInMonth, 0.0);
        }

        trendLabels = List<String>.generate(daysInMonth, (i) => '${i + 1}');

        if (categoryRes.success && categoryRes.data != null) {
          final cats = categoryRes.data!['categories'];
          if (cats is List) {
            for (final item in cats) {
              if (item is Map) {
                final name = (item['category'] ?? 'Other').toString();
                final val = (item['total_sales'] ?? 0);
                categoryMap[name] = (val is num)
                    ? val.toDouble()
                    : double.tryParse('$val') ?? 0.0;
              }
            }
          }
        }
      } else {
        final year = now.year;
        final prevYear = year - 1;

        final results = await Future.wait<ApiResponse<Map<String, dynamic>>>([
          _apiService.getYearlyReport(year: year),
          _apiService.getYearlyReport(year: prevYear),
          _apiService.getCategoryBreakdown(timeframe: 'year', year: year),
        ]);

        final currentYearRes = results[0];
        final previousYearRes = results[1];
        final categoryRes = results[2];

        if (!mounted) return;

        if (currentYearRes.success && currentYearRes.data != null) {
          currentTrend = _monthlySalesFromYearlyReport(
            currentYearRes.data!,
            year: year,
          );
        } else {
          currentTrend = List<double>.filled(12, 0.0);
        }

        if (previousYearRes.success && previousYearRes.data != null) {
          previousTrend = _monthlySalesFromYearlyReport(
            previousYearRes.data!,
            year: prevYear,
          );
        } else {
          previousTrend = List<double>.filled(12, 0.0);
        }

        trendLabels = _monthLabels;

        if (categoryRes.success && categoryRes.data != null) {
          final cats = categoryRes.data!['categories'];
          if (cats is List) {
            for (final item in cats) {
              if (item is Map) {
                final name = (item['category'] ?? 'Other').toString();
                final val = (item['total_sales'] ?? 0);
                categoryMap[name] = (val is num)
                    ? val.toDouble()
                    : double.tryParse('$val') ?? 0.0;
              }
            }
          }
        }
      }

      if (categoryMap.isEmpty) {
        categoryMap = {'Other': 0.0};
      }

      setState(() {
        _trendCurrentYear = currentTrend;
        _trendPreviousYear = previousTrend;
        _trendLabels = trendLabels;
        _salesByCategory = categoryMap;
      });
    } catch (_) {
      return;
    }
  }

  int get _desktopNotificationCount {
    return _notifications
        .where((n) => n.status == _NotificationStatus.unread)
        .length;
  }

  void _enqueueNotification(_DashboardNotificationItem item) {
    if (_suppressedSourceKeys.contains(item.sourceKey)) return;
    final alreadyExists = _notifications.any(
      (n) =>
          n.sourceKey == item.sourceKey &&
          n.title == item.title &&
          n.message == item.message,
    );
    if (alreadyExists) return;

    _notifications.insert(0, item);
    // Keep memory bounded.
    if (_notifications.length > 200) {
      _notifications.removeRange(200, _notifications.length);
    }
  }

  void _setNotificationStatus(String id, _NotificationStatus status) {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index < 0) return;
    setState(() {
      _notifications[index] = _notifications[index].copyWith(status: status);
    });
    _persistNotificationStorage();
  }

  void _deleteNotification(String id) {
    setState(() {
      final index = _notifications.indexWhere((n) => n.id == id);
      if (index >= 0) {
        final key = _notifications[index].sourceKey;
        if (key.startsWith('low_stock:') ||
            key.startsWith('pending_account:')) {
          _suppressedSourceKeys.add(key);
        }
        _notifications.removeAt(index);
      }
    });
    _persistNotificationStorage();
  }

  List<_DashboardNotificationItem> _getFilteredNotifications(
    _NotificationsFilter filter,
  ) {
    switch (filter) {
      case _NotificationsFilter.unread:
        return _notifications
            .where((n) => n.status == _NotificationStatus.unread)
            .toList();
      case _NotificationsFilter.archived:
        return _notifications
            .where((n) => n.status == _NotificationStatus.archived)
            .toList();
      case _NotificationsFilter.all:
        return _notifications.toList();
    }
  }

  Future<void> _showNotificationsPopup() async {
    if (!mounted) return;

    var filter = _NotificationsFilter.unread;
    final approvingSourceKeys = <String>{};

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final items = _getFilteredNotifications(filter);

            Future<void> confirmDelete(String id) async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Delete notification?'),
                  content: const Text(
                    'This will permanently remove the notification.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                _deleteNotification(id);
                setModalState(() {});
              }
            }

            Widget buildFilterChip(
              String label,
              _NotificationsFilter value,
              String? badge,
            ) {
              final selected = filter == value;
              return ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label),
                    if (badge != null) ...[
                      const SizedBox(width: 6),
                      Badge(
                        label: Text(badge),
                        backgroundColor: selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                        textColor: selected
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),
                selected: selected,
                onSelected: (_) => setModalState(() => filter = value),
              );
            }

            final unreadCount = _notifications
                .where((n) => n.status == _NotificationStatus.unread)
                .length;
            final archivedCount = _notifications
                .where((n) => n.status == _NotificationStatus.archived)
                .length;

            final media = MediaQuery.of(context);
            final availableWidth = media.size.width - 32;
            final availableHeight =
                media.size.height - media.padding.vertical - 32;
            final dialogWidth = availableWidth > 560 ? 560.0 : availableWidth;
            final dialogHeight = availableHeight > 620
                ? 620.0
                : availableHeight;

            return Dialog(
              insetPadding: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: SizedBox(
                width: dialogWidth,
                height: dialogHeight,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Notifications', style: AppTypography.heading4),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          buildFilterChip(
                            'All',
                            _NotificationsFilter.all,
                            _notifications.isEmpty
                                ? null
                                : '${_notifications.length}',
                          ),
                          buildFilterChip(
                            'Unread',
                            _NotificationsFilter.unread,
                            unreadCount == 0 ? null : '$unreadCount',
                          ),
                          buildFilterChip(
                            'Archived',
                            _NotificationsFilter.archived,
                            archivedCount == 0 ? null : '$archivedCount',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: items.isEmpty
                            ? Center(
                                child: Text(
                                  filter == _NotificationsFilter.archived
                                      ? 'No archived notifications.'
                                      : filter == _NotificationsFilter.unread
                                      ? 'You\'re all caught up.'
                                      : 'No notifications yet.',
                                  style: AppTypography.bodyMedium.copyWith(
                                    color: context.textSecondaryColor,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: items.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final n = items[index];
                                  final (bg, _, icon) = _notificationStyle(
                                    type: n.type,
                                  );
                                  final timeText = DateFormat(
                                    'MMM d • hh:mm a',
                                  ).format(n.createdAt);

                                  final isUnread =
                                      n.status == _NotificationStatus.unread;
                                  final isArchived =
                                      n.status == _NotificationStatus.archived;

                                  final pendingAccountId =
                                      _pendingAccountIdFromSourceKey(
                                        n.sourceKey,
                                      );
                                  final canApprove =
                                      pendingAccountId != null &&
                                      _canManageApprovals;
                                  final isApproving = approvingSourceKeys
                                      .contains(n.sourceKey);

                                  return Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: context.cardColor,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isUnread
                                            ? AppColors.primary.withValues(
                                                alpha: 0.35,
                                              )
                                            : bg.withValues(alpha: 0.20),
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              width: 36,
                                              height: 36,
                                              decoration: BoxDecoration(
                                                color: bg.withValues(
                                                  alpha: 0.12,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Icon(
                                                icon,
                                                color: bg,
                                                size: 18,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          n.title,
                                                          style: AppTypography
                                                              .labelLarge
                                                              .copyWith(
                                                                color: context
                                                                    .textPrimaryColor,
                                                                fontWeight:
                                                                    isUnread
                                                                    ? FontWeight
                                                                          .w700
                                                                    : FontWeight
                                                                          .w600,
                                                              ),
                                                        ),
                                                      ),
                                                      if (isUnread)
                                                        Container(
                                                          width: 8,
                                                          height: 8,
                                                          decoration:
                                                              const BoxDecoration(
                                                                color: AppColors
                                                                    .primary,
                                                                shape: BoxShape
                                                                    .circle,
                                                              ),
                                                        ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    n.message,
                                                    style: AppTypography
                                                        .bodySmall
                                                        .copyWith(
                                                          color: context
                                                              .textSecondaryColor,
                                                        ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    timeText,
                                                    style: AppTypography.caption
                                                        .copyWith(
                                                          color: context
                                                              .textLightColor,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 6,
                                              children: [
                                                TextButton.icon(
                                                  onPressed: isArchived
                                                      ? null
                                                      : () {
                                                          _setNotificationStatus(
                                                            n.id,
                                                            isUnread
                                                                ? _NotificationStatus
                                                                      .read
                                                                : _NotificationStatus
                                                                      .unread,
                                                          );
                                                          setModalState(() {});
                                                        },
                                                  icon: Icon(
                                                    isUnread
                                                        ? Icons.done_rounded
                                                        : Icons
                                                              .mark_chat_unread_rounded,
                                                    size: 18,
                                                  ),
                                                  label: Text(
                                                    isUnread
                                                        ? 'Mark read'
                                                        : 'Mark unread',
                                                  ),
                                                ),
                                                TextButton.icon(
                                                  onPressed: () {
                                                    _setNotificationStatus(
                                                      n.id,
                                                      isArchived
                                                          ? _NotificationStatus
                                                                .read
                                                          : _NotificationStatus
                                                                .archived,
                                                    );
                                                    setModalState(() {});
                                                  },
                                                  icon: Icon(
                                                    isArchived
                                                        ? Icons
                                                              .unarchive_rounded
                                                        : Icons
                                                              .archive_outlined,
                                                    size: 18,
                                                  ),
                                                  label: Text(
                                                    isArchived
                                                        ? 'Unarchive'
                                                        : 'Archive',
                                                  ),
                                                ),
                                                if (canApprove)
                                                  ElevatedButton.icon(
                                                    onPressed:
                                                        (isArchived ||
                                                            isApproving)
                                                        ? null
                                                        : () async {
                                                            setModalState(() {
                                                              approvingSourceKeys
                                                                  .add(
                                                                    n.sourceKey,
                                                                  );
                                                            });

                                                            final ok =
                                                                await _approvePendingAccountFromNotification(
                                                                  accountId:
                                                                      pendingAccountId,
                                                                );

                                                            if (mounted) {
                                                              setModalState(() {
                                                                approvingSourceKeys
                                                                    .remove(
                                                                      n.sourceKey,
                                                                    );
                                                              });
                                                            }

                                                            if (ok) {
                                                              _setNotificationStatus(
                                                                n.id,
                                                                _NotificationStatus
                                                                    .archived,
                                                              );
                                                              setModalState(
                                                                () {},
                                                              );
                                                            }
                                                          },
                                                    icon: isApproving
                                                        ? const SizedBox(
                                                            width: 16,
                                                            height: 16,
                                                            child:
                                                                CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      2,
                                                                ),
                                                          )
                                                        : const Icon(
                                                            Icons
                                                                .check_circle_outline_rounded,
                                                            size: 18,
                                                          ),
                                                    label: Text(
                                                      isApproving
                                                          ? 'Approving'
                                                          : 'Approve',
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.end,
                                              children: [
                                                IconButton(
                                                  tooltip: 'Delete',
                                                  onPressed: () =>
                                                      confirmDelete(n.id),
                                                  icon: const Icon(
                                                    Icons
                                                        .delete_outline_rounded,
                                                  ),
                                                ),
                                                if (n.onTap != null)
                                                  IconButton(
                                                    tooltip: 'Open',
                                                    onPressed: () {
                                                      Navigator.of(
                                                        context,
                                                      ).pop();
                                                      n.onTap?.call();
                                                    },
                                                    icon: const Icon(
                                                      Icons.open_in_new_rounded,
                                                    ),
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
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDesktopNotificationButton() {
    final count = _desktopNotificationCount;
    final bg = context.isDarkMode
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.grey.shade100;

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(
            child: IconButton(
              onPressed: () {
                _showNotificationsPopup();
              },
              icon: Icon(
                Icons.notifications_none_rounded,
                color: context.textPrimaryColor,
              ),
              tooltip: 'Notifications',
            ),
          ),
          if (count > 0)
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                constraints: const BoxConstraints(minWidth: 16),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showDashboardNotification(
    String message, {
    DashboardNotificationType type = DashboardNotificationType.info,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (!mounted) return;

    final (bg, fg, icon) = _notificationStyle(type: type);

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        duration: duration,
        backgroundColor: bg,
        content: Row(
          children: [
            Icon(icon, color: fg, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: AppTypography.bodySmall.copyWith(color: fg),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        action: (actionLabel != null && onAction != null)
            ? SnackBarAction(
                label: actionLabel,
                textColor: fg,
                onPressed: onAction,
              )
            : null,
      ),
    );
  }

  (Color bg, Color fg, IconData icon) _notificationStyle({
    required DashboardNotificationType type,
  }) {
    final isDark = context.isDarkMode;

    switch (type) {
      case DashboardNotificationType.success:
        return (
          isDark ? const Color(0xFF133A2A) : AppColors.success,
          Colors.white,
          Icons.check_circle_rounded,
        );
      case DashboardNotificationType.warning:
        return (
          isDark ? const Color(0xFF3A2C13) : AppColors.warning,
          Colors.white,
          Icons.warning_amber_rounded,
        );
      case DashboardNotificationType.error:
        return (
          isDark ? const Color(0xFF3A1717) : AppColors.error,
          Colors.white,
          Icons.error_rounded,
        );
      case DashboardNotificationType.info:
        return (
          isDark ? const Color(0xFF1E2A3A) : AppColors.primary,
          Colors.white,
          Icons.info_rounded,
        );
    }
  }

  Future<void> _onRefresh() async {
    setState(() => _isRefreshing = true);
    await _loadDashboardData();
    if (!mounted) return;
    setState(() => _isRefreshing = false);

    final errors = <String?>[
      if (_isSupervisor) _salesError,
      if (_isSupervisor) _lowStockError,
      _transactionsError,
    ].whereType<String>().toList();

    if (errors.isNotEmpty) {
      _showDashboardNotification(
        errors.first,
        type: DashboardNotificationType.warning,
        actionLabel: 'Retry',
        onAction: () {
          _onRefresh();
        },
      );
    } else {
      _showDashboardNotification(
        'Dashboard refreshed',
        type: DashboardNotificationType.success,
      );
    }
  }

  void _navigateToNewSale(BuildContext context) {
    // Navigate to New Sale tab (index 1)
    // Navigate to New Sale tab.
    final responsiveNavState = context
        .findAncestorStateOfType<ResponsiveNavigationShellState>();
    if (responsiveNavState != null) {
      responsiveNavState.setCurrentIndex(1);
      return;
    }

    final mainNavState = context
        .findAncestorStateOfType<MainNavigationScreenState>();
    if (mainNavState != null) {
      mainNavState.setCurrentIndex(1);
      return;
    }

    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const SalesScreen()));
  }

  void _navigateToProducts(BuildContext context) {
    // Navigate to Products tab (index 2)
    // Navigate to Products tab.
    final responsiveNavState = context
        .findAncestorStateOfType<ResponsiveNavigationShellState>();
    if (responsiveNavState != null) {
      responsiveNavState.setCurrentIndex(2);
      return;
    }

    final mainNavState = context
        .findAncestorStateOfType<MainNavigationScreenState>();
    if (mainNavState != null) {
      mainNavState.setCurrentIndex(2);
      return;
    }

    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const ProductsScreen()));
  }

  void _navigateToReports(BuildContext context) {
    // Navigate to Reports tab (index 4)
    // Navigate to Reports/Analytics tab.
    final responsiveNavState = context
        .findAncestorStateOfType<ResponsiveNavigationShellState>();
    if (responsiveNavState != null) {
      responsiveNavState.setCurrentIndex(5);
      return;
    }

    final mainNavState = context
        .findAncestorStateOfType<MainNavigationScreenState>();
    if (mainNavState != null) {
      mainNavState.setCurrentIndex(4);
      return;
    }

    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const ReportsScreen()));
  }

  // _navigateToTransactions removed (unused)

  void _navigateToSettings(BuildContext context) {
    // Navigate to Settings tab (index 5)
    final mainNavState = context
        .findAncestorStateOfType<MainNavigationScreenState>();
    if (mainNavState != null) {
      mainNavState.setCurrentIndex(5);
    }
  }

  Future<void> _loadDailyReport() async {
    final previousError = _salesError;

    setState(() {
      _isLoadingSales = true;
      _salesError = null;
    });

    final now = DateTime.now();

    Future<ApiResponse<Map<String, dynamic>>> currentFuture;
    Future<ApiResponse<Map<String, dynamic>>> previousFuture;

    switch (_timeframe) {
      case DashboardTimeframe.day:
        currentFuture = _apiService.getDailyReport();
        final yesterday = now.subtract(const Duration(days: 1));
        previousFuture = _apiService.getDailyReport(_ymd(yesterday));
        break;
      case DashboardTimeframe.week:
        currentFuture = _apiService.getWeeklyReport();
        final lastWeek = now.subtract(const Duration(days: 7));
        previousFuture = _apiService.getWeeklyReport(_ymd(lastWeek));
        break;
      case DashboardTimeframe.month:
        currentFuture = _apiService.getMonthlyReport(
          year: now.year,
          month: now.month,
        );
        final previousMonth = DateTime(now.year, now.month - 1, 1);
        previousFuture = _apiService.getMonthlyReport(
          year: previousMonth.year,
          month: previousMonth.month,
        );
        break;
      case DashboardTimeframe.year:
        currentFuture = _apiService.getYearlyReport(year: now.year);
        previousFuture = _apiService.getYearlyReport(year: now.year - 1);
        break;
    }

    final responses = await Future.wait([currentFuture, previousFuture]);
    final response = responses[0];
    final previousResponse = responses[1];
    if (!mounted) return;

    setState(() {
      _isLoadingSales = false;

      if (response.success && response.data != null) {
        _dailyReport = response.data;
        _activeSalesError = null;

        final currentTotal = _extractTotalSales(response.data);

        double? computedGrowth;
        if (previousResponse.success && previousResponse.data != null) {
          final previousTotal = _extractTotalSales(previousResponse.data);
          computedGrowth = _calculateGrowthPercent(
            current: currentTotal,
            previous: previousTotal,
          );
        }

        _totalSalesGrowthPercent =
            computedGrowth ??
            _coerceGrowthPercent(response.data?['growth_percentage']);

        _syncGrossSalesChartFromReport(response.data!);
      } else {
        final err = response.message ?? 'Failed to load sales data';
        _salesError = err;

        if (_activeSalesError != err || previousError == null) {
          _enqueueNotification(
            _DashboardNotificationItem(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              sourceKey: 'sales_error',
              createdAt: DateTime.now(),
              type: DashboardNotificationType.error,
              title: 'Sales report failed',
              message: err,
              status: _NotificationStatus.unread,
              onTap: _loadDailyReport,
            ),
          );
          _activeSalesError = err;
        }
      }
    });

    _persistNotificationStorage();
  }

  double _extractTotalSales(Map<String, dynamic>? report) {
    final raw = report?['total_sales'] ?? report?['total'] ?? 0;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString()) ?? 0.0;
  }

  double _calculateGrowthPercent({
    required double current,
    required double previous,
  }) {
    if (previous <= 0) {
      return current <= 0 ? 0.0 : 100.0;
    }
    return ((current - previous) / previous) * 100.0;
  }

  double _coerceGrowthPercent(dynamic raw) {
    if (raw == null) return 0.0;
    final v = (raw is num) ? raw.toDouble() : double.tryParse(raw.toString());
    if (v == null) return 0.0;
    // Some backends return 0.12 for 12%. Convert when it looks like a ratio.
    if (v.abs() <= 1.0) return v * 100.0;
    return v;
  }

  Future<void> _showItemsSoldPopup() async {
    if (!mounted) return;

    var isLoading = true;
    String? error;
    var query = '';
    var limit = 50;
    var items = <_SoldProductItem>[];

    await showDialog<void>(
      context: context,
      builder: (context) {
        var started = false;

        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> load() async {
              if (!_canViewAnalytics) {
                setModalState(() {
                  isLoading = false;
                  error = 'You don\'t have access to view sold products.';
                  items = [];
                });
                return;
              }

              setModalState(() {
                isLoading = true;
                error = null;
              });

              try {
                final res = await _apiService.getTopProducts(limit: limit);
                if (!mounted) return;

                if (!res.success || res.data == null) {
                  setModalState(() {
                    isLoading = false;
                    error = res.message ?? 'Failed to load sold products';
                    items = [];
                  });
                  return;
                }

                final parsed = res.data!
                    .map((m) => _SoldProductItem.fromMap(m))
                    .where((p) => p.name.trim().isNotEmpty)
                    .toList();

                setModalState(() {
                  isLoading = false;
                  error = null;
                  items = parsed;
                });
              } catch (e) {
                if (!mounted) return;
                setModalState(() {
                  isLoading = false;
                  error = 'Failed to load sold products: $e';
                  items = [];
                });
              }
            }

            if (!started) {
              started = true;
              unawaited(load());
            }

            final filtered = query.trim().isEmpty
                ? items
                : items
                      .where(
                        (p) => p.name.toLowerCase().contains(
                          query.trim().toLowerCase(),
                        ),
                      )
                      .toList();

            final totalQty = filtered.fold<int>(
              0,
              (sum, p) => sum + p.quantity,
            );
            final totalSales = filtered.fold<double>(
              0.0,
              (sum, p) => sum + p.sales,
            );
            final money = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

            final media = MediaQuery.of(context);
            final availableWidth = media.size.width - 32;
            final availableHeight =
                media.size.height - media.padding.vertical - 32;
            final dialogWidth = availableWidth > 720 ? 720.0 : availableWidth;
            final dialogHeight = availableHeight > 680
                ? 680.0
                : availableHeight;

            return Dialog(
              insetPadding: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: SizedBox(
                width: dialogWidth,
                height: dialogHeight,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Items Sold', style: AppTypography.heading4),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Refresh',
                            onPressed: isLoading ? null : () => load(),
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              onChanged: (v) => setModalState(() => query = v),
                              decoration: InputDecoration(
                                hintText: 'Search product…',
                                prefixIcon: const Icon(Icons.search_rounded),
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          DropdownButton<int>(
                            value: limit,
                            onChanged: (v) {
                              if (v == null) return;
                              setModalState(() => limit = v);
                              unawaited(load());
                            },
                            items: const [10, 25, 50, 100]
                                .map(
                                  (v) => DropdownMenuItem<int>(
                                    value: v,
                                    child: Text('Top $v'),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: isLoading
                            ? const Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.primary,
                                  strokeWidth: 2,
                                ),
                              )
                            : error != null
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.error_outline_rounded,
                                      color: AppColors.error,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      error!,
                                      style: AppTypography.bodySmall.copyWith(
                                        color: context.textSecondaryColor,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 10),
                                    TextButton(
                                      onPressed: () => load(),
                                      child: const Text('Retry'),
                                    ),
                                  ],
                                ),
                              )
                            : filtered.isEmpty
                            ? Center(
                                child: Text(
                                  query.trim().isEmpty
                                      ? 'No sold products yet.'
                                      : 'No matches.',
                                  style: AppTypography.bodyMedium.copyWith(
                                    color: context.textSecondaryColor,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final p = filtered[index];
                                  return Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: context.cardColor,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.12,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 36,
                                          height: 36,
                                          decoration: BoxDecoration(
                                            color: Colors.green.withValues(
                                              alpha: 0.12,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.shopping_bag_rounded,
                                            color: Colors.green,
                                            size: 18,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                p.name,
                                                style: AppTypography.labelLarge
                                                    .copyWith(
                                                      color: context
                                                          .textPrimaryColor,
                                                    ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${p.quantity} sold',
                                                style: AppTypography.caption
                                                    .copyWith(
                                                      color: context
                                                          .textSecondaryColor,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          money.format(p.sales),
                                          style: AppTypography.labelLarge
                                              .copyWith(
                                                color: AppColors.primary,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            'Total qty: $totalQty',
                            style: AppTypography.labelMedium.copyWith(
                              color: context.textSecondaryColor,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Total sales: ${money.format(totalSales)}',
                            style: AppTypography.labelMedium.copyWith(
                              color: context.textSecondaryColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showTransactionsPopup() async {
    if (!mounted) return;

    var query = '';

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> refresh() async {
              await _loadRecentTransactions();
              if (!mounted) return;
              setModalState(() {});
            }

            final media = MediaQuery.of(context);
            final availableWidth = media.size.width - 32;
            final availableHeight =
                media.size.height - media.padding.vertical - 32;
            final dialogWidth = availableWidth > 720 ? 720.0 : availableWidth;
            final dialogHeight = availableHeight > 680
                ? 680.0
                : availableHeight;

            final q = query.trim().toLowerCase();
            final filtered = q.isEmpty
                ? _recentTransactions
                : _recentTransactions.where((t) {
                    final method = t.paymentMethod.toString().split('.').last;
                    return t.id.toLowerCase().contains(q) ||
                        t.time.toLowerCase().contains(q) ||
                        method.toLowerCase().contains(q);
                  }).toList();

            return Dialog(
              insetPadding: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: SizedBox(
                width: dialogWidth,
                height: dialogHeight,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Transactions', style: AppTypography.heading4),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Refresh',
                            onPressed: _isLoadingTransactions
                                ? null
                                : () => refresh(),
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        onChanged: (v) => setModalState(() => query = v),
                        decoration: InputDecoration(
                          hintText: 'Search by customer or receipt…',
                          prefixIcon: const Icon(Icons.search_rounded),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _isLoadingTransactions
                            ? const Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.primary,
                                  strokeWidth: 2,
                                ),
                              )
                            : _transactionsError != null
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.error_outline_rounded,
                                      color: AppColors.error,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _transactionsError!,
                                      style: AppTypography.bodySmall.copyWith(
                                        color: context.textSecondaryColor,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 10),
                                    TextButton(
                                      onPressed: () => refresh(),
                                      child: const Text('Retry'),
                                    ),
                                  ],
                                ),
                              )
                            : filtered.isEmpty
                            ? Center(
                                child: Text(
                                  query.trim().isEmpty
                                      ? 'No transactions yet.'
                                      : 'No matches.',
                                  style: AppTypography.bodyMedium.copyWith(
                                    color: context.textSecondaryColor,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final txn = filtered[index];
                                  return _TransactionItem(transaction: txn);
                                },
                              ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            'Showing ${filtered.length}',
                            style: AppTypography.labelMedium.copyWith(
                              color: context.textSecondaryColor,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const TransactionsScreen(),
                                ),
                              );
                            },
                            child: const Text('View all'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _loadLowStockProducts() async {
    final previousActiveIds = Set<String>.from(_activeLowStockProductIds);
    final previousError = _lowStockError;

    setState(() {
      _isLoadingLowStock = true;
      _lowStockError = null;
    });

    final response = await _apiService.getLowStockProducts();

    if (mounted) {
      setState(() {
        _isLoadingLowStock = false;
        if (response.success && response.data != null) {
          final products = response.data!
              .map(
                (p) => Product(
                  id: p['id'].toString(),
                  name: p['name'] ?? '',
                  category: p['category_name'] ?? '',
                  price: (p['selling_price'] ?? p['price'] ?? 0).toDouble(),
                  stock: p['stock_quantity'] ?? p['stock'] ?? 0,
                  barcode: p['barcode'],
                ),
              )
              .toList();

          _lowStockProducts = products;
          _activeLowStockError = null;

          final currentIds = products.map((p) => p.id).toSet();
          // Add notifications only for newly-entered low-stock items.
          for (final p in products) {
            if (!previousActiveIds.contains(p.id)) {
              final sourceKey = 'low_stock:${p.id}';
              if (_suppressedSourceKeys.contains(sourceKey)) continue;
              _enqueueNotification(
                _DashboardNotificationItem(
                  id: DateTime.now().microsecondsSinceEpoch.toString(),
                  sourceKey: sourceKey,
                  createdAt: DateTime.now(),
                  type: DashboardNotificationType.warning,
                  title: 'Low stock',
                  message: '${p.name} • ${p.stock} left',
                  status: _NotificationStatus.unread,
                  onTap: () => _navigateToProducts(context),
                ),
              );
            }
          }

          // If a product is no longer low-stock, allow future re-notification.
          for (final oldId in previousActiveIds) {
            if (!currentIds.contains(oldId)) {
              _suppressedSourceKeys.remove('low_stock:$oldId');
            }
          }

          _activeLowStockProductIds
            ..clear()
            ..addAll(currentIds);
        } else {
          final err = response.message ?? 'Failed to load low stock data';
          _lowStockError = err;
          if (_activeLowStockError != err || previousError == null) {
            _enqueueNotification(
              _DashboardNotificationItem(
                id: DateTime.now().microsecondsSinceEpoch.toString(),
                sourceKey: 'low_stock_error',
                createdAt: DateTime.now(),
                type: DashboardNotificationType.error,
                title: 'Low stock check failed',
                message: err,
                status: _NotificationStatus.unread,
                onTap: _loadLowStockProducts,
              ),
            );
            _activeLowStockError = err;
          }
        }
      });
      _persistNotificationStorage();
    }
  }

  Future<void> _loadRecentTransactions() async {
    final previousError = _transactionsError;

    setState(() {
      _isLoadingTransactions = true;
      _transactionsError = null;
    });

    final nowPh = PhTime.now();
    DateTime start;
    DateTime end;

    // Cashier dashboard should always show only today's transactions.
    if (_isCashier) {
      start = DateTime(nowPh.year, nowPh.month, nowPh.day);
      end = start;
    } else {
      switch (_timeframe) {
        case DashboardTimeframe.day:
          start = DateTime(nowPh.year, nowPh.month, nowPh.day);
          end = start;
          break;
        case DashboardTimeframe.week:
          start = _startOfWeek(nowPh);
          end = start.add(const Duration(days: 6));
          break;
        case DashboardTimeframe.month:
          start = DateTime(nowPh.year, nowPh.month, 1);
          // Last day of current month.
          end = DateTime(nowPh.year, nowPh.month + 1, 0);
          break;
        case DashboardTimeframe.year:
          start = DateTime(nowPh.year, 1, 1);
          end = DateTime(nowPh.year, 12, 31);
          break;
      }
    }

    final response = await _apiService.getTransactions(
      startDate: _ymd(start),
      endDate: _ymd(end),
      perPage: _isCashier ? 100 : 5,
    );

    debugPrint('🔍 Transaction API Response:');
    debugPrint('  - Success: ${response.success}');
    debugPrint('  - Message: ${response.message}');
    debugPrint('  - Data is null: ${response.data == null}');
    debugPrint('  - Status Code: ${response.statusCode}');

    if (mounted) {
      setState(() {
        _isLoadingTransactions = false;
        if (response.success && response.data != null) {
          try {
            debugPrint('🔍 Response data type: ${response.data.runtimeType}');
            debugPrint('🔍 Transactions count: ${response.data!.length}');

            _recentTransactions = response.data!.map((t) {
              final createdAt = PhTime.parseToPhOrNow(
                t['created_at']?.toString(),
              );
              final time = DateFormat('hh:mm a').format(createdAt);

              return _TransactionData(
                id: t['transaction_id']?.toString() ?? 'TXN-${t['id']}',
                createdAt: createdAt,
                time: time,
                amount: (t['total_amount'] ?? 0).toDouble(),
                items: t['item_count'] ?? 0,
                paymentMethod: _parsePaymentMethod(t['payment_method']),
              );
            }).toList();
            _recentTransactions.sort(
              (a, b) => b.createdAt.compareTo(a.createdAt),
            );

            _activeTransactionsError = null;
          } catch (e, stackTrace) {
            debugPrint('❌ Error parsing transactions: $e');
            debugPrint('Stack trace: $stackTrace');
            final err = 'Failed to parse response: $e';
            _transactionsError = err;
            if (_activeTransactionsError != err || previousError == null) {
              _enqueueNotification(
                _DashboardNotificationItem(
                  id: DateTime.now().microsecondsSinceEpoch.toString(),
                  sourceKey: 'transactions_error',
                  createdAt: DateTime.now(),
                  type: DashboardNotificationType.error,
                  title: 'Transactions failed',
                  message: err,
                  status: _NotificationStatus.unread,
                  onTap: _loadRecentTransactions,
                ),
              );
              _activeTransactionsError = err;
            }
          }
        } else {
          final err = response.message ?? 'Failed to load transactions';
          _transactionsError = err;
          if (_activeTransactionsError != err || previousError == null) {
            _enqueueNotification(
              _DashboardNotificationItem(
                id: DateTime.now().microsecondsSinceEpoch.toString(),
                sourceKey: 'transactions_error',
                createdAt: DateTime.now(),
                type: DashboardNotificationType.error,
                title: 'Transactions failed',
                message: err,
                status: _NotificationStatus.unread,
                onTap: _loadRecentTransactions,
              ),
            );
            _activeTransactionsError = err;
          }
        }
      });
      _persistNotificationStorage();
    }
  }

  PaymentMethod _parsePaymentMethod(String? method) {
    switch (method?.toLowerCase()) {
      case 'cash':
        return PaymentMethod.cash;
      case 'card':
        return PaymentMethod.card;
      case 'gcash':
        return PaymentMethod.gcash;
      case 'maya':
        return PaymentMethod.maya;
      default:
        return PaymentMethod.cash;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    // Use responsive layout based on screen size
    final isDesktop = context.isDesktop;
    final isTablet = context.isTablet;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          color: AppColors.primary,
          child: isDesktop
              ? _buildDesktopLayout()
              : isTablet
              ? _buildTabletLayout()
              : _buildMobileLayout(),
        ),
      ),
    );
  }

  /// Desktop Layout - Full featured with charts and multi-column
  Widget _buildDesktopLayout() {
    if (_isCashier) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDesktopHeader(),
            const SizedBox(height: 24),
            _buildQuickActions(context),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SalesStatCard(
                    title: 'Quick Refund',
                    value: 'Scan / Refund',
                    subtitle: 'Scan receipt QR or enter TXN code',
                    icon: Icons.qr_code_scanner_rounded,
                    color: AppColors.primary,
                    onTap: _showReceiptLookupDialog,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildRecentTransactions(),
          ],
        ),
      );
    }

    final totalSales = (_dailyReport?['total_sales'] ?? 0.0).toDouble();
    final transactionCount =
        _dailyReport?['total_transactions'] ??
        _dailyReport?['transaction_count'] ??
        0;
    final itemsSold =
        _dailyReport?['total_items_sold'] ??
        _dailyReport?['total_items'] ??
        _dailyReport?['items_sold'] ??
        0;
    final growthPercentage = _totalSalesGrowthPercent;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with search
          _buildDesktopHeader(),

          const SizedBox(height: 24),

          // Quick Stats Cards Row
          if (_isLoadingSales)
            const Center(child: CircularProgressIndicator())
          else if (_salesError != null)
            _buildErrorState(_salesError!, _loadDailyReport)
          else
            QuickStatsRow(
              todaySales: totalSales,
              transactions: transactionCount,
              itemsSold: itemsSold,
              growthPercentage: growthPercentage,
              salesSubtitle: _timeframeSubtitle,
              totalSalesTimeframeLabel: _timeframePickerLabel,
              onTotalSalesTap: _showTotalSalesTimeframePopup,
              onTransactionsTap: () => _showTransactionsPopup(),
              onItemsSoldTap: () => _showItemsSoldPopup(),
              onAvgOrderTap: () => _navigateToReports(context),
            ),

          if (_canManageApprovals && !_isLoadingSales && _salesError == null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                children: [
                  Expanded(
                    child: SalesStatCard(
                      title: 'Refunded Products',
                      value:
                          ((_dailyReport?['refunded_products'] ??
                                  _dailyReport?['refunded_items'] ??
                                  0)
                              is num
                          ? (_dailyReport?['refunded_products'] ??
                                    _dailyReport?['refunded_items'] ??
                                    0)
                                .toInt()
                                .toString()
                          : '${_dailyReport?['refunded_products'] ?? _dailyReport?['refunded_items'] ?? 0}'),
                      subtitle: _refundSubtitle,
                      icon: Icons.assignment_return_rounded,
                      color: AppColors.error,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SalesStatCard(
                      title: 'Quick Refund',
                      value: 'Scan / Refund',
                      subtitle: 'Scan receipt QR or enter TXN code',
                      icon: Icons.qr_code_scanner_rounded,
                      color: AppColors.primary,
                      onTap: _showReceiptLookupDialog,
                    ),
                  ),
                ],
              ),
            )
          else if (!_isLoadingSales && _salesError == null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                children: [
                  Expanded(
                    child: SalesStatCard(
                      title: 'Quick Refund',
                      value: 'Scan / Refund',
                      subtitle: 'Scan receipt QR or enter TXN code',
                      icon: Icons.qr_code_scanner_rounded,
                      color: AppColors.primary,
                      onTap: _showReceiptLookupDialog,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 24),

          // Charts Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Bar Chart - Gross Sales
              Expanded(
                flex: 2,
                child: SalesBarChart(
                  data: _grossSalesChartData,
                  labels: _grossSalesChartLabels,
                  title: 'Gross Sales',
                ),
              ),
              const SizedBox(width: 16),
              // Pie Chart - Sales by Category
              Expanded(
                child: SalesPieChart(
                  data: _salesByCategory,
                  title: 'Sales by Category',
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Second row - Line chart and Activity
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Line Chart - Sales Trends
              Expanded(
                flex: 2,
                child: SalesLineChart(
                  currentData: _trendCurrentYear,
                  previousData: _trendPreviousYear,
                  labels: _trendLabels,
                  title: 'Sales Trends',
                  currentLabel: _trendCurrentLabel,
                  previousLabel: _trendPreviousLabel,
                ),
              ),
              const SizedBox(width: 16),
              // Low Stock + Recent Activity
              Expanded(
                child: Column(
                  children: [
                    _buildLowStockAlertCompact(),
                    const SizedBox(height: 16),
                    _buildRecentTransactionsCompact(),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Tablet Layout - Two column where appropriate
  Widget _buildTabletLayout() {
    if (_isCashier) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 24),
            _buildQuickActions(context),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SalesStatCard(
                    title: 'Quick Refund',
                    value: 'Scan / Refund',
                    subtitle: 'Scan receipt QR or enter TXN code',
                    icon: Icons.qr_code_scanner_rounded,
                    color: AppColors.primary,
                    onTap: _showReceiptLookupDialog,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildRecentTransactions(),
            const SizedBox(height: 20),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 24),

          _buildSalesCard(),
          const SizedBox(height: 20),

          // Quick actions in a row (already responsive)
          _buildQuickActions(context),

          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SalesStatCard(
                  title: 'Quick Refund',
                  value: 'Scan / Refund',
                  subtitle: 'Scan receipt QR or enter TXN code',
                  icon: Icons.qr_code_scanner_rounded,
                  color: AppColors.primary,
                  onTap: _showReceiptLookupDialog,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Two column layout for low stock and transactions
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildLowStockAlert()),
              const SizedBox(width: 16),
              Expanded(child: _buildRecentTransactions()),
            ],
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// Mobile Layout - Single column (original layout)
  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          _buildHeader(),

          const SizedBox(height: 24),

          // Cashier: keep the dashboard focused (avoid infinite loaders)
          if (_canViewAnalytics) ...[
            // Today's Sales Card
            _buildSalesCard(),
            const SizedBox(height: 20),
          ],

          // Quick Actions
          _buildQuickActions(context),

          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SalesStatCard(
                  title: 'Quick Refund',
                  value: 'Scan / Refund',
                  subtitle: 'Scan receipt QR or enter TXN code',
                  icon: Icons.qr_code_scanner_rounded,
                  color: AppColors.primary,
                  onTap: _showReceiptLookupDialog,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          if (_canViewAnalytics) ...[
            // Low Stock Alert
            _buildLowStockAlert(),
            const SizedBox(height: 24),
          ],

          // Recent Transactions
          _buildRecentTransactions(),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// Desktop Header with Search Bar
  Widget _buildDesktopHeader() {
    final hour = DateTime.now().hour;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    String greeting = 'Good Morning';
    if (hour >= 12 && hour < 17) {
      greeting = 'Good Afternoon';
    } else if (hour >= 17) {
      greeting = 'Good Evening';
    }

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greeting, ${widget.userName}',
                style: textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Here\'s what\'s happening with your store today.',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        // Search bar — M3 surface container
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => showGlobalSearchDialog(context),
            borderRadius: BorderRadius.circular(28),
            child: Container(
              width: 300,
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    color: context.textLightColor,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AbsorbPointer(
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search products, receipts, members...',
                          hintStyle: TextStyle(
                            color: context.textLightColor,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Notifications
        _buildDesktopNotificationButton(),
        const SizedBox(width: 8),
        // Refresh
        if (_isRefreshing)
          const SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else
          IconButton(
            onPressed: _onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
      ],
    );
  }

  /// Compact Low Stock Alert for Desktop sidebar
  Widget _buildLowStockAlertCompact() {
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.warning,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Low Stock',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Badge(
                  label: Text('${_lowStockProducts.length}'),
                  backgroundColor: AppColors.warning,
                  textColor: Colors.white,
                ),
              ],
            ),
            if (_lowStockProducts.isNotEmpty) ...[
              const SizedBox(height: 12),
              ..._lowStockProducts
                  .take(3)
                  .map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              p.name,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? Colors.white70
                                    : AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${p.stock} left',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.warning,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  /// Compact Recent Transactions for Desktop sidebar
  Widget _buildRecentTransactionsCompact() {
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Sales',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TransactionsScreen(),
                      ),
                    );
                  },
                  child: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_recentTransactions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    'No transactions yet',
                    style: TextStyle(
                      color: isDark ? Colors.white38 : AppColors.textLight,
                    ),
                  ),
                ),
              )
            else
              ..._recentTransactions
                  .take(4)
                  .map(
                    (txn) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.receipt_rounded,
                              color: AppColors.success,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  txn.id,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? Colors.white
                                        : AppColors.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  txn.time,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? Colors.white38
                                        : AppColors.textLight,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '₱${txn.amount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final hour = DateTime.now().hour;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    String greeting = 'Good Morning';
    if (hour >= 12 && hour < 17) {
      greeting = 'Good Afternoon';
    } else if (hour >= 17) {
      greeting = 'Good Evening';
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              greeting,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.userName,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                widget.userRole == 'supervisor' ? 'Supervisor' : 'Cashier',
                style: textTheme.labelSmall?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        Row(
          children: [
            // Notifications
            _buildMobileNotificationButton(),
            // Refresh Button
            if (_isRefreshing)
              Container(
                padding: const EdgeInsets.all(10),
                child: const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                onPressed: _onRefresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            // Profile Avatar
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  widget.userName.isNotEmpty
                      ? widget.userName[0].toUpperCase()
                      : 'U',
                  style: textTheme.titleLarge?.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMobileNotificationButton() {
    final count = _desktopNotificationCount;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          onPressed: _showNotificationsPopup,
          icon: Icon(
            Icons.notifications_rounded,
            color: context.textPrimaryColor,
          ),
          tooltip: 'Notifications',
        ),
        if (count > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSalesCard() {
    // Get data from daily report
    final totalSales = _dailyReport?['total_sales'] ?? 0.0;
    final transactionCount =
        _dailyReport?['total_transactions'] ??
        _dailyReport?['transaction_count'] ??
        0;
    final itemsSold =
        _dailyReport?['total_items_sold'] ??
        _dailyReport?['total_items'] ??
        _dailyReport?['items_sold'] ??
        0;
    final growthPercentage = _totalSalesGrowthPercent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: (_isLoadingSales || _salesError != null)
            ? null
            : _showTotalSalesTimeframePopup,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: _isLoadingSales
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(
                      color: AppColors.white,
                      strokeWidth: 2,
                    ),
                  ),
                )
              : _salesError != null
              ? _buildErrorState(_salesError!, _loadDailyReport)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Sales',
                          style: AppTypography.bodyLarge.copyWith(
                            color: AppColors.white.withValues(alpha: 0.9),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                growthPercentage >= 0
                                    ? Icons.trending_up_rounded
                                    : Icons.trending_down_rounded,
                                color: AppColors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${growthPercentage >= 0 ? '+' : ''}${growthPercentage.toStringAsFixed(1)}%',
                                style: AppTypography.labelMedium.copyWith(
                                  color: AppColors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _timeframeSubtitle,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.white.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '₱ ${_formatCurrency(totalSales.toDouble())}',
                      style: AppTypography.heading1.copyWith(
                        color: AppColors.white,
                        fontSize: 36,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _buildSalesInfo(
                            icon: Icons.receipt_long_rounded,
                            label: 'Transactions',
                            value: transactionCount.toString(),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildSalesInfo(
                            icon: Icons.shopping_bag_rounded,
                            label: 'Items Sold',
                            value: itemsSold.toString(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
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

  Widget _buildErrorState(String message, VoidCallback onRetry) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.error_outline_rounded,
          color: AppColors.white.withValues(alpha: 0.8),
          size: 32,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.white.withValues(alpha: 0.8),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: onRetry,
          child: Text(
            'Retry',
            style: AppTypography.labelMedium.copyWith(color: AppColors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildSalesInfo({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.white, size: 16),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                label,
                style: AppTypography.caption.copyWith(
                  color: AppColors.white.withValues(alpha: 0.8),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppStrings.quickActions, style: AppTypography.heading4),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _QuickActionCard(
                icon: Icons.add_shopping_cart_rounded,
                label: AppStrings.newSale,
                color: AppColors.primary,
                onTap: () => _navigateToNewSale(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickActionCard(
                icon: _isCashier
                    ? Icons.person_add_rounded
                    : Icons.inventory_2_rounded,
                label: _isCashier ? 'Add Member' : AppStrings.products,
                color: AppColors.accent,
                onTap: () => _isCashier
                    ? _openAddLoyaltyMember(context)
                    : _navigateToProducts(context),
              ),
            ),
            if (!_isCashier) ...[
              const SizedBox(width: 12),
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.bar_chart_rounded,
                  label: AppStrings.reports,
                  color: AppColors.info,
                  onTap: () => _navigateToReports(context),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  void _openAddLoyaltyMember(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            LoyaltyScreen(userRole: widget.userRole, autoOpenRegister: true),
      ),
    );
  }

  Widget _buildLowStockAlert() {
    if (_isLoadingLowStock) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: AppColors.warningLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
        ),
        child: const Center(
          child: CircularProgressIndicator(
            color: AppColors.warning,
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (_lowStockError != null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.errorLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error),
            const SizedBox(height: 8),
            Text(_lowStockError!, style: AppTypography.bodySmall),
            TextButton(
              onPressed: _loadLowStockProducts,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_lowStockProducts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.successLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppColors.success,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'All products are well stocked!',
                style: AppTypography.bodyMedium.copyWith(
                  color: context.textPrimaryColor,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.warning,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppStrings.lowStockAlert,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.heading4.copyWith(
                    color: context.textPrimaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.warning,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_lowStockProducts.length} ${AppStrings.itemsLowStock}',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._lowStockProducts
              .take(5)
              .map((product) => _LowStockItem(product: product)),
          if (_lowStockProducts.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: TextButton(
                  onPressed: () {
                    // TODO: Navigate to products screen with low stock filter
                  },
                  child: Text(
                    'View all ${_lowStockProducts.length} items',
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.warning,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecentTransactions() {
    // Loading state
    if (_isLoadingTransactions) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppStrings.recentTransactions,
                style: AppTypography.heading4,
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const TransactionsScreen(),
                    ),
                  );
                },
                child: Text(
                  AppStrings.viewAll,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Builder(
            builder: (context) => Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: context.cardColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 2,
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Error state
    if (_transactionsError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppStrings.recentTransactions,
                style: AppTypography.heading4,
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const TransactionsScreen(),
                    ),
                  );
                },
                child: Text(
                  AppStrings.viewAll,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.errorLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                const Icon(Icons.error_outline, color: AppColors.error),
                const SizedBox(height: 8),
                Text(_transactionsError!, style: AppTypography.bodySmall),
                TextButton(
                  onPressed: _loadRecentTransactions,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Empty state
    if (_recentTransactions.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppStrings.recentTransactions,
                style: AppTypography.heading4,
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const TransactionsScreen(),
                    ),
                  );
                },
                child: Text(
                  AppStrings.viewAll,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Builder(
            builder: (context) => Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 48,
                      color: context.textLightColor,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No recent transactions',
                      style: AppTypography.bodyMedium.copyWith(
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Data state - has transactions
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(AppStrings.recentTransactions, style: AppTypography.heading4),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const TransactionsScreen(),
                  ),
                );
              },
              child: Text(
                AppStrings.viewAll,
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._recentTransactions.map((txn) => _TransactionItem(transaction: txn)),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  label,
                  style: textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeframePickTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final DashboardTimeframe value;
  final DashboardTimeframe groupValue;
  final ValueChanged<DashboardTimeframe> onSelected;

  const _TimeframePickTile({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.groupValue,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final selected = value == groupValue;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onSelected(value),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: isDark ? 0.18 : 0.10)
                : (isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.grey.shade50),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.35)
                  : (isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.grey.shade200),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
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
              const SizedBox(width: 12),
              // TODO: migrate to RadioGroup once stable in our Flutter channel.
              // ignore: deprecated_member_use
              Radio<DashboardTimeframe>(
                value: value,
                // ignore: deprecated_member_use
                groupValue: groupValue,
                // ignore: deprecated_member_use
                onChanged: (v) {
                  if (v != null) onSelected(v);
                },
                activeColor: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LowStockItem extends StatelessWidget {
  final Product product;

  const _LowStockItem({required this.product});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.inventory_outlined,
              color: context.textSecondaryColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: AppTypography.labelLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  product.category,
                  style: AppTypography.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: product.stock <= 3
                  ? AppColors.errorLight
                  : AppColors.warningLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${product.stock} left',
              style: AppTypography.labelSmall.copyWith(
                color: product.stock <= 3 ? AppColors.error : AppColors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionData {
  final String id;
  final DateTime createdAt;
  final String time;
  final double amount;
  final int items;
  final PaymentMethod paymentMethod;

  _TransactionData({
    required this.id,
    required this.createdAt,
    required this.time,
    required this.amount,
    required this.items,
    required this.paymentMethod,
  });
}

class _TransactionItem extends StatelessWidget {
  final _TransactionData transaction;

  const _TransactionItem({required this.transaction});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) =>
                  ReceiptScreen(transactionId: transaction.id),
            ),
          );
        },
        child: Card(
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
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.successLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.receipt_rounded,
                    color: AppColors.success,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transaction.id,
                        style: AppTypography.labelLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.access_time_rounded,
                                size: 12,
                                color: context.textLightColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                transaction.time,
                                style: AppTypography.caption,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.shopping_bag_outlined,
                                size: 12,
                                color: context.textLightColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${transaction.items} items',
                                style: AppTypography.caption,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '₱ ${transaction.amount.toStringAsFixed(2)}',
                      style: AppTypography.priceRegular.copyWith(
                        color: AppColors.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: context.surfaceColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        transaction.paymentMethod.displayName,
                        style: AppTypography.labelSmall.copyWith(fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SoldProductItem {
  final String name;
  final int quantity;
  final double sales;

  const _SoldProductItem({
    required this.name,
    required this.quantity,
    required this.sales,
  });

  factory _SoldProductItem.fromMap(Map<String, dynamic> map) {
    final name = (map['name'] ?? map['product_name'] ?? '').toString();

    final qtyRaw = map['quantity'] ?? map['qty'] ?? map['units_sold'] ?? 0;
    final quantity = (qtyRaw is num)
        ? qtyRaw.toInt()
        : int.tryParse(qtyRaw.toString()) ?? 0;

    final salesRaw = map['sales'] ?? map['total_sales'] ?? map['revenue'] ?? 0;
    final sales = (salesRaw is num)
        ? salesRaw.toDouble()
        : double.tryParse(salesRaw.toString()) ?? 0.0;

    return _SoldProductItem(name: name, quantity: quantity, sales: sales);
  }
}

class _PendingRefundsDialog extends StatefulWidget {
  final ApiService apiService;

  const _PendingRefundsDialog({required this.apiService});

  @override
  State<_PendingRefundsDialog> createState() => _PendingRefundsDialogState();
}

class _PendingRefundsDialogState extends State<_PendingRefundsDialog> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];
  final Set<String> _busyIds = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await widget.apiService.getPendingRefundRequests();
      if (!mounted) return;
      if (!res.success) {
        setState(() {
          _isLoading = false;
          _error = res.message ?? 'Failed to load pending refunds';
          _items = const [];
        });
        return;
      }

      setState(() {
        _isLoading = false;
        _error = null;
        _items = res.data ?? const [];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to load pending refunds: $e';
        _items = const [];
      });
    }
  }

  Future<void> _act({required String id, required bool approve}) async {
    if (_busyIds.contains(id)) return;
    setState(() {
      _busyIds.add(id);
    });
    try {
      final intId = int.tryParse(id);
      if (intId == null) {
        if (!mounted) return;
        setState(() {
          _busyIds.remove(id);
          _error = 'Invalid refund request id: $id';
        });
        return;
      }

      final res = approve
          ? await widget.apiService.approveRefundRequest(intId)
          : await widget.apiService.rejectRefundRequest(intId);
      if (!mounted) return;

      if (res.success) {
        await _load();
      } else {
        setState(() {
          _error =
              res.message ?? (approve ? 'Approve failed' : 'Reject failed');
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Action failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busyIds.remove(id);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final media = MediaQuery.of(context);
    final availableWidth = media.size.width - 32;
    final availableHeight = media.size.height - media.padding.vertical - 32;
    final dialogWidth = availableWidth > 680 ? 680.0 : availableWidth;
    final dialogHeight = availableHeight > 620 ? 620.0 : availableHeight;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Pending Refunds', style: AppTypography.heading4),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _isLoading ? null : _load,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                          strokeWidth: 2,
                        ),
                      )
                    : _items.isEmpty
                    ? Center(
                        child: Text(
                          'No pending refund requests.',
                          style: AppTypography.bodyMedium.copyWith(
                            color: context.textSecondaryColor,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final rr = _items[index];
                          final id = (rr['id'] ?? '').toString();
                          final txn = rr['transaction'];
                          String txnCode = '';
                          if (txn is Map) {
                            txnCode = (txn['transaction_id'] ?? txn['id'] ?? '')
                                .toString();
                          }
                          if (txnCode.isEmpty) {
                            txnCode = (rr['transaction_id'] ?? '').toString();
                          }
                          final amountRaw =
                              rr['amount'] ??
                              (txn is Map ? txn['total_amount'] : null) ??
                              0;
                          final amount = (amountRaw is num)
                              ? amountRaw.toDouble()
                              : double.tryParse(amountRaw.toString()) ?? 0.0;

                          final busy = _busyIds.contains(id);

                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: context.cardColor,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: context.dividerColor),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        txnCode.isEmpty
                                            ? 'Transaction'
                                            : txnCode,
                                        style: AppTypography.labelLarge,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        money.format(amount),
                                        style: AppTypography.bodySmall.copyWith(
                                          color: context.textSecondaryColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                TextButton(
                                  onPressed: busy
                                      ? null
                                      : () => _act(id: id, approve: false),
                                  child: busy
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('Reject'),
                                ),
                                const SizedBox(width: 6),
                                ElevatedButton(
                                  onPressed: busy
                                      ? null
                                      : () => _act(id: id, approve: true),
                                  child: const Text('Approve'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
