import 'dart:async';

import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_typography.dart';
import '../core/theme/theme_helper.dart';
import '../services/api_service.dart';
import 'receipt_screen.dart';

Future<void> showGlobalSearchDialog(BuildContext context) async {
  final api = ApiService();

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => _GlobalSearchDialog(api: api),
  );
}

class _GlobalSearchDialog extends StatefulWidget {
  final ApiService api;

  const _GlobalSearchDialog({required this.api});

  @override
  State<_GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends State<_GlobalSearchDialog> {
  final _controller = TextEditingController();
  Timer? _debounce;

  bool _loading = false;
  String? _error;

  String? _productsError;
  String? _transactionsError;
  String? _membersError;

  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _members = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();

    final q = value.trim();
    if (q.length < 2) {
      setState(() {
        _loading = false;
        _error = null;
        _productsError = null;
        _transactionsError = null;
        _membersError = null;
        _products = [];
        _transactions = [];
        _members = [];
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 250), () {
      _runSearch(q);
    });
  }

  Future<void> _runSearch(String query) async {
    setState(() {
      _loading = true;
      _error = null;
      _productsError = null;
      _transactionsError = null;
      _membersError = null;
    });

    try {
      final results = await Future.wait([
        widget.api.getProducts(search: query),
        widget.api.getTransactions(search: query, page: 1, perPage: 10),
        widget.api.getLoyaltyMembers(page: 1, perPage: 10, search: query),
      ]);

      final productsResp =
          results[0] as ApiResponse<List<Map<String, dynamic>>>;
      final txResp = results[1] as ApiResponse<List<Map<String, dynamic>>>;
      final membersResp = results[2] as ApiResponse<Map<String, dynamic>>;

      if (!mounted) return;

      final products = productsResp.success
          ? (productsResp.data ?? [])
          : <Map<String, dynamic>>[];
      final tx = txResp.success
          ? (txResp.data ?? [])
          : <Map<String, dynamic>>[];
      final members = membersResp.success
          ? List<Map<String, dynamic>>.from(
              (membersResp.data?['members'] as List?) ?? const [],
            )
          : <Map<String, dynamic>>[];

      // Prefer showing a single combined error only if everything failed.
      final allFailed =
          !productsResp.success && !txResp.success && !membersResp.success;
      final msg = allFailed
          ? (productsResp.message ??
                txResp.message ??
                membersResp.message ??
                'Search failed')
          : null;

      setState(() {
        _products = products.take(8).toList();
        _transactions = tx.take(10).toList();
        _members = members.take(10).toList();
        _productsError = productsResp.success
            ? null
            : '${productsResp.statusCode}: ${productsResp.message ?? 'Failed to load products'}';
        _transactionsError = txResp.success
            ? null
            : '${txResp.statusCode}: ${txResp.message ?? 'Failed to load receipts'}';
        _membersError = membersResp.success
            ? null
            : '${membersResp.statusCode}: ${membersResp.message ?? 'Failed to load members'}';
        _error = msg;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final availableWidth = media.size.width - 32;
    final availableHeight = media.size.height - media.padding.vertical - 32;
    final dialogWidth = availableWidth > 820 ? 820.0 : availableWidth;
    final dialogHeight = availableHeight > 720 ? 720.0 : availableHeight;

    final q = _controller.text.trim();

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: context.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.search_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Search', style: AppTypography.heading4),
                        const SizedBox(height: 2),
                        Text(
                          'Products • Receipts • Members',
                          style: AppTypography.caption.copyWith(
                            color: context.textSecondaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _onQueryChanged,
                decoration: InputDecoration(
                  hintText: 'Search products, receipts (TXN-...), members...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: q.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          onPressed: () {
                            _controller.clear();
                            _onQueryChanged('');
                            setState(() {});
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_loading)
                const LinearProgressIndicator(
                  color: AppColors.primary,
                  minHeight: 2,
                )
              else
                const SizedBox(height: 2),
              const SizedBox(height: 10),
              Expanded(
                child: _error != null
                    ? _buildErrorState(_error!)
                    : (q.length < 2)
                    ? _buildHintState()
                    : _buildResults(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHintState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tips_and_updates_outlined,
              size: 48,
              color: context.textLightColor,
            ),
            const SizedBox(height: 12),
            Text(
              'Type at least 2 characters to search.',
              style: AppTypography.bodyMedium.copyWith(
                color: context.textSecondaryColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Tip: paste a receipt code like TXN-2026...',
              style: AppTypography.caption.copyWith(
                color: context.textLightColor,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.error,
              size: 48,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: AppTypography.bodySmall.copyWith(
                color: context.textSecondaryColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => _runSearch(_controller.text.trim()),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    final hasAny =
        _products.isNotEmpty ||
        _transactions.isNotEmpty ||
        _members.isNotEmpty ||
        _productsError != null ||
        _transactionsError != null ||
        _membersError != null;
    if (!hasAny) {
      return Center(
        child: Text(
          'No matches.',
          style: AppTypography.bodyMedium.copyWith(
            color: context.textSecondaryColor,
          ),
        ),
      );
    }

    return ListView(
      children: [
        if (_products.isNotEmpty || _productsError != null) ...[
          _SectionHeader(title: 'Products', icon: Icons.inventory_2_outlined),
          const SizedBox(height: 8),
          if (_productsError != null)
            _InfoTile(message: _productsError!)
          else
            ..._products.map(_buildProductTile),
          const SizedBox(height: 14),
        ],
        if (_transactions.isNotEmpty || _transactionsError != null) ...[
          _SectionHeader(
            title: 'Receipts / Transactions',
            icon: Icons.receipt_long_outlined,
          ),
          const SizedBox(height: 8),
          if (_transactionsError != null)
            _InfoTile(message: _transactionsError!)
          else
            ..._transactions.map(_buildTransactionTile),
          const SizedBox(height: 14),
        ],
        if (_members.isNotEmpty || _membersError != null) ...[
          _SectionHeader(title: 'Members', icon: Icons.people_outline),
          const SizedBox(height: 8),
          if (_membersError != null)
            _InfoTile(message: _membersError!)
          else
            ..._members.map(_buildMemberTile),
        ],
      ],
    );
  }

  Widget _buildProductTile(Map<String, dynamic> p) {
    final name = (p['name'] ?? 'Product').toString();
    final sku = (p['sku'] ?? '').toString();
    final stock = p['stock_quantity'];
    final price = p['selling_price'] ?? p['price'];

    return _ResultTile(
      leadingColor: Colors.green,
      icon: Icons.shopping_bag_outlined,
      title: name,
      subtitle: [
        if (sku.trim().isNotEmpty) 'SKU: $sku',
        if (stock != null) 'Stock: $stock',
        if (price != null) '₱${(price as num).toStringAsFixed(2)}',
      ].join(' • '),
      onTap: () => _showProductQuickView(p),
    );
  }

  Widget _buildTransactionTile(Map<String, dynamic> t) {
    final code = (t['transaction_id'] ?? t['id'] ?? '').toString();
    final customer = (t['customer_name'] ?? 'Walk-in').toString();
    final total = t['total_amount'];
    final method = (t['payment_method'] ?? '').toString();

    return _ResultTile(
      leadingColor: AppColors.primary,
      icon: Icons.receipt_long_outlined,
      title: code.isEmpty ? 'Transaction' : code,
      subtitle: [
        if (customer.trim().isNotEmpty) customer,
        if (total != null) '₱${(total as num).toStringAsFixed(2)}',
        if (method.trim().isNotEmpty) method.toUpperCase(),
      ].join(' • '),
      onTap: () {
        if (code.isEmpty) return;
        Navigator.of(context).pop();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ReceiptScreen(transactionId: code)),
        );
      },
    );
  }

  Widget _buildMemberTile(Map<String, dynamic> m) {
    final customer = m['customer'] as Map<String, dynamic>?;
    final name = (customer?['name'] ?? 'Member').toString();
    final phone = (customer?['phone'] ?? '').toString();
    final memberNo = (m['member_number'] ?? '').toString();
    final points = m['current_points'];

    return _ResultTile(
      leadingColor: Colors.purple,
      icon: Icons.person_outline,
      title: name,
      subtitle: [
        if (memberNo.trim().isNotEmpty) memberNo,
        if (phone.trim().isNotEmpty) phone,
        if (points != null) '${points.toString()} pts',
      ].join(' • '),
      onTap: () => _showMemberQuickView(m),
    );
  }

  Future<void> _showProductQuickView(Map<String, dynamic> p) async {
    final name = (p['name'] ?? 'Product').toString();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(name, style: AppTypography.heading4),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv('SKU', p['sku']),
            _kv('Barcode', p['barcode']),
            _kv('Price', p['selling_price'] ?? p['price']),
            _kv('Stock', p['stock_quantity']),
            _kv('Category', p['category_name'] ?? p['category_id']),
          ].whereType<Widget>().toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showMemberQuickView(Map<String, dynamic> m) async {
    final customer = m['customer'] as Map<String, dynamic>?;
    final name = (customer?['name'] ?? 'Member').toString();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(name, style: AppTypography.heading4),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv('Member #', m['member_number']),
            _kv('Phone', customer?['phone']),
            _kv('Email', customer?['email']),
            _kv('Points', m['current_points']),
            _kv(
              'Status',
              m['card_status'] ??
                  (m['is_active'] == true ? 'active' : 'inactive'),
            ),
          ].whereType<Widget>().toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget? _kv(String k, Object? v) {
    if (v == null) return null;
    final text = v.toString().trim();
    if (text.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              k,
              style: AppTypography.labelMedium.copyWith(
                color: context.textSecondaryColor,
              ),
            ),
          ),
          Expanded(child: Text(text, style: AppTypography.bodyMedium)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: context.textSecondaryColor),
        const SizedBox(width: 8),
        Text(
          title,
          style: AppTypography.labelLarge.copyWith(
            color: context.textPrimaryColor,
          ),
        ),
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  final Color leadingColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _ResultTile({
    required this.leadingColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: context.isDarkMode
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: leadingColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: leadingColor, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTypography.labelLarge.copyWith(
                          color: context.textPrimaryColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: AppTypography.caption.copyWith(
                          color: context.textSecondaryColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.chevron_right_rounded,
                  color: context.textLightColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String message;

  const _InfoTile({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.isDarkMode
              ? Colors.white.withValues(alpha: 0.03)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.10)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 18,
              color: context.textSecondaryColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: AppTypography.caption.copyWith(
                  color: context.textSecondaryColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
