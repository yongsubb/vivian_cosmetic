/// Product Model for the cosmetic shop
class Product {
  static const String redeemedRewardMarker = '__redeemed_reward__';

  final String id;
  final String name;
  final String category;
  final String? categoryId;
  final double price;
  final double? promoPrice;
  final int pointsCost;
  final int stock;
  final String? imageUrl;
  final String? barcode;
  final String? description;
  final bool isActive;

  Product({
    required this.id,
    required this.name,
    required this.category,
    this.categoryId,
    required this.price,
    this.promoPrice,
    this.pointsCost = 0,
    required this.stock,
    this.imageUrl,
    this.barcode,
    this.description,
    this.isActive = true,
  });

  bool get isLowStock => stock <= 10 && stock > 0;
  bool get isOutOfStock => stock <= 0;
  bool get hasPromoPrice => promoPrice != null && promoPrice! < price;
  double get effectivePrice => hasPromoPrice ? promoPrice! : price;

  bool get isRedeemedReward =>
      pointsCost > 0 && description == Product.redeemedRewardMarker;

  bool get isRewardOnlyRedeemable => pointsCost > 0 && effectivePrice <= 0;
}

/// Cart Item Model
class CartItem {
  final Product product;
  int quantity;

  CartItem({required this.product, this.quantity = 1});

  double get total => product.effectivePrice * quantity;
}

/// Transaction Model
class Transaction {
  final String id;
  final DateTime dateTime;
  final List<CartItem> items;
  final double subtotal;
  final double tax;
  final double discount;
  final double total;
  final PaymentMethod paymentMethod;
  final String cashierName;
  final String? customerName;

  Transaction({
    required this.id,
    required this.dateTime,
    required this.items,
    required this.subtotal,
    required this.tax,
    required this.discount,
    required this.total,
    required this.paymentMethod,
    required this.cashierName,
    this.customerName,
  });
}

/// Payment Method Enum
enum PaymentMethod { cash, card, gcash, maya }

extension PaymentMethodExtension on PaymentMethod {
  String get displayName {
    switch (this) {
      case PaymentMethod.cash:
        return 'Cash';
      case PaymentMethod.card:
        return 'Card';
      case PaymentMethod.gcash:
        return 'GCash';
      case PaymentMethod.maya:
        return 'Maya';
    }
  }

  String get icon {
    switch (this) {
      case PaymentMethod.cash:
        return '💵';
      case PaymentMethod.card:
        return '💳';
      case PaymentMethod.gcash:
        return '📱';
      case PaymentMethod.maya:
        return '📲';
    }
  }
}

/// User Model
class User {
  final String id;
  final String name;
  final String username;
  final UserRole role;
  final bool isActive;

  User({
    required this.id,
    required this.name,
    required this.username,
    required this.role,
    this.isActive = true,
  });
}

/// User Role Enum
enum UserRole { cashier, supervisor, admin }

extension UserRoleExtension on UserRole {
  String get displayName {
    switch (this) {
      case UserRole.cashier:
        return 'Cashier';
      case UserRole.supervisor:
        return 'Supervisor';
      case UserRole.admin:
        return 'Admin';
    }
  }
}

/// Customer Model (Optional module)
class Customer {
  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String? skinType;
  final String? preferences;
  final List<String> purchaseHistory;

  Customer({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.skinType,
    this.preferences,
    this.purchaseHistory = const [],
  });
}

/// Category Model
class Category {
  final String id;
  final String name;
  final String icon;

  Category({required this.id, required this.name, required this.icon});
}
