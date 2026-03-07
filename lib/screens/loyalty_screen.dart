import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart' hide Barcode;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../core/utils/mobile_scanner_support.dart';
import '../core/widgets/camera_permission_prompt.dart';
import '../core/theme/theme_helper.dart';
import '../core/constants/app_colors.dart';
import '../services/api_service.dart';

class LoyaltyScreen extends StatefulWidget {
  final String userRole;
  final bool autoOpenRegister;

  const LoyaltyScreen({
    super.key,
    required this.userRole,
    this.autoOpenRegister = false,
  });

  @override
  State<LoyaltyScreen> createState() => _LoyaltyScreenState();
}

class _LoyaltyScreenState extends State<LoyaltyScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // Keep state when switching tabs

  static const int _expiringSoonDays = 30;

  final ApiService _apiService = ApiService();
  late TabController _tabController;

  String get _normalizedRole =>
      widget.userRole.toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');
  bool get _isCashier => _normalizedRole == 'cashier';
  bool get _isAdmin =>
      const {'supervisor', 'admin', 'superadmin'}.contains(_normalizedRole);

  int get _tabCount {
    if (_isCashier) return 1;
    if (_isAdmin) return 3; // Members, Promotions, Tiers
    return 2; // Members, Tiers
  }

  bool _isLoading = false;
  List<Map<String, dynamic>> _members = [];
  bool _membersLoaded = false;
  String? _membersError;
  List<Map<String, dynamic>> _tiers = [];
  Map<String, dynamic>? _dashboardData;
  int _currentPage = 1;
  int _totalPages = 1;
  String _searchQuery = '';
  bool _wasCurrentBefore = false;

  bool _rewardProductsLoaded = false;
  String? _rewardProductsError;
  List<Map<String, dynamic>> _rewardProducts = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
    _loadData();

    if (widget.autoOpenRegister) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showRegisterMemberDialog();
      });
    }
  }

  Future<void> _showRecentMembersSheet() async {
    if (_isCashier) return;
    final response = await _apiService.getRecentLoyaltyMembers(
      days: 30,
      limit: 50,
    );
    if (!mounted) return;
    if (!response.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response.message ?? 'Failed to load recent members'),
        ),
      );
      return;
    }

    final List<Map<String, dynamic>> recent = List<Map<String, dynamic>>.from(
      response.data ?? [],
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
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
              const SizedBox(height: 8),
              const Text(
                'Recent Loyalty Members',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: recent.length,
                  itemBuilder: (context, index) {
                    final m = recent[index];
                    final customer = m['customer'] as Map<String, dynamic>?;
                    final tier = m['tier'] as Map<String, dynamic>?;
                    final createdAt = m['created_at']?.toString();
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primaryLight,
                        child: Text(
                          (customer?['name'] ?? 'M')
                              .toString()
                              .substring(0, 1)
                              .toUpperCase(),
                        ),
                      ),
                      title: Text(
                        customer?['name'] ?? m['member_number'] ?? 'Member',
                      ),
                      subtitle: Text(
                        'Joined: ${createdAt != null ? DateFormat('MMM dd, yyyy').format(DateTime.parse(createdAt)) : 'N/A'}',
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          tier?['name'] ?? 'Bronze',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _showMemberDetails(m);
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
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
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      await Future.wait([
        _loadMembers(),
        _loadTiers(),
        if (!_isCashier) _loadDashboard(),
        if (_isAdmin) _loadRewardProducts(),
      ]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMembers() async {
    if (mounted) {
      setState(() {
        _membersError = null;
      });
    }

    final response = await _apiService.getLoyaltyMembers(
      page: _currentPage,
      search: _searchQuery.isEmpty ? null : _searchQuery,
    );

    debugPrint('🔍 Loyalty Members API Response:');
    debugPrint('  - Success: ${response.success}');
    debugPrint('  - Data is null: ${response.data == null}');
    debugPrint('  - Status Code: ${response.statusCode}');
    if (response.data != null) {
      debugPrint('  - Data type: ${response.data.runtimeType}');
      debugPrint('  - Data keys: ${response.data!.keys}');
      debugPrint('  - Members: ${response.data!['members']}');
      debugPrint(
        '  - Members count: ${(response.data!['members'] as List?)?.length ?? 0}',
      );
    }

    if (response.success && response.data != null) {
      setState(() {
        _members = List<Map<String, dynamic>>.from(
          response.data!['members'] ?? [],
        );
        _totalPages = response.data!['pages'] ?? 1;
        _membersLoaded = true;
        _membersError = null;
      });
      debugPrint('  - Loaded ${_members.length} members');
    } else {
      final msg = (response.message?.trim().isNotEmpty == true)
          ? response.message!.trim()
          : 'Failed to load members';
      debugPrint('  - Failed to load members: $msg');

      if (mounted) {
        setState(() {
          _members = [];
          _totalPages = 1;
          _membersLoaded = true;
          _membersError = '${response.statusCode}: $msg';
        });
      }
    }
  }

  Future<void> _loadTiers() async {
    final response = await _apiService.getLoyaltyTiers();
    if (response.success && response.data != null) {
      setState(() {
        _tiers = response.data!;
      });
    }
  }

  Future<void> _loadDashboard() async {
    final response = await _apiService.getLoyaltyDashboard();
    debugPrint('🔍 Loyalty Dashboard API Response:');
    debugPrint('  - Success: ${response.success}');
    debugPrint('  - Data: ${response.data}');
    if (response.success && response.data != null) {
      setState(() {
        _dashboardData = response.data!;
      });
      debugPrint(
        '  - Dashboard loaded: total_members = ${_dashboardData!['total_members']}',
      );
    }
  }

  void _openArchivedMembers() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArchivedMembersScreen(apiService: _apiService),
      ),
    );
  }

  int _asInt(dynamic raw, {int fallback = 0}) {
    if (raw == null) return fallback;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString().trim()) ?? fallback;
  }

  Future<void> _loadRewardProducts() async {
    if (mounted) {
      setState(() {
        _rewardProductsError = null;
      });
    }

    final response = await _apiService.getProducts();
    if (!mounted) return;

    if (response.success && response.data != null) {
      final items = response.data!
          .where((p) => _asInt(p['points_cost']) > 0)
          .toList(growable: false);

      setState(() {
        _rewardProducts = items;
        _rewardProductsLoaded = true;
        _rewardProductsError = null;
      });
      return;
    }

    final msg = (response.message?.trim().isNotEmpty == true)
        ? response.message!.trim()
        : 'Failed to load reward products';
    setState(() {
      _rewardProducts = const [];
      _rewardProductsLoaded = true;
      _rewardProductsError = '${response.statusCode}: $msg';
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    final tabs = <Tab>[
      const Tab(text: 'Members'),
      if (_isAdmin) const Tab(text: 'Rewards'),
      if (!_isCashier) const Tab(text: 'Tiers'),
    ];

    final tabViews = <Widget>[
      _buildMembersTab(),
      if (_isAdmin) _buildRewardsUploadTab(),
      if (!_isCashier) _buildTiersTab(),
    ];

    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(
        backgroundColor: context.cardColor,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Loyalty Management',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: context.textPrimaryColor,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadData,
            tooltip: 'Reload',
          ),
        ],
        bottom: TabBar(controller: _tabController, tabs: tabs),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) {
          final isMembersTab = _tabController.index == 0;
          if (!isMembersTab) return const SizedBox.shrink();

          return FloatingActionButton(
            heroTag: 'loyalty_register_fab',
            onPressed: _showRegisterMemberDialog,
            child: const Icon(Icons.person_add),
          );
        },
      ),
      body: Stack(
        children: [
          TabBarView(controller: _tabController, children: tabViews),
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: context.isDarkMode ? Colors.black38 : Colors.black12,
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================================
  // REWARD PRODUCTS UPLOAD TAB (ADMIN)
  // ============================================================================

  Future<String?> _scanBarcode() async {
    if (!isMobileScannerSupported) {
      await showScannerUnsupportedDialog(context);
      return null;
    }

    final controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );

    try {
      final scanned = await showDialog<String?>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: 520,
                height: 520,
                child: MobileScanner(
                  controller: controller,
                  onDetect: (capture) {
                    final barcodes = capture.barcodes;
                    final raw = barcodes.isNotEmpty
                        ? (barcodes.first.rawValue ?? '').trim()
                        : '';
                    if (raw.isEmpty) return;
                    Navigator.of(dialogContext).pop(raw);
                  },
                  errorBuilder: (context, error, child) {
                    return CameraPermissionInlineMessage(
                      onEnable: () async {
                        await showEnableCameraDialog(
                          context: context,
                          onRetry: () async {
                            try {
                              await controller.start();
                            } catch (_) {}
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          );
        },
      );
      return scanned?.trim().isNotEmpty == true ? scanned!.trim() : null;
    } finally {
      controller.dispose();
    }
  }

  Future<void> _showUpsertRewardProductDialog({
    Map<String, dynamic>? existing,
  }) async {
    final isEditing = existing != null;
    int? existingId = _asInt(existing?['id']);
    if (existingId == 0) existingId = null;

    final nameController = TextEditingController(
      text: (existing?['name']?.toString() ?? '').trim(),
    );
    final barcodeController = TextEditingController(
      text: (existing?['barcode']?.toString() ?? '').trim(),
    );
    final pointsController = TextEditingController(
      text: _asInt(existing?['points_cost']) > 0
          ? _asInt(existing?['points_cost']).toString()
          : '',
    );

    Uint8List? selectedImageBytes;
    String? selectedImageName;
    bool isSaving = false;

    Future<void> lookupByBarcode(StateSetter setLocalState) async {
      final code = barcodeController.text.trim();
      if (code.isEmpty) return;
      final res = await _apiService.getProductByBarcode(code);
      if (!mounted) return;
      if (!res.success || res.data == null) return;

      final data = res.data!;
      final foundId = _asInt(data['id']);
      if (foundId <= 0) return;

      setLocalState(() {
        existingId = foundId;
        nameController.text = (data['name']?.toString() ?? '').trim();
        final pc = _asInt(data['points_cost']);
        pointsController.text = pc > 0 ? pc.toString() : pointsController.text;
      });
    }

    Future<void> pickImage(StateSetter setLocalState) async {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1000,
        maxHeight: 1000,
        imageQuality: 85,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setLocalState(() {
        selectedImageBytes = bytes;
        selectedImageName = image.name;
      });
    }

    Future<void> submit(StateSetter setLocalState) async {
      final name = nameController.text.trim();
      final barcode = barcodeController.text.trim();
      final pointsCost = int.tryParse(pointsController.text.trim()) ?? 0;

      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product name is required')),
        );
        return;
      }
      if (pointsCost <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Points price must be at least 1')),
        );
        return;
      }

      setLocalState(() => isSaving = true);

      ApiResponse<Map<String, dynamic>> res;
      if (existingId != null) {
        res = await _apiService.updateProduct(
          productId: existingId!,
          name: name,
          barcode: barcode.isNotEmpty ? barcode : null,
          pointsCost: pointsCost,
        );
      } else {
        res = await _apiService.createProduct(
          name: name,
          sellingPrice: 0,
          barcode: barcode.isNotEmpty ? barcode : null,
          pointsCost: pointsCost,
          stockQuantity: 0,
        );
      }

      if (!mounted) return;

      if (!res.success) {
        setLocalState(() => isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.message ?? 'Failed to save product')),
        );
        return;
      }

      final productId = _asInt(res.data?['id']);
      if (selectedImageBytes != null && productId > 0) {
        final uploadRes = await _apiService.uploadProductImage(
          productId: productId,
          imageBytes: selectedImageBytes!,
          fileName: (selectedImageName?.trim().isNotEmpty == true)
              ? selectedImageName!.trim()
              : 'image.jpg',
        );
        if (!mounted) return;
        if (!uploadRes.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                uploadRes.message ?? 'Saved, but failed to upload image',
              ),
            ),
          );
        }
      }

      setLocalState(() => isSaving = false);
      if (mounted) Navigator.of(context).pop();
      await _loadRewardProducts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (existingId != null || isEditing)
                ? 'Reward product updated'
                : 'Reward product created',
          ),
        ),
      );
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              backgroundColor: context.cardColor,
              title: Text(
                (existingId != null || isEditing)
                    ? 'Edit Redeemable Product'
                    : 'Add Redeemable Product',
                style: TextStyle(color: context.textPrimaryColor),
              ),
              content: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: isSaving ? null : () => pickImage(setLocalState),
                        child: Container(
                          height: 120,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: context.dividerColor),
                            image: selectedImageBytes != null
                                ? DecorationImage(
                                    image: MemoryImage(selectedImageBytes!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: selectedImageBytes == null
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.image_outlined,
                                      color: context.textSecondaryColor,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Tap to choose image',
                                      style: TextStyle(
                                        color: context.textSecondaryColor,
                                      ),
                                    ),
                                  ],
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameController,
                        enabled: !isSaving,
                        decoration: const InputDecoration(
                          labelText: 'Product name *',
                          prefixIcon: Icon(Icons.shopping_bag_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: pointsController,
                        enabled: !isSaving,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Points price *',
                          prefixIcon: Icon(Icons.stars_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: barcodeController,
                              enabled: !isSaving,
                              decoration: const InputDecoration(
                                labelText: 'Barcode',
                                prefixIcon: Icon(Icons.qr_code_2_outlined),
                              ),
                              onSubmitted: (_) =>
                                  lookupByBarcode(setLocalState),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton(
                            tooltip: 'Scan barcode',
                            onPressed: isSaving
                                ? null
                                : () async {
                                    final code = await _scanBarcode();
                                    if (!mounted || code == null) return;
                                    setLocalState(() {
                                      barcodeController.text = code;
                                    });
                                    await lookupByBarcode(setLocalState);
                                  },
                            icon: const Icon(Icons.qr_code_scanner_rounded),
                            color: AppColors.primary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: isSaving ? null : () => submit(setLocalState),
                  icon: isSaving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(isSaving ? 'Saving...' : 'Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildRewardsUploadTab() {
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: _loadRewardProducts,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Redeemable Products',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: context.textPrimaryColor,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showUpsertRewardProductDialog(),
                icon: const Icon(Icons.add),
                label: const Text('New'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_rewardProductsError != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.error.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: theme.colorScheme.error,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _rewardProductsError!,
                      style: TextStyle(color: context.textSecondaryColor),
                    ),
                  ),
                  TextButton(
                    onPressed: _loadRewardProducts,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),

          if (!_rewardProductsLoaded && _rewardProductsError == null)
            Padding(
              padding: const EdgeInsets.only(top: 30),
              child: Center(
                child: Text(
                  'Loading products...',
                  style: TextStyle(color: context.textSecondaryColor),
                ),
              ),
            )
          else if (_rewardProductsLoaded && _rewardProducts.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 30),
              child: Center(
                child: Text(
                  'No redeemable products yet',
                  style: TextStyle(color: context.textSecondaryColor),
                ),
              ),
            )
          else
            ..._rewardProducts.map((p) {
              final name = p['name']?.toString() ?? 'Product';
              final barcode = (p['barcode']?.toString() ?? '').trim();
              final points = _asInt(p['points_cost']);
              final stock = _asInt(p['stock_quantity']);
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: context.cardColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.dividerColor),
                ),
                child: ListTile(
                  leading: Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.card_giftcard, color: AppColors.primary),
                  ),
                  title: Text(
                    name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  subtitle: Text(
                    '$points pts • Stock: $stock${barcode.isNotEmpty ? ' • $barcode' : ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.textSecondaryColor),
                  ),
                  trailing: Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        onPressed: () =>
                            _showUpsertRewardProductDialog(existing: p),
                        icon: const Icon(Icons.edit_outlined),
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                  onTap: () => _showUpsertRewardProductDialog(existing: p),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildCompactStatCard(
    String label,
    String value,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(color: context.textPrimaryColor, fontSize: 12),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // MEMBERS TAB
  // ============================================================================

  Widget _buildMembersTab() {
    return Column(
      children: [
        // Search Bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search members...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: context.surfaceColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
                _currentPage = 1;
              });
              _loadMembers();
            },
          ),
        ),

        // Stats Cards (restricted for cashiers)
        if (!_isCashier && _dashboardData != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: _buildCompactStatCard(
                    'Total Members',
                    '${_dashboardData!['total_members'] ?? 0}',
                    Icons.people,
                    const Color(0xFFE91E63),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildCompactStatCard(
                    'Archive',
                    '${_dashboardData!['archived_members'] ?? 0}',
                    Icons.archive_outlined,
                    Colors.orange,
                    onTap: _openArchivedMembers,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildCompactStatCard(
                    'Recent Members',
                    '${_dashboardData!['recent_signups'] ?? 0}',
                    Icons.trending_up,
                    Colors.red,
                    onTap: _showRecentMembersSheet,
                  ),
                ),
              ],
            ),
          ),

        Expanded(
          child: _members.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _membersError != null
                            ? Icons.error_outline
                            : Icons.people_outline,
                        size: 80,
                        color: _membersError != null
                            ? Colors.orange
                            : context.textLightColor,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _membersError != null
                            ? 'Can\'t load members'
                            : (_membersLoaded
                                  ? 'No members found'
                                  : 'Loading…'),
                        style: TextStyle(
                          color: context.textSecondaryColor,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_membersError != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            _membersError!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: context.textLightColor,
                              fontSize: 12,
                            ),
                          ),
                        )
                      else
                        Text(
                          'Members list length: ${_members.length}',
                          style: TextStyle(
                            color: context.textLightColor,
                            fontSize: 12,
                          ),
                        ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _isLoading ? null : _loadData,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _members.length,
                  itemBuilder: (context, index) {
                    final member = _members[index];
                    return _buildMemberCard(member);
                  },
                ),
        ),
        if (_totalPages > 1) _buildPagination(),
      ],
    );
  }

  Widget _buildMemberCard(Map<String, dynamic> member) {
    final customer = member['customer'] as Map<String, dynamic>?;
    final tier = member['tier'] as Map<String, dynamic>?;

    final tierColor = tier != null && tier['color'] != null
        ? Color(int.parse(tier['color'].replaceFirst('#', '0xFF')))
        : Colors.grey;

    final statusRingColor = _memberStatusRingColor(member);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      color: context.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.dividerColor, width: 1),
      ),
      child: InkWell(
        onTap: _isCashier ? null : () => _showMemberDetails(member),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Member Avatar
                Container(
                  width: 66,
                  height: 66,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: statusRingColor, width: 3),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [tierColor.withValues(alpha: 0.6), tierColor],
                      ),
                    ),
                    child: Center(
                      child: Text(
                        customer?['name']?.substring(0, 1).toUpperCase() ?? 'M',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Member Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer?['name'] ?? 'Unknown',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: tierColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              tier?['name'] ?? 'Bronze',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'ID: ${member['member_number']}',
                            style: TextStyle(
                              color: context.textSecondaryColor,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.star_outline,
                            size: 16,
                            color: context.textSecondaryColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${(member['current_points'] ?? 0)} pts',
                            style: TextStyle(
                              color: context.textSecondaryColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Lifetime: ${(member['lifetime_points'] ?? 0)}',
                            style: TextStyle(
                              color: context.textLightColor,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _buildValidityLine(member),
                    ],
                  ),
                ),
                // Actions (restricted for cashiers)
                if (!_isCashier)
                  SizedBox(
                    width: 48,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.credit_card, size: 20),
                            onPressed: () => _showCardDialog(member),
                            color: AppColors.primary,
                            tooltip: 'View Card',
                          ),
                        ),
                        if (_shouldShowRenew(member))
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.autorenew, size: 20),
                              onPressed: () => _confirmRenewMember(member),
                              color: Colors.orange,
                              tooltip: 'Renew Membership',
                            ),
                          ),
                        if (member['card_issued'] != true)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Pending',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    // Supports either ISO (2025-12-20T...) or yyyy-MM-dd.
    return DateTime.tryParse(s);
  }

  bool _shouldShowRenew(Map<String, dynamic> member) {
    final expiry = _parseDate(member['expiry_date']);
    if (expiry == null) return false;

    final now = DateTime.now();
    final daysLeft = expiry.difference(now).inDays;
    return daysLeft <= _expiringSoonDays;
  }

  Color _memberStatusRingColor(Map<String, dynamic> member) {
    final expiry = _parseDate(member['expiry_date']);
    if (expiry == null) return Colors.grey;

    final now = DateTime.now();
    final isExpired = expiry.isBefore(now);
    return isExpired ? Colors.grey : Colors.green;
  }

  Widget _buildValidityLine(Map<String, dynamic> member) {
    final expiry = _parseDate(member['expiry_date']);
    if (expiry == null) {
      return Text(
        'Validity: N/A',
        style: TextStyle(color: context.textSecondaryColor, fontSize: 12),
      );
    }

    return Row(
      children: [
        Expanded(
          child: Text(
            'Valid until: ${DateFormat('MMM dd, yyyy').format(expiry)}',
            style: TextStyle(color: context.textSecondaryColor, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Future<void> _confirmRenewMember(Map<String, dynamic> member) async {
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Renew Membership'),
        content: const Text('Renew this member for another 1 year?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);

              final response = await _apiService.renewLoyaltyMembership(
                member['id'] as int,
              );

              if (!mounted) return;
              final messenger = ScaffoldMessenger.of(context);
              if (response.success) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Membership renewed')),
                );
                await _loadData();
              } else {
                messenger.showSnackBar(
                  SnackBar(content: Text(response.message ?? 'Error')),
                );
              }
            },
            child: const Text('Renew'),
          ),
        ],
      ),
    );
  }

  Widget _buildPagination() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _currentPage > 1
                ? () {
                    setState(() => _currentPage--);
                    _loadMembers();
                  }
                : null,
          ),
          Text('Page $_currentPage of $_totalPages'),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _currentPage < _totalPages
                ? () {
                    setState(() => _currentPage++);
                    _loadMembers();
                  }
                : null,
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // TIERS TAB
  // ============================================================================

  Widget _buildTiersTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _tiers.length,
      itemBuilder: (context, index) {
        final tier = _tiers[index];
        return _buildTierCard(tier);
      },
    );
  }

  Widget _buildTierCard(Map<String, dynamic> tier) {
    final tierColor = tier['color'] != null
        ? Color(int.parse(tier['color'].replaceFirst('#', '0xFF')))
        : Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [tierColor.withValues(alpha: 0.2), Colors.white],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: tierColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getTierIcon(tier['icon']),
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tier['name'] ?? 'Unknown',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: tierColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _showEditTierDialog(tier),
                  ),
                ],
              ),
              const Divider(height: 24),
              _buildTierInfo('Discount', '${tier['discount_percent']}%'),
              if (tier['benefits'] != null && tier['benefits'].isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    tier['benefits'],
                    style: TextStyle(
                      color: context.textSecondaryColor,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: tierColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${tier['member_count'] ?? 0} members',
                  style: TextStyle(
                    color: tierColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTierInfo(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: context.textSecondaryColor)),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  }

  IconData _getTierIcon(String? iconName) {
    switch (iconName) {
      case 'star':
        return Icons.star;
      case 'star_half':
        return Icons.star_half;
      case 'auto_awesome':
        return Icons.auto_awesome;
      default:
        return Icons.stars;
    }
  }

  // ============================================================================
  // DIALOGS
  // ============================================================================

  Future<void> _showRegisterMemberDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final addressController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    String normalizePhone(String input) => input.trim();

    String? validatePhone(String? value) {
      final raw = (value ?? '').trim();
      if (raw.isEmpty) return null; // Optional
      if (!RegExp(r'^\d*$').hasMatch(raw)) {
        return 'Phone can contain numbers only';
      }
      if (raw.length < 11 || raw.length > 12) {
        return 'Phone must be 11-12 digits';
      }
      return null;
    }

    String? validateEmail(String? value) {
      final raw = (value ?? '').trim();
      if (raw.isEmpty) return null; // Optional
      // Basic email validation: must include '@' and a domain suffix.
      final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
      if (!emailRegex.hasMatch(raw)) {
        return 'Enter a valid email address';
      }
      return null;
    }

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Register New Member'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(12),
                  ],
                  validator: validatePhone,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: validateEmail,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: addressController,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) return;

              Navigator.pop(dialogContext);

              final response = await _apiService.registerLoyaltyMember({
                'name': nameController.text.trim(),
                'phone': normalizePhone(phoneController.text),
                'email': emailController.text.trim(),
                'address': addressController.text.trim(),
              });

              if (!mounted) return;
              final messenger = ScaffoldMessenger.of(context);
              if (response.success) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Member registered successfully'),
                  ),
                );
                _loadData();
              } else {
                messenger.showSnackBar(
                  SnackBar(content: Text(response.message ?? 'Error')),
                );
              }
            },
            child: const Text('Register'),
          ),
        ],
      ),
    );
  }

  Future<void> _showMemberDetails(Map<String, dynamic> member) async {
    if (_isCashier) return;
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: 500,
          constraints: const BoxConstraints(maxHeight: 700),
          child: _MemberDetailsView(member: member, onUpdate: _loadData),
        ),
      ),
    );
  }

  Future<void> _showCardDialog(Map<String, dynamic> member) async {
    final response = await _apiService.getLoyaltyCardData(member['id'] as int);

    if (!response.success || response.data == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response.message ?? 'Error loading card')),
        );
      }
      return;
    }

    if (mounted) {
      await showDialog(
        context: context,
        builder: (dialogContext) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            constraints: const BoxConstraints(maxWidth: 450, maxHeight: 650),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Loyalty Card',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: () => Navigator.pop(dialogContext),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildLoyaltyCard(response.data!),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _printCard(response.data!),
                          icon: const Icon(Icons.print, size: 20),
                          label: const Text('Print'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      if (member['card_issued'] != true) ...{
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final dialogNav = Navigator.of(dialogContext);
                              final issueResponse = await _apiService
                                  .issueLoyaltyCard(member['id'] as int);
                              if (!mounted) return;
                              if (issueResponse.success) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Card marked as issued'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                                dialogNav.pop();
                                _loadData();
                              }
                            },
                            icon: const Icon(Icons.check_circle, size: 20),
                            label: const Text('Mark Issued'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      },
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

  Widget _buildLoyaltyCard(Map<String, dynamic> cardData) {
    final tierColor = cardData['tier_color'] != null
        ? Color(int.parse(cardData['tier_color'].replaceFirst('#', '0xFF')))
        : const Color(0xFFE91E63);

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 360),
      decoration: BoxDecoration(
        color: tierColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: tierColor.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Section
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cardData['store_name'] ?? 'Vivian Cosmetic Shop',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'LOYALTY MEMBER CARD',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 11,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        cardData['tier_name'] ?? 'Bronze',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  cardData['customer_name'] ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'ID: ${cardData['member_number'] ?? ''}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          // Barcode Section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Column(
              children: [
                BarcodeWidget(
                  barcode: Barcode.code128(),
                  data: cardData['card_barcode'] ?? '2000000000000',
                  width: double.infinity,
                  height: 60,
                  drawText: false,
                ),
                const SizedBox(height: 8),
                Text(
                  cardData['card_barcode'] ?? '2000000000000',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _printCard(Map<String, dynamic> cardData) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Container(
              width: 340,
              height: 200,
              decoration: pw.BoxDecoration(
                color: PdfColors.purple,
                borderRadius: pw.BorderRadius.circular(16),
              ),
              child: pw.Padding(
                padding: const pw.EdgeInsets.all(20),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          cardData['store_name'] ?? 'Vivian Cosmetic Shop',
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          cardData['tier_name'] ?? 'Bronze',
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    pw.Spacer(),
                    pw.Text(
                      cardData['customer_name'] ?? '',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'ID: ${cardData['member_number'] ?? ''}',
                      style: const pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 14,
                      ),
                    ),
                    pw.Spacer(),
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.code128(),
                      data: cardData['card_barcode'] ?? '2000000000000',
                      width: 200,
                      height: 40,
                      drawText: false,
                      color: PdfColors.white,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  Future<void> _showEditTierDialog(Map<String, dynamic> tier) async {
    final discountController = TextEditingController(
      text: tier['discount_percent'].toString(),
    );

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Edit ${tier['name']} Tier'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: discountController,
              decoration: const InputDecoration(
                labelText: 'Discount Percent',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);

              final response = await _apiService.updateLoyaltyTier(
                tier['id'] as int,
                {'discount_percent': double.parse(discountController.text)},
              );

              if (!mounted) return;
              final messenger = ScaffoldMessenger.of(context);

              if (response.success) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Tier updated successfully')),
                );
                _loadTiers();
              } else {
                messenger.showSnackBar(
                  SnackBar(content: Text(response.message ?? 'Error')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class ArchivedMembersScreen extends StatefulWidget {
  final ApiService apiService;
  const ArchivedMembersScreen({super.key, required this.apiService});

  @override
  State<ArchivedMembersScreen> createState() => _ArchivedMembersScreenState();
}

class _ArchivedMembersScreenState extends State<ArchivedMembersScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _members = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await widget.apiService.getArchivedLoyaltyMembers();
      if (!mounted) return;
      if (res.success && res.data != null) {
        final data = res.data!;
        final list = data['members'];
        setState(() {
          _members = list is List
              ? List<Map<String, dynamic>>.from(list)
              : const [];
          _loading = false;
        });
      } else {
        setState(() {
          _error = res.message ?? 'Failed to load archived members';
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load archived members: $e';
        _loading = false;
      });
    }
  }

  Future<void> _showActions(Map<String, dynamic> member) async {
    final id = member['id'];
    final memberId = (id is int) ? id : int.tryParse('$id');
    if (memberId == null) return;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archived member'),
        content: const Text('Choose an action.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('restore'),
            child: const Text('Restore'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop('delete'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (action == null || action == 'cancel') return;

    final messenger = ScaffoldMessenger.of(context);

    if (action == 'restore') {
      final res = await widget.apiService.restoreLoyaltyMember(memberId);
      if (!mounted) return;
      if (res.success) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Member restored')),
        );
        await _load();
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text(res.message ?? 'Failed to restore member')),
        );
      }
      return;
    }

    if (action == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete member'),
          content: const Text(
            'Delete this loyalty membership permanently? This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              child: const Text('Delete'),
            ),
          ],
        ),
      );

      if (confirm != true) return;
      final res = await widget.apiService.deleteLoyaltyMember(memberId);
      if (!mounted) return;
      if (res.success) {
        messenger.showSnackBar(const SnackBar(content: Text('Member deleted')));
        await _load();
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text(res.message ?? 'Failed to delete member')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Archived Members'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : (_members.isEmpty)
          ? const Center(child: Text('No archived members'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemBuilder: (context, index) {
                final m = _members[index];
                final customer = m['customer'] as Map<String, dynamic>?;
                final name = customer?['name']?.toString() ?? 'Member';
                final memberNo = m['member_number']?.toString() ?? '';
                final archivedAt = m['archived_at']?.toString();

                return ListTile(
                  leading: const Icon(Icons.archive_outlined),
                  title: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    archivedAt != null && archivedAt.isNotEmpty
                        ? 'ID: $memberNo\nArchived: $archivedAt'
                        : 'ID: $memberNo',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.more_vert),
                  onTap: () => _showActions(m),
                );
              },
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemCount: _members.length,
            ),
    );
  }
}

// ============================================================================
// MEMBER DETAILS VIEW
// ============================================================================

class _MemberDetailsView extends StatefulWidget {
  final Map<String, dynamic> member;
  final VoidCallback onUpdate;

  const _MemberDetailsView({required this.member, required this.onUpdate});

  @override
  State<_MemberDetailsView> createState() => _MemberDetailsViewState();
}

class _MemberDetailsViewState extends State<_MemberDetailsView> {
  final ApiService _apiService = ApiService();

  Future<void> _editMemberDetails() async {
    final customer = widget.member['customer'] as Map<String, dynamic>?;
    final nameController = TextEditingController(text: customer?['name'] ?? '');
    final phoneController = TextEditingController(
      text: customer?['phone'] ?? '',
    );
    final emailController = TextEditingController(
      text: customer?['email'] ?? '',
    );
    final addressController = TextEditingController(
      text: customer?['address'] ?? '',
    );

    final formKey = GlobalKey<FormState>();

    String normalizePhone(String input) => input.trim();

    String? validatePhone(String? value) {
      final raw = (value ?? '').trim();
      if (raw.isEmpty) return null; // Optional
      if (!RegExp(r'^\d*$').hasMatch(raw)) {
        return 'Phone can contain numbers only';
      }
      if (raw.length < 11 || raw.length > 12) {
        return 'Phone must be 11-12 digits';
      }
      return null;
    }

    String? validateEmail(String? value) {
      final raw = (value ?? '').trim();
      if (raw.isEmpty) return null; // Optional
      final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
      if (!emailRegex.hasMatch(raw)) {
        return 'Enter a valid email address';
      }
      return null;
    }

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Member'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(12),
                  ],
                  validator: validatePhone,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: validateEmail,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: addressController,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              Navigator.pop(context, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (shouldSave != true) return;

    final response = await _apiService.updateLoyaltyMember(
      widget.member['id'] as int,
      {
        'customer': {
          'name': nameController.text.trim(),
          'phone': normalizePhone(phoneController.text),
          'email': emailController.text.trim(),
          'address': addressController.text.trim(),
        },
      },
    );

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (response.success && response.data != null) {
      setState(() {
        widget.member
          ..clear()
          ..addAll(response.data!);
      });
      messenger.showSnackBar(const SnackBar(content: Text('Member updated')));
      widget.onUpdate();
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(response.message ?? 'Error')),
      );
    }
  }

  Future<void> _setExpiryDate() async {
    final currentExpiry = _parseDate(widget.member['expiry_date']);
    final initial = currentExpiry ?? DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked == null) return;

    final response = await _apiService
        .updateLoyaltyMember(widget.member['id'] as int, {
          'expiry_date': DateTime(
            picked.year,
            picked.month,
            picked.day,
          ).toIso8601String(),
        });

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (response.success && response.data != null) {
      setState(() {
        widget.member
          ..clear()
          ..addAll(response.data!);
      });
      messenger.showSnackBar(const SnackBar(content: Text('Validity updated')));
      widget.onUpdate();
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(response.message ?? 'Error')),
      );
    }
  }

  Future<void> _toggleCardIssued() async {
    final isIssued = widget.member['card_issued'] == true;
    final messenger = ScaffoldMessenger.of(context);

    final response = await _apiService.updateLoyaltyMember(
      widget.member['id'] as int,
      {'card_issued': !isIssued},
    );

    if (!mounted) return;
    if (response.success && response.data != null) {
      setState(() {
        widget.member
          ..clear()
          ..addAll(response.data!);
      });
      messenger.showSnackBar(
        SnackBar(content: Text(isIssued ? 'Marked pending' : 'Marked issued')),
      );
      widget.onUpdate();
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(response.message ?? 'Error')),
      );
    }
  }

  Future<void> _archiveMember() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive Member'),
        content: const Text(
          'Archive this loyalty membership? You can restore it from the Archive page.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final response = await _apiService.archiveLoyaltyMember(
      widget.member['id'] as int,
    );

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    if (response.success) {
      messenger.showSnackBar(const SnackBar(content: Text('Member archived')));
      widget.onUpdate();
      nav.pop();
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(response.message ?? 'Error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.member['customer'] as Map<String, dynamic>?;

    return Column(
      children: [
        AppBar(
          title: Text(customer?['name'] ?? 'Member Details'),
          automaticallyImplyLeading: false,
          actions: [
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    _editMemberDetails();
                    break;
                  case 'expiry':
                    _setExpiryDate();
                    break;
                  case 'toggle_issued':
                    _toggleCardIssued();
                    break;
                  case 'delete':
                    _archiveMember();
                    break;
                }
              },
              itemBuilder: (context) {
                final isIssued = widget.member['card_issued'] == true;
                return [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(
                    value: 'expiry',
                    child: Text('Set Valid Until'),
                  ),
                  PopupMenuItem(
                    value: 'toggle_issued',
                    child: Text(isIssued ? 'Mark Pending' : 'Mark Issued'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(value: 'delete', child: Text('Archive')),
                ];
              },
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoCard(),
                const SizedBox(height: 16),
                _buildValidityCard(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard() {
    final customer = widget.member['customer'] as Map<String, dynamic>?;
    final tier = widget.member['tier'] as Map<String, dynamic>?;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Member ID: ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(widget.member['member_number'] ?? ''),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text(
                  'Tier: ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    tier?['name'] ?? 'Bronze',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text(
                  'Current Points: ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('${widget.member['current_points'] ?? 0}'),
                const SizedBox(width: 12),
                const Text(
                  'Lifetime: ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('${widget.member['lifetime_points'] ?? 0}'),
              ],
            ),
            const SizedBox(height: 8),
            Text('Phone: ${customer?['phone'] ?? 'N/A'}'),
            Text('Email: ${customer?['email'] ?? 'N/A'}'),
            Text('Member since: ${_formatDate(widget.member['join_date'])}'),
          ],
        ),
      ),
    );
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  Widget _buildValidityCard() {
    final expiry = _parseDate(widget.member['expiry_date']);
    final now = DateTime.now();

    final bool hasExpiry = expiry != null;
    final int? daysLeft = hasExpiry ? expiry.difference(now).inDays : null;
    final bool isExpired = daysLeft != null && daysLeft < 0;
    final bool isExpiringSoon = daysLeft != null && daysLeft <= 30;

    return Card(
      color: AppColors.primaryLight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Membership Validity',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Valid until: ${expiry != null ? DateFormat('MMM dd, yyyy').format(expiry) : 'N/A'}',
            ),
            if (daysLeft != null)
              Text(
                'Days left: ${daysLeft < 0 ? 0 : daysLeft}',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            const SizedBox(height: 12),
            if (isExpiringSoon || isExpired)
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final response = await _apiService.renewLoyaltyMembership(
                      widget.member['id'] as int,
                    );

                    if (!mounted) return;
                    if (response.success && response.data != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Membership renewed')),
                      );
                      widget.onUpdate();
                      Navigator.pop(context);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(response.message ?? 'Error')),
                      );
                    }
                  },
                  icon: const Icon(Icons.autorenew),
                  label: const Text('Renew (1 year)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    try {
      final DateTime dt = DateTime.parse(date.toString());
      return DateFormat('MMM dd, yyyy').format(dt);
    } catch (e) {
      return 'N/A';
    }
  }
}
