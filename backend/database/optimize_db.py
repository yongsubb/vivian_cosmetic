"""
Database optimization script
Adds indexes for improved query performance
"""
from extensions import db

def add_indexes():
    """Add database indexes for performance optimization"""
    
    # Products table indexes
    db.session.execute("""
        CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode);
    """)
    
    db.session.execute("""
        CREATE INDEX IF NOT EXISTS idx_products_category_id ON products(category_id);
    """)
    
    db.session.execute("""
        CREATE INDEX IF NOT EXISTS idx_products_is_active ON products(is_active);
    """)
    
    db.session.execute("""
        CREATE INDEX IF NOT EXISTS idx_products_stock ON products(stock_quantity);
    """)
    
    db.session.execute("""
        CREATE INDEX IF NOT EXISTS idx_products_name ON products(name);
    """)
    
    # Transactions table indexes
    db.session.execute("""
        CREATE INDEX IF NOT EXISTS idx_transactions_cashier_id ON transactions(cashier_id);
    """)
    
    db.session.execute("""
        CREATE INDEX IF NOT EXISTS idx_transactions_customer_id ON transactions(customer_id);
    """)
    
    db.session.execute("""
        CREATE INDEX IF NOT EXISTS idx_transactions_created_at ON transactions(created_at);
    """)
    
    db.session.execute("""
        CREATE INDEX IF NOT EXISTS idx_transactions_status ON transactions(status);
    """)
    
    db.session.execute("""
        CREATE INDEX IF NOT EXISTS idx_transactions_payment_method ON transactions(payment_method);
    """)
    
    # Transaction items table indexes
    db.session.execute("""
        CREATE INDEX IF NOT EXISTS idx_transaction_items_transaction_id ON transaction_items(transaction_id);
    """)
    
    db.session.execute("""
        CREATE INDEX IF NOT EXISTS idx_transaction_items_product_id ON transaction_items(product_id);
    """)
    
    # Customers table indexes
    db.session.execute("""
        CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone);
    """)
    
    db.session.execute("""
        CREATE INDEX IF NOT EXISTS idx_customers_email ON customers(email);
    """)
    
    db.session.execute("""
        CREATE INDEX IF NOT EXISTS idx_customers_loyalty_points ON customers(loyalty_points);
    """)
    
    # Users table indexes
    db.session.execute("""
        CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
    """)
    
    db.session.execute("""
        CREATE INDEX IF NOT EXISTS idx_users_is_active ON users(is_active);
    """)
    
    db.session.execute("""
        CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
    """)
    
    # Activity logs table indexes (if exists)
    db.session.execute("""
        CREATE INDEX IF NOT EXISTS idx_activity_logs_user_id ON activity_logs(user_id);
    """)
    
    db.session.execute("""
        CREATE INDEX IF NOT EXISTS idx_activity_logs_action ON activity_logs(action);
    """)
    
    db.session.execute("""
        CREATE INDEX IF NOT EXISTS idx_activity_logs_created_at ON activity_logs(created_at);
    """)
    
    db.session.commit()
    print("✅ Database indexes created successfully!")

def analyze_tables():
    """Analyze tables for optimization"""
    tables = [
        'products', 'categories', 'transactions', 'transaction_items',
        'customers', 'users', 'activity_logs'
    ]
    
    for table in tables:
        try:
            db.session.execute(f"ANALYZE TABLE {table};")
            print(f"✅ Analyzed table: {table}")
        except Exception as e:
            print(f"⚠️ Could not analyze {table}: {e}")
    
    db.session.commit()

def optimize_tables():
    """Optimize tables for better performance"""
    tables = [
        'products', 'categories', 'transactions', 'transaction_items',
        'customers', 'users', 'activity_logs'
    ]
    
    for table in tables:
        try:
            db.session.execute(f"OPTIMIZE TABLE {table};")
            print(f"✅ Optimized table: {table}")
        except Exception as e:
            print(f"⚠️ Could not optimize {table}: {e}")
    
    db.session.commit()

if __name__ == "__main__":
    from app import app
    
    with app.app_context():
        print("🔧 Adding database indexes...")
        add_indexes()
        
        print("\n📊 Analyzing tables...")
        analyze_tables()
        
        print("\n⚡ Optimizing tables...")
        optimize_tables()
        
        print("\n✨ Database optimization complete!")
