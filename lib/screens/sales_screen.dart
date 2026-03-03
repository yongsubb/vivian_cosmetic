import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_strings.dart';
import '../core/constants/app_typography.dart';
import '../core/theme/theme_helper.dart';
import '../core/widgets/camera_permission_prompt.dart';
import '../core/utils/mobile_scanner_support.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../state/cart_provider.dart';
import 'checkout_screen.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true; // Keep state when switching tabs

  final ApiService _apiService = ApiService();
  double _taxRate = 0.12; // Default 12%
  String _selectedCategory = 'All';
  String? _selectedCategoryId;
  final _searchController = TextEditingController();

  bool _cartRestored = false;

  // If a reward was redeemed in this sale flow, keep the member applied so
  // checkout can attach the correct customer_id for receipts and refunds.
  Map<String, dynamic>? _preselectedLoyaltyMember;

  // Products loaded from API
  List<Product> _products = [];
  List<Map<String, dynamic>> _categories = [];
  bool _isLoading = true;
  bool _isLoadingCategories = true;
  String? _errorMessage;
  bool _wasCurrentBefore = false;

  List<CartItem> get _cartItems => context.watch<CartProvider>().items;

  CartProvider? get _cart {
    if (!mounted) return null;
    try {
      return context.read<CartProvider>();
    } catch (e) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isCurrent = ModalRoute.of(context)?.isCurrent == true;

    // Reload data when page becomes visible (switches to this tab)
    if (isCurrent && !_wasCurrentBefore) {
      _loadData();
    }

    _wasCurrentBefore = isCurrent;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only reload when app truly resumes from background (not when dialogs open/close)
    if (state == AppLifecycleState.resumed && _wasCurrentBefore) {
      _loadSettings();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  /// Load products and categories from API
  Future<void> _loadData() async {
    if (!mounted) return;

    await Future.wait([_loadProducts(), _loadCategories(), _loadSettings()]);

    // Load saved cart after products are loaded (only once per screen lifecycle)
    if (!_cartRestored && mounted) {
      _cartRestored = true;
      final cart = _cart;
      if (cart != null) {
        await cart.loadSavedCart(_products);
      }
    }
  }

  /// Load settings (tax rate)
  Future<void> _loadSettings() async {
    try {
      final response = await _apiService.getSetting('tax_rate');
      if (response.success && response.data != null) {
        if (mounted) {
          setState(() {
            // API returns {tax_rate: 12}, so extract the value
            final taxData = response.data as Map<String, dynamic>;
            final taxValue = taxData['tax_rate'] ?? 12;
            _taxRate = (double.tryParse(taxValue.toString()) ?? 12) / 100;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading tax rate: $e');
    }
  }

  /// Load products from API
  Future<void> _loadProducts() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _apiService.getProducts(
        categoryId: _selectedCategoryId,
        search: _searchController.text.isNotEmpty
            ? _searchController.text
            : null,
      );

      if (response.success && response.data != null) {
        if (!mounted) return;
        setState(() {
          _products = response.data!
              .map(
                (json) => Product(
                  id: json['id']?.toString() ?? '',
                  name: json['name'] ?? '',
                  category: json['category_name'] ?? 'Uncategorized',
                  categoryId: json['category_id']?.toString(),
                  price: (json['selling_price'] ?? 0).toDouble(),
                  pointsCost:
                      int.tryParse(json['points_cost']?.toString() ?? '') ?? 0,
                  promoPrice:
                      json['discount_percent'] != null &&
                          json['discount_percent'] > 0
                      ? (json['selling_price'] ?? 0).toDouble() *
                            (1 - (json['discount_percent'] / 100))
                      : null,
                  stock: json['stock_quantity'] ?? 0,
                  barcode: json['barcode'],
                  description: json['description']?.toString(),
                  imageUrl: ApiConfig.resolveMediaUrl(
                    json['image_url']?.toString(),
                  ),
                ),
              )
              .toList();
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = response.message ?? 'Failed to load products';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error loading products: $e';
        _isLoading = false;
      });
    }
  }

  /// Load categories from API
  Future<void> _loadCategories() async {
    if (!mounted) return;
    setState(() => _isLoadingCategories = true);

    try {
      final response = await _apiService.getCategories();
      if (response.success && response.data != null) {
        if (!mounted) return;
        setState(() {
          _categories = response.data!;
          _isLoadingCategories = false;
        });
      } else {
        if (!mounted) return;
        setState(() => _isLoadingCategories = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingCategories = false);
    }
  }

  /// Get category names list for filter chips
  List<String> get _categoryNames {
    final names = ['All'];
    names.addAll(
      _categories
          .map((c) => c['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty),
    );
    return names;
  }

  /// Get filtered products based on search (category already filtered via API)
  List<Product> get _filteredProducts {
    if (_searchController.text.isEmpty) {
      return _products;
    }
    return _products.where((product) {
      return product.name.toLowerCase().contains(
        _searchController.text.toLowerCase(),
      );
    }).toList();
  }

  double get _subtotal => context.watch<CartProvider>().subtotal;

  double get _tax => _subtotal * _taxRate;

  double get _total => _subtotal + _tax;

  int get _totalItems => context.watch<CartProvider>().totalItems;

  /// Check stock availability before adding to cart
  bool _canAddToCart(Product product, {int quantity = 1}) {
    return _cart?.canAdd(product, quantity: quantity) ?? false;
  }

  /// Get current cart quantity for a product
  int _getCartQuantity(String productId) {
    return _cart?.getQuantity(productId) ?? 0;
  }

  Future<void> _promptAddQuantity(Product product) async {
    final maxAddable = product.stock - _getCartQuantity(product.id);
    if (maxAddable <= 0) {
      _showStockError(
        'Cannot add more ${product.name}. Maximum stock: ${product.stock}',
      );
      return;
    }

    final qtyController = TextEditingController(text: '1');
    String? errorText;

    final selectedQty = await showDialog<int>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Quantity', style: AppTypography.heading4),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: AppTypography.labelMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Available: $maxAddable (Stock: ${product.stock})',
                    style: AppTypography.bodySmall.copyWith(
                      color: context.textSecondaryColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: qtyController,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      hintText: 'Enter quantity',
                      errorText: errorText,
                      isDense: true,
                    ),
                    onSubmitted: (value) {
                      final parsed = int.tryParse(value);
                      if (parsed == null || parsed <= 0) {
                        setDialogState(() {
                          errorText = 'Enter a valid quantity';
                        });
                        return;
                      }
                      if (parsed > maxAddable) {
                        setDialogState(() {
                          errorText = 'Max you can add is $maxAddable';
                        });
                        return;
                      }
                      Navigator.of(context).pop(parsed);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: maxAddable <= 0
                      ? null
                      : () {
                          final parsed = int.tryParse(qtyController.text);
                          if (parsed == null || parsed <= 0) {
                            setDialogState(() {
                              errorText = 'Enter a valid quantity';
                            });
                            return;
                          }
                          if (parsed > maxAddable) {
                            setDialogState(() {
                              errorText = 'Max you can add is $maxAddable';
                            });
                            return;
                          }
                          Navigator.of(context).pop(parsed);
                        },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );

    // IMPORTANT: Don't dispose immediately after pop.
    // The dialog route may still be in its closing animation and the TextField
    // can still be attached for a short time.
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      qtyController.dispose();
    });

    if (!mounted) return;
    if (selectedQty == null) return;

    _addToCart(product, quantity: selectedQty);
  }

  Future<void> _addToCart(Product product, {int quantity = 1}) async {
    // Reward-only (₱0) items should not be sold as normal products.
    // Redeemable products with a real selling price can still be purchased normally.
    if (product.isRewardOnlyRedeemable && !product.isRedeemedReward) {
      _showStockError(
        'This is a reward item. Scan the member Reward QR to redeem it.',
      );
      return;
    }

    // Check stock availability
    if (product.isOutOfStock) {
      _showStockError('${product.name} is out of stock');
      return;
    }

    if (!_canAddToCart(product, quantity: quantity)) {
      final cartQty = _getCartQuantity(product.id);
      _showStockError(
        'Cannot add more ${product.name}. Stock: ${product.stock}, In cart: $cartQty',
      );
      return;
    }

    final cart = _cart;
    if (cart == null) return;

    await cart.add(product, quantity: quantity);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                quantity == 1
                    ? '${product.name} added to cart'
                    : '$quantity × ${product.name} added to cart',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showStockError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.warning,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _setQuantity(int index, int quantity) async {
    final cart = _cart;
    if (cart == null) return;

    final items = cart.items;
    if (index < 0 || index >= items.length) return;

    final item = items[index];
    final maxStock = item.product.stock;

    if (quantity <= 0) {
      await cart.setQuantity(index, 0);
      return;
    }

    if (quantity > maxStock) {
      _showStockError(
        'Cannot add more ${item.product.name}. Maximum stock: $maxStock',
      );
      quantity = maxStock;
    }

    await cart.setQuantity(index, quantity);
  }

  Future<void> _updateQuantity(int index, int delta) async {
    final cart = _cart;
    if (cart == null) return;

    final items = cart.items;
    if (index < 0 || index >= items.length) return;
    final item = items[index];
    await _setQuantity(index, item.quantity + delta);
  }

  Future<void> _removeFromCart(int index) async {
    final cart = _cart;
    if (cart == null) return;
    await cart.removeAt(index);
  }

  /// Clear all items from the cart
  Future<void> _clearCart() async {
    final cart = _cart;
    if (cart == null) return;
    await cart.clear();
  }

  // ============================================================
  // Barcode Scanner Methods
  // ============================================================

  /// Open barcode scanner dialog
  void _openBarcodeScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _BarcodeScannerSheet(onBarcodeScanned: _handleBarcodeScanned),
    );
  }

  /// Handle scanned barcode
  Future<void> _handleBarcodeScanned(String barcode) async {
    if (!mounted) return;
    Navigator.of(context).pop(); // Close scanner

    final rewardPayload = _tryParseRewardRedeemPayload(barcode);
    if (rewardPayload != null) {
      await _redeemRewardFromQr(
        memberNumber: rewardPayload.$1,
        productId: rewardPayload.$2,
        quantity: rewardPayload.$3,
      );
      return;
    }

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );

    try {
      final response = await _apiService.getProductByBarcode(barcode);
      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading

      if (response.success && response.data != null) {
        final json = response.data!;
        final product = Product(
          id: json['id']?.toString() ?? '',
          name: json['name'] ?? '',
          category: json['category_name'] ?? 'Uncategorized',
          categoryId: json['category_id']?.toString(),
          price: (json['selling_price'] ?? 0).toDouble(),
          pointsCost: int.tryParse(json['points_cost']?.toString() ?? '') ?? 0,
          promoPrice:
              json['discount_percent'] != null && json['discount_percent'] > 0
              ? (json['selling_price'] ?? 0).toDouble() *
                    (1 - (json['discount_percent'] / 100))
              : null,
          stock: json['stock_quantity'] ?? 0,
          barcode: json['barcode'],
          description: json['description']?.toString(),
          imageUrl: ApiConfig.resolveMediaUrl(json['image_url']?.toString()),
        );

        _addToCart(product);
      } else {
        _showStockError('Product not found for barcode: $barcode');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading
      _showStockError('Error looking up barcode: $e');
    }
  }

  (String, int, int)? _tryParseRewardRedeemPayload(String raw) {
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

      return (memberBarcode, productId, quantity);
    } catch (_) {
      return null;
    }
  }

  Future<void> _redeemRewardFromQr({
    required String memberNumber,
    required int productId,
    required int quantity,
  }) async {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );

    try {
      final memberRes = await _apiService.scanMemberCard(memberNumber);
      if (!mounted) return;

      if (!memberRes.success || memberRes.data == null) {
        Navigator.of(context).pop();
        _showStockError(memberRes.message ?? 'Member not found');
        return;
      }

      final memberData = memberRes.data!;
      final memberId = int.tryParse(memberData['id']?.toString() ?? '');
      if (memberId == null || memberId <= 0) {
        Navigator.of(context).pop();
        _showStockError('Invalid member');
        return;
      }

      final redeemRes = await _apiService.redeemRewardProductForMember(
        memberId: memberId,
        productId: productId,
        quantity: quantity,
      );
      if (!mounted) return;

      Navigator.of(context).pop();

      if (!redeemRes.success) {
        _showStockError(redeemRes.message ?? 'Failed to redeem reward');
        return;
      }

      final product = redeemRes.data?['product'] as Map<String, dynamic>?;
      final productName = product?['name']?.toString() ?? 'Reward';
      final pointsSpent = redeemRes.data?['points_spent']?.toString();

      final cart = _cart;
      if (cart == null) {
        _showStockError('Cart is not available');
        return;
      }

      final redeemedProduct = Product(
        id: '$productId${Product.redeemedRewardMarker}',
        name: productName,
        category: product?['category_name']?.toString() ?? 'Rewards',
        categoryId: product?['category_id']?.toString(),
        price: 0,
        promoPrice: null,
        pointsCost:
            int.tryParse(product?['points_cost']?.toString() ?? '') ?? 0,
        stock:
            int.tryParse(product?['stock_quantity']?.toString() ?? '') ??
            (quantity > 0 ? quantity : 1),
        barcode: product?['barcode']?.toString(),
        imageUrl: ApiConfig.resolveMediaUrl(product?['image_url']?.toString()),
        description: Product.redeemedRewardMarker,
      );

      await cart.add(redeemedProduct, quantity: quantity);

      if (mounted) {
        setState(() {
          _preselectedLoyaltyMember = memberData;
        });
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pointsSpent != null
                ? 'Redeemed $productName (spent $pointsSpent points) — added to cart'
                : 'Redeemed $productName — added to cart',
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );

      // Refresh products to reflect stock changes.
      _loadProducts();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _showStockError('Failed to redeem reward: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(AppStrings.newSale),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadProducts,
            tooltip: 'Refresh Products',
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: _openBarcodeScanner,
            tooltip: 'Scan product / reward',
          ),
        ],
      ),
      body: Row(
        children: [
          // Products Section
          Expanded(
            flex: 2,
            child: Column(
              children: [
                // Search Bar
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _loadProducts(),
                    decoration: InputDecoration(
                      hintText: AppStrings.searchProducts,
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: context.textLightColor,
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _loadProducts();
                              },
                            )
                          : null,
                    ),
                  ),
                ),

                // Category Chips
                SizedBox(
                  height: 44,
                  child: _isLoadingCategories
                      ? const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _categoryNames.length,
                          itemBuilder: (context, index) {
                            final category = _categoryNames[index];
                            final isSelected = category == _selectedCategory;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(category),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setState(() {
                                    _selectedCategory = category;
                                    if (category == 'All') {
                                      _selectedCategoryId = null;
                                    } else {
                                      // Find category ID
                                      final cat = _categories.firstWhere(
                                        (c) => c['name'] == category,
                                        orElse: () => {},
                                      );
                                      _selectedCategoryId = cat['id']
                                          ?.toString();
                                    }
                                  });
                                  _loadProducts();
                                },
                              ),
                            );
                          },
                        ),
                ),

                const SizedBox(height: 8),

                // Product Grid with loading/error states
                Expanded(child: _buildProductGrid()),
              ],
            ),
          ),

          // Cart Section (visible on larger screens or as bottom sheet on mobile)
          if (MediaQuery.of(context).size.width > 600)
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Container(
                width: 320,
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                child: _buildCartSection(),
              ),
            ),
        ],
      ),

      // Mobile Cart Button
      floatingActionButton: MediaQuery.of(context).size.width <= 600
          ? Stack(
              clipBehavior: Clip.none,
              children: [
                FloatingActionButton(
                  heroTag: 'sales_cart_fab',
                  onPressed: () => _showCartBottomSheet(context),
                  child: const Icon(
                    Icons.shopping_cart_rounded,
                    color: Colors.white,
                  ),
                ),
                if (_totalItems > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Text(
                        _totalItems > 99 ? '99+' : '$_totalItems',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            )
          : null,

      // Checkout Button (Fixed at bottom for desktop)
      bottomNavigationBar:
          MediaQuery.of(context).size.width > 600 && _cartItems.isNotEmpty
          ? null
          : null,
    );
  }

  Widget _buildProductGrid() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 16),
            Text('Loading products...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: AppColors.error.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: context.textSecondaryColor,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadProducts,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredProducts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: AppColors.textLight.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No products found',
              style: AppTypography.heading4.copyWith(
                color: context.textSecondaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different search or category',
              style: AppTypography.bodySmall,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadProducts,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.75,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _filteredProducts.length,
        itemBuilder: (context, index) {
          final product = _filteredProducts[index];
          final cartQty = _getCartQuantity(product.id);
          return _ProductCard(
            product: product,
            cartQuantity: cartQty,
            onTap: () => _promptAddQuantity(product),
          );
        },
      ),
    );
  }

  Widget _buildCartSection() {
    return Column(
      children: [
        // Cart Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.secondary.withValues(alpha: 0.5),
          ),
          child: Row(
            children: [
              const Icon(Icons.shopping_cart_rounded, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(AppStrings.cart, style: AppTypography.heading4),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_totalItems items',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.white,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Cart Items
        Expanded(
          child: _cartItems.isEmpty
              ? _buildEmptyCart()
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _cartItems.length,
                  itemBuilder: (context, index) {
                    final item = _cartItems[index];
                    final isRedeemed = item.product.isRedeemedReward;
                    return _CartItemCard(
                      key: ValueKey(item.product.id),
                      item: item,
                      onQuantityChanged: (delta) {
                        if (isRedeemed) return;
                        _updateQuantity(index, delta);
                      },
                      onQuantitySet: (value) {
                        if (isRedeemed) return;
                        _setQuantity(index, value);
                      },
                      onRemove: () => _removeFromCart(index),
                    );
                  },
                ),
        ),

        // Cart Summary
        if (_cartItems.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Column(
              children: [
                _SummaryRow(
                  label: AppStrings.subtotal,
                  value: '₱ ${_subtotal.toStringAsFixed(2)}',
                ),
                const SizedBox(height: 8),
                _SummaryRow(
                  label: 'Tax (${(_taxRate * 100).toStringAsFixed(0)}%)',
                  value: '₱ ${_tax.toStringAsFixed(2)}',
                ),
                const Divider(height: 20),
                _SummaryRow(
                  label: AppStrings.total,
                  value: '₱ ${_total.toStringAsFixed(2)}',
                  isTotal: true,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => CheckoutScreen(
                            cartItems: _cartItems,
                            subtotal: _subtotal,
                            tax: _tax,
                            total: _total,
                            initialLoyaltyMember: _preselectedLoyaltyMember,
                          ),
                        ),
                      );
                      // Clear cart and reload data after returning from checkout/payment
                      await _clearCart();
                      if (mounted) {
                        setState(() {
                          _preselectedLoyaltyMember = null;
                        });
                      }
                      _loadData(); // Refresh products, categories, and settings
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.shopping_cart_checkout_rounded),
                        const SizedBox(width: 8),
                        Text(
                          AppStrings.checkout,
                          style: AppTypography.buttonLarge,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyCart() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.secondary,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shopping_cart_outlined,
              size: 48,
              color: AppColors.textLight,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            AppStrings.emptyCart,
            style: AppTypography.heading4.copyWith(
              color: context.textSecondaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(AppStrings.addItems, style: AppTypography.bodySmall),
        ],
      ),
    );
  }

  void _showCartBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              return Column(
                children: [
                  // Handle
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  Expanded(child: _buildCartSection()),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final int cartQuantity;
  final VoidCallback onTap;

  const _ProductCard({
    required this.product,
    required this.onTap,
    this.cartQuantity = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: product.isOutOfStock ? null : onTap,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product Image
                Expanded(
                  flex: 3,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.secondary,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      child:
                          product.imageUrl != null &&
                              product.imageUrl!.isNotEmpty
                          ? Image.network(
                              product.imageUrl!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              errorBuilder: (context, error, stackTrace) {
                                return Center(
                                  child: Icon(
                                    _getCategoryIcon(product.category),
                                    size: 40,
                                    color: AppColors.primary.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                );
                              },
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Center(
                                      child: CircularProgressIndicator(
                                        value:
                                            loadingProgress
                                                    .expectedTotalBytes !=
                                                null
                                            ? loadingProgress
                                                      .cumulativeBytesLoaded /
                                                  loadingProgress
                                                      .expectedTotalBytes!
                                            : null,
                                        strokeWidth: 2,
                                      ),
                                    );
                                  },
                            )
                          : Center(
                              child: Icon(
                                _getCategoryIcon(product.category),
                                size: 40,
                                color: AppColors.primary.withValues(alpha: 0.5),
                              ),
                            ),
                    ),
                  ),
                ),

                // Product Info
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: AppTypography.labelMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            if (product.hasPromoPrice) ...[
                              Text(
                                '₱${product.price.toStringAsFixed(0)}',
                                style: AppTypography.caption.copyWith(
                                  decoration: TextDecoration.lineThrough,
                                  color: AppColors.textLight,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              '₱${product.effectivePrice.toStringAsFixed(0)}',
                              style: AppTypography.priceRegular.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Stock Badge
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: product.isOutOfStock
                      ? AppColors.error
                      : product.isLowStock
                      ? AppColors.warning
                      : AppColors.success,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  product.isOutOfStock
                      ? 'Out of Stock'
                      : '${product.stock} in stock',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.white,
                    fontSize: 9,
                  ),
                ),
              ),
            ),

            // Promo Badge
            if (product.hasPromoPrice)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'SALE',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 9,
                    ),
                  ),
                ),
              ),

            // Out of Stock Overlay
            if (product.isOutOfStock)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.white.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),

            // Cart Quantity Badge
            if (cartQuantity > 0)
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.shopping_cart_rounded,
                        size: 12,
                        color: AppColors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$cartQuantity',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.bold,
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

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Lipstick':
        return Icons.brush_rounded;
      case 'Foundation':
        return Icons.format_paint_rounded;
      case 'Skincare':
        return Icons.water_drop_rounded;
      case 'Eye Makeup':
        return Icons.visibility_rounded;
      case 'Fragrance':
        return Icons.air_rounded;
      default:
        return Icons.shopping_bag_rounded;
    }
  }
}

class _CartItemCard extends StatelessWidget {
  final CartItem item;
  final ValueChanged<int> onQuantityChanged;
  final ValueChanged<int> onQuantitySet;
  final VoidCallback onRemove;

  const _CartItemCard({
    super.key,
    required this.item,
    required this.onQuantityChanged,
    required this.onQuantitySet,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isRedeemed = item.product.isRedeemedReward;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Product Image
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppColors.secondary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child:
                  item.product.imageUrl != null &&
                      item.product.imageUrl!.isNotEmpty
                  ? Image.network(
                      item.product.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.shopping_bag_outlined,
                          color: AppColors.primary,
                        );
                      },
                    )
                  : const Icon(
                      Icons.shopping_bag_outlined,
                      color: AppColors.primary,
                    ),
            ),
          ),
          const SizedBox(width: 12),

          // Product Info
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
                  '₱${item.product.effectivePrice.toStringAsFixed(2)}',
                  style: AppTypography.priceSmall.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),

          // Quantity Controls
          _CartQuantityControls(
            quantity: item.quantity,
            onQuantityChanged: onQuantityChanged,
            onQuantitySet: onQuantitySet,
          ),
        ],
      ),
    );
  }
}

class _CartQuantityControls extends StatefulWidget {
  final int quantity;
  final ValueChanged<int> onQuantityChanged;
  final ValueChanged<int> onQuantitySet;

  const _CartQuantityControls({
    required this.quantity,
    required this.onQuantityChanged,
    required this.onQuantitySet,
  });

  @override
  State<_CartQuantityControls> createState() => _CartQuantityControlsState();
}

class _CartQuantityControlsState extends State<_CartQuantityControls> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.quantity.toString());
  }

  @override
  void didUpdateWidget(covariant _CartQuantityControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    final expected = widget.quantity.toString();
    if (_controller.text != expected) {
      _controller.text = expected;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    final parsed = int.tryParse(_controller.text);
    if (parsed == null) {
      _controller.text = widget.quantity.toString();
      return;
    }
    widget.onQuantitySet(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _QuantityButton(
          icon: Icons.remove,
          onTap: () => widget.onQuantityChanged(-1),
        ),
        SizedBox(
          width: 44,
          child: TextField(
            controller: _controller,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => _commit(),
            onTapOutside: (_) => _commit(),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 6, horizontal: 6),
              border: OutlineInputBorder(borderSide: BorderSide.none),
              filled: true,
              fillColor: AppColors.white,
            ),
            style: AppTypography.labelLarge,
          ),
        ),
        _QuantityButton(
          icon: Icons.add,
          onTap: () => widget.onQuantityChanged(1),
        ),
      ],
    );
  }
}

class _QuantityButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _QuantityButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: AppColors.primary),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isTotal;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.isTotal = false,
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
              : AppTypography.priceRegular.copyWith(
                  color: context.textPrimaryColor,
                ),
        ),
      ],
    );
  }
}

// ============================================================
// Barcode Scanner Sheet
// ============================================================

class _BarcodeScannerSheet extends StatefulWidget {
  final Function(String) onBarcodeScanned;

  const _BarcodeScannerSheet({required this.onBarcodeScanned});

  @override
  State<_BarcodeScannerSheet> createState() => _BarcodeScannerSheetState();
}

class _BarcodeScannerSheetState extends State<_BarcodeScannerSheet> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  bool _isScanned = false;
  bool _torchOn = false;
  bool _didShowCameraPermissionDialog = false;
  final _manualBarcodeController = TextEditingController();

  @override
  void dispose() {
    try {
      _scannerController.dispose();
    } catch (_) {}
    _manualBarcodeController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isScanned) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
      setState(() => _isScanned = true);
      widget.onBarcodeScanned(barcodes.first.rawValue!);
    }
  }

  void _submitManualBarcode() {
    final barcode = _manualBarcodeController.text.trim();
    if (barcode.isNotEmpty) {
      widget.onBarcodeScanned(barcode);
    }
  }

  void _maybeShowCameraPermissionDialog(MobileScannerException error) {
    if (_didShowCameraPermissionDialog) return;
    if (error.errorCode != MobileScannerErrorCode.permissionDenied) return;

    _didShowCameraPermissionDialog = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showEnableCameraDialog(
        context: context,
        onRetry: () async {
          try {
            await _scannerController.start();
          } catch (_) {
            // If the permission is still denied, the scanner will keep showing
            // the error UI and the user can enable it in settings.
          }
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final supported = isMobileScannerSupported;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.dividerColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text('Scan Product / Reward', style: AppTypography.heading4),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    _torchOn ? Icons.flash_on : Icons.flash_off,
                    color: _torchOn
                        ? AppColors.warning
                        : context.textSecondaryColor,
                  ),
                  onPressed: supported
                      ? () {
                          setState(() => _torchOn = !_torchOn);
                          try {
                            _scannerController.toggleTorch();
                          } catch (_) {}
                        }
                      : null,
                ),
                IconButton(
                  icon: Icon(Icons.close, color: context.textSecondaryColor),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Scanner View
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary, width: 2),
              ),
              clipBehavior: Clip.hardEdge,
              child: Stack(
                children: [
                  if (supported) ...[
                    MobileScanner(
                      controller: _scannerController,
                      onDetect: _onDetect,
                      errorBuilder: (context, error, child) {
                        _maybeShowCameraPermissionDialog(error);
                        return CameraPermissionInlineMessage(
                          onEnable: () {
                            showEnableCameraDialog(
                              context: context,
                              onRetry: () async {
                                try {
                                  await _scannerController.start();
                                } catch (_) {}
                              },
                            );
                          },
                        );
                      },
                    ),
                    // Scan overlay
                    Center(
                      child: Container(
                        width: 250,
                        height: 100,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AppColors.primary,
                            width: 3,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ] else ...[
                    const ScannerUnsupportedInlineMessage(),
                  ],
                ],
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(
              'You can scan normal product barcodes or Reward QR codes.',
              style: AppTypography.bodySmall.copyWith(
                color: context.textSecondaryColor,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: 16),

          // Manual Entry
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Or enter barcode manually:',
                  style: AppTypography.bodySmall.copyWith(
                    color: context.textSecondaryColor,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manualBarcodeController,
                        decoration: const InputDecoration(
                          hintText: 'Enter barcode number',
                          prefixIcon: Icon(Icons.dialpad_rounded),
                        ),
                        keyboardType: TextInputType.number,
                        onSubmitted: (_) => _submitManualBarcode(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _submitManualBarcode,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                      ),
                      child: const Text('Add'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
