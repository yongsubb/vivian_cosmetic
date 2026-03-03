import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_typography.dart';
import '../core/theme/theme_helper.dart';
import '../services/api_service.dart';

class ItemsSoldScreen extends StatefulWidget {
  final int limit;

  const ItemsSoldScreen({super.key, this.limit = 50});

  @override
  State<ItemsSoldScreen> createState() => _ItemsSoldScreenState();
}

class _TopProduct {
  final String id;
  final String name;
  final int quantity;
  final double sales;

  const _TopProduct({
    required this.id,
    required this.name,
    required this.quantity,
    required this.sales,
  });

  factory _TopProduct.fromMap(Map<String, dynamic> m) {
    final rawId = m['product_id'] ?? m['id'] ?? '';
    final rawName = m['product_name'] ?? m['name'] ?? '';
    final rawQty = m['total_quantity'] ?? m['quantity'] ?? 0;
    final rawSales = m['total_sales'] ?? m['sales'] ?? 0;

    return _TopProduct(
      id: rawId.toString(),
      name: rawName.toString(),
      quantity: (rawQty is num) ? rawQty.toInt() : int.tryParse('$rawQty') ?? 0,
      sales: (rawSales is num)
          ? rawSales.toDouble()
          : double.tryParse('$rawSales') ?? 0.0,
    );
  }
}

class _ItemsSoldScreenState extends State<ItemsSoldScreen> {
  final ApiService _apiService = ApiService();

  bool _isLoading = true;
  String? _error;
  List<_TopProduct> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await _apiService.getTopProducts(limit: widget.limit);
      if (!mounted) return;

      if (!res.success || res.data == null) {
        setState(() {
          _isLoading = false;
          _error = res.message ?? 'Failed to load items sold';
        });
        return;
      }

      final parsed = res.data!
          .map((m) => _TopProduct.fromMap(m))
          .where((p) => p.name.trim().isNotEmpty)
          .toList();

      setState(() {
        _isLoading = false;
        _items = parsed;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to load items sold: $e';
      });
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Items Sold'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: context.textPrimaryColor,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : _items.isEmpty
              ? Center(
                  child: Text(
                    'No data yet',
                    style: AppTypography.bodyMedium.copyWith(
                      color: context.textSecondaryColor,
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 720;
                    if (!wide) {
                      return ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final p = _items[index];
                          return Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.shopping_bag_rounded,
                                      color: AppColors.primary,
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
                                          style: AppTypography.labelLarge,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${p.quantity} sold',
                                          style: AppTypography.caption.copyWith(
                                            color: context.textSecondaryColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    '₱ ${_formatCurrency(p.sales)}',
                                    style: AppTypography.labelLarge.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    }

                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: DataTable(
                            headingRowHeight: 44,
                            dataRowMinHeight: 48,
                            dataRowMaxHeight: 56,
                            columns: const [
                              DataColumn(label: Text('Product')),
                              DataColumn(label: Text('Qty')),
                              DataColumn(label: Text('Sales')),
                            ],
                            rows: _items
                                .map(
                                  (p) => DataRow(
                                    cells: [
                                      DataCell(
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: 420,
                                          ),
                                          child: Text(
                                            p.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      DataCell(Text('${p.quantity}')),
                                      DataCell(
                                        Text('₱ ${_formatCurrency(p.sales)}'),
                                      ),
                                    ],
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.error),
            const SizedBox(height: 8),
            Text(
              message,
              style: AppTypography.bodySmall.copyWith(
                color: context.textSecondaryColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
