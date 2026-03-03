import 'dart:math' as math;
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:barcode_widget/barcode_widget.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_strings.dart';
import '../core/constants/app_typography.dart';
import '../core/constants/payment_qr_config.dart';
import '../core/services/in_app_notification_service.dart';
import '../core/theme/theme_helper.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import 'receipt_screen.dart';

class PaymentScreen extends StatefulWidget {
  final double total;
  final List<CartItem> cartItems;
  final double? subtotal;
  final double? tax;
  final double? discount;
  final String? voucherCode;
  final int? customerId;
  final int? loyaltyMemberId;

  const PaymentScreen({
    super.key,
    required this.total,
    required this.cartItems,
    this.subtotal,
    this.tax,
    this.discount,
    this.voucherCode,
    this.customerId,
    this.loyaltyMemberId,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final ApiService _apiService = ApiService();
  PaymentMethod _selectedMethod = PaymentMethod.cash;
  final _amountController = TextEditingController();
  bool _isProcessing = false;

  double get _amountReceived => double.tryParse(_amountController.text) ?? 0;

  double get _change => _amountReceived - widget.total;

  bool get _canProceed {
    if (_selectedMethod == PaymentMethod.cash) {
      return _amountReceived >= widget.total;
    }
    return true;
  }

  Future<void> _onConfirmPressed() async {
    if (_isProcessing) return;

    if (_selectedMethod == PaymentMethod.gcash) {
      final ewalletQrPayload = PaymentQrConfig.gcashQrPayload;
      final ewalletQrAssetPath = PaymentQrConfig.gcashQrAssetPath;

      final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (context) => _EwalletQrScreen(
            method: _selectedMethod,
            total: widget.total,
            qrAssetPath: ewalletQrAssetPath,
            qrPayload: ewalletQrPayload,
          ),
        ),
      );

      if (ok == true && mounted) {
        _processPayment();
      }
      return;
    }

    _processPayment();
  }

  void _processPayment() async {
    setState(() => _isProcessing = true);

    try {
      // Prepare transaction items.
      // Include redeemed reward items so a receipt/transaction record exists,
      // but mark them to skip stock adjustments (stock is decremented at redeem time).
      final items = widget.cartItems.map((item) {
        if (item.product.isRedeemedReward) {
          final raw = item.product.id;
          final productIdStr = raw.replaceAll(Product.redeemedRewardMarker, '');
          return {
            'product_id': int.parse(productIdStr),
            'quantity': item.quantity,
            'unit_price': 0,
            'subtotal': 0,
            'discount_percent': 0,
            'skip_stock': true,
            'is_redeemed_reward': true,
          };
        }

        return {
          'product_id': int.parse(item.product.id),
          'quantity': item.quantity,
          'unit_price': item.product.effectivePrice,
          'subtotal': item.total,
          'discount_percent': 0,
        };
      }).toList();

      // Calculate totals
      final subtotal =
          widget.subtotal ??
          widget.cartItems.fold<double>(0, (sum, item) => sum + item.total);
      double tax = widget.tax ?? 0;
      if (widget.tax == null) {
        try {
          final taxResp = await _apiService.getSetting('tax_rate');
          if (taxResp.success && taxResp.data != null) {
            final data = taxResp.data;
            final num? taxRatePercent = (data is Map)
                ? (data['tax_rate'] as num?)
                : (data as num?);
            final rate = (taxRatePercent ?? 0).toDouble() / 100;
            tax = subtotal * rate;
          }
        } catch (_) {
          // Keep tax as 0 if settings cannot be loaded
        }
      }
      final discount = widget.discount ?? 0;

      // Create transaction via API
      final response = await _apiService.createTransaction(
        items: items,
        subtotal: subtotal,
        totalAmount: widget.total,
        paymentMethod: _selectedMethod.name,
        amountReceived: _amountReceived,
        taxAmount: tax,
        discountAmount: discount,
        changeAmount: _change > 0 ? _change : 0,
        voucherCode: widget.voucherCode,
        voucherDiscount: discount,
        customerId: widget.customerId,
      );

      if (!mounted) return;

      if (response.success && response.data != null) {
        final isOffline = response.data?['offline'] == true;
        if (isOffline) {
          InAppNotificationService.showInfo(
            response.message ?? 'Saved offline. Will sync when online.',
          );
        } else {
          InAppNotificationService.showSuccess('Transaction completed');
        }

        // Navigate to receipt screen with actual transaction data
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => ReceiptScreen(
              transactionId:
                  response.data!['transaction_id'] ??
                  'TXN-${response.data!['id']}',
              cartItems: widget.cartItems,
              total: widget.total,
              paymentMethod: _selectedMethod,
              amountReceived: _amountReceived,
              change: _change > 0 ? _change : 0,
              subtotal: subtotal,
              tax: tax,
              discount: discount,
              customerId: widget.customerId,
              cashierName: response.data!['cashier_name'] as String?,
            ),
          ),
        );
      } else {
        // Show error
        setState(() => _isProcessing = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Transaction failed'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.total.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 980;

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            title: const Text('Payment'),
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: isWide
              ? _buildWideBody(availableWidth: constraints.maxWidth)
              : _buildMobileBody(),
        );
      },
    );
  }

  Widget _buildTotalCard({required bool compact}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 18 : 24),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(compact ? 20 : 24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Total Amount',
            style: AppTypography.bodyLarge.copyWith(
              color: AppColors.white.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '₱ ${widget.total.toStringAsFixed(2)}',
            style: AppTypography.heading1.copyWith(
              color: AppColors.white,
              fontSize: compact ? 34 : 40,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMethodsGrid({
    required int crossAxisCount,
    required double childAspectRatio,
  }) {
    return GridView.count(
      crossAxisCount: crossAxisCount,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: childAspectRatio,
      children: [
        _PaymentMethodCard(
          method: PaymentMethod.cash,
          icon: Icons.payments_rounded,
          isSelected: _selectedMethod == PaymentMethod.cash,
          onTap: () {
            setState(() {
              _selectedMethod = PaymentMethod.cash;
            });
          },
        ),
        _PaymentMethodCard(
          method: PaymentMethod.gcash,
          icon: Icons.phone_android_rounded,
          color: const Color(0xFF007DFE),
          isSelected: _selectedMethod == PaymentMethod.gcash,
          onTap: () {
            setState(() {
              _selectedMethod = PaymentMethod.gcash;
            });
          },
        ),
      ],
    );
  }

  double get _effectiveSubtotal {
    return widget.subtotal ??
        widget.cartItems.fold<double>(0, (sum, item) => sum + item.total);
  }

  double get _effectiveTax {
    return widget.tax ?? 0;
  }

  double get _effectiveDiscount {
    return widget.discount ?? 0;
  }

  Widget _buildSummaryCard() {
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
            Text('Order Summary', style: AppTypography.heading4),
            const SizedBox(height: 12),
            _KeyValueRow(
              label: AppStrings.subtotal,
              value: '₱ ${_effectiveSubtotal.toStringAsFixed(2)}',
            ),
            const SizedBox(height: 10),
            _KeyValueRow(
              label: 'Tax',
              value: '₱ ${_effectiveTax.toStringAsFixed(2)}',
            ),
            if (_effectiveDiscount > 0) ...[
              const SizedBox(height: 10),
              _KeyValueRow(
                label: AppStrings.discount,
                value: '- ₱ ${_effectiveDiscount.toStringAsFixed(2)}',
                valueColor: AppColors.error,
              ),
            ],
            const SizedBox(height: 14),
            Divider(color: context.dividerColor, height: 1),
            const SizedBox(height: 14),
            _KeyValueRow(
              label: AppStrings.total,
              value: '₱ ${widget.total.toStringAsFixed(2)}',
              isTotal: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCashDetailsCard() {
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
            Text('Cash Payment', style: AppTypography.heading4),
            const SizedBox(height: 12),
            Text(AppStrings.amountReceived, style: AppTypography.labelLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              style: AppTypography.heading3,
              textAlign: TextAlign.center,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixText: '₱ ',
                prefixStyle: AppTypography.heading3,
                filled: true,
                fillColor: AppColors.secondary.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _QuickAmountButton(
                  amount: widget.total,
                  label: 'Exact',
                  onTap: () {
                    _amountController.text = widget.total.toStringAsFixed(2);
                    setState(() {});
                  },
                ),
                _QuickAmountButton(
                  amount: 500,
                  onTap: () {
                    _amountController.text = '500.00';
                    setState(() {});
                  },
                ),
                _QuickAmountButton(
                  amount: 1000,
                  onTap: () {
                    _amountController.text = '1000.00';
                    setState(() {});
                  },
                ),
                _QuickAmountButton(
                  amount: 2000,
                  onTap: () {
                    _amountController.text = '2000.00';
                    setState(() {});
                  },
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (_change >= 0)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.successLight,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.monetization_on_rounded,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppStrings.change,
                          style: AppTypography.labelLarge.copyWith(
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '₱ ${_change.toStringAsFixed(2)}',
                      style: AppTypography.heading2.copyWith(
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEwalletDetailsCard() {
    final methodLabel = _selectedMethod.name.toUpperCase();
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
            Text('$methodLabel Payment', style: AppTypography.heading4),
            const SizedBox(height: 10),
            Text(
              'After you confirm, a QR code will appear for the customer to scan.',
              style: AppTypography.bodyLarge.copyWith(
                color: context.textLightColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentContent({
    required bool isWide,
    required int methodsCrossAxisCount,
    required double methodsChildAspectRatio,
    double? cashSectionMaxWidth,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Total Amount Card
        Container(
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
          child: Column(
            children: [
              Text(
                'Total Amount',
                style: AppTypography.bodyLarge.copyWith(
                  color: AppColors.white.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '₱ ${widget.total.toStringAsFixed(2)}',
                style: AppTypography.heading1.copyWith(
                  color: AppColors.white,
                  fontSize: 40,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),

        // Payment Method Selection
        Text(AppStrings.selectPaymentMethod, style: AppTypography.heading4),

        const SizedBox(height: 16),

        // Payment Methods Grid
        GridView.count(
          crossAxisCount: methodsCrossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: methodsChildAspectRatio,
          children: [
            _PaymentMethodCard(
              method: PaymentMethod.cash,
              icon: Icons.payments_rounded,
              isSelected: _selectedMethod == PaymentMethod.cash,
              onTap: () {
                setState(() {
                  _selectedMethod = PaymentMethod.cash;
                });
              },
            ),
            _PaymentMethodCard(
              method: PaymentMethod.gcash,
              icon: Icons.phone_android_rounded,
              color: const Color(0xFF007DFE),
              isSelected: _selectedMethod == PaymentMethod.gcash,
              onTap: () {
                setState(() {
                  _selectedMethod = PaymentMethod.gcash;
                });
              },
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Cash Payment Section
        if (_selectedMethod == PaymentMethod.cash) ...[
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: cashSectionMaxWidth ?? double.infinity,
            ),
            child: Column(
              crossAxisAlignment: isWide
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.amountReceived,
                  style: AppTypography.labelLarge,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  style: AppTypography.heading3,
                  textAlign: TextAlign.center,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixText: '₱ ',
                    prefixStyle: AppTypography.heading3,
                    filled: true,
                    fillColor: AppColors.secondary.withValues(alpha: 0.5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 2,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Quick Amount Buttons
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _QuickAmountButton(
                      amount: widget.total,
                      label: 'Exact',
                      onTap: () {
                        _amountController.text = widget.total.toStringAsFixed(
                          2,
                        );
                        setState(() {});
                      },
                    ),
                    _QuickAmountButton(
                      amount: 500,
                      onTap: () {
                        _amountController.text = '500.00';
                        setState(() {});
                      },
                    ),
                    _QuickAmountButton(
                      amount: 1000,
                      onTap: () {
                        _amountController.text = '1000.00';
                        setState(() {});
                      },
                    ),
                    _QuickAmountButton(
                      amount: 2000,
                      onTap: () {
                        _amountController.text = '2000.00';
                        setState(() {});
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Change Display
                if (_change >= 0)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.successLight,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.success.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.monetization_on_rounded,
                              color: AppColors.success,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              AppStrings.change,
                              style: AppTypography.labelLarge.copyWith(
                                color: AppColors.success,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '₱ ${_change.toStringAsFixed(2)}',
                          style: AppTypography.heading2.copyWith(
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildConfirmBar({required bool isWide}) {
    final button = SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: _canProceed && !_isProcessing ? _onConfirmPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.success,
          disabledBackgroundColor: context.dividerColor,
        ),
        child: _isProcessing
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: AppColors.white,
                  strokeWidth: 2,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_rounded),
                  const SizedBox(width: 8),
                  Text(
                    AppStrings.confirmPayment,
                    style: AppTypography.buttonLarge,
                  ),
                ],
              ),
      ),
    );

    if (!isWide) {
      return Material(
        color: Theme.of(context).cardColor,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          child: SafeArea(child: button),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: button,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileBody() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _buildPaymentContent(
              isWide: false,
              methodsCrossAxisCount: 2,
              methodsChildAspectRatio: 1.5,
            ),
          ),
        ),
        _buildConfirmBar(isWide: false),
      ],
    );
  }

  Widget _buildWideBody({required double availableWidth}) {
    final confirmButton = SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: _canProceed && !_isProcessing ? _onConfirmPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.success,
          disabledBackgroundColor: context.dividerColor,
        ),
        child: _isProcessing
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: AppColors.white,
                  strokeWidth: 2,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_rounded),
                  const SizedBox(width: 8),
                  Text(
                    AppStrings.confirmPayment,
                    style: AppTypography.buttonLarge,
                  ),
                ],
              ),
      ),
    );

    final methodsAspectRatio = availableWidth >= 1200 ? 3.2 : 2.8;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTotalCard(compact: false),
              const SizedBox(height: 22),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppStrings.selectPaymentMethod,
                              style: AppTypography.heading4,
                            ),
                            const SizedBox(height: 16),
                            _buildMethodsGrid(
                              crossAxisCount: 2,
                              childAspectRatio: methodsAspectRatio,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 22),
                  SizedBox(
                    width: 420,
                    child: Column(
                      children: [
                        _buildSummaryCard(),
                        const SizedBox(height: 16),
                        _selectedMethod == PaymentMethod.cash
                            ? _buildCashDetailsCard()
                            : _buildEwalletDetailsCard(),
                        const SizedBox(height: 16),
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: confirmButton,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isTotal;
  final Color? valueColor;

  const _KeyValueRow({
    required this.label,
    required this.value,
    this.isTotal = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: isTotal
                ? AppTypography.heading4
                : AppTypography.bodyLarge.copyWith(
                    color: context.textLightColor,
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: (isTotal ? AppTypography.heading4 : AppTypography.bodyLarge)
              .copyWith(color: valueColor),
        ),
      ],
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  final PaymentMethod method;
  final IconData icon;
  final Color? color;
  final bool isSelected;
  final VoidCallback onTap;

  const _PaymentMethodCard({
    required this.method,
    required this.icon,
    this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = color ?? AppColors.primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? cardColor.withValues(alpha: 0.1)
              : context.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? cardColor : context.dividerColor,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: cardColor.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected ? cardColor : context.textSecondaryColor,
            ),
            const SizedBox(height: 8),
            Text(
              method.displayName,
              style: AppTypography.labelMedium.copyWith(
                color: isSelected ? cardColor : context.textSecondaryColor,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAmountButton extends StatelessWidget {
  final double amount;
  final String? label;
  final VoidCallback onTap;

  const _QuickAmountButton({
    required this.amount,
    this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.secondary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label ?? '₱${amount.toStringAsFixed(0)}',
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _EwalletQrScreen extends StatefulWidget {
  final PaymentMethod method;
  final double total;
  final String qrAssetPath;
  final String qrPayload;

  const _EwalletQrScreen({
    required this.method,
    required this.total,
    required this.qrAssetPath,
    required this.qrPayload,
  });

  @override
  State<_EwalletQrScreen> createState() => _EwalletQrScreenState();
}

class _EwalletQrScreenState extends State<_EwalletQrScreen> {
  bool _loading = true;
  String? _backendQrPayload;
  String? _backendQrImageUrl;
  String? _backendError;
  String? _qrphSessionId;
  Timer? _statusPollTimer;
  bool _autoCompleted = false;

  @override
  void initState() {
    super.initState();
    _loadQrFromBackend();
  }

  @override
  void dispose() {
    _statusPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadQrFromBackend() async {
    try {
      // IMPORTANT: Customer will scan inside the GCash app.
      // GCash' QR scanner expects a QRPH (EMV) payload. A URL QR (hosted checkout)
      // will be treated as invalid.
      final resp = await ApiService().generatePaymongoStaticQrph(
        amount: widget.total,
      );

      if (!mounted) {
        return;
      }

      if (resp.success) {
        final data = resp.data ?? const <String, dynamic>{};
        _backendQrPayload = (data['qr_payload'] as String?)?.trim();
        _backendQrImageUrl = (data['qr_image_url'] as String?)?.trim();
        _qrphSessionId = (data['session_id'] as String?)?.trim();

        if (_qrphSessionId != null && _qrphSessionId!.isNotEmpty) {
          _startStatusPolling(_qrphSessionId!);
        }
      } else {
        _backendError = (resp.message ?? 'Failed to generate QR').trim();
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      _backendError = e.toString();
    } finally {
      // Don't use `return` inside `finally` (analyzer rule: control_flow_in_finally).
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _startStatusPolling(String sessionId) {
    _statusPollTimer?.cancel();

    // Poll the backend (which is updated via PayMongo webhooks).
    _statusPollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted || _autoCompleted) {
        return;
      }

      try {
        final resp = await ApiService().getPaymongoQrphSessionStatus(sessionId);
        if (!mounted || _autoCompleted) {
          return;
        }

        if (!resp.success) {
          return;
        }

        final session = resp.data ?? const <String, dynamic>{};
        final status = (session['status'] as String?)?.toLowerCase();

        if (status == 'expired') {
          _statusPollTimer?.cancel();
          setState(() {
            _backendError = 'QR code expired. Please generate a new QR.';
          });
          return;
        }

        if (status == 'amount_mismatch') {
          _statusPollTimer?.cancel();

          final expectedRaw = session['expected_amount_centavos'];
          final lastPayment = session['last_payment'];
          final paidAmountRaw = (lastPayment is Map<String, dynamic>)
              ? lastPayment['amount']
              : null;

          final expected = (expectedRaw is num) ? expectedRaw.toInt() : null;
          final paidAmount = (paidAmountRaw is num)
              ? paidAmountRaw.toInt()
              : null;

          setState(() {
            if (expected != null && paidAmount != null) {
              _backendError =
                  'Payment received but amount mismatch. Expected ₱${(expected / 100).toStringAsFixed(2)}, got ₱${(paidAmount / 100).toStringAsFixed(2)}.';
            } else if (expected != null) {
              _backendError =
                  'Payment received but amount mismatch. Expected ₱${(expected / 100).toStringAsFixed(2)}.';
            } else {
              _backendError = 'Payment received but amount mismatch.';
            }
          });
          return;
        }

        if (status == 'paid') {
          final expectedRaw = session['expected_amount_centavos'];
          final lastPayment = session['last_payment'];
          final paidAmountRaw = (lastPayment is Map<String, dynamic>)
              ? lastPayment['amount']
              : null;

          final expected = (expectedRaw is num) ? expectedRaw.toInt() : null;
          final paidAmount = (paidAmountRaw is num)
              ? paidAmountRaw.toInt()
              : null;

          if (expected != null &&
              paidAmount != null &&
              expected != paidAmount) {
            _statusPollTimer?.cancel();
            setState(() {
              _backendError =
                  'Payment received but amount mismatch. Expected ₱${(expected / 100).toStringAsFixed(2)}.';
            });
            return;
          }

          _autoCompleted = true;
          _statusPollTimer?.cancel();
          if (mounted) {
            Navigator.pop(context, true);
          }
        }
      } catch (_) {
        // Ignore transient network errors and keep polling.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.method.displayName),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Text('Scan QR Code', style: AppTypography.heading4),
                  const SizedBox(height: 6),
                  Text(
                    'Total: ₱ ${widget.total.toStringAsFixed(2)}',
                    style: AppTypography.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final side =
                            (math.min(
                                      constraints.maxWidth,
                                      constraints.maxHeight,
                                    ) *
                                    0.95)
                                .clamp(220.0, 420.0);

                        final effectivePayload =
                            (_backendQrPayload != null &&
                                _backendQrPayload!.isNotEmpty)
                            ? _backendQrPayload!
                            : widget.qrPayload;

                        final hasBackendPayload =
                            _backendQrPayload != null &&
                            _backendQrPayload!.isNotEmpty;
                        final hasBackendImage =
                            _backendQrImageUrl != null &&
                            _backendQrImageUrl!.isNotEmpty;

                        Uint8List? dataUriBytes;
                        if (hasBackendImage &&
                            _backendQrImageUrl!.startsWith('data:image/')) {
                          final comma = _backendQrImageUrl!.indexOf(',');
                          if (comma != -1 &&
                              comma + 1 < _backendQrImageUrl!.length) {
                            final b64 = _backendQrImageUrl!.substring(
                              comma + 1,
                            );
                            try {
                              dataUriBytes = base64Decode(b64);
                            } catch (_) {
                              dataUriBytes = null;
                            }
                          }
                        }

                        return Center(
                          child: Container(
                            width: side,
                            height: side,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: _loading
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : hasBackendImage
                                ? (dataUriBytes != null
                                      ? Image.memory(
                                          dataUriBytes,
                                          width: side,
                                          height: side,
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, __, ___) {
                                            return BarcodeWidget(
                                              barcode: Barcode.qrCode(),
                                              data: effectivePayload,
                                              width: side,
                                              height: side,
                                              drawText: false,
                                            );
                                          },
                                        )
                                      : Image.network(
                                          _backendQrImageUrl!,
                                          width: side,
                                          height: side,
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, __, ___) {
                                            return BarcodeWidget(
                                              barcode: Barcode.qrCode(),
                                              data: effectivePayload,
                                              width: side,
                                              height: side,
                                              drawText: false,
                                            );
                                          },
                                        ))
                                : hasBackendPayload
                                ? BarcodeWidget(
                                    barcode: Barcode.qrCode(),
                                    data: effectivePayload,
                                    width: side,
                                    height: side,
                                    drawText: false,
                                  )
                                : Image.asset(
                                    widget.qrAssetPath,
                                    width: side,
                                    height: side,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) {
                                      return BarcodeWidget(
                                        barcode: Barcode.qrCode(),
                                        data: effectivePayload,
                                        width: side,
                                        height: side,
                                        drawText: false,
                                      );
                                    },
                                  ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Customer scans to pay with ${widget.method.displayName}',
                    style: AppTypography.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  if (_backendError != null && _backendError!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      _backendError!,
                      style: AppTypography.bodySmall.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ),
          Material(
            color: Theme.of(context).cardColor,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.success,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_rounded),
                        const SizedBox(width: 8),
                        Text('OK', style: AppTypography.buttonLarge),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
