import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/app_colors.dart';
import '../core/theme/theme_helper.dart';
import '../core/constants/app_strings.dart';
import '../core/constants/app_typography.dart';
import '../core/utils/ph_time.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class _ReceiptLineItem {
  final String name;
  final double unitPrice;
  final int quantity;
  final double lineTotal;
  final bool isRedeemedReward;

  const _ReceiptLineItem({
    required this.name,
    required this.unitPrice,
    required this.quantity,
    required this.lineTotal,
    required this.isRedeemedReward,
  });
}

class ReceiptScreen extends StatefulWidget {
  final String transactionId;
  final List<CartItem>? cartItems;
  final double? total;
  final PaymentMethod? paymentMethod;
  final double? amountReceived;
  final double? change;
  final double? subtotal;
  final double? tax;
  final double? discount;
  final int? customerId;
  final String? cashierName;

  const ReceiptScreen({
    super.key,
    required this.transactionId,
    this.cartItems,
    this.total,
    this.paymentMethod,
    this.amountReceived,
    this.change,
    this.subtotal,
    this.tax,
    this.discount,
    this.customerId,
    this.cashierName,
  });

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  final ApiService _apiService = ApiService();
  Map<String, dynamic>? _transactionDetails;
  bool _isLoading = false;
  String? _loadError;
  final DateTime _now = PhTime.now();

  double get _discount {
    if (widget.discount != null) return widget.discount!;
    final txDiscount = _transactionDetails?['discount_amount'];
    final txVoucherDiscount = _transactionDetails?['voucher_discount'];
    return (txDiscount is num ? txDiscount.toDouble() : 0) +
        (txVoucherDiscount is num ? txVoucherDiscount.toDouble() : 0);
  }

  DateTime get _createdAt {
    final createdAtStr = _transactionDetails?['created_at']?.toString();
    return PhTime.parseToPhOrNow(createdAtStr, fallback: _now);
  }

  double get _total {
    if (widget.total != null) return widget.total!;
    final txTotal =
        _transactionDetails?['total_amount'] ??
        _transactionDetails?['total'] ??
        _transactionDetails?['totalAmount'];
    if (txTotal is num) return txTotal.toDouble();
    return 0;
  }

  PaymentMethod get _paymentMethod {
    if (widget.paymentMethod != null) return widget.paymentMethod!;
    final pm = _transactionDetails?['payment_method']?.toString().toLowerCase();
    switch (pm) {
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

  double get _amountReceived {
    if (widget.amountReceived != null) return widget.amountReceived!;
    final tx = _transactionDetails?['amount_received'];
    if (tx is num) return tx.toDouble();
    return 0;
  }

  double get _change {
    if (widget.change != null) return widget.change!;
    final tx = _transactionDetails?['change_amount'];
    if (tx is num) return tx.toDouble();
    return 0;
  }

  List<_ReceiptLineItem> get _items {
    final cart = widget.cartItems;
    if (cart != null && cart.isNotEmpty) {
      return cart
          .map(
            (item) => _ReceiptLineItem(
              name: item.product.name,
              unitPrice: item.product.effectivePrice,
              quantity: item.quantity,
              lineTotal: item.total,
              isRedeemedReward: item.product.isRedeemedReward,
            ),
          )
          .toList();
    }

    final txItems = _transactionDetails?['items'];
    if (txItems is List) {
      return txItems.whereType<Map>().map((raw) {
        final double unitPrice = (raw['unit_price'] is num)
            ? (raw['unit_price'] as num).toDouble()
            : 0.0;
        final double lineTotal = (raw['subtotal'] is num)
            ? (raw['subtotal'] as num).toDouble()
            : 0.0;

        final explicitRedeemed = raw['is_redeemed_reward'] == true;
        final heuristicRedeemed = unitPrice <= 0 && lineTotal <= 0;

        return _ReceiptLineItem(
          name: raw['product_name']?.toString() ?? 'Item',
          unitPrice: unitPrice,
          quantity: (raw['quantity'] is num)
              ? (raw['quantity'] as num).toInt()
              : 0,
          lineTotal: lineTotal,
          isRedeemedReward: explicitRedeemed || heuristicRedeemed,
        );
      }).toList();
    }
    return const [];
  }

  String _displayItemName(_ReceiptLineItem item) {
    if (!item.isRedeemedReward) return item.name;
    return '${item.name} (REDEEMED)';
  }

  double get _subtotal {
    if (widget.subtotal != null) return widget.subtotal!;
    final txSubtotal = _transactionDetails?['subtotal'];
    if (txSubtotal is num) return txSubtotal.toDouble();

    final tax = _tax;
    return _total - tax;
  }

  double get _tax {
    if (widget.tax != null) return widget.tax!;
    final txTax =
        _transactionDetails?['tax_amount'] ?? _transactionDetails?['tax'];
    if (txTax is num) return txTax.toDouble();
    return 0;
  }

  String get _cashierName {
    final name = widget.cashierName;
    if (name != null && name.trim().isNotEmpty) return name.trim();

    final txCashier = _transactionDetails?['cashier_name'];
    if (txCashier is String && txCashier.trim().isNotEmpty) {
      return txCashier.trim();
    }
    return 'Cashier';
  }

  int get _taxPercent {
    final subtotal = _subtotal;
    if (subtotal <= 0) return 0;
    return ((_tax / subtotal) * 100).round();
  }

  @override
  void initState() {
    super.initState();
    _loadTransactionDetails();
  }

  Future<void> _loadTransactionDetails() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      // Preferred: fetch by transaction code (TXN-...) since UI uses it.
      var response = await _apiService.getTransactionByCode(
        widget.transactionId,
      );

      // Back-compat: if transactionId is a numeric DB id string, try that.
      if (!response.success) {
        final idMatch = RegExp(r'^\d+$').firstMatch(widget.transactionId);
        if (idMatch != null) {
          response = await _apiService.getTransaction(
            int.parse(widget.transactionId),
          );
        }
      }

      if (!mounted) return;

      if (response.success && response.data != null) {
        setState(() {
          _transactionDetails = response.data;
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _transactionDetails = null;
        _isLoading = false;
        // If we don't have cartItems, the API is the only source of details.
        // Show a helpful error instead of a blank receipt.
        if (widget.cartItems == null || widget.cartItems!.isEmpty) {
          final msg = (response.message ?? 'Unable to load receipt details');
          _loadError =
              '${_sanitizeApiMessage(msg)} (code ${response.statusCode})';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (widget.cartItems == null || widget.cartItems!.isEmpty) {
          _loadError = 'Unable to load receipt details. $e';
        }
      });
    }
  }

  String _sanitizeApiMessage(String raw) {
    // Keep errors user-friendly.
    final msg = raw.trim();
    if (msg.isEmpty) return 'Unable to load receipt details';
    return msg;
  }

  // Generate PDF document
  Future<pw.Document> _generatePdf() async {
    final pdf = pw.Document();
    final dateFormat = DateFormat('MMM dd, yyyy');
    final timeFormat = DateFormat('hh:mm a');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Header
              pw.Text(
                'VIVIAN COSMETIC SHOP',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Official Receipt',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.SizedBox(height: 10),
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 5),

              // Transaction Info
              _pdfInfoRow('Transaction ID:', widget.transactionId),
              _pdfInfoRow('Date:', dateFormat.format(_createdAt)),
              _pdfInfoRow('Time:', timeFormat.format(_createdAt)),
              _pdfInfoRow('Cashier:', _cashierName),
              pw.SizedBox(height: 5),
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 5),

              // Items
              ..._items.map(
                (item) => pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 5),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              _displayItemName(item),
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                            pw.Text(
                              'P${item.unitPrice.toStringAsFixed(2)} x ${item.quantity}',
                              style: const pw.TextStyle(fontSize: 8),
                            ),
                          ],
                        ),
                      ),
                      pw.Text(
                        'P${item.lineTotal.toStringAsFixed(2)}',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),

              pw.SizedBox(height: 5),
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 5),

              // Totals
              _pdfInfoRow('Subtotal:', 'P${_subtotal.toStringAsFixed(2)}'),
              _pdfInfoRow(
                'Tax ($_taxPercent%):',
                'P${_tax.toStringAsFixed(2)}',
              ),
              if (_discount > 0)
                _pdfInfoRow('Discount:', '-P${_discount.toStringAsFixed(2)}'),
              pw.SizedBox(height: 5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'TOTAL',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'P${_total.toStringAsFixed(2)}',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 5),
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 5),

              // Payment Info
              _pdfInfoRow('Payment:', _paymentMethod.displayName),
              if (_paymentMethod == PaymentMethod.cash) ...[
                _pdfInfoRow(
                  'Received:',
                  'P${_amountReceived.toStringAsFixed(2)}',
                ),
                _pdfInfoRow('Change:', 'P${_change.toStringAsFixed(2)}'),
              ],

              pw.SizedBox(height: 15),

              // Refund QR Code (encode transaction code)
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: widget.transactionId,
                width: 90,
                height: 90,
                drawText: false,
              ),
              pw.SizedBox(height: 10),

              // Footer
              pw.Text(
                'Thank you for shopping!',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Visit us again soon!',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  pw.Widget _pdfInfoRow(String label, String value) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
        pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
      ],
    );
  }

  // Print receipt
  Future<void> _printReceipt() async {
    try {
      final pdf = await _generatePdf();
      await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
        name: 'Receipt_${widget.transactionId}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // Share receipt as PDF
  Future<void> _shareReceipt() async {
    try {
      final pdf = await _generatePdf();
      final bytes = await pdf.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'Receipt_${widget.transactionId}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Share error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // Email receipt
  Future<void> _emailReceipt() async {
    final emailController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Email Receipt'),
        content: TextField(
          controller: emailController,
          decoration: const InputDecoration(
            labelText: 'Email Address',
            hintText: 'customer@example.com',
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, emailController.text),
            child: const Text('Send'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final dateFormat = DateFormat('MMM dd, yyyy hh:mm a');
      final itemsList = _items
          .map(
            (item) =>
                '${_displayItemName(item)} x${item.quantity} - P${item.lineTotal.toStringAsFixed(2)}',
          )
          .join('\n');

      final body =
          '''
VIVIAN COSMETIC SHOP
Official Receipt

Transaction ID: ${widget.transactionId}
Date: ${dateFormat.format(_createdAt)}

Items:
$itemsList

Subtotal: P${_subtotal.toStringAsFixed(2)}
Tax: P${_tax.toStringAsFixed(2)}
${_discount > 0 ? 'Discount: -P${_discount.toStringAsFixed(2)}\n' : ''}
TOTAL: P${_total.toStringAsFixed(2)}

Payment: ${_paymentMethod.displayName}
${_paymentMethod == PaymentMethod.cash ? 'Received: P${_amountReceived.toStringAsFixed(2)}\nChange: P${_change.toStringAsFixed(2)}' : ''}

Thank you for shopping at Vivian Cosmetic Shop!
''';

      final uri = Uri(
        scheme: 'mailto',
        path: result,
        query:
            'subject=Receipt - ${widget.transactionId}&body=${Uri.encodeComponent(body)}',
      );

      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        } else {
          // Fallback: share the receipt text
          await Share.share(body, subject: 'Receipt - ${widget.transactionId}');
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not open email: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  // SMS receipt
  Future<void> _smsReceipt() async {
    final phoneController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('SMS Receipt'),
        content: TextField(
          controller: phoneController,
          decoration: const InputDecoration(
            labelText: 'Phone Number',
            hintText: '+63 912 345 6789',
          ),
          keyboardType: TextInputType.phone,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, phoneController.text),
            child: const Text('Send'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final body =
          'Vivian Cosmetic Shop Receipt\n'
          'ID: ${widget.transactionId}\n'
          'Total: P${_total.toStringAsFixed(2)}\n'
          'Thank you!';

      final uri = Uri(
        scheme: 'sms',
        path: result,
        queryParameters: {'body': body},
      );

      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('SMS not available on this device')),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not open SMS: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, yyyy');
    final timeFormat = DateFormat('hh:mm a');

    return Scaffold(
      backgroundColor: AppColors.successLight,
      body: SafeArea(
        child: Column(
          children: [
            // Success Animation Header
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.success.withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: AppColors.white,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppStrings.paymentSuccessful,
                    style: AppTypography.heading3.copyWith(
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Builder(
                    builder: (context) => Text(
                      AppStrings.thankYou,
                      style: AppTypography.bodyMedium.copyWith(
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Receipt Card
            Expanded(
              child: Builder(
                builder: (context) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: context.cardColor,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(32),
                    ),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        // Receipt Header
                        Column(
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                gradient: AppColors.primaryGradient,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.storefront_rounded,
                                color: AppColors.white,
                                size: 30,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              AppStrings.appName,
                              style: AppTypography.heading4.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                            Text(
                              'Official Receipt',
                              style: AppTypography.caption,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // Dashed Divider
                        _DashedDivider(),
                        const SizedBox(height: 20),
                        // Transaction Info
                        _InfoRow(
                          label: AppStrings.transactionId,
                          value: widget.transactionId.length > 15
                              ? widget.transactionId.substring(0, 15)
                              : widget.transactionId,
                        ),
                        const SizedBox(height: 8),
                        _InfoRow(
                          label: AppStrings.date,
                          value: dateFormat.format(_createdAt),
                        ),
                        const SizedBox(height: 8),
                        _InfoRow(
                          label: AppStrings.time,
                          value: timeFormat.format(_createdAt),
                        ),
                        const SizedBox(height: 8),
                        _InfoRow(
                          label: AppStrings.cashier,
                          value: _cashierName,
                        ),
                        const SizedBox(height: 20),
                        _DashedDivider(),
                        const SizedBox(height: 16),
                        // Items
                        if (_isLoading)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: AppColors.primary,
                                strokeWidth: 2,
                              ),
                            ),
                          )
                        else if (_loadError != null)
                          Builder(
                            builder: (context) => Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.error.withValues(
                                    alpha: 0.25,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _loadError!,
                                    style: AppTypography.bodySmall.copyWith(
                                      color: context.textPrimaryColor,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: _loadTransactionDetails,
                                      icon: const Icon(Icons.refresh_rounded),
                                      label: const Text('Retry'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else if (_items.isEmpty)
                          Builder(
                            builder: (context) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'No items to display',
                                style: AppTypography.bodySmall.copyWith(
                                  color: context.textSecondaryColor,
                                ),
                              ),
                            ),
                          )
                        else
                          ..._items.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _displayItemName(item),
                                          style: AppTypography.labelMedium,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          '₱${item.unitPrice.toStringAsFixed(2)} × ${item.quantity}',
                                          style: AppTypography.caption,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Text(
                                      '₱${item.lineTotal.toStringAsFixed(2)}',
                                      style: AppTypography.labelMedium,
                                      textAlign: TextAlign.right,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        _DashedDivider(),
                        const SizedBox(height: 16),
                        // Totals
                        _InfoRow(
                          label: AppStrings.subtotal,
                          value: '₱${_subtotal.toStringAsFixed(2)}',
                        ),
                        const SizedBox(height: 8),
                        _InfoRow(
                          label: 'Tax ($_taxPercent%)',
                          value: '₱${_tax.toStringAsFixed(2)}',
                        ),
                        if (_discount > 0) ...[
                          const SizedBox(height: 8),
                          _InfoRow(
                            label: 'Discount',
                            value: '-₱${_discount.toStringAsFixed(2)}',
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              AppStrings.total,
                              style: AppTypography.heading4,
                            ),
                            Text(
                              '₱${_total.toStringAsFixed(2)}',
                              style: AppTypography.priceLarge,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _DashedDivider(),
                        const SizedBox(height: 16),
                        // Payment Info
                        _InfoRow(
                          label: 'Payment Method',
                          value: _paymentMethod.displayName,
                        ),
                        if (_paymentMethod == PaymentMethod.cash) ...[
                          const SizedBox(height: 8),
                          _InfoRow(
                            label: AppStrings.amountReceived,
                            value: '₱${_amountReceived.toStringAsFixed(2)}',
                          ),
                          const SizedBox(height: 8),
                          _InfoRow(
                            label: AppStrings.change,
                            value: '₱${_change.toStringAsFixed(2)}',
                          ),
                        ],
                        const SizedBox(height: 24),
                        // Share/Print Buttons
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _printReceipt,
                                icon: const Icon(Icons.print_rounded),
                                label: const Text('Reprint'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _emailReceipt,
                                icon: const Icon(Icons.email_rounded),
                                label: const Text('Email'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _smsReceipt,
                                icon: const Icon(Icons.sms_rounded),
                                label: const Text('SMS'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Share button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _shareReceipt,
                            icon: const Icon(Icons.share_rounded),
                            label: const Text('Share Receipt'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Refund QR Code (encode transaction code)
                        BarcodeWidget(
                          barcode: Barcode.qrCode(),
                          data: widget.transactionId,
                          width: 140,
                          height: 140,
                          drawText: false,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Thank you for shopping!',
                          style: AppTypography.labelLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Visit us again soon!',
                          style: AppTypography.caption,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // New Transaction Button
            Builder(
              builder: (context) => Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: context.surfaceColor),
                child: SafeArea(
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      onPressed: () {
                        // Navigate back to main screen
                        Navigator.of(
                          context,
                        ).popUntil((route) => route.isFirst);
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_shopping_cart_rounded),
                          const SizedBox(width: 8),
                          Text(
                            AppStrings.newTransaction,
                            style: AppTypography.buttonLarge,
                          ),
                        ],
                      ),
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
}

class _DashedDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(
        30,
        (index) => Expanded(
          child: Container(
            height: 1,
            color: index.isEven ? AppColors.divider : Colors.transparent,
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.caption),
        Text(value, style: AppTypography.labelMedium),
      ],
    );
  }
}
