"""
Database initialization script
Run this after creating the database to seed initial data
"""
import sys
import os

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import app, db
from models import Setting
from models.user import User
from models.product import Product, Category


def seed_users():
    """Create default users"""
    print("Creating default users...")
    
    # Check if admin exists
    if not User.query.filter_by(username='admin').first():
        admin = User(
            username='admin',
            first_name='Admin',
            last_name='User',
            password='admin123',
            role='supervisor',
            email='admin@viviancosmetics.com'
        )
        admin.set_pin('1234')
        db.session.add(admin)
        print("  ✓ Admin user created")
    else:
        print("  - Admin user already exists")
    
    # Check if cashier exists
    if not User.query.filter_by(username='cashier1').first():
        cashier = User(
            username='cashier1',
            first_name='Maria',
            last_name='Santos',
            password='cashier123',
            role='cashier',
            email='cashier1@viviancosmetics.com'
        )
        db.session.add(cashier)
        print("  ✓ Cashier user created")
    else:
        print("  - Cashier user already exists")
    
    db.session.commit()


def seed_categories():
    """Create default categories"""
    print("Creating default categories...")
    
    categories = [
        ('Lipstick', 'Lipsticks and lip products', 'lips', '#E91E63'),
        ('Foundation', 'Foundation and base makeup', 'face', '#F5E6DA'),
        ('Skincare', 'Skincare products and treatments', 'spa', '#4CAF50'),
        ('Eyeshadow', 'Eye makeup products', 'visibility', '#9C27B0'),
        ('Mascara', 'Mascara and eye products', 'remove_red_eye', '#2196F3'),
        ('Blush', 'Blush and cheek products', 'favorite', '#FF5722'),
        ('Perfume', 'Fragrances and perfumes', 'air', '#C9A24D'),
        ('Tools', 'Makeup brushes and tools', 'brush', '#607D8B'),
    ]
    
    for name, desc, icon, color in categories:
        if not Category.query.filter_by(name=name).first():
            category = Category(name=name, description=desc, icon=icon, color=color)
            db.session.add(category)
            print(f"  ✓ Category '{name}' created")
        else:
            print(f"  - Category '{name}' already exists")
    
    db.session.commit()


def seed_products():
    """Create sample products"""
    print("Creating sample products...")
    
    # Commit categories first to ensure they are saved
    db.session.commit()
    
    products = [
        ('LIP-001', '8901234567890', 'Velvet Matte Lipstick - Rose', 150.00, 350.00, 50, 1),
        ('LIP-002', '8901234567891', 'Velvet Matte Lipstick - Nude', 150.00, 350.00, 45, 1),
        ('LIP-003', '8901234567892', 'Glossy Lip Shine - Pink', 100.00, 250.00, 30, 1),
        ('FND-001', '8901234567893', 'Flawless Foundation - Light', 250.00, 599.00, 25, 2),
        ('FND-002', '8901234567894', 'Flawless Foundation - Medium', 250.00, 599.00, 20, 2),
        ('SKN-001', '8901234567895', 'Hydrating Moisturizer', 200.00, 450.00, 40, 3),
        ('SKN-002', '8901234567896', 'Vitamin C Serum', 350.00, 799.00, 15, 3),
        ('EYE-001', '8901234567897', 'Eyeshadow Palette - Natural', 300.00, 699.00, 20, 4),
        ('MAS-001', '8901234567898', 'Volume Mascara - Black', 120.00, 299.00, 35, 5),
        ('BLU-001', '8901234567899', 'Powder Blush - Coral', 100.00, 280.00, 28, 6),
        ('PRF-001', '8901234567900', 'Floral Eau de Parfum', 500.00, 1299.00, 10, 7),
        ('TLS-001', '8901234567901', 'Professional Brush Set', 400.00, 899.00, 12, 8),
    ]
    
    # Disable autoflush to prevent premature flushing
    with db.session.no_autoflush:
        for sku, barcode, name, cost, price, stock, cat_id in products:
            if not Product.query.filter_by(sku=sku).first():
                product = Product(
                    sku=sku,
                    barcode=barcode,
                    name=name,
                    cost_price=cost,
                    selling_price=price,
                    stock_quantity=stock,
                    category_id=cat_id,
                    low_stock_threshold=10
                )
                db.session.add(product)
                print(f"  ✓ Product '{name}' created")
            else:
                print(f"  - Product '{name}' already exists")
    
    db.session.commit()


def init_db():
    """Initialize database with default data"""
    with app.app_context():
        print("\n" + "="*50)
        print("Vivian Cosmetic Shop - Database Initialization")
        print("="*50 + "\n")
        
        # Create tables
        print("Creating database tables...")
        db.create_all()
        print("  ✓ Tables created\n")
        
        # Seed data
        seed_users()
        print()
        seed_categories()
        print()
        seed_products()
        
        print("\n" + "="*50)
        print("Database initialization complete!")
        print("="*50)
        print("\nDefault login credentials:")
        print("  Supervisor: admin / admin123 (PIN: 1234)")
        print("  Cashier: cashier1 / cashier123")
        print()


if __name__ == '__main__':
    init_db()
