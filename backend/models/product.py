"""
Product and Category models
"""
from datetime import datetime
from extensions import db


class Category(db.Model):
    """Category model for product categories"""
    __tablename__ = 'categories'
    
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    name = db.Column(db.String(100), unique=True, nullable=False)
    description = db.Column(db.Text, nullable=True)
    icon = db.Column(db.String(50), nullable=True)  # Icon name for Flutter
    color = db.Column(db.String(7), nullable=True)  # Hex color code
    is_active = db.Column(db.Boolean, default=True)
    
    # Timestamps
    created_at = db.Column(db.DateTime, default=datetime.now)
    updated_at = db.Column(db.DateTime, default=datetime.now, onupdate=datetime.now)
    
    # Relationships
    products = db.relationship('Product', backref='category', lazy='dynamic')
    
    def to_dict(self):
        return {
            'id': self.id,
            'name': self.name,
            'description': self.description,
            'icon': self.icon,
            'color': self.color,
            'is_active': self.is_active,
            'product_count': self.products.count()
        }
    
    def __repr__(self):
        return f'<Category {self.name}>'


class Product(db.Model):
    """Product model for cosmetic products"""
    __tablename__ = 'products'
    
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    sku = db.Column(db.String(50), unique=True, nullable=False, index=True)
    barcode = db.Column(db.String(50), unique=True, nullable=True, index=True)
    name = db.Column(db.String(200), nullable=False)
    description = db.Column(db.Text, nullable=True)
    
    # Pricing
    cost_price = db.Column(db.Numeric(10, 2), nullable=False, default=0)
    selling_price = db.Column(db.Numeric(10, 2), nullable=False)
    discount_percent = db.Column(db.Numeric(5, 2), default=0)
    points_cost = db.Column(db.Integer, nullable=False, default=0)
    
    # Inventory
    stock_quantity = db.Column(db.Integer, nullable=False, default=0)
    low_stock_threshold = db.Column(db.Integer, default=10)
    unit = db.Column(db.String(20), default='pcs')  # pcs, box, pack, etc.
    
    # Category
    category_id = db.Column(db.Integer, db.ForeignKey('categories.id'), nullable=True)
    
    # Media
    image_url = db.Column(db.String(255), nullable=True)
    
    # Status
    is_active = db.Column(db.Boolean, default=True)
    is_featured = db.Column(db.Boolean, default=False)
    
    # Timestamps
    created_at = db.Column(db.DateTime, default=datetime.now)
    updated_at = db.Column(db.DateTime, default=datetime.now, onupdate=datetime.now)
    
    # Relationships
    transaction_items = db.relationship('TransactionItem', backref='product', lazy='dynamic')
    
    @property
    def final_price(self):
        """Calculate final price after discount"""
        if self.discount_percent:
            discount = float(self.selling_price) * (float(self.discount_percent) / 100)
            return float(self.selling_price) - discount
        return float(self.selling_price)
    
    @property
    def is_low_stock(self):
        """Check if product is low on stock"""
        return self.stock_quantity <= self.low_stock_threshold
    
    @property
    def is_out_of_stock(self):
        """Check if product is out of stock"""
        return self.stock_quantity <= 0
    
    def to_dict(self):
        return {
            'id': self.id,
            'sku': self.sku,
            'barcode': self.barcode,
            'name': self.name,
            'description': self.description,
            'cost_price': float(self.cost_price),
            'selling_price': float(self.selling_price),
            'discount_percent': float(self.discount_percent) if self.discount_percent else 0,
            'points_cost': int(self.points_cost or 0),
            'final_price': self.final_price,
            'stock_quantity': self.stock_quantity,
            'low_stock_threshold': self.low_stock_threshold,
            'unit': self.unit,
            'category_id': self.category_id,
            'category_name': self.category.name if self.category else None,
            'image_url': self.image_url,
            'is_active': self.is_active,
            'is_featured': self.is_featured,
            'is_low_stock': self.is_low_stock,
            'is_out_of_stock': self.is_out_of_stock,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }
    
    def __repr__(self):
        return f'<Product {self.name}>'
