import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class OfflineStore {
  static bool _initialized = false;
  static late Box _cacheBox;
  static late Box _queueBox;

  static const String _cacheBoxName = 'offline_cache';
  static const String _queueBoxName = 'offline_queue';

  static const String _productsAllKey = 'products_all';
  static const String _transactionsQueueKey = 'transactions_queue';

  static Future<void> init() async {
    if (_initialized) return;

    await Hive.initFlutter();
    _cacheBox = await Hive.openBox(_cacheBoxName);
    _queueBox = await Hive.openBox(_queueBoxName);

    _initialized = true;
  }

  static Future<void> _ensureInit() async {
    if (_initialized) return;
    await init();
  }

  // ------------------------------------------------------------
  // Products cache
  // ------------------------------------------------------------

  static Future<void> cacheAllProducts(
    List<Map<String, dynamic>> products,
  ) async {
    await _ensureInit();
    await _cacheBox.put(_productsAllKey, products);
  }

  static Future<List<Map<String, dynamic>>> getCachedAllProducts() async {
    await _ensureInit();

    final raw = _cacheBox.get(_productsAllKey);
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    return <Map<String, dynamic>>[];
  }

  static Future<void> applyStockDeltasToCachedProducts({
    required List<Map<String, dynamic>> items,
  }) async {
    await _ensureInit();

    if (items.isEmpty) return;

    final products = await getCachedAllProducts();
    if (products.isEmpty) return;

    bool changed = false;

    for (final item in items) {
      final rawProductId = item['product_id'];
      final rawQty = item['quantity'];
      final productId = rawProductId?.toString();
      final qty = rawQty is num ? rawQty.toInt() : int.tryParse('$rawQty');

      if (productId == null || productId.isEmpty) continue;
      if (qty == null || qty <= 0) continue;

      final idx = products.indexWhere((p) => p['id']?.toString() == productId);
      if (idx < 0) continue;

      final currentRaw = products[idx]['stock_quantity'];
      final current = currentRaw is num
          ? currentRaw.toInt()
          : int.tryParse('$currentRaw') ?? 0;
      final updated = (current - qty);
      products[idx]['stock_quantity'] = updated < 0 ? 0 : updated;
      changed = true;
    }

    if (changed) {
      await _cacheBox.put(_productsAllKey, products);
    }
  }

  static Future<void> setCachedProductStock({
    required String productId,
    required int stockQuantity,
  }) async {
    await _ensureInit();
    final products = await getCachedAllProducts();
    if (products.isEmpty) return;

    final idx = products.indexWhere((p) => p['id']?.toString() == productId);
    if (idx < 0) return;

    products[idx]['stock_quantity'] = stockQuantity < 0 ? 0 : stockQuantity;
    await _cacheBox.put(_productsAllKey, products);
  }

  // ------------------------------------------------------------
  // Offline transactions queue
  // ------------------------------------------------------------

  static Future<List<Map<String, dynamic>>> getQueuedTransactions() async {
    await _ensureInit();

    final raw = _queueBox.get(_transactionsQueueKey);
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    return <Map<String, dynamic>>[];
  }

  static Future<int> pendingTransactionCount() async {
    final list = await getQueuedTransactions();
    return list.where((e) => (e['status'] ?? 'pending') == 'pending').length;
  }

  static Future<String> enqueueTransaction({
    required Map<String, dynamic> payload,
    Map<String, dynamic>? meta,
  }) async {
    await _ensureInit();

    final localId = 'OFFLINE-${DateTime.now().millisecondsSinceEpoch}';
    final entry = <String, dynamic>{
      'local_id': localId,
      'created_at': DateTime.now().toIso8601String(),
      'status': 'pending',
      'attempts': 0,
      'payload': payload,
      if (meta != null) ...meta,
    };

    final list = await getQueuedTransactions();
    list.add(entry);
    await _queueBox.put(_transactionsQueueKey, list);

    return localId;
  }

  static Future<void> markTransactionSynced(
    String localId, {
    Map<String, dynamic>? serverData,
  }) async {
    await _ensureInit();

    final list = await getQueuedTransactions();
    final idx = list.indexWhere((e) => e['local_id'] == localId);
    if (idx < 0) return;

    final updated = Map<String, dynamic>.from(list[idx]);
    updated['status'] = 'synced';
    updated['synced_at'] = DateTime.now().toIso8601String();
    if (serverData != null) {
      updated['server_data'] = serverData;
    }

    list[idx] = updated;
    await _queueBox.put(_transactionsQueueKey, list);
  }

  static Future<int> syncQueuedTransactions({
    required Future<Map<String, dynamic>?> Function(
      Map<String, dynamic> payload,
    )
    sendOnline,
    int maxToSync = 25,
  }) async {
    await _ensureInit();

    final list = await getQueuedTransactions();
    var synced = 0;

    for (final entry in list) {
      if (synced >= maxToSync) break;
      if ((entry['status'] ?? 'pending') != 'pending') continue;

      final localId = (entry['local_id'] ?? '').toString();
      final payload = entry['payload'];
      if (localId.isEmpty || payload is! Map) continue;

      try {
        final server = await sendOnline(Map<String, dynamic>.from(payload));
        if (server != null) {
          await markTransactionSynced(localId, serverData: server);
          synced++;
        } else {
          // Stop early if server not reachable.
          break;
        }
      } catch (e) {
        debugPrint('Offline sync error: $e');
        break;
      }
    }

    return synced;
  }
}
