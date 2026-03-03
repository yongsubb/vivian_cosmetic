import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_strings.dart';
import '../core/constants/app_typography.dart';
import '../core/theme/theme_helper.dart';
import '../core/widgets/camera_permission_prompt.dart';
import '../core/utils/mobile_scanner_support.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // Keep state when switching tabs

  final ApiService _apiService = ApiService();
  final _searchController = TextEditingController();
  Timer? _debounceTimer;

  // State
  bool _isLoading = true;
  String? _error;
  List<Product> _products = [];
  List<Map<String, dynamic>> _categories = [];
  String _selectedCategoryId = 'all';
  bool _wasCurrentBefore = false;

  @override
  void initState() {
    super.initState();
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
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    await Future.wait([_loadCategories(), _loadProducts()]);

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _onRefresh() async {
    await _loadData();
  }

  Future<void> _loadCategories() async {
    final response = await _apiService.getCategories();
    if (mounted && response.success && response.data != null) {
      setState(() {
        _categories = response.data!;
      });
    }
  }

  Future<void> _loadProducts() async {
    final response = await _apiService.getProducts(
      categoryId: _selectedCategoryId == 'all' ? null : _selectedCategoryId,
      search: _searchController.text.isNotEmpty ? _searchController.text : null,
    );

    if (mounted) {
      if (response.success && response.data != null) {
        setState(() {
          _products = response.data!
              .map(
                (p) => Product(
                  id: p['id'].toString(),
                  name: p['name'] ?? '',
                  category: p['category_name'] ?? '',
                  price: (p['selling_price'] ?? 0).toDouble(),
                  promoPrice:
                      p['discount_percent'] != null &&
                          (p['discount_percent'] as num) > 0
                      ? (p['final_price'] ?? p['selling_price']).toDouble()
                      : null,
                  pointsCost: (p['points_cost'] as int?) ?? 0,
                  stock: p['stock_quantity'] ?? 0,
                  barcode: p['barcode'],
                  imageUrl: ApiConfig.resolveMediaUrl(
                    p['image_url']?.toString(),
                  ),
                  description: p['description'],
                ),
              )
              .toList();
          _error = null;
        });
      } else {
        setState(() {
          _error = response.message ?? 'Failed to load products';
        });
      }
    }
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _loadProducts();
    });
  }

  void _onCategorySelected(String categoryId) {
    setState(() {
      _selectedCategoryId = categoryId;
    });
    _loadProducts();
  }

  Future<void> _removeCategory(String categoryId, String categoryName) async {
    final id = int.tryParse(categoryId);
    if (id == null) {
      _showSnackBar('Invalid category', isError: true);
      return;
    }

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove Category'),
            content: Text(
              'Remove "$categoryName"?\n\n'
              'This will hide the category from the list.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final response = await _apiService.deleteCategory(id);
      if (!mounted) return;
      Navigator.pop(context);

      if (response.success) {
        if (_selectedCategoryId == categoryId) {
          setState(() => _selectedCategoryId = 'all');
        }
        await _loadCategories();
        await _loadProducts();
        _showSnackBar('Category removed');
      } else {
        _showSnackBar(
          response.message ?? 'Failed to remove category',
          isError: true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showSnackBar('Failed to remove category', isError: true);
    }
  }

  List<Map<String, dynamic>> get _allCategories {
    return [
      {'id': 'all', 'name': 'All'},
      ..._categories,
    ];
  }

  int get _lowStockCount => _products.where((p) => p.isLowStock).length;
  int get _outOfStockCount => _products.where((p) => p.isOutOfStock).length;

  double? _tryParseDouble(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  int? _tryParseInt(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    return int.tryParse(s);
  }

  _ScannedProductPayload _parseScannedProductPayload(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const _ScannedProductPayload();

    // 1) JSON payload (recommended)
    if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('product:{') && trimmed.endsWith('}'))) {
      final jsonString = trimmed.startsWith('product:')
          ? trimmed.substring('product:'.length)
          : trimmed;
      try {
        final decoded = jsonDecode(jsonString);
        if (decoded is Map) {
          final name = decoded['name'] ?? decoded['product_name'];
          final barcode = decoded['barcode'] ?? decoded['code'];
          final description = decoded['description'] ?? decoded['details'];
          final categoryId = decoded['category_id'] ?? decoded['categoryId'];
          final categoryName =
              decoded['category_name'] ??
              decoded['categoryName'] ??
              decoded['category'];
          final price = decoded['selling_price'] ?? decoded['price'];
          final stock = decoded['stock_quantity'] ?? decoded['stock'];

          return _ScannedProductPayload(
            name: name?.toString(),
            barcode: barcode?.toString(),
            description: description?.toString(),
            price: _tryParseDouble(price),
            stock: _tryParseInt(stock),
            categoryId: _tryParseInt(categoryId),
            categoryName: categoryName?.toString(),
          );
        }
      } catch (_) {}
    }

    // 2) URL/query-string style
    try {
      final uri = Uri.parse(trimmed);
      if (uri.hasQuery) {
        final qp = uri.queryParameters;
        final name = qp['name'] ?? qp['product_name'];
        final barcode = qp['barcode'] ?? qp['code'];
        final description = qp['description'];
        final categoryId = qp['category_id'] ?? qp['categoryId'];
        final categoryName = qp['category_name'] ?? qp['categoryName'];
        final price = qp['selling_price'] ?? qp['price'];
        final stock = qp['stock_quantity'] ?? qp['stock'];

        if (name != null || barcode != null || price != null || stock != null) {
          return _ScannedProductPayload(
            name: name,
            barcode: barcode,
            description: description,
            price: _tryParseDouble(price),
            stock: _tryParseInt(stock),
            categoryId: _tryParseInt(categoryId),
            categoryName: categoryName,
          );
        }
      }
    } catch (_) {}

    // 3) Pipe delimited: name|price|stock|barcode|description
    final parts = trimmed.split('|').map((p) => p.trim()).toList();
    if (parts.length >= 3 && parts.length <= 5) {
      final price = _tryParseDouble(parts[1]);
      final stock = _tryParseInt(parts[2]);
      if (price != null || stock != null) {
        return _ScannedProductPayload(
          name: parts.isNotEmpty ? parts[0] : null,
          price: price,
          stock: stock,
          barcode: parts.length >= 4 ? parts[3] : null,
          description: parts.length >= 5 ? parts[4] : null,
        );
      }
    }

    // Default: treat as a plain barcode/QR raw value.
    return _ScannedProductPayload(barcode: trimmed);
  }

  bool _looksLikeBarcodeForLookup(String value) {
    final v = value.trim();
    if (v.isEmpty) return false;
    if (v.length > 64) return false;
    if (RegExp(r'\s').hasMatch(v)) return false;
    return true;
  }

  bool _looksLikePaymentQr(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return false;
    // Common EMVCo payment QR patterns (PH/QRPH, Maya/GCash-style, etc.).
    if (v.startsWith('000201')) return true;
    final lower = v.toLowerCase();
    if (lower.contains('p2pqrpay')) return true;
    if (lower.contains('com.p2pqrpay')) return true;
    return false;
  }

  Future<bool> _confirmUseRawAsBarcode(String raw) async {
    final preview = raw.trim();
    final shortPreview = preview.length > 60
        ? '${preview.substring(0, 60)}…'
        : preview;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Not a product QR'),
        content: Text(
          'This looks like a payment/other QR code, not a product QR/barcode.\n\n'
          'Scanned value:\n$shortPreview\n\n'
          'To auto-fill Name/Price/Stock, scan a product QR that contains product data (JSON) or scan a normal barcode.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Use as barcode anyway'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  Future<void> _startScanFromCatalog() async {
    final raw = await _showBarcodeScannerForResult();
    if (raw == null || !mounted) return;

    final payload = _parseScannedProductPayload(raw);
    if (payload.hasNonBarcodeFields) {
      _showAddProductDialog(
        initialName: payload.name,
        initialPrice: payload.price,
        initialStock: payload.stock,
        initialBarcode: payload.barcode,
        initialDescription: payload.description,
        initialCategoryId: payload.categoryId?.toString(),
        initialCategoryName: payload.categoryName,
      );
      return;
    }

    final barcode = (payload.barcode ?? '').trim();
    if (barcode.isEmpty) return;
    if (!_looksLikeBarcodeForLookup(barcode) || _looksLikePaymentQr(raw)) {
      _showSnackBar(
        'This QR is not a product barcode. Scan a product QR or a normal barcode.',
        isError: true,
      );
      return;
    }
    await _lookupBarcode(barcode);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(AppStrings.productCatalog),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadData,
            tooltip: 'Reload',
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: _isLoading ? null : _startScanFromCatalog,
            tooltip: AppStrings.scanBarcode,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildErrorState()
          : RefreshIndicator(
              onRefresh: _onRefresh,
              child: Column(
                children: [
                  // Search Bar
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
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

                  // Category Tabs
                  SizedBox(
                    height: 44,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _allCategories.length,
                      itemBuilder: (context, index) {
                        final category = _allCategories[index];
                        final categoryId = category['id'].toString();
                        final categoryName = category['name'] as String;
                        final isSelected = categoryId == _selectedCategoryId;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onLongPress: categoryId == 'all'
                                ? null
                                : () =>
                                      _removeCategory(categoryId, categoryName),
                            child: FilterChip(
                              label: Text(categoryName),
                              selected: isSelected,
                              onSelected: (selected) {
                                _onCategorySelected(categoryId);
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Stats Row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        _StatChip(
                          label: 'Total Products',
                          value: '${_products.length}',
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 12),
                        _StatChip(
                          label: 'Low Stock',
                          value: '$_lowStockCount',
                          color: AppColors.warning,
                        ),
                        const SizedBox(width: 12),
                        _StatChip(
                          label: 'Out of Stock',
                          value: '$_outOfStockCount',
                          color: AppColors.error,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Product List
                  Expanded(
                    child: _products.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _products.length,
                            itemBuilder: (context, index) {
                              final product = _products[index];
                              return _ProductListItem(
                                product: product,
                                onEdit: () => _showEditProductDialog(product),
                                onDelete: () =>
                                    _showDeleteConfirmation(product),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: FloatingActionButton(
          heroTag: 'products_add_fab',
          onPressed: _showAddOptionsSheet,
          child: const Icon(Icons.add_rounded),
        ),
      ),
    );
  }

  void _showAddOptionsSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('Add', style: AppTypography.heading3),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.inventory_2_rounded),
                title: const Text('Add Product'),
                onTap: () {
                  Navigator.pop(context);
                  _showAddProductDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.category_rounded),
                title: const Text('Add Category'),
                onTap: () {
                  Navigator.pop(context);
                  _showAddCategorySheet();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddCategorySheet() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> save() async {
              if (isSaving) return;
              final sheetContext = context;
              final name = nameController.text.trim();
              final description = descriptionController.text.trim();

              if (name.isEmpty) {
                _showSnackBar('Category name is required');
                return;
              }

              setModalState(() => isSaving = true);
              try {
                final response = await _apiService.createCategory(
                  name: name,
                  description: description.isEmpty ? null : description,
                );

                if (!mounted) return;
                if (!sheetContext.mounted) return;

                if (response.success) {
                  Navigator.pop(sheetContext);
                  _showSnackBar('Category saved');
                  await _loadCategories();
                } else {
                  _showSnackBar(response.message ?? 'Failed to save category');
                }
              } catch (e) {
                if (!mounted) return;
                _showSnackBar('Failed to save category');
              } finally {
                if (mounted) setModalState(() => isSaving = false);
              }
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.dividerColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Add Category', style: AppTypography.heading3),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Category Name',
                      prefixIcon: Icon(Icons.category_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isSaving ? null : save,
                      child: isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save Category'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        ),
      ),
    ).whenComplete(() {
      nameController.dispose();
      descriptionController.dispose();
    });
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: AppTypography.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _loadData, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.inventory_2_outlined,
            size: 64,
            color: AppColors.textLight,
          ),
          const SizedBox(height: 16),
          Text(
            'No products found',
            style: AppTypography.bodyLarge.copyWith(
              color: context.textSecondaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add your first product to get started',
            style: AppTypography.bodySmall.copyWith(
              color: context.textLightColor,
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _showBarcodeScannerForResult() async {
    if (!isMobileScannerSupported) {
      showScannerUnsupportedDialog(context);
      return null;
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

    var didPop = false;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text('Scan Code', style: AppTypography.heading3),
            const SizedBox(height: 8),
            Text(
              'Position the QR/barcode within the frame',
              style: AppTypography.bodyMedium.copyWith(
                color: context.textSecondaryColor,
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: MobileScanner(
                    controller: scannerController,
                    onDetect: (capture) {
                      final List<Barcode> barcodes = capture.barcodes;
                      if (barcodes.isEmpty) return;
                      final raw = barcodes.first.rawValue;
                      if (raw == null || raw.trim().isEmpty) return;
                      if (didPop) return;
                      didPop = true;
                      Navigator.pop(context, raw);
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
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    ).whenComplete(scannerController.dispose);

    return result;
  }

  Future<void> _lookupBarcode(String barcode) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final response = await _apiService.getProductByBarcode(barcode);

    if (mounted) {
      Navigator.pop(context);

      if (response.success && response.data != null) {
        final p = response.data!;
        final product = Product(
          id: p['id'].toString(),
          name: p['name'] ?? '',
          category: p['category_name'] ?? '',
          price: (p['selling_price'] ?? 0).toDouble(),
          stock: p['stock_quantity'] ?? 0,
          barcode: p['barcode'],
        );
        _showEditProductDialog(product);
      } else {
        _showSnackBar(
          'Product not found. Creating new product with this barcode.',
        );
        _showAddProductDialog(initialBarcode: barcode);
      }
    }
  }

  void _showAddProductDialog({
    String? initialBarcode,
    String? initialName,
    double? initialPrice,
    int? initialStock,
    String? initialDescription,
    String? initialCategoryId,
    String? initialCategoryName,
  }) {
    _showProductFormDialog(
      null,
      initialBarcode: initialBarcode,
      initialName: initialName,
      initialPrice: initialPrice,
      initialStock: initialStock,
      initialDescription: initialDescription,
      initialCategoryId: initialCategoryId,
      initialCategoryName: initialCategoryName,
    );
  }

  void _showEditProductDialog(Product product) {
    _showProductFormDialog(product);
  }

  void _showProductFormDialog(
    Product? product, {
    String? initialBarcode,
    String? initialName,
    double? initialPrice,
    int? initialStock,
    String? initialDescription,
    String? initialCategoryId,
    String? initialCategoryName,
  }) {
    final isEditing = product != null;
    final nameController = TextEditingController(
      text: product?.name ?? initialName ?? '',
    );
    final priceController = TextEditingController(
      text:
          product?.price.toStringAsFixed(2) ??
          (initialPrice != null ? initialPrice.toStringAsFixed(2) : ''),
    );
    final stockController = TextEditingController(
      text:
          product?.stock.toString() ??
          (initialStock != null ? initialStock.toString() : '0'),
    );
    final pointsController = TextEditingController(
      text: (product?.pointsCost ?? 0) > 0 ? '${product?.pointsCost ?? 0}' : '',
    );
    final barcodeController = TextEditingController(
      text: (initialBarcode ?? product?.barcode ?? '').trim(),
    );
    final descriptionController = TextEditingController(
      text: product?.description ?? initialDescription ?? '',
    );

    String? selectedCategoryId;

    if (product?.category != null && _categories.isNotEmpty) {
      final category = _categories.firstWhere(
        (c) => c['name'] == product?.category,
        orElse: () => <String, dynamic>{},
      );
      if (category.isNotEmpty) {
        selectedCategoryId = category['id'].toString();
      }
    }

    if (!isEditing && selectedCategoryId == null) {
      if (initialCategoryId != null && initialCategoryId.trim().isNotEmpty) {
        selectedCategoryId = initialCategoryId.trim();
      } else if (initialCategoryName != null &&
          initialCategoryName.trim().isNotEmpty &&
          _categories.isNotEmpty) {
        final category = _categories.firstWhere(
          (c) =>
              (c['name']?.toString().toLowerCase() ?? '') ==
              initialCategoryName.trim().toLowerCase(),
          orElse: () => <String, dynamic>{},
        );
        if (category.isNotEmpty) {
          selectedCategoryId = category['id'].toString();
        }
      }
    }

    Uint8List? selectedImageBytes;
    String? selectedImageName;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: StatefulBuilder(
          builder: (context, setModalState) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.dividerColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    isEditing ? AppStrings.editProduct : AppStrings.addProduct,
                    style: AppTypography.heading3,
                  ),
                  const SizedBox(height: 24),

                  // Product Image
                  Center(
                    child: GestureDetector(
                      onTap: () async {
                        final picker = ImagePicker();
                        final XFile? image = await picker.pickImage(
                          source: ImageSource.gallery,
                          maxWidth: 800,
                          maxHeight: 800,
                          imageQuality: 85,
                        );
                        if (image != null) {
                          final bytes = await image.readAsBytes();
                          setModalState(() {
                            selectedImageBytes = bytes;
                            selectedImageName = image.name;
                          });
                        }
                      },
                      child: Stack(
                        children: [
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: AppColors.secondary,
                              borderRadius: BorderRadius.circular(20),
                              image: selectedImageBytes != null
                                  ? DecorationImage(
                                      image: MemoryImage(selectedImageBytes!),
                                      fit: BoxFit.cover,
                                    )
                                  : product?.imageUrl != null
                                  ? DecorationImage(
                                      image: NetworkImage(product!.imageUrl!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child:
                                selectedImageBytes == null &&
                                    product?.imageUrl == null
                                ? const Icon(
                                    Icons.image_outlined,
                                    size: 40,
                                    color: AppColors.textLight,
                                  )
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                color: AppColors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text(AppStrings.productName, style: AppTypography.labelLarge),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      hintText: 'Enter product name',
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text('Redeem Points', style: AppTypography.labelLarge),
                  const SizedBox(height: 8),
                  TextField(
                    controller: pointsController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      hintText: 'Optional (e.g. 100) — leave blank to disable',
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    AppStrings.productCategory,
                    style: AppTypography.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCategoryId,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.secondary.withValues(alpha: 0.3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      hintText: 'Select category',
                    ),
                    items: _categories
                        .map(
                          (category) => DropdownMenuItem(
                            value: category['id'].toString(),
                            child: Text(category['name'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setModalState(() => selectedCategoryId = value);
                    },
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppStrings.productPrice,
                              style: AppTypography.labelLarge,
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: priceController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                hintText: '0.00',
                                prefixText: '₱ ',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppStrings.productStock,
                              style: AppTypography.labelLarge,
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: stockController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(hintText: '0'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Text('Barcode', style: AppTypography.labelLarge),
                  const SizedBox(height: 8),
                  TextField(
                    controller: barcodeController,
                    decoration: InputDecoration(
                      hintText: 'Scan or enter barcode',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        onPressed: isSaving
                            ? null
                            : () async {
                                final raw =
                                    await _showBarcodeScannerForResult();
                                if (raw == null || !mounted) return;

                                final payload = _parseScannedProductPayload(
                                  raw,
                                );
                                final barcode = (payload.barcode ?? '').trim();

                                // If it's not structured data and doesn't look like a barcode,
                                // don't auto-stuff the long raw content into the barcode field.
                                if (!payload.hasNonBarcodeFields &&
                                    barcode.isNotEmpty &&
                                    (!_looksLikeBarcodeForLookup(barcode) ||
                                        _looksLikePaymentQr(raw))) {
                                  final useAnyway =
                                      await _confirmUseRawAsBarcode(raw);
                                  if (!useAnyway || !mounted) return;

                                  setModalState(() {
                                    barcodeController.text = raw.trim();
                                  });
                                  return;
                                }

                                setModalState(() {
                                  if (!isEditing &&
                                      payload.name != null &&
                                      payload.name!.trim().isNotEmpty) {
                                    nameController.text = payload.name!.trim();
                                  }
                                  if (payload.price != null) {
                                    priceController.text = payload.price!
                                        .toStringAsFixed(2);
                                  }
                                  if (payload.stock != null) {
                                    stockController.text = payload.stock!
                                        .toString();
                                  }
                                  if (barcode.isNotEmpty) {
                                    barcodeController.text = barcode;
                                  }
                                  if (payload.description != null &&
                                      payload.description!.trim().isNotEmpty) {
                                    descriptionController.text = payload
                                        .description!
                                        .trim();
                                  }

                                  if (payload.categoryId != null) {
                                    selectedCategoryId = payload.categoryId
                                        .toString();
                                  } else if (payload.categoryName != null &&
                                      payload.categoryName!.trim().isNotEmpty &&
                                      _categories.isNotEmpty) {
                                    final category = _categories.firstWhere(
                                      (c) =>
                                          (c['name']
                                                  ?.toString()
                                                  .toLowerCase() ??
                                              '') ==
                                          payload.categoryName!
                                              .trim()
                                              .toLowerCase(),
                                      orElse: () => <String, dynamic>{},
                                    );
                                    if (category.isNotEmpty) {
                                      selectedCategoryId = category['id']
                                          .toString();
                                    }
                                  }
                                });

                                // If the scan didn't contain structured fields, attempt
                                // a barcode lookup to auto-fill the rest.
                                if (!payload.hasNonBarcodeFields &&
                                    _looksLikeBarcodeForLookup(barcode)) {
                                  final response = await _apiService
                                      .getProductByBarcode(barcode);
                                  if (!mounted) return;

                                  if (response.success &&
                                      response.data != null) {
                                    final p = response.data!;
                                    final foundId = p['id']?.toString();

                                    if (!isEditing) {
                                      Navigator.of(this.context).pop();
                                      _showSnackBar(
                                        'Product found. Opening edit form.',
                                      );
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                            if (!mounted) return;
                                            _showEditProductDialog(
                                              Product(
                                                id: foundId ?? '',
                                                name: p['name'] ?? '',
                                                category:
                                                    p['category_name'] ?? '',
                                                price: (p['selling_price'] ?? 0)
                                                    .toDouble(),
                                                stock: p['stock_quantity'] ?? 0,
                                                barcode: p['barcode'],
                                              ),
                                            );
                                          });
                                      return;
                                    }

                                    if (foundId != null &&
                                        foundId != product.id) {
                                      _showSnackBar(
                                        'This barcode belongs to another product.',
                                        isError: true,
                                      );
                                      return;
                                    }

                                    setModalState(() {
                                      nameController.text = p['name'] ?? '';
                                      priceController.text =
                                          ((p['selling_price'] ?? 0).toDouble())
                                              .toStringAsFixed(2);
                                      stockController.text =
                                          (p['stock_quantity'] ?? 0).toString();
                                      final foundBarcode = p['barcode']
                                          ?.toString()
                                          .trim();
                                      if (foundBarcode != null &&
                                          foundBarcode.isNotEmpty) {
                                        barcodeController.text = foundBarcode;
                                      }
                                    });
                                  }
                                }
                              },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text('Description', style: AppTypography.labelLarge),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descriptionController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Enter product description (optional)',
                    ),
                  ),
                  const SizedBox(height: 32),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isSaving
                              ? null
                              : () => Navigator.pop(context),
                          child: Text(AppStrings.cancel),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isSaving
                              ? null
                              : () async {
                                  final modalNav = Navigator.of(context);
                                  if (nameController.text.trim().isEmpty) {
                                    _showSnackBar(
                                      'Please enter product name',
                                      isError: true,
                                    );
                                    return;
                                  }
                                  if (priceController.text.trim().isEmpty) {
                                    _showSnackBar(
                                      'Please enter product price',
                                      isError: true,
                                    );
                                    return;
                                  }

                                  setModalState(() => isSaving = true);

                                  final price =
                                      double.tryParse(priceController.text) ??
                                      0;
                                  final stock =
                                      int.tryParse(stockController.text) ?? 0;
                                  final pointsCost =
                                      int.tryParse(pointsController.text) ?? 0;
                                  final categoryId = selectedCategoryId != null
                                      ? int.tryParse(selectedCategoryId!)
                                      : null;

                                  ApiResponse<Map<String, dynamic>> response;
                                  if (isEditing) {
                                    response = await _apiService.updateProduct(
                                      productId: int.parse(product.id),
                                      name: nameController.text.trim(),
                                      sellingPrice: price,
                                      stockQuantity: stock,
                                      pointsCost: pointsCost,
                                      barcode:
                                          barcodeController.text
                                              .trim()
                                              .isNotEmpty
                                          ? barcodeController.text.trim()
                                          : null,
                                      description:
                                          descriptionController.text
                                              .trim()
                                              .isNotEmpty
                                          ? descriptionController.text.trim()
                                          : null,
                                      categoryId: categoryId,
                                    );
                                  } else {
                                    response = await _apiService.createProduct(
                                      name: nameController.text.trim(),
                                      sellingPrice: price,
                                      stockQuantity: stock,
                                      pointsCost: pointsCost,
                                      barcode:
                                          barcodeController.text
                                              .trim()
                                              .isNotEmpty
                                          ? barcodeController.text.trim()
                                          : null,
                                      description:
                                          descriptionController.text
                                              .trim()
                                              .isNotEmpty
                                          ? descriptionController.text.trim()
                                          : null,
                                      categoryId: categoryId,
                                    );
                                  }

                                  if (response.success &&
                                      selectedImageBytes != null) {
                                    final int? productId = isEditing
                                        ? int.tryParse(product.id)
                                        : int.tryParse(
                                            response.data?['id']?.toString() ??
                                                '',
                                          );

                                    if (productId != null) {
                                      final uploadResponse = await _apiService
                                          .uploadProductImage(
                                            productId: productId,
                                            imageBytes: selectedImageBytes!,
                                            fileName:
                                                (selectedImageName
                                                        ?.trim()
                                                        .isNotEmpty ==
                                                    true)
                                                ? selectedImageName!.trim()
                                                : 'image.jpg',
                                          );

                                      if (!uploadResponse.success) {
                                        _showSnackBar(
                                          uploadResponse.message ??
                                              'Failed to upload product image',
                                          isError: true,
                                        );
                                      }
                                    }
                                  }

                                  setModalState(() => isSaving = false);

                                  if (response.success) {
                                    if (mounted) modalNav.pop();
                                    _showSnackBar(
                                      isEditing
                                          ? 'Product updated successfully'
                                          : 'Product added successfully',
                                    );
                                    _loadProducts();
                                  } else {
                                    _showSnackBar(
                                      response.message ??
                                          'Failed to save product',
                                      isError: true,
                                    );
                                  }
                                },
                          child: isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.white,
                                  ),
                                )
                              : Text(
                                  isEditing
                                      ? AppStrings.update
                                      : AppStrings.save,
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _showDeleteConfirmation(Product product) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(AppStrings.confirmDelete, style: AppTypography.heading4),
        content: Text(
          'Are you sure you want to delete "${product.name}"?',
          style: AppTypography.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppStrings.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);

              final progressNav = Navigator.of(context);
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) =>
                    const Center(child: CircularProgressIndicator()),
              );

              final response = await _apiService.deleteProduct(
                int.parse(product.id),
              );

              if (!mounted) return;

              progressNav.pop();
              if (response.success) {
                _showSnackBar('Product deleted successfully');
                _loadProducts();
              } else {
                _showSnackBar(
                  response.message ?? 'Failed to delete product',
                  isError: true,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: Text(AppStrings.delete),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value, style: AppTypography.heading4.copyWith(color: color)),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppTypography.caption.copyWith(color: color),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductListItem extends StatelessWidget {
  final Product product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProductListItem({
    required this.product,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(12),
                image: product.imageUrl != null && product.imageUrl!.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(product.imageUrl!),
                        fit: BoxFit.cover,
                        onError: (exception, stackTrace) {},
                      )
                    : null,
              ),
              child: product.imageUrl == null || product.imageUrl!.isEmpty
                  ? Icon(
                      _getCategoryIcon(product.category),
                      color: AppColors.primary.withValues(alpha: 0.6),
                      size: 28,
                    )
                  : null,
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
                          product.name,
                          style: AppTypography.labelLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (product.hasPromoPrice)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'SALE',
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.white,
                              fontSize: 8,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(product.category, style: AppTypography.caption),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (product.hasPromoPrice) ...[
                        Text(
                          '₱${product.price.toStringAsFixed(0)}',
                          style: AppTypography.caption.copyWith(
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        '₱${product.effectivePrice.toStringAsFixed(2)}',
                        style: AppTypography.priceRegular.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: product.isOutOfStock
                              ? AppColors.errorLight
                              : product.isLowStock
                              ? AppColors.warningLight
                              : AppColors.successLight,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          product.isOutOfStock
                              ? 'Out of Stock'
                              : '${product.stock} in stock',
                          style: AppTypography.labelSmall.copyWith(
                            color: product.isOutOfStock
                                ? AppColors.error
                                : product.isLowStock
                                ? AppColors.warning
                                : AppColors.success,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: context.textLightColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      const Icon(Icons.edit_rounded, size: 20),
                      const SizedBox(width: 12),
                      Text('Edit', style: AppTypography.bodyMedium),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      const Icon(
                        Icons.delete_rounded,
                        size: 20,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Delete',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              onSelected: (value) {
                if (value == 'edit') onEdit();
                if (value == 'delete') onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'lipstick':
        return Icons.brush_rounded;
      case 'foundation':
        return Icons.format_paint_rounded;
      case 'skincare':
        return Icons.water_drop_rounded;
      case 'eye makeup':
        return Icons.visibility_rounded;
      case 'face makeup':
        return Icons.face_rounded;
      case 'fragrance':
        return Icons.air_rounded;
      default:
        return Icons.shopping_bag_rounded;
    }
  }
}

class _ScannedProductPayload {
  final String? name;
  final double? price;
  final int? stock;
  final String? barcode;
  final String? description;
  final int? categoryId;
  final String? categoryName;

  const _ScannedProductPayload({
    this.name,
    this.price,
    this.stock,
    this.barcode,
    this.description,
    this.categoryId,
    this.categoryName,
  });

  bool get hasNonBarcodeFields {
    return (name?.trim().isNotEmpty == true) ||
        price != null ||
        stock != null ||
        (description?.trim().isNotEmpty == true) ||
        categoryId != null ||
        (categoryName?.trim().isNotEmpty == true);
  }
}
