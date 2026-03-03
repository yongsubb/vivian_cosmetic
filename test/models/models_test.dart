import 'package:flutter_test/flutter_test.dart';
import 'package:vivian_cosmetic_shop_application/models/models.dart';

void main() {
  group('Product Model Tests', () {
    test('Product should be created with required fields', () {
      final product = Product(
        id: '1',
        name: 'Lipstick',
        category: 'Makeup',
        price: 299.99,
        stock: 50,
      );

      expect(product.id, '1');
      expect(product.name, 'Lipstick');
      expect(product.category, 'Makeup');
      expect(product.price, 299.99);
      expect(product.stock, 50);
      expect(product.isActive, true);
    });

    test('Product isLowStock should return true when stock <= 10 and > 0', () {
      final product1 = Product(
        id: '1',
        name: 'Test',
        category: 'Test',
        price: 100.0,
        stock: 10,
      );
      final product2 = Product(
        id: '2',
        name: 'Test',
        category: 'Test',
        price: 100.0,
        stock: 5,
      );
      final product3 = Product(
        id: '3',
        name: 'Test',
        category: 'Test',
        price: 100.0,
        stock: 11,
      );

      expect(product1.isLowStock, true);
      expect(product2.isLowStock, true);
      expect(product3.isLowStock, false);
    });

    test('Product isOutOfStock should return true when stock <= 0', () {
      final product1 = Product(
        id: '1',
        name: 'Test',
        category: 'Test',
        price: 100.0,
        stock: 0,
      );
      final product2 = Product(
        id: '2',
        name: 'Test',
        category: 'Test',
        price: 100.0,
        stock: -1,
      );
      final product3 = Product(
        id: '3',
        name: 'Test',
        category: 'Test',
        price: 100.0,
        stock: 1,
      );

      expect(product1.isOutOfStock, true);
      expect(product2.isOutOfStock, true);
      expect(product3.isOutOfStock, false);
    });

    test(
      'Product hasPromoPrice should return true when promo price < regular price',
      () {
        final product1 = Product(
          id: '1',
          name: 'Test',
          category: 'Test',
          price: 100.0,
          promoPrice: 80.0,
          stock: 10,
        );
        final product2 = Product(
          id: '2',
          name: 'Test',
          category: 'Test',
          price: 100.0,
          promoPrice: 100.0,
          stock: 10,
        );
        final product3 = Product(
          id: '3',
          name: 'Test',
          category: 'Test',
          price: 100.0,
          stock: 10,
        );

        expect(product1.hasPromoPrice, true);
        expect(product2.hasPromoPrice, false);
        expect(product3.hasPromoPrice, false);
      },
    );

    test('Product effectivePrice should return promo price when available', () {
      final product1 = Product(
        id: '1',
        name: 'Test',
        category: 'Test',
        price: 100.0,
        promoPrice: 80.0,
        stock: 10,
      );
      final product2 = Product(
        id: '2',
        name: 'Test',
        category: 'Test',
        price: 100.0,
        stock: 10,
      );

      expect(product1.effectivePrice, 80.0);
      expect(product2.effectivePrice, 100.0);
    });
  });

  group('CartItem Model Tests', () {
    late Product testProduct;

    setUp(() {
      testProduct = Product(
        id: '1',
        name: 'Test Product',
        category: 'Test',
        price: 100.0,
        stock: 50,
      );
    });

    test('CartItem should be created with default quantity of 1', () {
      final cartItem = CartItem(product: testProduct);

      expect(cartItem.quantity, 1);
      expect(cartItem.product, testProduct);
    });

    test('CartItem should calculate total correctly', () {
      final cartItem = CartItem(product: testProduct, quantity: 3);

      expect(cartItem.total, 300.0);
    });

    test(
      'CartItem should use effective price (promo price) in calculation',
      () {
        final promoProduct = Product(
          id: '1',
          name: 'Test',
          category: 'Test',
          price: 100.0,
          promoPrice: 80.0,
          stock: 10,
        );
        final cartItem = CartItem(product: promoProduct, quantity: 2);

        expect(cartItem.total, 160.0);
      },
    );

    test('CartItem quantity should be mutable', () {
      final cartItem = CartItem(product: testProduct, quantity: 1);

      expect(cartItem.quantity, 1);

      cartItem.quantity = 5;

      expect(cartItem.quantity, 5);
      expect(cartItem.total, 500.0);
    });
  });

  group('Transaction Model Tests', () {
    late Transaction testTransaction;
    late List<CartItem> testItems;

    setUp(() {
      final product1 = Product(
        id: '1',
        name: 'Product 1',
        category: 'Test',
        price: 100.0,
        stock: 50,
      );
      final product2 = Product(
        id: '2',
        name: 'Product 2',
        category: 'Test',
        price: 200.0,
        stock: 30,
      );

      testItems = [
        CartItem(product: product1, quantity: 2),
        CartItem(product: product2, quantity: 1),
      ];

      testTransaction = Transaction(
        id: 'TXN001',
        dateTime: DateTime(2025, 1, 1, 10, 30),
        items: testItems,
        subtotal: 400.0,
        tax: 48.0,
        discount: 0.0,
        total: 448.0,
        paymentMethod: PaymentMethod.cash,
        cashierName: 'John Doe',
      );
    });

    test('Transaction should be created with all required fields', () {
      expect(testTransaction.id, 'TXN001');
      expect(testTransaction.items.length, 2);
      expect(testTransaction.subtotal, 400.0);
      expect(testTransaction.total, 448.0);
      expect(testTransaction.paymentMethod, PaymentMethod.cash);
      expect(testTransaction.cashierName, 'John Doe');
    });

    test('Transaction should support optional customer name', () {
      final transaction = Transaction(
        id: 'TXN002',
        dateTime: DateTime.now(),
        items: testItems,
        subtotal: 400.0,
        tax: 48.0,
        discount: 0.0,
        total: 448.0,
        paymentMethod: PaymentMethod.cash,
        cashierName: 'John Doe',
        customerName: 'Jane Smith',
      );

      expect(transaction.customerName, 'Jane Smith');
    });
  });

  group('PaymentMethod Enum Tests', () {
    test('PaymentMethod should have correct display names', () {
      expect(PaymentMethod.cash.displayName, 'Cash');
      expect(PaymentMethod.card.displayName, 'Card');
      expect(PaymentMethod.gcash.displayName, 'GCash');
      expect(PaymentMethod.maya.displayName, 'Maya');
    });

    test('PaymentMethod should have correct icons', () {
      expect(PaymentMethod.cash.icon, '💵');
      expect(PaymentMethod.card.icon, '💳');
      expect(PaymentMethod.gcash.icon, '📱');
      expect(PaymentMethod.maya.icon, '📲');
    });
  });

  group('User Model Tests', () {
    test('User should be created with required fields', () {
      final user = User(
        id: '1',
        name: 'John Doe',
        username: 'johndoe',
        role: UserRole.cashier,
      );

      expect(user.id, '1');
      expect(user.name, 'John Doe');
      expect(user.username, 'johndoe');
      expect(user.role, UserRole.cashier);
      expect(user.isActive, true);
    });

    test('User should support inactive status', () {
      final user = User(
        id: '1',
        name: 'John Doe',
        username: 'johndoe',
        role: UserRole.cashier,
        isActive: false,
      );

      expect(user.isActive, false);
    });
  });

  group('UserRole Enum Tests', () {
    test('UserRole should have correct display names', () {
      expect(UserRole.cashier.displayName, 'Cashier');
      expect(UserRole.supervisor.displayName, 'Supervisor');
      expect(UserRole.admin.displayName, 'Admin');
    });
  });

  group('Customer Model Tests', () {
    test('Customer should be created with required fields', () {
      final customer = Customer(id: '1', name: 'Jane Smith');

      expect(customer.id, '1');
      expect(customer.name, 'Jane Smith');
      expect(customer.purchaseHistory, isEmpty);
    });

    test('Customer should support all optional fields', () {
      final customer = Customer(
        id: '1',
        name: 'Jane Smith',
        phone: '09123456789',
        email: 'jane@example.com',
        skinType: 'Oily',
        preferences: 'Organic products',
        purchaseHistory: ['TXN001', 'TXN002'],
      );

      expect(customer.phone, '09123456789');
      expect(customer.email, 'jane@example.com');
      expect(customer.skinType, 'Oily');
      expect(customer.preferences, 'Organic products');
      expect(customer.purchaseHistory.length, 2);
    });
  });

  group('Category Model Tests', () {
    test('Category should be created with required fields', () {
      final category = Category(id: '1', name: 'Makeup', icon: '💄');

      expect(category.id, '1');
      expect(category.name, 'Makeup');
      expect(category.icon, '💄');
    });
  });
}
