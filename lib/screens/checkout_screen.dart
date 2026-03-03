import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_strings.dart';
import '../core/constants/app_typography.dart';
import '../core/theme/theme_helper.dart';
import '../core/widgets/camera_permission_prompt.dart';
import '../core/utils/mobile_scanner_support.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import 'payment_screen.dart';

class _RewardRedeemQrPayload {
  final String memberNumber;
  final int productId;
  final int quantity;

  const _RewardRedeemQrPayload({
    required this.memberNumber,
    required this.productId,
    required this.quantity,
  });
}

class CheckoutScreen extends StatefulWidget {
  final List<CartItem> cartItems;
  final double subtotal;
  final double tax;
  final double total;
  final Map<String, dynamic>? initialLoyaltyMember;

  const CheckoutScreen({
    super.key,
    required this.cartItems,
    required this.subtotal,
    required this.tax,
    required this.total,
    this.initialLoyaltyMember,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _apiService = ApiService();
  final _loyaltySearchController = TextEditingController();
  double _discount = 0;
  Map<String, dynamic>? _loyaltyMember;
  bool _isSearchingMember = false;
  Map<String, dynamic>? _selectedCustomer;

  double get _finalTotal => widget.subtotal + widget.tax - _discount;

  @override
  void initState() {
    super.initState();

    final initial = widget.initialLoyaltyMember;
    if (initial != null) {
      final tier = initial['tier'] as Map<String, dynamic>?;
      final discountPercent = tier?['discount_percent'] ?? 0;

      double calculatedDiscount = 0;
      if (discountPercent is num && discountPercent > 0) {
        calculatedDiscount = widget.subtotal * (discountPercent / 100);
      }

      _loyaltyMember = initial;
      _selectedCustomer = initial['customer'] as Map<String, dynamic>?;
      _discount = calculatedDiscount;
    }
  }

  @override
  void dispose() {
    _loyaltySearchController.dispose();
    super.dispose();
  }

  Future<void> _searchLoyaltyMember() async {
    final searchQuery = _loyaltySearchController.text.trim();
    if (searchQuery.isEmpty) return;

    setState(() => _isSearchingMember = true);

    try {
      // Try scanning by barcode first
      final response = await _apiService.scanMemberCard(searchQuery);

      if (mounted) {
        setState(() => _isSearchingMember = false);

        if (response.success && response.data != null) {
          final memberData = response.data!;
          final tier = memberData['tier'] as Map<String, dynamic>?;
          final discountPercent = tier?['discount_percent'] ?? 0;

          double calculatedDiscount = 0;
          if (discountPercent > 0) {
            calculatedDiscount = widget.subtotal * (discountPercent / 100);
          }

          setState(() {
            _loyaltyMember = memberData;
            _discount = calculatedDiscount;
            // Also set as selected customer
            _selectedCustomer = memberData['customer'] as Map<String, dynamic>?;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: AppColors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Loyalty member applied! $discountPercent% discount (₱${calculatedDiscount.toStringAsFixed(2)})',
                      ),
                    ),
                  ],
                ),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          }
        } else {
          _showError(response.message ?? 'Member not found');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearchingMember = false);
        _showError('Error searching member: $e');
      }
    }
  }

  void _removeLoyaltyMember() {
    setState(() {
      _loyaltyMember = null;
      _discount = 0;
      _loyaltySearchController.clear();
    });
  }

  Future<void> _startBarcodeScanner() async {
    if (!isMobileScannerSupported) {
      await showScannerUnsupportedDialog(context);
      return;
    }

    final scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
    var didShowCameraPermissionDialog = false;

    void maybeShowCameraPermissionDialog(MobileScannerException error) {
      if (didShowCameraPermissionDialog) return;
      if (error.errorCode != MobileScannerErrorCode.permissionDenied) return;

      didShowCameraPermissionDialog = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showEnableCameraDialog(
          context: context,
          onRetry: () async {
            try {
              await scannerController.start();
            } catch (_) {}
          },
        );
      });
    }

    await showDialog(
      context: context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: 400,
          height: 500,
          child: Column(
            children: [
              AppBar(
                title: const Text('Scan Loyalty / Reward QR'),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Expanded(
                child: MobileScanner(
                  controller: scannerController,
                  onDetect: (capture) {
                    final List<Barcode> barcodes = capture.barcodes;
                    if (barcodes.isNotEmpty) {
                      final barcode = barcodes.first.rawValue;
                      if (barcode != null) {
                        final rewardPayload = _tryParseRewardRedeemPayload(
                          barcode,
                        );
                        Navigator.pop(context);
                        if (rewardPayload != null) {
                          _redeemRewardFromQr(rewardPayload);
                          return;
                        }

                        _loyaltySearchController.text = barcode;
                        _searchLoyaltyMember();
                      }
                    }
                  },
                  errorBuilder: (context, error, child) {
                    maybeShowCameraPermissionDialog(error);
                    return CameraPermissionInlineMessage(
                      onEnable: () {
                        showEnableCameraDialog(
                          context: context,
                          onRetry: () async {
                            try {
                              await scannerController.start();
                            } catch (_) {}
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    scannerController.dispose();
  }

  _RewardRedeemQrPayload? _tryParseRewardRedeemPayload(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    String jsonString = trimmed;
    if (trimmed.startsWith('reward:')) {
      jsonString = trimmed.substring('reward:'.length).trim();
    }

    if (!(jsonString.startsWith('{') && jsonString.endsWith('}'))) {
      return null;
    }

    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is! Map) return null;
      final map = decoded.cast<String, dynamic>();
      final type = map['type']?.toString();
      if (type != 'reward_redeem') return null;

      final memberBarcode = (map['card_barcode'] ?? map['member_number'])
          ?.toString()
          .trim();
      final productId = int.tryParse(map['product_id']?.toString() ?? '');
      final quantity = int.tryParse(map['quantity']?.toString() ?? '') ?? 1;

      if (memberBarcode == null || memberBarcode.isEmpty) return null;
      if (productId == null || productId <= 0) return null;
      if (quantity <= 0) return null;

      return _RewardRedeemQrPayload(
        memberNumber: memberBarcode,
        productId: productId,
        quantity: quantity,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _redeemRewardFromQr(_RewardRedeemQrPayload payload) async {
    if (!mounted) return;

    setState(() => _isSearchingMember = true);
    try {
      final memberRes = await _apiService.scanMemberCard(payload.memberNumber);
      if (!mounted) return;
      if (!memberRes.success || memberRes.data == null) {
        setState(() => _isSearchingMember = false);
        _showError(memberRes.message ?? 'Member not found');
        return;
      }

      final memberData = memberRes.data!;
      final memberId = int.tryParse(memberData['id']?.toString() ?? '');
      if (memberId == null || memberId <= 0) {
        setState(() => _isSearchingMember = false);
        _showError('Invalid member');
        return;
      }

      final redeemRes = await _apiService.redeemRewardProductForMember(
        memberId: memberId,
        productId: payload.productId,
        quantity: payload.quantity,
      );

      if (!mounted) return;
      setState(() => _isSearchingMember = false);

      if (!redeemRes.success) {
        _showError(redeemRes.message ?? 'Failed to redeem reward');
        return;
      }

      // Keep the member applied to this checkout as well.
      setState(() {
        _loyaltyMember = memberData;
        _selectedCustomer = memberData['customer'] as Map<String, dynamic>?;
      });

      final product = redeemRes.data?['product'] as Map<String, dynamic>?;
      final productName = product?['name']?.toString() ?? 'Reward';
      final pointsSpent = redeemRes.data?['points_spent']?.toString();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pointsSpent != null
                ? 'Redeemed $productName (spent $pointsSpent points)'
                : 'Redeemed $productName',
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSearchingMember = false);
      _showError('Failed to redeem reward: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _proceedToPayment() {
    final hasRedeemedRewards = widget.cartItems.any(
      (e) => e.product.isRedeemedReward,
    );
    if (hasRedeemedRewards && _selectedCustomer == null) {
      _showError(
        'This sale includes redeemed rewards. Please scan/apply the member card before proceeding so points can be restored on refunds.',
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PaymentScreen(
          total: _finalTotal,
          cartItems: widget.cartItems,
          subtotal: widget.subtotal,
          tax: widget.tax,
          discount: _discount,
          voucherCode: null,
          customerId: _selectedCustomer != null
              ? _selectedCustomer!['id'] as int?
              : null,
          loyaltyMemberId: _loyaltyMember != null
              ? _loyaltyMember!['id'] as int?
              : null,
        ),
      ),
    );
  }

  Widget _buildCheckoutFormContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Order Summary Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.receipt_long_rounded,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Order Summary', style: AppTypography.heading4),
                Text(
                  '${widget.cartItems.length} items',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Order Items
        Container(
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: widget.cartItems.map((item) {
              return _OrderItem(item: item);
            }).toList(),
          ),
        ),

        const SizedBox(height: 24),

        // Loyalty Member Section
        Text('Loyalty Member Discount', style: AppTypography.labelLarge),
        const SizedBox(height: 12),

        if (_loyaltyMember != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFE91E63).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFE91E63).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: Color(0xFFE91E63),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.card_membership,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _loyaltyMember!['customer']['name'] ?? '',
                        style: AppTypography.labelLarge.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _getTierColor(
                                _loyaltyMember!['tier']?['color'],
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _loyaltyMember!['tier']?['name'] ?? 'Member',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_loyaltyMember!['tier']?['discount_percent'] ?? 0}% discount',
                            style: AppTypography.caption.copyWith(
                              color: const Color(0xFFE91E63),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _removeLoyaltyMember,
                  color: Colors.grey,
                ),
              ],
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _loyaltySearchController,
                  decoration: InputDecoration(
                    hintText: 'Scan or enter member ID',
                    prefixIcon: Icon(
                      Icons.card_membership,
                      color: context.textLightColor,
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(
                        Icons.qr_code_scanner,
                        color: Color(0xFFE91E63),
                      ),
                      onPressed: _startBarcodeScanner,
                      tooltip: 'Scan barcode',
                    ),
                  ),
                  onSubmitted: (_) => _searchLoyaltyMember(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _isSearchingMember ? null : _searchLoyaltyMember,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                ),
                child: _isSearchingMember
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Apply'),
              ),
            ],
          ),

        const SizedBox(height: 24),

        // Customer Info (Optional)
        _buildCustomerSection(),
      ],
    );
  }

  Widget _buildSummaryPanel({required bool isWide}) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SummaryRow(
          label: AppStrings.subtotal,
          value: '₱ ${widget.subtotal.toStringAsFixed(2)}',
        ),
        const SizedBox(height: 8),
        _SummaryRow(
          label: widget.subtotal > 0
              ? 'Tax (${((widget.tax / widget.subtotal) * 100).toStringAsFixed(0)}%)'
              : 'Tax (0%)',
          value: '₱ ${widget.tax.toStringAsFixed(2)}',
        ),
        if (_discount > 0) ...[
          const SizedBox(height: 8),
          _SummaryRow(
            label: AppStrings.discount,
            value: '- ₱ ${_discount.toStringAsFixed(2)}',
            isDiscount: true,
          ),
        ],
        const Divider(height: 24),
        _SummaryRow(
          label: AppStrings.total,
          value: '₱ ${_finalTotal.toStringAsFixed(2)}',
          isTotal: true,
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton(
            onPressed: _proceedToPayment,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.payment_rounded),
                const SizedBox(width: 8),
                Text(
                  AppStrings.proceedToPayment,
                  style: AppTypography.buttonLarge,
                ),
              ],
            ),
          ),
        ),
      ],
    );

    if (!isWide) {
      return Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          child: SafeArea(child: content),
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(padding: const EdgeInsets.all(20), child: content),
    );
  }

  Widget _buildMobileBody() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _buildCheckoutFormContent(),
          ),
        ),
        _buildSummaryPanel(isWide: false),
      ],
    );
  }

  Widget _buildWideBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
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
              padding: const EdgeInsets.all(28),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: _buildCheckoutFormContent(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  SizedBox(width: 380, child: _buildSummaryPanel(isWide: true)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 980;

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            title: const Text(AppStrings.checkout),
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: isWide ? _buildWideBody() : _buildMobileBody(),
        );
      },
    );
  }

  Color _getTierColor(String? colorHex) {
    if (colorHex == null) return const Color(0xFFE91E63);
    try {
      return Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
    } catch (e) {
      return const Color(0xFFE91E63);
    }
  }

  Widget _buildCustomerSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.person_outline_rounded,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text('Customer (Optional)', style: AppTypography.labelLarge),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(
              hintText: 'Customer name',
              prefixIcon: Icon(
                Icons.badge_outlined,
                color: context.textLightColor,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              hintText: 'Phone number',
              prefixIcon: Icon(
                Icons.phone_outlined,
                color: context.textLightColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderItem extends StatelessWidget {
  final CartItem item;

  const _OrderItem({required this.item});

  @override
  Widget build(BuildContext context) {
    final isRedeemed = item.product.isRedeemedReward;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: context.dividerColor.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppColors.secondary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.shopping_bag_outlined,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.product.name,
                        style: AppTypography.labelMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isRedeemed) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: AppColors.success.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          'REDEEMED',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.success,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '₱${item.product.effectivePrice.toStringAsFixed(2)} × ${item.quantity}',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
          Text(
            '₱${item.total.toStringAsFixed(2)}',
            style: AppTypography.priceRegular.copyWith(
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isTotal;
  final bool isDiscount;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.isTotal = false,
    this.isDiscount = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: isTotal
              ? AppTypography.heading4
              : AppTypography.bodyMedium.copyWith(
                  color: context.textSecondaryColor,
                ),
        ),
        Text(
          value,
          style: isTotal
              ? AppTypography.priceLarge
              : isDiscount
              ? AppTypography.priceRegular.copyWith(color: AppColors.success)
              : AppTypography.priceRegular.copyWith(
                  color: context.textPrimaryColor,
                ),
        ),
      ],
    );
  }
}
