import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/api_service.dart';

class CartProvider extends ChangeNotifier {
  static const String storageKey = 'vivian_cart_items';

  final List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);

  int get totalItems => _items.fold(0, (sum, item) => sum + item.quantity);

  double get subtotal => _items.fold(0, (sum, item) => sum + item.total);

  Future<void> loadSavedCart(List<Product> products) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cartJson = prefs.getString(storageKey);
      if (cartJson == null || cartJson.isEmpty) return;

      final List<dynamic> cartData = jsonDecode(cartJson);
      final restored = <CartItem>[];

      for (final raw in cartData) {
        final item = raw as Map<String, dynamic>;

        final productId = item['product_id']?.toString() ?? '';
        final existing = products.where((p) => p.id == productId).firstOrNull;

        if (existing != null) {
          final savedPointsCost =
              int.tryParse(item['product_points_cost']?.toString() ?? '') ?? 0;
          final savedDescription = item['product_description']?.toString();

          final savedQty = (item['quantity'] ?? 1) as int;
          final validQty = savedQty > existing.stock
              ? existing.stock
              : savedQty;
          if (validQty > 0) {
            final mergedProduct = Product(
              id: existing.id,
              name: existing.name,
              category: existing.category,
              categoryId: existing.categoryId,
              price: existing.price,
              promoPrice: existing.promoPrice,
              pointsCost: existing.pointsCost != 0
                  ? existing.pointsCost
                  : savedPointsCost,
              stock: existing.stock,
              imageUrl: existing.imageUrl,
              barcode: existing.barcode,
              description:
                  (savedDescription != null && savedDescription.isNotEmpty)
                  ? savedDescription
                  : existing.description,
              isActive: existing.isActive,
            );

            restored.add(CartItem(product: mergedProduct, quantity: validQty));
          }
          continue;
        }

        final product = Product(
          id: productId,
          name: item['product_name'] ?? 'Unknown',
          category: item['product_category'] ?? 'Unknown',
          price: (item['product_price'] ?? 0).toDouble(),
          promoPrice: item['product_promo_price'] != null
              ? (item['product_promo_price']).toDouble()
              : null,
          pointsCost:
              int.tryParse(item['product_points_cost']?.toString() ?? '') ?? 0,
          stock: item['product_stock'] ?? 0,
          barcode: item['product_barcode'],
          imageUrl: ApiConfig.resolveMediaUrl(
            item['product_image_url']?.toString(),
          ),
          description: item['product_description']?.toString(),
        );

        restored.add(
          CartItem(product: product, quantity: item['quantity'] ?? 1),
        );
      }

      _items
        ..clear()
        ..addAll(restored);
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading cart: $e');
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cartData = _items
          .map(
            (item) => {
              'product_id': item.product.id,
              'product_name': item.product.name,
              'product_category': item.product.category,
              'product_price': item.product.price,
              'product_promo_price': item.product.promoPrice,
              'product_points_cost': item.product.pointsCost,
              'product_stock': item.product.stock,
              'product_barcode': item.product.barcode,
              'product_image_url': item.product.imageUrl,
              'product_description': item.product.description,
              'quantity': item.quantity,
            },
          )
          .toList();
      await prefs.setString(storageKey, jsonEncode(cartData));
    } catch (e) {
      debugPrint('Error saving cart: $e');
    }
  }

  int getQuantity(String productId) {
    final item = _items.where((e) => e.product.id == productId).firstOrNull;
    return item?.quantity ?? 0;
  }

  bool canAdd(Product product, {int quantity = 1}) {
    final inCart = getQuantity(product.id);
    return (inCart + quantity) <= product.stock;
  }

  Future<void> add(Product product, {int quantity = 1}) async {
    final existingIndex = _items.indexWhere((e) => e.product.id == product.id);
    if (existingIndex >= 0) {
      _items[existingIndex].quantity += quantity;
    } else {
      _items.add(CartItem(product: product, quantity: quantity));
    }
    await _save();
    notifyListeners();
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _items.length) return;
    _items.removeAt(index);
    await _save();
    notifyListeners();
  }

  Future<void> setQuantity(int index, int quantity) async {
    if (index < 0 || index >= _items.length) return;

    if (quantity <= 0) {
      _items.removeAt(index);
    } else {
      final stock = _items[index].product.stock;
      _items[index].quantity = quantity > stock ? stock : quantity;
    }

    await _save();
    notifyListeners();
  }

  Future<void> clear() async {
    _items.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
    notifyListeners();
  }
}
