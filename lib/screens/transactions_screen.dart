import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_typography.dart';
import '../core/theme/theme_helper.dart';
import '../core/utils/ph_time.dart';
import '../services/api_service.dart';
import 'receipt_screen.dart';
import 'package:provider/provider.dart';
import '../state/auth_provider.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _transactions = [];
  bool _isLoading = false;
  String? _error;
  String _selectedFilter = 'Today';
  String _statusFilter = 'All';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTransactions() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final now = DateTime.now();
      String startDate;
      String? endDate;

      switch (_selectedFilter) {
        case 'Today':
          startDate = DateFormat('yyyy-MM-dd').format(now);
          endDate = DateFormat('yyyy-MM-dd').format(now);
          break;
        case 'Yesterday':
          final yesterday = now.subtract(const Duration(days: 1));
          startDate = DateFormat('yyyy-MM-dd').format(yesterday);
          final endOfYesterday = yesterday;
          endDate = DateFormat('yyyy-MM-dd').format(endOfYesterday);
          break;
        case 'This Week':
          final weekStart = now.subtract(Duration(days: now.weekday - 1));
          startDate = DateFormat('yyyy-MM-dd').format(weekStart);
          break;
        case 'This Month':
          startDate = DateFormat('yyyy-MM-01').format(now);
          break;
        default:
          startDate = DateFormat('yyyy-MM-dd').format(now);
      }

      final normalizedStatus = _statusFilter.toLowerCase().trim();
      final statusParam = normalizedStatus == 'all' ? null : normalizedStatus;

      final response = await _apiService.getTransactions(
        startDate: startDate,
        endDate: endDate,
        status: statusParam,
        perPage: 100,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          if (response.success && response.data != null) {
            // ApiService unwraps backend {success, data: [...], pagination} to response.data = [...]
            _transactions = response.data!;
          } else {
            _error = response.message ?? 'Failed to load transactions';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Error: $e';
        });
      }
    }
  }

  bool get _isSupervisor {
    final role = context.read<AuthProvider>().role.toLowerCase();
    return role == 'supervisor' || role == 'admin' || role == 'superadmin';
  }

  Future<void> _requestRefund(Map<String, dynamic> txn) async {
    final idRaw = txn['id'];
    final id = (idRaw is int) ? idRaw : int.tryParse('$idRaw');
    if (id == null) return;

    final status = (txn['status'] ?? '').toString().toLowerCase();
    if (status == 'refunded' || status == 'voided') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('This transaction is already $status.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(_isSupervisor ? 'Refund Transaction' : 'Request Refund'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isSupervisor
                    ? 'This will refund the transaction immediately.'
                    : 'This will send a refund request for admin approval.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: Text(_isSupervisor ? 'Refund' : 'Send Request'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final response = await _apiService.requestRefund(
      id,
      reason: reasonController.text,
    );

    if (!mounted) return;

    if (response.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            response.message ??
                (_isSupervisor
                    ? 'Transaction refunded successfully'
                    : 'Refund request submitted for approval'),
          ),
          backgroundColor: AppColors.success,
        ),
      );
      await _loadTransactions();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response.message ?? 'Refund failed'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  List<Map<String, dynamic>> get _filteredTransactions {
    final normalizedStatus = _statusFilter.toLowerCase();
    final statusFiltered = normalizedStatus == 'all'
        ? _transactions
        : _transactions.where((txn) {
            final status = (txn['status'] ?? 'completed')
                .toString()
                .toLowerCase();
            switch (normalizedStatus) {
              case 'completed':
                return status == 'completed';
              case 'refunded':
                return status == 'refunded';
              case 'voided':
                return status == 'voided';
              default:
                return true;
            }
          }).toList();

    if (_searchController.text.isEmpty) return statusFiltered;

    final query = _searchController.text.toLowerCase();
    return statusFiltered.where((txn) {
      final id = (txn['transaction_id'] ?? txn['id']).toString().toLowerCase();
      final amount = (txn['total_amount'] ?? 0).toString();
      final method = (txn['payment_method'] ?? '').toString().toLowerCase();
      final status = (txn['status'] ?? '').toString().toLowerCase();
      return id.contains(query) ||
          amount.contains(query) ||
          method.contains(query) ||
          status.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(title: const Text('Transactions')),
      body: Column(
        children: [
          // Search and Filter — M3 surface container
          Material(
            color: colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Search bar
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search by ID, amount, or method...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Time filter chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('Today'),
                        _buildFilterChip('Yesterday'),
                        _buildFilterChip('This Week'),
                        _buildFilterChip('This Month'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Status filter chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildStatusChip('All'),
                        _buildStatusChip('Completed'),
                        _buildStatusChip('Refunded'),
                        _buildStatusChip('Voided'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Transactions list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 64,
                          color: colorScheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text(_error!, style: textTheme.bodyMedium),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _loadTransactions,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _filteredTransactions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 64,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchController.text.isNotEmpty
                              ? 'No transactions found'
                              : 'No transactions for $_selectedFilter',
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadTransactions,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _filteredTransactions.length,
                      itemBuilder: (context, index) {
                        final txn = _filteredTransactions[index];
                        return _TransactionCard(
                          transaction: txn,
                          onRefund: () => _requestRefund(txn),
                          canRefund: true,
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _selectedFilter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            _selectedFilter = label;
            _loadTransactions();
          });
        },
      ),
    );
  }

  Widget _buildStatusChip(String label) {
    final isSelected = _statusFilter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) {
          setState(() {
            _statusFilter = label;
            _loadTransactions();
          });
        },
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final Map<String, dynamic> transaction;

  final VoidCallback? onRefund;
  final bool canRefund;

  const _TransactionCard({
    required this.transaction,
    this.onRefund,
    this.canRefund = false,
  });

  @override
  Widget build(BuildContext context) {
    final id =
        transaction['transaction_id']?.toString() ?? 'TXN-${transaction['id']}';
    final receiptTransactionId =
        (transaction['transaction_id'] ?? transaction['id']).toString();
    final amount = (transaction['total_amount'] ?? 0).toDouble();
    final itemCount = transaction['item_count'] ?? 0;
    final paymentMethod = transaction['payment_method']?.toString() ?? 'cash';
    final createdAt = PhTime.parseToPhOrNow(
      transaction['created_at']?.toString(),
    );

    final timeFormat = DateFormat('hh:mm a');
    final dateFormat = DateFormat('MMM dd, yyyy');

    final statusRaw = (transaction['status'] ?? 'completed').toString();
    final status = statusRaw.toLowerCase();
    final refundable =
        canRefund &&
        onRefund != null &&
        status != 'refunded' &&
        status != 'voided';

    final statusLabel = status == 'refunded'
        ? 'Refunded'
        : status == 'voided'
        ? 'Voided'
        : 'Completed';
    final statusColor = status == 'refunded'
        ? AppColors.error
        : status == 'voided'
        ? AppColors.warning
        : AppColors.success;
    final statusIcon = status == 'refunded'
        ? Icons.assignment_return_rounded
        : status == 'voided'
        ? Icons.block_rounded
        : Icons.check_circle;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  ReceiptScreen(transactionId: receiptTransactionId),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          id,
                          style: AppTypography.labelLarge.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${timeFormat.format(createdAt)} • ${dateFormat.format(createdAt)}',
                          style: AppTypography.caption.copyWith(
                            color: context.textSecondaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '₱ ${amount.toStringAsFixed(2)}',
                        style: AppTypography.heading4.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$itemCount ${itemCount == 1 ? "item" : "items"}',
                        style: AppTypography.caption.copyWith(
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildPaymentMethodChip(paymentMethod),
                  const Spacer(),
                  if (refundable)
                    TextButton(
                      onPressed: onRefund,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                      ),
                      child: const Text('Refund'),
                    )
                  else ...[
                    Icon(statusIcon, color: statusColor, size: 20),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: AppTypography.labelSmall.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right,
                      color: context.textLightColor,
                      size: 20,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentMethodChip(String method) {
    IconData icon;
    Color color;

    switch (method.toLowerCase()) {
      case 'cash':
        icon = Icons.payments_rounded;
        color = const Color(0xFF4CAF50);
        break;
      case 'card':
        icon = Icons.credit_card_rounded;
        color = const Color(0xFF2196F3);
        break;
      case 'gcash':
        icon = Icons.account_balance_wallet_rounded;
        color = const Color(0xFF007DFF);
        break;
      case 'maya':
        icon = Icons.smartphone_rounded;
        color = const Color(0xFF00B140);
        break;
      default:
        icon = Icons.payments_rounded;
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            method.toUpperCase(),
            style: AppTypography.labelSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
